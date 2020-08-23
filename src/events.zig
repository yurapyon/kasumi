const std = @import("std");

const Channel = @import("ringbuf.zig").Channel;

pub fn EventChannel(comptime T: type) type {
    return struct {
        pub const Event = struct {
            timestamp: u64,
            data: T,
        };

        pub const Receiver = struct {
            event_channel: *EventChannel(T),
            last_event: ?Event,

            pub fn tryRecv(self: *Receiver, now: u64) ?Event {
                if (self.last_event) |ev| {
                    if (ev.timestamp <= now) {
                        // const ret = ev;
                        // self.last_event = null;
                        // return ret;
                        self.last_event = null;
                        return ev;
                    } else {
                        return null;
                    }
                } else {
                    const get = self.event_channel.channel.pop() catch {
                        return null;
                    };

                    if (get.timestamp <= now) {
                        return get;
                    } else {
                        self.last_event = get;
                        return null;
                    }
                }
            }
        };

        pub const Sender = struct {
            event_channel: *EventChannel(T),

            pub fn send(self: *Sender, timestamp: u64, data: T) !void {
                // TODO make sure this timestamp isnt before the last one pushed
                // invalid timestamp error
                return self.event_channel.channel.push(.{
                    .timestamp = timestamp,
                    .data = data,
                });
            }
        };

        channel: Channel(Event),

        pub fn init(events_buffer: []Event) EventChannel(T) {
            return .{ .channel = Channel(Event).init(events_buffer) };
        }

        pub fn makeSender(self: *EventChannel(T)) Sender {
            return .{ .event_channel = self };
        }

        pub fn makeReceiver(self: *EventChannel(T)) Receiver {
            return .{
                .event_channel = self,
                .last_event = null,
            };
        }
    };
}

test "EventChannel: send recv" {
    const expect = std.testing.expect;

    const EnvChan = EventChannel(u8);

    var buf: [50]EnvChan.Event = undefined;
    var chan = EnvChan.init(&buf);
    var send = chan.makeSender();
    var recv = chan.makeReceiver();

    var tm = Timer.start();

    try send.send(tm.now(), 0);
    try send.send(tm.now(), 1);
    try send.send(tm.now(), 2);

    expect(recv.tryRecv(tm.now()).?.data == 0);
    expect(recv.tryRecv(tm.now()).?.data == 1);
    expect(recv.tryRecv(tm.now()).?.data == 2);

    const time = tm.now();

    try send.send(time, 0);
    try send.send(time + 10, 1);
    try send.send(time + 20, 2);

    expect(recv.tryRecv(time).?.data == 0);
    expect(recv.tryRecv(time) == null);
    expect(recv.tryRecv(time + 9) == null);
    expect(recv.tryRecv(time + 10).?.data == 1);
    expect(recv.tryRecv(time + 15) == null);
    expect(recv.tryRecv(time + 25).?.data == 2);
}

pub const Timer = struct {
    const Self = @This();

    tm: std.time.Timer,
    last_now: u64,

    pub fn start() Self {
        return .{
            .tm = std.time.Timer.start() catch unreachable,
            .last_now = 0,
        };
    }

    pub fn now(self: *Self) u64 {
        const time = self.tm.read();
        _ = @atomicRmw(@TypeOf(self.last_now), &self.last_now, .Max, time, .Monotonic);
        return self.last_now;
    }
};

test "timer" {
    const expect = std.testing.expect;

    var tm = Timer.start();
    const first = tm.now();

    expect(tm.now() > first);
    expect(tm.now() > first);
    expect(tm.now() > first);
}
