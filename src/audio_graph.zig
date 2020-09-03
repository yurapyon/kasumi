const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const nitori = @import("nitori");

const communication = nitori.communication;
const Channel = communication.Channel;
const EventChannel = communication.EventChannel;

const graph = nitori.graph;
const Graph = graph.Graph;
const NodeIndex = graph.NodeIndex;
const EdgeIndex = graph.EdgeIndex;

//;

const module = @import("module.zig");
const Module = module.Module;

const system = @import("system.zig");
const CallbackContext = system.CallbackContext;

//;

pub const max_callback_len: usize = 2048;

pub const Sample = f32;

pub const GraphModule = struct {
    module: Module,
    buffer: [max_callback_len]Sample,
};

// TODO move this to module.zig maybe
pub const InBuffer = struct {
    id: usize,
    buf: []const Sample,
};

//;

fn cloneArrayList(comptime T: type, allocator: *Allocator, alist: ArrayList(T)) !ArrayList(T) {
    var ret = try ArrayList(T).initCapacity(allocator, alist.capacity);
    ret.items.len = alist.items.len;
    for (alist.items) |item, i| ret.items[i] = item;
}

//;

// ptrs can be shared between audio thread and main thread,
//   audio thread is the only one modifying and accessing the ptrs
//     after theyve been allocated on main thread, then swapped atomically
//     freed by main thread
const AudioGraphBase = struct {
    allocator: *Allocator,

    modules: ArrayList(*GraphModule),
    graph: Graph(usize, usize),
    sort: []NodeIndex,
    output: ?NodeIndex,

    temp_in_bufs: ArrayList(InBuffer),
    removals: ArrayList(usize),

    fn init(allocator: *Allocator) Self {
        const graph = Graph(usize, usize).init(allocator);
        return .{
            .allocator = allocator,
            .modules = ArrayList(*GraphModule).init(allocator),
            .graph = graph,
            .sort = graph.toposort(allocator, allocator) catch unreachable,
            .output = null,
            .temp_in_bufs = ArrayList(InBuffer).init(allocator),
            .removals = ArrayList(usize).init(allocator),
        };
    }

    fn deinit(self: *Self) void {
        self.removals.deinit();
        self.temp_in_bufs.deinit();
        self.allocator.free(self.sort);
        self.modules.deinit();
        self.graph.deinit();
    }

    //!

    fn sort(self: *Self, workspace_allocator: *Allocator) !void {
        self.sort = try self.graph.toposort(self.allocator, workspace_allocator);
    }

    // clones using allocator sent on init
    fn clone(self: Self) !Self {
        var ret: Self = undefined;
        ret.allocator = self.allocator;
        ret.modules = try cloneArrayList(*GraphModule, self.allocator, self.modules);
        ret.graph = try self.graph.clone(self.allocator);
        ret.sort = try self.allocator.dupe(NodeIndex, self.sort);
        ret.output = self.output;
        ret.temp_in_bufs = try cloneArrayList(InBuffer, self.allocator, self.temp_in_bufs);
        ret.removals = try cloneArrayList(usize, self.allocator, self.removals);
    }
};

// Audio-thread side audio graph
// nothing should or needs to support reallocation
pub const AudioGraph = struct {
    const Self = @This();

    base: AudioGraphBase,

    tx: Channel.Sender(AudioGraphBase),
    rx: EventChannel.Receiver(AudioGraphBase),

    // allocator must be the same as used for the controller
    pub fn init(
        allocator: *Allocator,
        channel: *Channel,
        event_channel: *EventChannel,
    ) Self {
        return .{
            .base = AudioGraphBase.init(allocator),
            .tx = channel.makeSender(),
            .rx = event_channel.makeReceiver(),
        };
    }

    // deinit is called when audio thread is killed
    pub fn deinit(self: *Self) void {
        self.base.deinit();
    }

    //;

    fn moduleIdxFromNodeIdx(self: Self, idx: NodeIndex) usize {
        return self.base.graph.nodes.items[idx].weight;
    }

    pub fn frame(self: *Self, ctx: CallbackContext) void {
        if (self.rx.tryRecv(ctx.now)) |*swap| {
            std.mem.swap(AudioGraphBase, &self.base, swap);
            std.mem.swap(AudioGraphBase, &self.base.removals, &swap.removals);
            self.tx.send(swap.*);
        }

        for (self.base.sort) |idx| {
            const module_idx = self.moduleIdxFromNodeIdx(idx);
            self.modules[module_idx].frame(ctx);
        }
    }

    pub fn compute(self: *Self, ctx: CallbackContext, out: []Sample) void {
        if (self.base.output) |output_idx| {
            for (self.base.sort) |idx| {
                const module_idx = self.moduleIdxFromNodeIdx(idx);

                var in_bufs_at: usize = 0;
                var edge_iter = self.base.graph.edgesDirected(idx, .Incoming);
                while (edge_iter.next()) |ref| {
                    const in_buf_idx = self.moduleIdxFromNodeIdx(ref.edge.start_node);
                    self.base.temp_in_bufs[in_bufs_at] = .{
                        .id = ref.edge.weight,
                        .buf = self.out_bufs[in_buf_idx],
                    };
                    in_bufs_at += 1;
                }

                var out_buf = &self.out_bufs[module_idx];
                self.modules[module_idx].compute(ctx, self.base.temp_in_bufs[0..in_bufs_at], out_buf);
                std.mem.copy(Sample, out_buf, self.out_bufs[output_idx].buffer[0..ctx.frame_len]);
            }
        } else {
            std.mem.set(Sample, out_buf, 0.);
        }
    }
};

