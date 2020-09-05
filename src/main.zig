const std = @import("std");

const audio_graph = @import("audio_graph.zig");
const system = @import("system.zig");
const module = @import("module.zig");

const Sine = @import("modules/sine.zig").Sine;

pub fn main() anyerror!void {}

test "main" {
    var sys: system.System = undefined;
    try sys.init(.{
        .allocator = std.testing.allocator,
        .device_number = 5,
    });

    var sine = Sine.init(440.);

    var graph_ctl = &sys.controller;
    const sine_idx = try graph_ctl.addModule(module.Module.init(&sine));
    graph_ctl.setOutput(sine_idx);
    try graph_ctl.pushChanges(0, std.testing.allocator);

    defer sys.deinit();

    while (true) {}
}
