const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const audio_graph = @import("audio_graph.zig");
const wav = @import("wav.zig");

//;

pub const generators = struct {
    // TODO test this

    // more generators, sine, tri, square, noise

    // generates one period of a sine to the output slice
    pub fn genSine(out: []f32) void {
        const step = std.math.tau / @intToFloat(f32, out);

        var i: usize = 0;
        while (i < out.len) : (i += 1) {
            out[i] = std.math.sine(i * step);
        }
    }
};

//;

// TODO frame_ct ?
pub const SampleBuffer = struct {
    const Self = @This();

    // TODO arraylist?
    data: ArrayList(f32),
    sample_rate: u32,
    channel_ct: u8,
    frame_ct: u32,

    // TODO have this?
    pub fn init(
        allocator: *Allocator,
        sample_rate: u32,
        channel_ct: u8,
    ) Self {
        return .{
            .data = ArrayList(f32).init(allocator),
            .sample_rate = sample_rate,
            .channel_ct = channel_ct,
            .frame_ct = 0,
        };
    }

    pub fn initBuffer(
        allocator: *Allocator,
        sample_rate: u32,
        channel_ct: u8,
        buf: []f32,
    ) Self {
        return .{
            .data = ArrayList(f32).fromOwnedSlice(allocator, buf),
            .sample_rate = sample_rate,
            .channel_ct = channel_ct,
            .frame_ct = buf.len / channel_ct,
        };
    }

    // TODO take workspace alloc
    pub fn initWav(allocator: *Allocator, wav_file: []const u8) !Self {
        var reader = std.io.fixedBufferStream(wav_file).reader();
        const Loader = wav.Loader(@TypeOf(reader), true);
        const header = try Loader.readHeader(&reader);

        // TODO
        // if channel ct is not 1 or 2, error
        // if sample rate not supported

        var data = try allocator.alloc(f32, header.channel_ct * header.frame_ct);
        errdefer allocator.free(data);

        try Loader.loadConvert_F32(&reader, header, data, allocator);

        return Self{
            .data = ArrayList(f32).fromOwnedSlice(allocator, data),
            .sample_rate = header.sample_rate,
            .channel_ct = @intCast(u8, header.channel_ct),
            .frame_ct = header.frame_ct,
        };
    }

    pub fn deinit(self: *Self) void {
        self.data.deinit();
    }
};

// tests ==

test "load file" {
    const file = @embedFile("../content/square.wav");
    var sb = try SampleBuffer.initWav(std.testing.allocator, file);
    defer sb.deinit();
}
