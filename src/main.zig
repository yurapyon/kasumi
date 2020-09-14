const std = @import("std");

const audio_graph = @import("audio_graph.zig");
const system = @import("system.zig");
const module = @import("module.zig");
const modules = module.modules;
const sample_buffer = @import("sample_buffer.zig");

const Utility = modules.Utility;
const SamplePlayer = modules.SamplePlayer;
const SampleBuffer = sample_buffer.SampleBuffer;

pub fn main() anyerror!void {}

test "" {
    _ = audio_graph;
    _ = system;
    _ = module;
    _ = modules;
    _ = sample_buffer;
}

test "main" {
    var sys: system.System = undefined;
    try sys.init(.{
        .allocator = std.testing.allocator,
        .suggested_latency = 0.15,
        .device_number = 5,
    });
    defer sys.deinit();

    var graph_ctl = &sys.controller;

    var play_ctl: module.Controlled(SamplePlayer) = undefined;
    try play_ctl.init(std.testing.allocator, 10, modules.SamplePlayer.init());
    var play_ctlr = play_ctl.makeController();

    var play_idx = try graph_ctl.addModule(module.Module.init(&play_ctl));
    graph_ctl.setOutput(play_idx);

    try graph_ctl.pushChanges(std.testing.allocator, sys.tm.now());

    const file = @embedFile("../content/amen_brother.wav");
    var smp = try SampleBuffer.initWav(std.testing.allocator, file);
    defer smp.deinit();

    try play_ctlr.send(sys.tm.now(), .{ .setSample = &smp });
    try play_ctlr.send(sys.tm.now(), .{ .setPlayRate = 1. });
    try play_ctlr.send(sys.tm.now(), .{ .setPlayPosition = 1000 });
    try play_ctlr.send(sys.tm.now(), .{ .setAntiClick = true });
    try play_ctlr.send(sys.tm.now(), .play);
    try play_ctlr.send(sys.tm.now() + 700000000, .pause);
    try play_ctlr.send(sys.tm.now() + 970000000, .play);
    try play_ctlr.send(sys.tm.now(), .{ .setLoop = true });

    //     var sine = modules.Sine.init(440.);
    //     var util = modules.Utility.init();
    //
    //     var util_ctl: module.Controlled(Utility) = undefined;
    //     try util_ctl.init(&util, std.testing.allocator, 10);
    //
    //     var util_ctlr = util_ctl.makeController();
    //
    //     const sine_idx = try graph_ctl.addModule(module.Module.init(&sine));
    //     const util_idx = try graph_ctl.addModule(module.Module.init(&util_ctl));
    //
    //     _ = try graph_ctl.addEdge(sine_idx, util_idx, 0);
    //     graph_ctl.setOutput(util_idx);

    var in = std.io.getStdIn();
    var buf = [_]u8{ 0, 0, 0 };
    while (buf[0] != 'q') {
        // std.time.sleep(1000000000);
        _ = try in.read(&buf);
        //         try util_ctlr.send(0, vol0);
        //         graph_ctl.frame();
        //
        //         _ = try in.read(&buf);
        //         try util_ctlr.send(0, vol1);
        //         graph_ctl.frame();
    }
}
