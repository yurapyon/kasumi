const std = @import("std");

const nitori = @import("nitori");
const vtable = nitori.vtable;

const audio_graph = @import("audio_graph.zig");
const InBuffer = audio_graph.InBuffer;
const Sample = audio_graph.Sample;

const system = @import("system.zig");
const CallbackContext = system.CallbackContext;

//;

pub const Module = struct {
    const Self = @This();

    const VTable = struct {
        pub const Impl = @Type(.Opaque);

        frame: ?fn (*Impl, CallbackContext) void,
        compute: fn (
            *Impl,
            CallbackContext,
            []const InBuffer,
            []Sample,
        ) void,

        pub fn frame(_module: *Impl, _ctx: CallbackContext) void {}
    };

    vtable: *const VTable,
    impl: *VTable.Impl,

    pub fn init(module: anytype) Self {
        return .{
            .vtable = comptime vtable.populate(VTable, @TypeOf(module).Child),
            .impl = @ptrCast(*VTable.Impl, module),
        };
    }

    pub fn frame(self: *Self, ctx: CallbackContext) void {
        self.vtable.frame.?(self.impl, ctx);
    }

    pub fn compute(
        self: *Self,
        ctx: CallbackContext,
        in_buffers: []const InBuffer,
        out_buffer: []Sample,
    ) void {
        self.vtable.compute(self.impl, ctx, in_buffers, out_buffer);
    }
};
