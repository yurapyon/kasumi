const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const communication = @import("communication.zig");
const graph = @import("graph.zig");
const module = @import("module.zig");
const system = @import("system.zig");

const Channel = communication.Channel;
const EventChannel = communication.EventChannel;

const Graph = graph.Graph;

const Module = module.Module;

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

pub const Swap = struct {
    //;
};

pub const ControlledAudioGraph = struct {
    const Self = @This();

    graph: AudioGraph,
    tx: Channel.Sender(Swap),
    rx: EventChannel.Receiver(Swap),
};

pub const AudioGraphController = struct {
    const Self = @This();

    base: AudioGraphBase,
    tx: EventChannel.Sender(Swap),
    rx: Channel.Receiver(Swap),

    pub fn init(allocator: *Allocator) Self {
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
