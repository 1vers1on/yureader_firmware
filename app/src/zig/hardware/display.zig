const std = @import("std");

pub const DisplayCaps = extern struct {
    width: u16,
    height: u16,
    pixel_formats: u32,
    screen_info: u32,

    current_pixel_format: u32,
    current_orientation: u32,
};

pub const DisplayOrientation = enum(u32) {
    Normal = 0,
    Rotate90 = 1,
    Rotate180 = 2,
    Rotate270 = 3,
};

extern fn zig_display_is_ready() c_int;
extern fn zig_display_get_caps(caps: *DisplayCaps) c_int;
extern fn zig_display_set_mono01() c_int;
extern fn zig_display_set_mono10() c_int;
extern fn zig_display_set_blanking_on() c_int;
extern fn zig_display_set_blanking_off() c_int;
extern fn zig_display_write(
    x: u16,
    y: u16,
    width: u16,
    height: u16,
    pitch: u16,
    buf: [*]const anyopaque,
    buf_size: usize,
) c_int;
extern fn zig_display_set_orientation(orientation: DisplayOrientation) c_int;
extern fn zig_display_clear() c_int;

pub const Error = error{
    ZephyrError,
};

fn check(rc: c_int) Error!void {
    if (rc < 0) return Error.ZephyrError;
}

pub fn display_is_ready() bool {
    return zig_display_is_ready() != 0;
}

pub fn display_get_caps() Error!DisplayCaps {
    var caps: DisplayCaps = undefined;
    try check(zig_display_get_caps(&caps));
    return caps;
}

pub fn display_set_mono01() Error!void {
    try check(zig_display_set_mono01());
}

pub fn display_set_mono10() Error!void {
    try check(zig_display_set_mono10());
}

pub fn display_set_blanking_on() Error!void {
    try check(zig_display_set_blanking_on());
}

pub fn display_set_blanking_off() Error!void {
    try check(zig_display_set_blanking_off());
}

pub fn display_write(
    x: u16,
    y: u16,
    width: u16,
    height: u16,
    pitch: u16,
    buf: [*]const u8,
    buf_size: usize,
) Error!void {
    try check(zig_display_write(x, y, width, height, pitch, buf, buf_size));
}

pub fn display_set_orientation(orientation: DisplayOrientation) Error!void {
    try check(zig_display_set_orientation(orientation));
}

pub fn display_clear() Error!void {
    try check(zig_display_clear());
}
