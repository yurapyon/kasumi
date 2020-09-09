const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const audio_graph = @import("audio_graph.zig");

//;

pub const generators = struct {
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

const SampleBuffer = struct {
    const Self = @This();

    data: ArrayList(f32),
    sample_rate: u32,
    channel_ct: u8,

    pub fn init(
        allocator: *Allocator,
        sample_rate: u32,
        channel_ct: u8,
    ) Self {
        return .{
            .data = ArrayList(f32).init(allocator),
            .sample_rate = sample_rate,
            .channel_ct = channel_ct,
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
        };
    }

    pub fn initWav(allocator: *Allocator, wav_file: []u8) Self {}

    pub fn deinit(self: *Self) void {
        self.data.deinit();
    }
};
