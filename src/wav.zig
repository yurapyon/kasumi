// adapted from 'https://github.com/dbandstra/zig-wav'

// for more info see: 'http://soundfile.sapp.org/doc/WaveFormat/'

const builtin = @import("builtin");

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

pub const Format = enum {
    U8,
    I16le,
    I24le,
    I32le,
};

pub const Header = struct {
    format: Format,
    channel_ct: u16,
    sample_rate: u32,
    frame_ct: u32,
    byte_ct: u32,
};

// TODO change this api, big rewrite
// have loader be an obj that has a reader and verbose boolean

// parameterized namespace thing
//   not a generic struct
pub fn Loader(comptime Reader: type, comptime verbose: bool) type {
    return struct {
        fn readIdentifier(reader: *Reader) ![4]u8 {
            var ret: [4]u8 = undefined;
            try reader.readNoEof(&ret);
            return ret;
        }

        fn loaderError(comptime msg: []const u8) !Header {
            if (verbose) {
                std.debug.warn("{}\n", .{msg});
            }
            return error.WavLoadFailed;
        }

        pub fn readHeader(reader: *Reader) !Header {
            const chunk_id = try readIdentifier(reader);
            if (!std.mem.eql(u8, &chunk_id, "RIFF")) {
                return loaderError("missing \"RIFF\" header");
            }

            try reader.skipBytes(4, .{});

            const format_id = try readIdentifier(reader);
            if (!std.mem.eql(u8, &format_id, "WAVE")) {
                return loaderError("missing \"WAVE\" identifier");
            }

            const subchunk1_id = try readIdentifier(reader);
            if (!std.mem.eql(u8, &subchunk1_id, "fmt ")) {
                return loaderError("missing \"fmt \" header");
            }

            const subchunk1_size = try reader.readIntLittle(u32);
            if (subchunk1_size != 16) {
                return loaderError("not PCM (subchunk1_size != 16)");
            }

            const audio_format = try reader.readIntLittle(u16);
            if (audio_format != 1) {
                return loaderError("not integer PCM (audio_format != 1)");
            }

            const channel_ct = try reader.readIntLittle(u16);
            const sample_rate = try reader.readIntLittle(u32);
            const byte_rate = try reader.readIntLittle(u32);
            const block_align = try reader.readIntLittle(u16);
            const bits_per_sample = try reader.readIntLittle(u16);

            const format: Format = switch (bits_per_sample) {
                8 => .U8,
                16 => .I16le,
                24 => .I24le,
                32 => .I32le,
                else => return loaderError("invalid bits per sample"),
            };

            const bytes_per_sample = bits_per_sample / 8;

            if (byte_rate != sample_rate * channel_ct * bytes_per_sample) {
                return loaderError("invalid byte_rate");
            }

            if (block_align != channel_ct * bytes_per_sample) {
                return loaderError("invalid block_align");
            }

            const subchunk2_id = try readIdentifier(reader);
            if (!std.mem.eql(u8, &subchunk2_id, "data")) {
                return loaderError("missing \"data\" header");
            }

            const subchunk2_size = try reader.readIntLittle(u32);
            if ((subchunk2_size % (channel_ct * bytes_per_sample)) != 0) {
                return loaderError("invalid subchunk2_size");
            }

            const frame_ct = subchunk2_size / (channel_ct * bytes_per_sample);

            return Header{
                .format = format,
                .sample_rate = sample_rate,
                .channel_ct = channel_ct,
                .frame_ct = frame_ct,
                .byte_ct = subchunk2_size,
            };
        }

        fn loadRaw(reader: *Reader, header: Header, out: []u8) !void {
            // TODO maybe these lens should be exactly equal?
            assert(out.len >= header.byte_ct);
            try reader.readNoEof(out[0..header.byte_ct]);
        }

        pub fn load_U8(reader: *Reader, header: Header, out: []u8) !void {
            assert(header.format == .U8);
            try loadRaw(reader, header, out);
        }

        pub fn load_I16le(reader: *Reader, header: Header, out: []i16) !void {
            assert(header.format == .I16le);
            var buf: []u8 = undefined;
            buf.ptr = @ptrCast([*]u8, out.ptr);
            buf.len = out.len * 2;
            try loadRaw(reader, header, buf);
            // TODO verify this works
            if (builtin.endian == .Big) {
                var i: usize = 0;
                while (i < buf.len) : (i += 2) {
                    std.mem.swap(u8, &buf[i], &buf[i + 1]);
                }
            }
        }

        // TODO
        // note: for now i24s are i32s
        // pub fn load_I24le(reader: *Reader, header: Header, out: []i32) !void {
        //     assert(header.format == .I24le);
        //     var buf: []u8 = undefined;
        //     buf.ptr = @ptrCast([*]u8, out.ptr);
        //     buf.len = out.len * 4;
        //     try loadRaw(reader, header, buf);
        //     // TODO verify this works
        //     if (builtin.endian == .Big) {
        //         var i: usize = 0;
        //         while (i < buf.len) : (i += 4) {
        //             std.mem.swap(u8, &buf[i], &buf[i + 3]);
        //             std.mem.swap(u8, &buf[i + 1], &buf[i + 2]);
        //         }
        //     }
        // }

        pub fn load_I32le(reader: *Reader, header: Header, out: []i32) !void {
            assert(header.format == .I32le);
            var buf: []u8 = undefined;
            buf.ptr = @ptrCast([*]u8, out.ptr);
            buf.len = out.len * 4;
            try loadRaw(reader, header, buf);
            // TODO verify this works
            if (builtin.endian == .Big) {
                var i: usize = 0;
                while (i < buf.len) : (i += 4) {
                    std.mem.swap(u8, &buf[i], &buf[i + 3]);
                    std.mem.swap(u8, &buf[i + 1], &buf[i + 2]);
                }
            }
        }

        // TODO make this a more generic thing that acts on a buf of [u8] or whatever
        // TODO use the output as scratch space ??
        // note: very sublty clips values of i16 and i32 wavs
        // TODO move workspace alloc to the begining
        pub fn loadConvert_F32(
            reader: *Reader,
            header: Header,
            out: []f32,
            workspace_allocator: *Allocator,
        ) !void {
            assert(out.len >= header.frame_ct * header.channel_ct);
            assert(header.format != .I24le);
            switch (header.format) {
                .U8 => {
                    var buf = try workspace_allocator.alloc(u8, header.byte_ct);
                    defer workspace_allocator.free(buf);

                    try load_U8(reader, header, buf);
                    for (buf) |val, i| {
                        out[i] = @intToFloat(f32, val) /
                            @intToFloat(f32, std.math.maxInt(u8));
                    }
                },
                .I16le => {
                    var buf = try workspace_allocator.alloc(
                        i16,
                        header.frame_ct * header.channel_ct,
                    );
                    defer workspace_allocator.free(buf);

                    try load_I16le(reader, header, buf);
                    for (buf) |val, i| {
                        if (val == std.math.minInt(i16)) {
                            out[i] = -1.;
                            continue;
                        }

                        out[i] = @intToFloat(f32, val) /
                            @intToFloat(f32, std.math.maxInt(i16));
                    }
                },
                .I32le => {
                    var buf = try workspace_allocator.alloc(
                        i32,
                        header.frame_ct * header.channel_ct,
                    );
                    defer workspace_allocator.free(buf);

                    try load_I32le(reader, header, buf);
                    for (buf) |val, i| {
                        if (val == std.math.minInt(i32)) {
                            out[i] = 1.;
                            continue;
                        }

                        out[i] = @intToFloat(f32, val) /
                            @intToFloat(f32, std.math.maxInt(i32));
                    }
                },
                else => unreachable,
            }
        }
    };
}

