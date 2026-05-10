const std = @import("std");
const display_mod = @import("display.zig");

pub export fn zig_display_is_ready() c_int {
    return 1;
}

pub export fn zig_display_get_caps(caps: *display_mod.DisplayCaps) c_int {
    caps.* = .{
        .width = 296,
        .height = 128,
        .pixel_formats = 0,
        .screen_info = 0,
        .current_pixel_format = 0,
        .current_orientation = 0,
    };
    return 0;
}

pub export fn zig_display_set_mono01() c_int {
    return 0;
}

pub export fn zig_display_set_mono10() c_int {
    return 0;
}

pub export fn zig_display_set_blanking_on() c_int {
    return 0;
}

pub export fn zig_display_set_blanking_off() c_int {
    return 0;
}

pub export fn zig_display_write(
    x: u16,
    y: u16,
    width: u16,
    height: u16,
    pitch: u16,
    buf: [*]const u8,
    buf_size: usize,
) c_int {
    // Desktop: no-op write (rendering is done in software framebuffer)
    _ = x; _ = y; _ = width; _ = height; _ = pitch; _ = buf; _ = buf_size;
    return 0;
}

pub export fn zig_display_set_orientation(orientation: display_mod.DisplayOrientation) c_int {
    _ = orientation;
    return 0;
}

pub export fn zig_display_clear() c_int {
    return 0;
}
