const std = @import("std");

const interface = @import("nitori").interface;
const Module = @import("../module.zig").Module;

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
        ctx: Module.ComputeContext,
    ) void {
        var found: ?[]const f32 = null;
        for (ctx.inputs) |input| {
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
                ctx.output[ct] = input[ct] * mod_l;
                ctx.output[ct + 1] = input[ct + 1] * mod_r;
            }
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

    fn module_compute(m: Module, ctx: Module.ComputeContext) void {
        m.impl.cast(Self).compute(ctx);
    }

    //;

    pub const Message = union(enum) {
        setVolume: f32,
        setPan: f32,
    };

    pub fn takeMessage(self: *Self, msg: Message) void {
        switch (msg) {
            .setVolume => |to| {
                self.volume = to;
            },
            .setPan => |to| self.pan = to,
        }
    }
};
