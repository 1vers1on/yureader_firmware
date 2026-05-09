const std = @import("std");

extern fn zig_k_msleep(ms: i32) void;
extern fn zig_printk_str(s: [*:0]const u8) void;

extern fn zig_k_malloc(size: usize) ?*anyopaque;
extern fn zig_k_free(ptr: ?*anyopaque) void;
extern fn zig_k_calloc(nmemb: usize, size: usize) ?*anyopaque;
extern fn zig_k_realloc(ptr: ?*anyopaque, size: usize) ?*anyopaque;
extern fn zig_k_aligned_alloc(alignment: usize, size: usize) ?*anyopaque;

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

pub fn k_malloc(size: usize) ?*anyopaque {
    return zig_k_malloc(size);
}

pub fn k_free(ptr: ?*anyopaque) void {
    zig_k_free(ptr);
}

pub fn k_calloc(nmemb: usize, size: usize) ?*anyopaque {
    return zig_k_calloc(nmemb, size);
}

pub fn k_realloc(ptr: ?*anyopaque, size: usize) ?*anyopaque {
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

pub fn allocator() std.mem.Allocator {
    return ZephyrAllocator.allocator();
}

const ZephyrAllocator = struct {
    var ctx: u8 = 0;

    const vtable = std.mem.Allocator.VTable{
        .alloc = alloc,
        .resize = resize,
        .remap = remap,
        .free = free,
    };

    fn allocator() std.mem.Allocator {
        return .{
            .ptr = &ctx,
            .vtable = &vtable,
        };
    }

    fn alloc(
        _: *anyopaque,
        len: usize,
        alignment: std.mem.Alignment,
        _: usize,
    ) ?[*]u8 {
        if (len == 0) return null;

        const raw = zig_k_aligned_alloc(alignment.toByteUnits(), len) orelse return null;
        return @ptrCast(raw);
    }

    fn resize(
        _: *anyopaque,
        memory: []u8,
        _: std.mem.Alignment,
        new_len: usize,
        _: usize,
    ) bool {
        // `resize` is only allowed to succeed if the pointer does not move.
        // Zephyr's realloc may move memory, so we only guarantee success for shrinking.
        if (new_len == 0) return true;
        if (new_len <= memory.len) return true;
        // For growing, let the fallback mechanism handle it
        return false;
    }

    fn remap(
        _: *anyopaque,
        memory: []u8,
        _: std.mem.Alignment,
        new_len: usize,
        _: usize,
    ) ?[*]u8 {
        if (new_len == 0) {
            zig_k_free(@ptrCast(memory.ptr));
            return null;
        }

        // Try to reallocate
        const new_ptr = zig_k_realloc(@ptrCast(memory.ptr), new_len) orelse return null;
        
        // Check if pointer moved; if so, we can't use it for in-place remap
        const old_ptr: usize = @intFromPtr(memory.ptr);
        const new_ptr_int: usize = @intFromPtr(new_ptr);
        
        if (old_ptr == new_ptr_int) {
            // Pointer stayed in place, success
            return @ptrCast(new_ptr);
        } else {
            // Pointer moved; realloc succeeded but it's not in-place
            // Free the new allocation and return null to trigger fallback
            zig_k_free(new_ptr);
            return null;
        }
    }

    fn free(
        _: *anyopaque,
        memory: []u8,
        _: std.mem.Alignment,
        _: usize,
    ) void {
        if (memory.len == 0) return;
        zig_k_free(@ptrCast(memory.ptr));
    }
};
