const z = @import("zephyr.zig");
const sd = @import("hardware/sd.zig");

fn sd_card_inserted_callback() void {
    z.printk("SD card inserted callback triggered.\n", .{});
    sd.mount() catch {
        z.printk("Failed to mount SD card during insertion.\n", .{});
    };
}

fn sd_card_removed_callback() void {
    z.printk("SD card removed callback triggered.\n", .{});
    sd.unmount() catch {
        z.printk("Failed to unmount SD card during removal.\n", .{});
    };
}

export fn zig_main() callconv(.c) void {
    z.printk("Hello from Zig!\n", .{});

    z.printk("Registering SD card callbacks...\n", .{});
    sd.register_callbacks(
        &sd_card_inserted_callback,
        &sd_card_removed_callback,
    );

    sd.init() catch {
        z.printk("Failed to initialize SD card interface.\n", .{});
        return;
    };

    if (sd.card_present()) {
        z.printk("SD card is present.\n", .{});
        z.printk("Mounting SD card...\n", .{});
        sd.mount() catch {
            z.printk("Failed to mount SD card.\n", .{});
            return;
        };
        z.printk("SD card mounted successfully.\n", .{});
    } else {
        z.printk("SD card is not present.\n", .{});
    }
}
