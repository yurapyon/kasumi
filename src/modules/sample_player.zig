const std = @import("std");

usingnamespace @import("../module.zig").prelude;

const SampleBuffer = @import("../sample_buffer.zig").SampleBuffer;

//;

// note:
// anti-click is a needless expense if used for a game,
//   so anti-click defaults to be off
//   just, dont stop or play sounds from a point that will click
//         precalculate fadeins and outs in the sampledata itself,
//           or if a change in fading is ever needed, do it deliberately with some other module

// state == .PrePause isnt the same as pause_timer > 0
//   because pause_timer could be positive, then play is pressed afterwards

// pausing is annoying because
//   maybe you want it to happen instantaneously from when its called from the main thread
//   message passing will delay that timing
// maybe just have an atomicPause/Play that atomically pauses it and is thread safe

// TODO note: currently playrate changes click length
//        "okay" for down pitch, not okay for up pitch, might be skipping frames

pub const SamplePlayer = struct {
    const Self = @This();

    pub const Message = union(enum) {
        play,
        pause,
        stop,
        setLoop: bool,
        setSample: *const SampleBuffer,
        setPlayRate: f32,
        setPlayPosition: usize,
        setAntiClick: bool,
    };

    pub const State = enum {
        Playing,
        PrePause,
        Paused,
    };

    // TODO use this
    pub const Interpolation = enum {
        None,
        Linear,
    };

    curr_sample: ?*const SampleBuffer,
    frame_at: usize,
    remainder: f32,
    // TODO probably use f64
    // fraction of sample rate to ctx rate
    sample_rate_mult: f32,

    do_anti_click: bool,
    // TODO makes sense to have this as a constant
    //        not going to be changing it ever
    anti_click_len: u32,
    play_timer: u32,
    pause_timer: u32,
    pause_frame_at: usize,
    pause_remainder: f32,

    state: State,
    play_rate: f32,
    do_loop: bool,

    pub fn init() Self {
        return .{
            .curr_sample = null,
            .frame_at = 0,
            .remainder = 0.,
            .sample_rate_mult = 1.,
            .do_anti_click = false,
            .anti_click_len = 1000,
            .play_timer = 0,
            .pause_timer = 0,
            .pause_frame_at = 0,
            .pause_remainder = 0.,
            .state = .Paused,
            .play_rate = 1.,
            .do_loop = false,
        };
    }

    pub fn compute(
        self: *Self,
        ctx: CallbackContext,
        _inputs: []const InBuffer,
        output: []f32,
    ) void {
        if (self.curr_sample) |sample| {
            if (self.state != .Paused) {
                var ct: usize = 0;
                var float_ct: f32 = 0;
                while (ct < ctx.frame_len) : (ct += 2) {
                    // anti-click fading
                    //   on starting the sample or reaching the end of it, fade is preempted
                    //     this takes precendence over pausing or playing;
                    //       if we're within the bounds of start and end, use this fade
                    //     TODO the logic for this isnt right
                    //            only handles the case if you pause while within the end window
                    //            misses the case when you play while in the sart window
                    //                         or when you pause and continue into the end window
                    //   on pause, you need to start the fade and continue reading ahead
                    //     switches state to PrePause, and saves the spot to return to once paused
                    //   on loop, fade (renoise does this)
                    const atten = if (!self.do_anti_click) blk: {
                        break :blk 1.;
                    } else if (self.frame_at < self.anti_click_len) blk: {
                        // TODO you also need to do a max and min here with the pause and play timers
                        //        and below
                        // pause timer here
                        const f_fa = @intToFloat(f32, self.frame_at);
                        const f_ac = @intToFloat(f32, self.anti_click_len);
                        break :blk f_fa / f_ac;
                    } else if (self.frame_at > sample.frame_ct - self.anti_click_len) blk: {
                        // TODO >>> here
                        const f_fa = @intToFloat(f32, sample.frame_ct - self.frame_at);
                        const f_ac = @intToFloat(f32, self.anti_click_len);
                        break :blk f_fa / f_ac;
                    } else if (self.play_timer > 0 and self.pause_timer > 0) blk: {
                        const f_tm = if (self.state == .PrePause) blk_: {
                            break :blk_ @intToFloat(f32, std.math.min(
                                self.anti_click_len - self.play_timer,
                                self.pause_timer,
                            ));
                        } else blk_: {
                            break :blk_ @intToFloat(f32, std.math.max(
                                self.anti_click_len - self.play_timer,
                                self.pause_timer,
                            ));
                        };
                        const f_ac = @intToFloat(f32, self.anti_click_len);
                        break :blk f_tm / f_ac;
                    } else if (self.play_timer > 0) blk: {
                        const f_pt = @intToFloat(f32, self.anti_click_len - self.play_timer);
                        const f_ac = @intToFloat(f32, self.anti_click_len);
                        break :blk f_pt / f_ac;
                    } else if (self.pause_timer > 0) blk: {
                        const f_st = @intToFloat(f32, self.pause_timer);
                        const f_ac = @intToFloat(f32, self.anti_click_len);
                        break :blk f_st / f_ac;
                    } else 1.;

                    if (self.play_timer > 0) {
                        self.play_timer -= 1;
                    }

                    if (self.pause_timer > 0) {
                        self.pause_timer -= 1;
                        if (self.state == .PrePause and self.pause_timer == 0) {
                            self.state = .Paused;
                            self.frame_at = self.pause_frame_at;
                            self.remainder = self.pause_remainder;
                            while (ct < ctx.frame_len) : (ct += 2) {
                                output[ct] = 0.;
                                output[ct + 1] = 0.;
                            }
                            return;
                        }
                    }

                    switch (sample.channel_ct) {
                        1 => {
                            output[ct] = sample.data.items[self.frame_at] * atten;
                            output[ct + 1] = sample.data.items[self.frame_at] * atten;
                        },
                        2 => {
                            output[ct] = sample.data.items[self.frame_at] * atten;
                            output[ct + 1] = sample.data.items[self.frame_at + 1] * atten;
                        },
                        else => unreachable,
                    }

                    float_ct += self.sample_rate_mult * self.play_rate;
                    if (float_ct > 1) {
                        float_ct -= 1;
                        self.frame_at += 1;

                        if (self.frame_at >= sample.frame_ct) {
                            if (self.do_loop) {
                                // TODO do you want to do the soft play or a hard play here?
                                self.play();
                                self.frame_at = 0;
                            } else {
                                self.state = .Paused;
                                self.pause_timer = 0;
                                ct += 2;
                                while (ct < ctx.frame_len) : (ct += 2) {
                                    output[ct] = 0.;
                                    output[ct + 1] = 0.;
                                }
                                return;
                            }
                        }
                    }
                }
                self.remainder = float_ct;
            } else {
                std.mem.set(f32, output, 0.);
            }
        } else {
            std.mem.set(f32, output, 0.);
        }
    }

    pub fn takeMessage(self: *Self, ctx: CallbackContext, msg: Message) void {
        switch (msg) {
            .play => self.play(),
            .pause => self.pause(),
            .stop => self.stop(),
            .setLoop => |to| self.do_loop = to,
            .setSample => |to| self.setSample(ctx, to),
            .setPlayRate => |to| self.play_rate = to,
            // TODO make into a function and error check
            .setPlayPosition => |to| self.frame_at = to,
            .setAntiClick => |to| self.do_anti_click = to,
        }
    }

    //;

    pub fn play(self: *Self) void {
        self.state = .Playing;
        self.play_timer = self.anti_click_len;
    }

    pub fn pause(self: *Self) void {
        if (self.do_anti_click) {
            self.state = .PrePause;
            self.pause_timer = self.anti_click_len;
            self.pause_frame_at = self.frame_at;
            self.pause_remainder = self.remainder;
        } else {
            self.state = .Paused;
        }
    }

    pub fn stop(self: *Self) void {
        if (self.do_anti_click) {
            self.state = .PrePause;
            self.pause_timer = self.anti_click_len;
            self.pause_frame_at = 0;
            self.pause_remainder = 0;
        } else {
            self.state = .Paused;
        }
    }

    pub fn setSample(self: *Self, ctx: CallbackContext, sample: *const SampleBuffer) void {
        self.curr_sample = sample;
        self.frame_at = 0;
        self.remainder = 0.;
        self.sample_rate_mult = @intToFloat(f32, sample.sample_rate) /
            @intToFloat(f32, ctx.sample_rate);
        self.state = .Paused;
    }
};
