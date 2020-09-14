const std = @import("std");
const Allocator = std.mem.Allocator;

const nitori = @import("nitori");
const vtable = nitori.vtable;
const EventChannel = nitori.communication.EventChannel;

//;

pub const prelude = struct {
    pub const audio_graph = @import("audio_graph.zig");
    pub const InBuffer = audio_graph.InBuffer;

    pub const system = @import("system.zig");
    pub const CallbackContext = system.CallbackContext;
};

pub const modules = struct {
    usingnamespace @import("modules/sine.zig");
    usingnamespace @import("modules/util.zig");
    usingnamespace @import("modules/sample_player.zig");
};

//;

usingnamespace prelude;

pub const Module = struct {
    const Self = @This();

    const VTable = struct {
        pub const Impl = @Type(.Opaque);

        frame: ?fn (*Impl, CallbackContext) void,
        compute: fn (
            *Impl,
            CallbackContext,
            []const InBuffer,
            []f32,
        ) void,
        // TODO should this be a special function specific to modules and not a general deinit?
        deinit: ?fn (*Impl) void,

        pub fn frame(_module: *Impl, _ctx: CallbackContext) void {}
        pub fn deinit(_module: *Impl) void {}
    };

    vtable: *const VTable,
    impl: *VTable.Impl,

    pub fn init(module: anytype) Self {
        return .{
            .vtable = comptime vtable.populate(VTable, @typeInfo(@TypeOf(module)).Pointer.child),
            .impl = @ptrCast(*VTable.Impl, module),
        };
    }

    //;

    // TODO this is a deinit of the inner data, not related to the module instance itself
    pub fn deinit(self: *Self) void {
        self.vtable.deinit.?(self.impl);
    }

    pub fn frame(self: *Self, ctx: CallbackContext) void {
        self.vtable.frame.?(self.impl, ctx);
    }

    pub fn compute(
        self: *Self,
        ctx: CallbackContext,
        in_buffers: []const InBuffer,
        out_buffer: []f32,
    ) void {
        self.vtable.compute(self.impl, ctx, in_buffers, out_buffer);
    }
};

pub fn Controlled(comptime T: type) type {
    return struct {
        const Self = @This();
        const EvChannel = EventChannel(T.Message);

        pub const Controller = struct {
            tx: EvChannel.Sender,

            pub fn send(self: *Controller, now: u64, msg: T.Message) !void {
                return self.tx.send(now, msg);
            }
        };

        inner_module: Module,
        inner: *T,

        channel: EvChannel,
        rx: EvChannel.Receiver,

        pub fn init(self: *Self, inner: *T, allocator: *Allocator, message_ct: usize) !void {
            self.inner_module = Module.init(inner);
            self.inner = inner;
            self.channel = try EvChannel.init(allocator, message_ct);
            self.rx = self.channel.makeReceiver();
        }

        pub fn deinit(self: *Self) void {
            self.channel.deinit();
            self.inner_module.deinit();
        }

        pub fn frame(
            self: *Self,
            ctx: CallbackContext,
        ) void {
            while (self.rx.tryRecv(ctx.now)) |msg| {
                self.inner.takeMessage(ctx, msg.data);
            }
            self.inner_module.frame(ctx);
        }

        pub fn compute(
            self: *Self,
            ctx: CallbackContext,
            inputs: []const InBuffer,
            output: []f32,
        ) void {
            self.inner_module.compute(ctx, inputs, output);
        }

        pub fn makeController(self: *Self) Controller {
            return Controller{
                .tx = self.channel.makeSender(),
            };
        }
    };
}
