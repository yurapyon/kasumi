const std = @import("std");

const audio_graph = @import("audio_graph.zig");
const system = @import("system.zig");

pub fn main() anyerror!void {
    var graph = audio_graph.AudioGraph.init();

    var sys = system.System.init();
    defer sys.deinit();

    while (true) {}
}
