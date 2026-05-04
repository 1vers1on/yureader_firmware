pub const OpenMode = enum(c_int) {
    read = 0,
    write_trunc = 1,
    append = 2,
    read_write = 3,
};

const Callback = struct {
    on_card_inserted: ?*const fn () void = null,
    on_card_removed: ?*const fn () void = null,
};

var callback: Callback = .{};

extern fn zig_sd_cd_init() c_int;
extern fn zig_sd_card_present() c_int;
extern fn zig_sd_mount() c_int;
extern fn zig_sd_unmount() c_int;
extern fn zig_sd_format() c_int;
extern fn zig_sd_open_file(path: [*:0]const u8, mode: OpenMode) c_int;
extern fn zig_sd_close_file(fd: c_int) c_int;
extern fn zig_sd_read_file(fd: c_int, buffer: [*]u8, size: usize) isize;
extern fn zig_sd_read_file_len(fd: c_int, buffer: [*]u8, offset: usize, len: usize) isize;
extern fn zig_sd_seek_file(fd: c_int, offset: isize, whence: c_int) c_int;
extern fn zig_sd_write_file(fd: c_int, buffer: [*]const u8, size: usize) isize;
extern fn zig_sd_mkdir(path: [*:0]const u8) c_int;
extern fn zig_sd_delete(path: [*:0]const u8) c_int;

pub const Error = error{
    ZephyrError,
    ShortWrite,
};

export fn zig_sd_card_changed() callconv(.c) void {
    if (card_present()) {
        if (callback.on_card_inserted) |f| f();
    } else {
        if (callback.on_card_removed) |f| f();
    }
}

fn check(rc: c_int) Error!void {
    if (rc < 0) return Error.ZephyrError;
}

fn check_size(rc: isize) Error!usize {
    if (rc < 0) return Error.ZephyrError;
    return @intCast(rc);
}

pub fn init() Error!void {
    try check(zig_sd_cd_init());
}

pub fn register_callbacks(
    on_inserted: ?*const fn () void,
    on_removed: ?*const fn () void,
) void {
    callback.on_card_inserted = on_inserted;
    callback.on_card_removed = on_removed;
}

pub fn card_present() bool {
    return zig_sd_card_present() != 0;
}

pub fn mount() Error!void {
    try check(zig_sd_mount());
}

pub fn unmount() Error!void {
    try check(zig_sd_unmount());
}

pub fn format() Error!void {
    try check(zig_sd_format());
}

pub fn open_file(path: [*:0]const u8, mode: OpenMode) Error!c_int {
    const fd = zig_sd_open_file(path, mode);
    if (fd < 0) return Error.ZephyrError;
    return fd;
}

pub fn close_file(fd: c_int) Error!void {
    try check(zig_sd_close_file(fd));
}

pub fn read_file(fd: c_int, buffer: []u8) Error!usize {
    return check_size(zig_sd_read_file(fd, buffer.ptr, buffer.len));
}

pub fn read_file_len(fd: c_int, buffer: []u8, offset: usize) Error!usize {
    return check_size(zig_sd_read_file_len(fd, buffer.ptr, offset, buffer.len));
}

pub fn seek_file(fd: c_int, offset: isize, whence: c_int) Error!void {
    try check(zig_sd_seek_file(fd, offset, whence));
}

pub fn write_file(fd: c_int, buffer: []const u8) Error!usize {
    const bytes_written = try check_size(zig_sd_write_file(fd, buffer.ptr, buffer.len));

    if (bytes_written < buffer.len) return Error.ShortWrite;
    return bytes_written;
}

pub fn mkdir(path: [*:0]const u8) Error!void {
    try check(zig_sd_mkdir(path));
}

pub fn delete(path: [*:0]const u8) Error!void {
    try check(zig_sd_delete(path));
}
