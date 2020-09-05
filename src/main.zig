const std = @import("std");

const audio_graph = @import("audio_graph.zig");
const system = @import("system.zig");
const module = @import("module.zig");
const modules = module.modules;

const Utility = modules.Utility;

pub fn main() anyerror!void {}

fn vol1(util: *Utility) void {
    util.volume = 1.;
}

fn vol0(util: *Utility) void {
    util.volume = 0.;
}

test "main" {
    var sys: system.System = undefined;
    try sys.init(.{
        .allocator = std.testing.allocator,
        .suggested_latency = 0.15,
        .device_number = 5,
    });
    defer sys.deinit();

    var sine = modules.Sine.init(440.);
    var util = modules.Utility.init();

    var util_ctl: module.Controlled(Utility) = undefined;
    try util_ctl.init(&util, std.testing.allocator, 10);

    var util_ctlr = util_ctl.makeController();

    var graph_ctl = &sys.controller;

    const sine_idx = try graph_ctl.addModule(module.Module.init(&sine));
    const util_idx = try graph_ctl.addModule(module.Module.init(&util_ctl));

    _ = try graph_ctl.addEdge(sine_idx, util_idx, 0);
    graph_ctl.setOutput(util_idx);

    try graph_ctl.pushChanges(0, std.testing.allocator);

    var in = std.io.getStdIn();
    var buf = [_]u8{0};
    while (buf[0] != 'q') {
        _ = try in.read(&buf);
        try util_ctlr.send(0, vol0);
        graph_ctl.frame();

        _ = try in.read(&buf);
        try util_ctlr.send(0, vol1);
        graph_ctl.frame();
    }
}
