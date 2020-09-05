const std = @import("std");
const Allocator = std.mem.Allocator;

const nitori = @import("nitori");
const communication = nitori.communication;
const Channel = communication.Channel;
const EventChannel = communication.EventChannel;
const ChunkIterator = nitori.chunks.ChunkIterator;

const audio_graph = @import("audio_graph.zig");
usingnamespace audio_graph;

const c = @import("c.zig");

const module = @import("module.zig");
const Module = module.Module;

//;

pub const CallbackContext = struct {
    sample_rate: u32,
    frame_len: usize,
    now: u64,
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

    var graph = @ptrCast(*AudioGraph, @alignCast(@alignOf(AudioGraph), userdata));

    var ctx = CallbackContext{
        // TODO
        .sample_rate = 44100,
        .frame_len = out_slice.len,
        // TODO
        .now = 0,
    };

    graph.frame(ctx);

    var chunks = ChunkIterator(Sample).init(out_slice, audio_graph.max_callback_len);
    while (chunks.next()) |chunk| {
        ctx.frame_len = chunk.len;
        graph.compute(ctx, chunk);
    }

    return 0;
}

// TODO theres probably a way to use a single event channel
//   might have to be mpmc? idk
//   for just doing swaps idk

pub const System = struct {
    pub const Settings = struct {
        allocator: *Allocator,
        device_number: u8,
        channel_size: usize = 50,
        suggested_latency: f32 = 1.,
        sample_rate: u32 = 44100,
    };

    const Self = @This();

    settings: Settings,

    stream: *c.PaStream,
    graph: AudioGraph,
    controller: Controller,

    channel: Channel(AudioGraphBase),
    event_channel: EventChannel(AudioGraphBase),

    pub fn queryDeviceNames(allocator: *Allocator) void {}

    pub fn init(self: *Self, settings: Settings) !void {
        const allocator = settings.allocator;

        self.settings = settings;

        self.channel = try Channel(AudioGraphBase).init(allocator, settings.channel_size);
        self.event_channel = try EventChannel(AudioGraphBase).init(allocator, settings.channel_size);

        self.graph = AudioGraph.init(allocator, &self.channel, &self.event_channel);
        self.controller = Controller.init(allocator, &self.channel, &self.event_channel);

        var err = c.Pa_Initialize();
        if (err != c.paNoError) {
            return error.CouldntInitPortAudio;
        }
        errdefer c.Pa_Terminate();

        var stream: ?*c.PaStream = null;
        var output_params = c.PaStreamParameters{
            .channelCount = 2,
            .device = settings.device_number,
            .hostApiSpecificStreamInfo = null,
            .sampleFormat = c.paFloat32,
            .suggestedLatency = settings.suggested_latency,
        };
        err = c.Pa_OpenStream(
            &stream,
            null,
            &output_params,
            @intToFloat(f32, settings.sample_rate),
            c.paFramesPerBufferUnspecified,
            c.paNoFlag,
            callback,
            &self.graph,
        );
        // check err
        // errdefer close stream

        _ = c.Pa_StartStream(stream);

        self.stream = stream.?;
    }

    pub fn deinit() void {
        // stop stream
        // close stream
        c.Pa_Terminate();
    }
};
