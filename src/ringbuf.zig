const std = @import("std");
const assert = std.debug.assert;

const Error = error{
    OutOfSpace,
    Empty,
};

/// SPSC, lock-free push and pop
/// allocation free, doesnt own data
pub fn RingBuffer(comptime T: type) type {
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

        buf: RingBuffer(T),
        write_lock: bool,

        pub fn init(data: []T) Self {
            return .{
                .write_lock = false,
                .buf = RingBuffer(T).init(data),
            };
        }

        pub fn push(self: *Self, val: T) !void {
            while (@atomicRmw(@TypeOf(self.write_lock), &self.write_lock, .Xchg, true, .SeqCst)) {}
            defer assert(@atomicRmw(@TypeOf(self.write_lock), &self.write_lock, .Xchg, false, .SeqCst));
            return self.buf.push(val);
        }

        pub fn pop(self: *Self) !T {
            return self.buf.pop();
        }
    };
}

test "push pop" {
    const expect = std.testing.expect;

    var buf: [15]u8 = undefined;
    var rb = RingBuffer(u8).init(&buf);
    try rb.push(1);
    try rb.push(2);
    try rb.push(3);

    expect((try rb.pop()) == 1);
    expect((try rb.pop()) == 2);
    expect((try rb.pop()) == 3);
}
