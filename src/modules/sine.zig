const std = @import("std");

const CallbackContext = @import("../system.zig").CallbackContext;
usingnamespace @import("../module.zig");

const PI = 3.1415927;

pub const Sine = struct {
    const Self = @This();

    module: Module = .{
        .compute = compute,
    },

    frame_ct: u32,
    move_ct: u32,

    move_freq: f32,
    freq: f32,

    pub fn init(move_freq: f32, freq: f32) Self {
        return Self{
            .frame_ct = 0,
            .move_ct = 0,
            .move_freq = move_freq,
            .freq = freq,
        };
    }

    fn compute(
        module: *Module,
        ctx: *const CallbackContext,
        _inputs: []const InputBuffer,
        output: []f32,
    ) void {
        var self = @fieldParentPtr(Self, "module", module);

        const srate_f = @intToFloat(f32, ctx.sample_rate);
        const period_base = PI * 2. / srate_f;

        var ct: usize = 0;
        while (ct < output.len) : (ct += 2) {
            const move_f = @intToFloat(f32, self.move_ct);
            const move_amt = std.math.sin(move_f * self.move_freq * period_base);

            const frame_f = @intToFloat(f32, self.frame_ct);
            const period = frame_f * (self.freq + move_amt * 100.) * period_base;

            const s = std.math.sin(period) * 0.5;
            output[ct] = s;
            output[ct + 1] = s;
            self.frame_ct += 1;
            if (self.frame_ct > ctx.sample_rate) {
                std.log.info("{}", .{std.math.sin(period)});
                self.frame_ct = 0;
            }
            self.move_ct += 1;
            if (self.move_ct > ctx.sample_rate) {
                self.move_ct = 0;
            }
        }
    }
};
