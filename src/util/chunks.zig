const std = @import("std");
const math = std.math;

pub fn ChunkIterator(comptime T: type) type {
    return struct {
        const Self = @This();

        buffer: []T,
        chunk_ct: usize,
        chunk_sz: usize,

        pub fn init(buffer: []T, chunk_sz: usize) Self {
            // todo panic on chunk_sz == 0
            return .{
                .buffer = buffer,
                .chunk_ct = 0,
                .chunk_sz = chunk_sz,
            };
        }

        pub fn next(self: *Self) ?[]T {
            if (self.chunk_ct * self.chunk_sz >= self.buffer.len) {
                return null;
            } else {
                const start = self.chunk_ct * self.chunk_sz;
                const end = math.min(start + self.chunk_sz, self.buffer.len);
                self.chunk_ct += 1;
                return self.buffer[start..end];
            }
        }
    };
}

// tests ===

const testing = std.testing;
const expect = testing.expect;

test "chunks" {
    var hello: [5]u8 = .{ 'h', 'e', 'l', 'l', 'o' };

    {
        var chunks = ChunkIterator(u8).init(&hello, 2);
        expect(std.mem.eql(u8, chunks.next().?, "he"));
        expect(std.mem.eql(u8, chunks.next().?, "ll"));
        expect(std.mem.eql(u8, chunks.next().?, "o"));
        expect(chunks.next() == null);
    }

    {
        var chunks = ChunkIterator(u8).init(&hello, 6);
        expect(std.mem.eql(u8, chunks.next().?, "hello"));
        expect(chunks.next() == null);
    }

    {
        var chunks = ChunkIterator(u8).init(&hello, 5);
        expect(std.mem.eql(u8, chunks.next().?, "hello"));
        expect(chunks.next() == null);
    }
}