// this needs to keep track of removals,
// so it can deinit removed modules after theve been swapped out
// module interface needs deinit (rust does this with Box<> but secretly)
pub const Controller = struct {
    const Self = @This();

    allocator: *Allocator,

    base: AudioGraphBase,
    max_inputs: usize,

    tx: EventChannel.Sender(AudioGraphBase),
    rx: Channel.Receiver(AudioGraphBase),

    pub fn init(
        allocator: *Allocator,
        channel: *Channel,
        event_channel: EventChannel,
    ) Self {
        return .{
            .allocator = allocator,
            .base = AudioGraphBase.init(allocator),
            .max_inputs = 0,
            .tx = event_channel.makeSender(),
            .rx = channel.makeReceiver(),
        };
    }

    pub fn deinit(self: *Self) void {
        self.base.deinit();
    }

    //;

    fn updateMaxInputs(self: *Self) void {
        self.max_inputs = 0;
        for (self.base.graph.nodes) |node, idx| {
            if (node.in_use) {
                var input_ct = 0;
                var edge_iter = self.base.graph.edgesDirected(idx, .Incoming);
                while (edge_iter.next()) : (input_ct += 1) {}
                if (input_ct > self.max_inputs) {
                    self.max_inputs = input_ct;
                }
            }
        }
    }

    // takes ownership of module
    // TODO handle not found errors? maybe not
    pub fn addModule(self: *Self, module: *Module) !NodeIndex {
        const id = self.base.modules.items.len;
        try self.base.modules.append(.{
            .module = module,
            .buffer = undefined,
        });
        return try self.base.graph.addNode(id);
    }

    pub fn addEdge(
        self: *Self,
        source: NodeIndex,
        target: NodeIndex,
        input_numnber: usize,
    ) !EdgeIndex {
        const edge_idx = try self.base.graph.addEdge(source, target, input_number);
        var input_ct = 0;
        var edge_iter = self.base.graph.edgesDirected(target, .Incoming);
        while (edge_iter.next()) : (input_ct += 1) {}
        if (input_ct > self.max_inputs) {
            self.max_inputs = input_ct;
        }
        return edge_idx;
    }

    // remove by node id
    //   module id is just uzsed internally
    pub fn removeModule(self: *Self, node_idx: NodeIndex) void {
        const module_idx = self.base.graph.nodes.items[node_idx].weight;
        self.base.graph.removeNode(node_idx);
        self.removals.append(module_idx);
        self.updateMaxInputs();
    }

    pub fn removeEdge(self: *Self, edge_idx: EdgeIndex) void {
        self.base.graph.removeEdge(edge_idx);
    }

    pub fn setOutput(self: *Self, node_idx: NodeIndex) void {
        self.base.output = node_idx;
    }

    pub fn pushChanges(
        self: Self,
        now: u64,
        workspace_allocator: *Allocator,
    ) !void {
        self.base.sort(workspace_allocator);
        self.base.temp_in_bufs.ensureCapacity(self.max_inputs);
        // TODO you have to clone here
        // this send here takes ownership
        // actual AudioGraphBase the controller started with is never sent to the other thread
        //   can be deinited normally when controller is deinited
        self.tx.send(now, self.base.clone());
    }

    pub fn frame(self: *Self) void {
        if (self.rx.tryRecv()) |*swap| {
            for (swap.removals.items) |module_idx| {
                swap.modules.items[module_idx].deinit();
                swap.modules.orderedRemove(module_idx);
            }
            // ??
            // TODO deinit and free and stuff
            // swap.deinit();
        }
    }
};