// TODO Saver

// tests ===

test "wav Loader basic coverage" {
    const null_wav = [_]u8{
        0x52, 0x49, 0x46, 0x46, 0x7C, 0x00, 0x00, 0x00, 0x57, 0x41, 0x56,
        0x45, 0x66, 0x6D, 0x74, 0x20, 0x10, 0x00, 0x00, 0x00, 0x01, 0x00,
        0x01, 0x00, 0x44, 0xAC, 0x00, 0x00, 0x88, 0x58, 0x01, 0x00, 0x02,
        0x00, 0x10, 0x00, 0x64, 0x61, 0x74, 0x61, 0x58, 0x00, 0x00, 0x00,
        0x00, 0x00, 0xFF, 0xFF, 0x02, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0x00,
        0x00, 0xFF, 0xFF, 0x02, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0xFE, 0xFF, 0x01, 0x00, 0x01,
        0x00, 0xFE, 0xFF, 0x03, 0x00, 0xFD, 0xFF, 0x02, 0x00, 0xFF, 0xFF,
        0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0xFF, 0xFF, 0x01, 0x00, 0xFE,
        0xFF, 0x02, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0x01, 0x00, 0xFF, 0xFF,
        0x00, 0x00, 0x01, 0x00, 0xFE, 0xFF, 0x02, 0x00, 0xFF, 0xFF, 0x00,
        0x00, 0x00, 0x00, 0xFF, 0xFF, 0x03, 0x00, 0xFC, 0xFF, 0x03, 0x00,
    };

    var reader = std.io.fixedBufferStream(&null_wav).reader();
    const MyLoader = Loader(@TypeOf(reader), true);
    const header = try MyLoader.readHeader(&reader);

    std.testing.expectEqual(@as(usize, 1), header.channel_ct);
    std.testing.expectEqual(@as(usize, 44100), header.sample_rate);
    std.testing.expectEqual(@as(Format, .I16le), header.format);
    std.testing.expectEqual(@as(usize, 44), header.frame_ct);

    var buffer: [44]i16 = undefined;
    try MyLoader.load_I16le(&reader, header, &buffer);
}

