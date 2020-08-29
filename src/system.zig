const std = @import("std");

const audio_graph = @import("audio_graph.zig");
const c = @import("c.zig");
const module = @import("module.zig");
const util = @import("util.zig");

const AudioGraph = audio_graph.AudioGraph;
const InBuffer = audio_graph.InBuffer;
const OutBuffer = audio_graph.OutBuffer;
const Sample = audio_graph.Sample;

const Module = module.Module;

const ChunkIterator = util.ChunkIterator;

//;

pub const CallbackContext = struct {
    sample_rate: u32,
    frame_len: usize,
};

//;

pub fn callback(
    input: ?*const c_void,
    output: ?*c_void,
    frame_ct: c_ulong,
    time_info: [*c]const c.PaStreamCallbackTimeInfo,
    status_flags: c.PaStreamCallbackFlags,
    userdata: ?*c_void,
) callconv(.C) c_int {
    var out_ptr = @ptrCast([*]f32, @alignCast(4, output));
    var out_slice = out_ptr[0 .. frame_ct * 2];

    var graph = @ptrCast(*AudioGraph, @alignCast(@alignOf(*AudioGraph), userdata));

    var ctx = CallbackContext{
        .sample_rate = 44100,
        .frame_len = out_slice.len,
    };

    graph.frame(ctx);

    var chunks = ChunkIterator(Sample).init(&out_slice, audio_graph.max_callback_len);
    while (chunks.next()) |chunk| {
        ctx.frame_len = chunk.len;
        graph.compute(ctx, chunk);
    }

    return 0;
}

pub const Context = struct {
    const Self = @This();

    stream: *c.PaStream,

    pub fn init(graph: *AudioGraph) !Self {
        const err = c.Pa_Initialize();
        if (err != c.paNoError) {
            return error.CouldntInitPortAudio;
        }

        var stream: ?*c.PaStream = null;
        var output_params = c.PaStreamParameters{
            .channelCount = 2,
            .device = 5,
            .hostApiSpecificStreamInfo = null,
            .sampleFormat = c.paFloat32,
            .suggestedLatency = 0.5,
        };
        const err = c.Pa_OpenStream(
            &stream,
            null,
            &output_params,
            44100.0,
            c.paFramesPerBufferUnspecified,
            c.paNoFlag,
            callback,
            graph,
        );
        _ = c.Pa_StartStream(stream);

        return Self{
            .stream = stream.?,
        };
    }

    pub fn deinit() void {
        c.Pa_Terminate();
    }
};
