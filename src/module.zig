const std = @import("std");
const Allocator = std.mem.Allocator;

const nitori = @import("nitori");
const communication = nitori.communication;
const interface = nitori.interface;
const EventChannel = communication.EventChannel;

//;

// TODO maybe have a *const System in the contexts?

pub const modules = struct {
    usingnamespace @import("modules/sine.zig");
    usingnamespace @import("modules/utility.zig");
    // usingnamespace @import("modules/sample_player.zig");
};

//;

pub const Module = struct {
    const Self = @This();

    pub const InBuffer = struct {
        id: usize,
        buf: []const f32,
    };

    pub const FrameContext = struct {
        now: u64,
    };

    pub const ComputeContext = struct {
        sample_rate: u32,
        frame_len: usize,
        inputs: []const InBuffer,
        output: []f32,
    };

    pub const VTable = struct {
        frame: fn (Self, FrameContext) void = _frame,
        compute: fn (Self, ComputeContext) void,

        pub fn _frame(module: Self, _ctx: FrameContext) void {}
    };

    impl: interface.Impl,
    vtable: *const VTable,
};

pub fn Controlled(comptime T: type) type {
    return struct {
        const Self = @This();
        const MsgChannel = EventChannel(T.Message);

        pub const Controller = struct {
            tx: MsgChannel.Sender,

            pub fn send(self: *Controller, now: u64, msg: T.Message) MsgChannel.Error!void {
                return self.tx.send(now, msg);
            }
        };

        inner: *T,
        channel: MsgChannel,
        rx: MsgChannel.Receiver,

        pub fn init(
            self: *Self,
            allocator: *Allocator,
            message_ct: usize,
            inner: *T,
        ) Allocator.Error!void {
            self.inner = inner;
            self.channel = try MsgChannel.init(allocator, message_ct);
            self.rx = self.channel.makeReceiver();
        }

        pub fn deinit(self: *Self) void {
            self.channel.deinit();
        }

        pub fn makeController(self: *Self) Controller {
            return Controller{
                .tx = self.channel.makeSender(),
            };
        }

        //;

        pub fn module(self: *Self) Module {
            return .{
                .impl = interface.Impl.init(self),
                .vtable = &comptime Module.VTable{
                    .frame = frame,
                    .compute = compute,
                },
            };
        }

        pub fn frame(m: Module, ctx: Module.FrameContext) void {
            var self = m.impl.cast(Self);
            while (self.rx.tryRecv(ctx.now)) |event| {
                self.inner.takeMessage(event.data);
            }
            if (@hasDecl(T, "frame")) {
                self.inner.frame(ctx);
            }
        }

        pub fn compute(m: Module, ctx: Module.ComputeContext) void {
            var self = m.impl.cast(Self);
            if (@hasDecl(T, "compute")) {
                self.inner.compute(ctx);
            }
        }
    };
}
