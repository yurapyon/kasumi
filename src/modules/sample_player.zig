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

// TODO anti-click fading
//   on starting the sample or reaching the end of it, fade needs to be preemted
//     fade early
//   on stop or pause, you need to start the fade and continure reading ahead
//     fade late
//     if stopping right before the end. fade should already be happening and not be changed
//   on loop fade, renoise does this
// TODO note: currently playrate changes click length
//        "okay" for down pitch, not okay for up pitch, might be skipping frames
// TODO stop_timer has to 'ghost' so that if you pause,
//        the timer goes beyond where you paused and doesnt actually influence frame_at
//      also setting state to .Stopped and then having sound contine to play after
//        gets in the way of some of the logic of stuff youre suposed to do after you stop
//        also mackes the check for state == .Playing ugly
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
        Paused,
        Stopped,
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
    stop_timer: u32,

    state: State,
    play_rate: f32,
    do_loop: bool,

    pub fn init() Self {
        return .{
            .curr_sample = null,
            .frame_at = 0,
            .remainder = 0.,
            .sample_rate_mult = 1.,
            .do_anti_click = true,
            .anti_click_len = 100,
            .play_timer = 0,
            .stop_timer = 0,
            .state = .Stopped,
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
            if (self.state == .Playing or
                (self.stop_timer > 0 and self.frame_at < sample.frame_ct))
            {
                var ct: usize = 0;
                var float_ct: f32 = 0;
                while (ct < ctx.frame_len) : (ct += 2) {
                    const atten = if (!self.do_anti_click) blk: {
                        break :blk 1.;
                    } else if (self.frame_at < self.anti_click_len) blk: {
                        const f_fa = @intToFloat(f32, self.frame_at);
                        const f_ac = @intToFloat(f32, self.anti_click_len);
                        break :blk f_fa / f_ac;
                    } else if (self.frame_at > sample.frame_ct - self.anti_click_len) blk: {
                        const f_fa = @intToFloat(f32, sample.frame_ct - self.frame_at);
                        const f_ac = @intToFloat(f32, self.anti_click_len);
                        break :blk f_fa / f_ac;
                    } else if (self.play_timer > 0 and self.stop_timer > 0) blk: {
                        // TODO if play happened before stop, this should be min
                        //      if stop happened before play, this should be max
                        const f_tm = @intToFloat(f32, std.math.max(
                            self.play_timer,
                            self.stop_timer,
                        ));
                        const f_ac = @intToFloat(f32, self.anti_click_len);
                        self.play_timer -= 1;
                        self.stop_timer -= 1;
                        break :blk f_tm / f_ac;
                    } else if (self.play_timer > 0) blk: {
                        const f_pt = @intToFloat(f32, self.anti_click_len - self.play_timer);
                        const f_ac = @intToFloat(f32, self.anti_click_len);
                        self.play_timer -= 1;
                        break :blk f_pt / f_ac;
                    } else if (self.stop_timer > 0) blk: {
                        // std.log.warn("{}\n", .{self.stop_timer});
                        const f_st = @intToFloat(f32, self.stop_timer);
                        const f_ac = @intToFloat(f32, self.anti_click_len);
                        self.stop_timer -= 1;
                        break :blk f_st / f_ac;
                    } else 1.;

                    if (self.state == .Stopped and self.stop_timer == 0) {
                        while (ct < ctx.frame_len) : (ct += 2) {
                            output[ct] = 0.;
                            output[ct + 1] = 0.;
                        }
                        return;
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
                                self.frame_at = 0;
                            } else {
                                self.stop();
                                self.stop_timer = 0;
                                // std.log.warn("fa {}", .{self.frame_at});
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
        self.state = .Paused;
        self.stop_timer = self.anti_click_len;
    }

    pub fn stop(self: *Self) void {
        self.state = .Stopped;
        self.stop_timer = self.anti_click_len;
        // TODO cant do this because of stop_timer
        // self.frame_at = 0;
    }

    pub fn setSample(self: *Self, ctx: CallbackContext, sample: *const SampleBuffer) void {
        // std.log.warn("fc {}", .{sample.frame_ct});
        self.curr_sample = sample;
        self.frame_at = 0;
        self.remainder = 0.;
        self.sample_rate_mult = @intToFloat(f32, sample.sample_rate) / @intToFloat(f32, ctx.sample_rate);
        self.state = .Paused;
    }
};
