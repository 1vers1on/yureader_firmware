const z = @import("zephyr.zig");
const sd = @import("hardware/sd.zig");
const logger = @import("logger.zig");

const log = logger.Logger(.{
    .module_name = "main",
});

fn sd_card_inserted_callback() void {
    log.info("SD card inserted callback triggered.", .{});
    sd.mount() catch {
        log.err("Failed to mount SD card during insertion.", .{});
    };
}

fn sd_card_removed_callback() void {
    log.info("SD card removed callback triggered.", .{});
    sd.unmount() catch {
        log.err("Failed to unmount SD card during removal.", .{});
    };
}

export fn zig_main() callconv(.c) void {
    log.info("Starting YuReader firmware...", .{});

    log.info("Registering SD card callbacks...", .{});
    sd.register_callbacks(
        &sd_card_inserted_callback,
        &sd_card_removed_callback,
    );

    sd.init() catch {
        log.err("Failed to initialize SD card interface.", .{});
        return;
    };

    if (sd.card_present()) {
        log.info("SD card is present.", .{});
        log.info("Mounting SD card...", .{});
        sd.mount() catch {
            log.err("Failed to mount SD card.", .{});
            return;
        };
        log.info("SD card mounted successfully.", .{});
    } else {
        log.info("SD card is not present.", .{});
    }
}
