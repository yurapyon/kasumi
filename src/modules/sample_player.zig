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
//      instead of using frame_at, use some raw frame_ct that just counts up
//      an 'actual frame_ct' thats adusted for the playback rate? or something

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
    pub const Loop = struct {
        start: usize,
        end: usize,
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
    fade_in_timer: u32,
    fade_out_timer: u32,
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
            .anti_click_len = 200,
            .fade_in_timer = 0,
            .fade_out_timer = 0,
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
                    if (self.do_anti_click) {
                        if (self.frame_at == 0) {
                            self.play();
                        } else if (self.frame_at == sample.frame_ct - self.anti_click_len) {
                            self.stop();
                        }
                    }

                    const atten = if (!self.do_anti_click) blk: {
                        break :blk 1.;
                    } else if (self.fade_in_timer > 0 and self.fade_out_timer > 0) blk: {
                        const f_tm = if (self.state == .PrePause) blk_: {
                            break :blk_ @intToFloat(f32, std.math.min(
                                self.anti_click_len - self.fade_in_timer,
                                self.fade_out_timer,
                            ));
                        } else blk_: {
                            break :blk_ @intToFloat(f32, std.math.max(
                                self.anti_click_len - self.fade_in_timer,
                                self.fade_out_timer,
                            ));
                        };
                        const f_ac = @intToFloat(f32, self.anti_click_len);
                        self.fade_in_timer -= 1;
                        self.fade_out_timer -= 1;
                        break :blk f_tm / f_ac;
                    } else if (self.fade_in_timer > 0) blk: {
                        const f_it = @intToFloat(f32, self.anti_click_len - self.fade_in_timer);
                        const f_ac = @intToFloat(f32, self.anti_click_len);
                        self.fade_in_timer -= 1;
                        break :blk f_it / f_ac;
                    } else if (self.fade_out_timer > 0) blk: {
                        const f_ot = @intToFloat(f32, self.fade_out_timer);
                        const f_ac = @intToFloat(f32, self.anti_click_len);
                        self.fade_out_timer -= 1;
                        break :blk f_ot / f_ac;
                    } else 1.;

                    switch (sample.channel_ct) {
                        1 => {
                            output[ct] = sample.data.items[self.frame_at] * atten;
                            output[ct + 1] = sample.data.items[self.frame_at] * atten;
                        },
                        2 => {
                            output[ct] = sample.data.items[self.frame_at] * atten;
                            output[ct + 1] = sample.data.items[self.frame_at + 1] * atten;
                            self.frame_at += 1;
                        },
                        else => unreachable,
                    }

                    // TODO simplify and combine these two things below
                    if (self.state == .PrePause and self.fade_out_timer == 0) {
                        // for most cases you dont need to check if youre looping here
                        //   we just want to stop
                        // but if this is a stop inititated above by reaching the end window,
                        //   we need to check
                        if (self.do_loop) {
                            self.frame_at = 0;
                            continue;
                        } else {
                            self.state = .Paused;
                            self.frame_at = self.pause_frame_at;
                            self.remainder = self.pause_remainder;
                            ct += 2;
                            while (ct < ctx.frame_len) : (ct += 2) {
                                output[ct] = 0.;
                                output[ct + 1] = 0.;
                            }
                            return;
                        }
                    }

                    float_ct += self.sample_rate_mult * self.play_rate;
                    if (float_ct > 1) {
                        float_ct -= 1;
                        self.frame_at += 1;

                        if (self.frame_at >= sample.frame_ct) {
                            if (self.do_loop) {
                                self.frame_at = 0;
                            } else {
                                self.state = .Paused;
                                self.fade_out_timer = 0;
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
        if (self.state != .Playing) {
            self.state = .Playing;
            self.fade_in_timer = self.anti_click_len;
        }
    }

    pub fn pause(self: *Self) void {
        if (self.state == .Playing) {
            if (self.do_anti_click) {
                self.state = .PrePause;
                self.fade_out_timer = self.anti_click_len;
                self.pause_frame_at = self.frame_at;
                self.pause_remainder = self.remainder;
            } else {
                self.state = .Paused;
            }
        }
    }

    pub fn stop(self: *Self) void {
        if (self.state == .Playing) {
            if (self.do_anti_click) {
                self.state = .PrePause;
                self.fade_out_timer = self.anti_click_len;
            } else {
                self.state = .Paused;
            }
        }
        // do this out here so if you pause then stop you restart the sample
        self.pause_frame_at = 0;
        self.pause_remainder = 0;
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
