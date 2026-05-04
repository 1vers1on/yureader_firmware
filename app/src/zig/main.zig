const z = @import("zephyr.zig");

export fn zig_main() callconv(.c) void {
    z.printk("Hello from Zig!\n", .{});
}
