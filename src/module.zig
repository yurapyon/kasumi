const CallbackContext = @import("system.zig").CallbackContext;

pub const InputBuffer = struct {
    idx: usize,
    buffer: []const f32,
};

pub const Module = struct {
    frame: fn (*Module, *const CallbackContext) void = frame,
    compute: fn (
        *Module,
        *const CallbackContext,
        []const InputBuffer,
        []f32,
    ) void,

    fn frame(_module: *Module, _ctx: *const CallbackContext) void {}
};
