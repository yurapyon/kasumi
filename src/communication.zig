const std = @import("std");
const debug = std.debug;

const Error = error{
    OutOfSpace,
    Empty,
};

/// SPSC, lock-free push and pop
/// allocation free, doesnt own data
pub fn Queue(comptime T: type) type {
    return struct {
        const Self = @This();

        data: []T,
        write_pt: usize,
        read_pt: usize,

        fn next_idx(self: Self, idx: usize) usize {
            return (idx + 1) % self.data.len;
        }

        pub fn init(data: []T) Self {
            return .{
                .data = data,
                .write_pt = 0,
                .read_pt = 0,
            };
        }

        pub fn push(self: *Self, val: T) !void {
            const read_pt = @atomicLoad(@TypeOf(self.read_pt), &self.read_pt, .Monotonic);
            if (read_pt == self.next_idx(self.write_pt)) {
                return error.OutOfSpace;
            }
            self.data[self.write_pt] = val;
            @fence(.SeqCst);
            self.write_pt = self.next_idx(self.write_pt);
        }

        pub fn pop(self: *Self) !T {
            const write_pt = @atomicLoad(@TypeOf(self.write_pt), &self.write_pt, .Monotonic);
            if (write_pt == self.read_pt) {
                return error.Empty;
            }
            const ret = self.data[self.read_pt];
            @fence(.SeqCst);
            self.read_pt = self.next_idx(self.read_pt);
            return ret;
        }
    };
}

/// MPSC, lock-free pop, uses spin lock to protect pushes
/// allocation free, doesnt own data
pub fn Channel(comptime T: type) type {
    return struct {
        const Self = @This();

        pub const Receiver = struct {
            channel: *Self,

            pub fn tryRecv(self: *Receiver) ?T {
                return self.channel.pop() catch null;
            }
        };

        pub const Sender = struct {
            channel: *Self,

            pub fn send(self: *Sender, val: T) !void {
                return self.channel.push(val);
            }
        };

        // TODO Receiver
        // TODO Sender

        queue: Queue(T),
        write_lock: bool,

        pub fn init(data: []T) Self {
            return .{
                .write_lock = false,
                .queue = Queue(T).init(data),
            };
        }

        pub fn push(self: *Self, val: T) !void {
            while (@atomicRmw(@TypeOf(self.write_lock), &self.write_lock, .Xchg, true, .SeqCst)) {}
            defer debug.assert(@atomicRmw(@TypeOf(self.write_lock), &self.write_lock, .Xchg, false, .SeqCst));
            return self.queue.push(val);
        }

        pub fn pop(self: *Self) !T {
            return self.queue.pop();
        }
    };
}

/// MPSC, lock-free pop, uses spin lock to protect pushes
/// allocation free, doesnt own data
/// timed-stamped messages
pub fn EventChannel(comptime T: type) type {
    return struct {
        const Self = @This();

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

        pub fn init(events_buffer: []Event) Self {
            return .{ .channel = Channel(Event).init(events_buffer) };
        }

        pub fn makeSender(self: *Self) Sender {
            return .{ .event_channel = self };
        }

        pub fn makeReceiver(self: *Self) Receiver {
            return .{
                .event_channel = self,
                .last_event = null,
            };
        }
    };
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

// tests ===

test "Queue: push pop" {
    const expect = std.testing.expect;

    var buf: [15]u8 = undefined;
    var q = Queue(u8).init(&buf);
    try q.push(1);
    try q.push(2);
    try q.push(3);

    expect((try q.pop()) == 1);
    expect((try q.pop()) == 2);
    expect((try q.pop()) == 3);
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

test "Timer" {
    const expect = std.testing.expect;

    var tm = Timer.start();
    const first = tm.now();

    expect(tm.now() > first);
    expect(tm.now() > first);
    expect(tm.now() > first);
}
