const std = @import("std");

extern fn zig_k_msleep(ms: i32) void;
extern fn zig_printk_str(s: [*:0]const u8) void;

extern fn zig_k_malloc(size: usize) ?*anyopaque;
extern fn zig_k_free(ptr: ?*anyopaque) void;
extern fn zig_k_calloc(nmemb: usize, size: usize) ?*anyopaque;
extern fn zig_k_realloc(ptr: ?*anyopaque, size: usize) ?*anyopaque;
extern fn zig_k_uptime_get() i64;
extern fn zig_k_cycle_get_32() u32;

pub fn k_msleep(ms: i32) void {
    zig_k_msleep(ms);
}

pub fn printk(comptime fmt: []const u8, args: anytype) void {
    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrintZ(&buf, fmt, args) catch return;
    zig_printk_str(msg.ptr);
}

pub fn malloc(size: usize) ?*anyopaque {
    return zig_k_malloc(size);
}

pub fn free(ptr: ?*anyopaque) void {
    zig_k_free(ptr);
}

pub fn calloc(nmemb: usize, size: usize) ?*anyopaque {
    return zig_k_calloc(nmemb, size);
}

pub fn realloc(ptr: ?*anyopaque, size: usize) ?*anyopaque {
    return zig_k_realloc(ptr, size);
}

pub fn allocBytes(size: usize) ?[]u8 {
    if (size == 0) return null;

    const raw = zig_k_malloc(size) orelse return null;
    const ptr: [*]u8 = @ptrCast(raw);
    return ptr[0..size];
}

pub fn callocBytes(nmemb: usize, size: usize) ?[]u8 {
    const total = std.math.mul(usize, nmemb, size) catch return null;
    if (total == 0) return null;

    const raw = zig_k_calloc(nmemb, size) orelse return null;
    const ptr: [*]u8 = @ptrCast(raw);
    return ptr[0..total];
}

pub fn freeBytes(buf: []u8) void {
    if (buf.len == 0) return;
    zig_k_free(@ptrCast(buf.ptr));
}

pub fn reallocBytes(buf: []u8, new_len: usize) ?[]u8 {
    if (new_len == 0) {
        freeBytes(buf);
        return null;
    }

    const raw = zig_k_realloc(@ptrCast(buf.ptr), new_len) orelse return null;
    const ptr: [*]u8 = @ptrCast(raw);
    return ptr[0..new_len];
}

pub fn uptimeGet() i64 {
    return zig_k_uptime_get();
}

pub fn cycleGet32() u32 {
    return zig_k_cycle_get_32();
}
