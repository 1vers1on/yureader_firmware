const std = @import("std");

pub const Callback = struct {
    on_pressed: ?*const fn (id: u8) void = null,
};

var callback: Callback = .{};

extern fn zig_buttons_init() c_int;

pub const Error = error{
    ZephyrError,
};

fn check(rc: c_int) Error!void {
    if (rc < 0) return Error.ZephyrError;
}

export fn zig_button_pressed(id: u8) callconv(.c) void {
    if (callback.on_pressed) |f| f(id);
}

pub fn init() Error!void {
    try check(zig_buttons_init());
}

pub fn register_callback(on_pressed: ?*const fn (id: u8) void) void {
    callback.on_pressed = on_pressed;
}
