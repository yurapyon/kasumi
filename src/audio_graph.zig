const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const nitori = @import("nitori");
const communication = nitori.communication;
const graph = nitori.graph;
const Channel = communication.Channel;
const EventChannel = communication.EventChannel;
const Graph = graph.Graph;

const module = @import("module.zig");
const Module = module.Module;

const system = @import("system.zig");
const CallbackContext = system.CallbackContext;

//;

pub const max_callback_len: usize = 2048;

pub const Sample = f32;

pub const OutBuffer = struct {
    buffer: [max_callback_len]Sample,
};

// TODO move this to module.zig maybe
pub const InBuffer = struct {
    id: usize,
    buf: []const Sample,
};

//;

const AudioGraphBase = struct {
    graph: Graph(usize, usize),
    sort: []graph.NodeIndex,
    output: ?NodeIndex,

    pub fn init(allocator: *Allocator) Self {
        const graph = Graph(usize, usize).init(allocator);
        return .{
            .graph = graph,
            .sort = graph.toposort() catch unreachable,
            .output = null,
        };
    }

    pub fn deinit(self: *Self) void {
        self.graph.deinit();
    }
};

// Audio-thread side audio graph
// nothing should or needs to support reallocation
pub const AudioGraph = struct {
    base: AudioGraphBase,
    modules: []*Module,
    out_bufs: []*OutBuffer,
    temp_in_bufs: []InBuffer,

    fn moduleIdxFromNodeIdx(self: Self, idx: NodeIndex) usize {
        return self.base.graph.nodes.items[idx].weight;
    }

    pub fn frame(self: *Self, ctx: CallbackContext) void {
        for (self.base.sort) |idx| {
            const module_idx = self.moduleIdxFromNodeIdx(idx);
            self.modules[module_idx].frame(ctx);
        }
    }

    pub fn compute(self: *Self, ctx: CallbackContext, out_buf: []Sample) void {
        if (self.base.output) |output_idx| {
            for (self.base.sort) |idx| {
                const module_idx = self.moduleIdxFromNodeIdx(idx);

                var in_bufs_at: usize = 0;
                var edge_iter = self.base.graph.edgesDirected(idx, .Incoming);
                while (edge_iter.next()) |ref| {
                    const in_buf_idx = self.moduleIdxFromNodeIdx(ref.edge.start_node);
                    self.temp_in_bufs[in_bufs_at] = .{
                        .id = ref.edge.weight,
                        .buf = self.out_bufs[in_buf_idx],
                    };
                    in_bufs_at += 1;
                }

                var out_buf = &self.out_bufs[module_idx];
                self.modules[module_idx].compute(ctx, self.temp_in_bufs[0..in_bufs_at], out_buf);
                std.mem.copy(Sample, out_buf, self.out_bufs[output_idx].buffer[0..ctx.frame_len]);
            }
        } else {
            std.mem.set(Sample, out_buf, 0.);
        }
    }
};

// do all allocations in main thread
//   swap out
// but you cant count on modules being copyable ? or something
// idk how to do this now

// the rust version you had to move everything around so modules wouldnt be Clone
//   and you had to have a separate outbuf and modules vec becuase of borrowing rules

// zig doesnt care, you could even put the outbufs in the modules themselves

pub const Swap = struct {
    base: AudioGraphBase,

    new_modules: ArrayList(Module),
    new_out_bufs: ArrayList(OutBuffer),

    //;
};

pub const ControlledAudioGraph = struct {
    const Self = @This();

    graph: AudioGraph,
    tx: Channel.Sender(Swap),
    rx: EventChannel.Receiver(Swap),

    // takes ownership of graph
    pub fn init(
        graph: AudioGraph,
        channel: *Channel,
        event_channel: *EventChannel,
    ) Self {
        return .{
            .graph = graph,
            .tx = channel.makeSender(),
            .rx = event_channel.makeReceiver(),
        };
    }
};

pub const AudioGraphController = struct {
    const Self = @This();

    base: AudioGraphBase,
    tx: EventChannel.Sender(Swap),
    rx: Channel.Receiver(Swap),

    pub fn init(
        base: AudioGraphBase,
        channel: *Channel,
        event_channel: EventChannel,
    ) Self {
        //;
    }

    pub fn deinit(self: *Self) void {
        //;
    }

    // even though these will allocate, maybe dont return errors?
    //  just panic? idk
    pub fn addModule() void {
        //;
    }

    pub fn addEdge() void {
        //;
    }

    pub fn removeModule() void {
        //;
    }

    pub fn removeEdge() void {
        //;
    }

    pub fn setOutput() void {
        //;
    }

    pub fn pushChanges() void {
        //;
    }

    pub fn frame() void {
        // check for any swaps and deallocate the stuff inside
    }
};
