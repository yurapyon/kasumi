const std = @import("std");

const c = @import("c.zig");
const system = @import("system.zig");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub fn main() anyerror!void {
    try system.init();
    var blah = system.System.init(&gpa.allocator);
    while (true) {}
    try system.deinit();
}
