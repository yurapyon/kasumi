const std = @import("std");

const audio_graph = @import("audio_graph.zig");
const system = @import("system.zig");
const interface = @import("util.zig").interface;

const InBuffer = audio_graph.InBuffer;
const Sample = audio_graph.Sample;
const CallbackContext = system.CallbackContext;

pub const Module = struct {
    const Self = @This();

    const Interface = struct {
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

    interface: *const Interface,
    impl: *Interface.Impl,

    pub fn init(module: anytype) Self {
        // TODO module must be a pointer
        return .{
            .interface = comptime interface.populate(Interface, @TypeOf(module).Child),
            .impl = @ptrCast(*Interface.Impl, module),
        };
    }

    pub fn frame(self: *Self, ctx: CallbackContext) void {
        self.interface.frame.?(self.impl, ctx);
    }

    pub fn compute(
        self: *Self,
        ctx: CallbackContext,
        in_buffers: []const InBuffer,
        out_buffer: []Sample,
    ) void {
        self.interface.compute(self.impl, ctx, in_buffers, out_buffer);
    }
};

// tests ===

const One = struct {
    x: u8,

    pub fn frame(self: *One, ctx: CallbackContext) void {
        std.log.warn("one frame\n", .{});
    }

    pub fn compute(
        self: *One,
        ctx: CallbackContext,
        in_buffers: []const InBuffer,
        out_buffer: *OutBuffer,
    ) void {
        std.log.warn("one compute\n", .{});
    }
};

const Two = struct {
    x: u8,

    pub fn compute(
        self: *Two,
        ctx: CallbackContext,
        in_buffers: []const InBuffer,
        out_buffer: *OutBuffer,
    ) void {
        std.log.warn("two compute\n", .{});
    }
};

test "module, no defaults" {
    var ctx: CallbackContext = undefined;
    var out_buffer: OutBuffer = undefined;

    var one = One{ .x = 255 };
    var mod = Module.init(&one);
    mod.frame(ctx);
    mod.compute(ctx, &[_]InBuffer{}, &out_buffer);
}

test "module, default" {
    var ctx: CallbackContext = undefined;
    var out_buffer: OutBuffer = undefined;

    var two = Two{ .x = 255 };
    var mod = Module.init(&two);
    mod.frame(ctx);
    mod.compute(ctx, &[_]InBuffer{}, &out_buffer);
}
