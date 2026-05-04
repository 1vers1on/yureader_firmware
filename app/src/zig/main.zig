const z = @import("zephyr.zig");
const sd = @import("hardware/sd.zig");

export fn zig_main() callconv(.c) void {
    z.printk("Hello from Zig!\n", .{});
}
