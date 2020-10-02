const std = @import("std");

const interface = @import("nitori").interface;
const Module = @import("../module.zig").Module;

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
        ctx: Module.ComputeContext,
    ) void {
        const srate_f = @intToFloat(f32, ctx.sample_rate);
        const period_base = std.math.tau / srate_f;

        var ct: usize = 0;
        while (ct < ctx.frame_len) : (ct += 2) {
            const frame_f = @intToFloat(f32, self.frame_ct);
            const period = frame_f * self.freq * period_base;

            const s = std.math.sin(period) * 0.5;
            ctx.output[ct] = s;
            ctx.output[ct + 1] = s;
            self.frame_ct += 1;
        }
    }

    // module

    pub fn module(self: *Self) Module {
        return .{
            .impl = interface.Impl.init(self),
            .vtable = &comptime Module.VTable{
                .compute = module_compute,
            },
        };
    }

    pub fn module_compute(
        m: Module,
        ctx: Module.ComputeContext,
    ) void {
        m.impl.cast(Self).compute(ctx);
    }

    //;

    pub const Message = union(enum) {
        setFreq: f32,
    };

    pub fn takeMessage(self: *Self, msg: Message) void {
        switch (msg) {
            .setFreq => |to| self.freq = to,
        }
    }
};
