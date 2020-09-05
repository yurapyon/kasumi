const std = @import("std");

usingnamespace @import("../module.zig").prelude;

//;

pub const Sine = struct {
    const Self = @This();

    frame_ct: u32,
    freq: f32,

    pub fn init(freq: f32) Self {
        return .{
            .frame_ct = 0,
            .freq = freq,
        };
    }

    pub fn compute(
        self: *Self,
        ctx: CallbackContext,
        _inputs: []const InBuffer,
        output: []Sample,
    ) void {
        const srate_f = @intToFloat(f32, ctx.sample_rate);
        const period_base = std.math.tau / srate_f;

        var ct: usize = 0;
        while (ct < ctx.frame_len) : (ct += 2) {
            const frame_f = @intToFloat(f32, self.frame_ct);
            const period = frame_f * self.freq * period_base;

            const s = std.math.sin(period) * 0.5;
            output[ct] = s;
            output[ct + 1] = s;
            self.frame_ct += 1;
        }
    }
};
