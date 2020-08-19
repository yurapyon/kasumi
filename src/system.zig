const std = @import("std");

const c = @import("c.zig");

const InitError = error{CouldntInitPortAudio};

pub fn init() !void {
    const err = c.Pa_Initialize();
    if (err != c.paNoError) {
        return error.CouldntInitPortAudio;
    }
}

pub fn deinit() !void {
    const err = c.Pa_Terminate();
    if (err != c.paNoError) {
        return error.CouldntInitPortAudio;
    }
}

pub fn callback(
    input: ?*const c_void,
    output: ?*c_void,
    frame_ct: c_ulong,
    time_info: [*c]const c.PaStreamCallbackTimeInfo,
    status_flags: c.PaStreamCallbackFlags,
    user_data: ?*c_void,
) callconv(.C) c_int {
    var out_ptr = @ptrCast([*]f32, @alignCast(4, output));
    var out_slice = out_ptr[0..frame_ct];

    for (out_slice) |*blah| {
        blah.* = 0.;
    }

    std.debug.warn("hi {}\n", .{frame_ct});
    return 0;
}

const Graph = @import("graph.zig").Graph;

const AudioGraph = Graph(usize, usize);

pub const System = struct {
    const Self = @This();

    stream: *c.PaStream,
    graph: AudioGraph,

    pub fn init(allocator: *std.mem.Allocator) !Self {
        var stream: ?*c.PaStream = null;
        var output_params = c.PaStreamParameters{
            .channelCount = 2,
            .device = 5,
            .hostApiSpecificStreamInfo = null,
            // .sampleFormat = c.paFloat32,
            .sampleFormat = 1,
            .suggestedLatency = 0.25,
        };
        const err = c.Pa_OpenStream(
            &stream,
            null,
            &output_params,
            44100.0,
            c.paFramesPerBufferUnspecified,
            // c.paNoFlag,
            0,
            callback,
            null,
        );
        // _ = c.Pa_StartStream(stream);

        var graph = AudioGraph.init(allocator);

        const n1 = try graph.add_node(0);
        const n2 = try graph.add_node(1);
        const n3 = try graph.add_node(2);

        const e1 = try graph.add_edge(n1, n2, 1);
        const e2 = try graph.add_edge(n2, n3, 2);
        const e3 = try graph.add_edge(n1, n3, 3);

        std.log.info("{} {}", .{
            graph.edges.items.len,
            graph.nodes.items.len,
        });

        var iter = graph.edges_directed(n1, true);
        while (iter.next()) |edge_idx| {
            std.log.info("edge_idx {}", .{edge_idx});
        }

        return Self{
            .stream = stream.?,
            .graph = graph,
        };
    }
};