test "wav Loader real file" {
    const file = @embedFile("../content/square.wav");

    var reader = std.io.fixedBufferStream(file).reader();
    const MyLoader = Loader(@TypeOf(reader), true);
    const header = try MyLoader.readHeader(&reader);

    std.testing.expectEqual(@as(usize, 2), header.channel_ct);
    std.testing.expectEqual(@as(usize, 44100), header.sample_rate);
    std.testing.expectEqual(@as(Format, .I16le), header.format);
    std.testing.expectEqual(@as(usize, 168), header.frame_ct);

    // var buffer: [168 * 2]i16 = undefined;
    // try MyLoader.load_I16le(&reader, header, &buffer);

    var fbuf: [168 * 2]f32 = undefined;
    try MyLoader.loadConvert_F32(&reader, header, &fbuf, std.testing.allocator);

    var i: usize = 0;
    while (i < header.frame_ct * header.channel_ct) : (i += 2) {
        // const l = buffer[i];
        // const r = buffer[i + 1];
        const fl = fbuf[i];
        const fr = fbuf[i + 1];
        if (i < 168) {
            // std.testing.expectEqual(@as(i16, std.math.maxInt(i16)), l);
            // std.testing.expectEqual(@as(i16, std.math.minInt(i16)), r);
            std.testing.expectEqual(@as(f32, 1.), fl);
            std.testing.expectEqual(@as(f32, -1.), fr);
        } else {
            // std.testing.expectEqual(@as(i16, std.math.minInt(i16)), l);
            // std.testing.expectEqual(@as(i16, std.math.maxInt(i16)), r);
            std.testing.expectEqual(@as(f32, -1.), fl);
            std.testing.expectEqual(@as(f32, 1.), fr);
        }
    }
}
