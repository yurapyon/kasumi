const std = @import("std");

usingnamespace @import("../module.zig").prelude;

//;

pub const Utility = struct {
    const Self = @This();

    volume: f32,
    pan: f32,

    pub fn init() Self {
        return .{
            .volume = 1.,
            .pan = 0.,
        };
    }

    pub fn compute(
        self: *Self,
        ctx: CallbackContext,
        inputs: []const InBuffer,
        output: []Sample,
    ) void {
        var found: ?[]const Sample = null;
        for (inputs) |input| {
            if (input.id == 0) {
                found = input.buf;
            }
        }

        if (found) |input| {
            const pan = self.pan / 2 + 0.5;
            const mod_l = (1 - pan) * self.volume;
            const mod_r = pan * self.volume;

            var ct: usize = 0;
            while (ct < ctx.frame_len) : (ct += 2) {
                output[ct] = input[ct] * mod_l;
                output[ct + 1] = input[ct + 1] * mod_r;
            }
        }
    }
};
