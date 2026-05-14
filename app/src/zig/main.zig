const std = @import("std");
const z = @import("zephyr.zig");
const sd = @import("hardware/sd.zig");
const logger = @import("logger.zig");
const gfx = @import("gfx.zig");
const font = @import("font.zig");
const Matrix3 = @import("util/Matrix3.zig").Matrix3;
const buttons = @import("hardware/buttons.zig");
const Framebuffer = @import("renderer.zig").Framebuffer;

const log = logger.Logger(.{
    .module_name = "main",
});

const framebuffer_width: usize = 296;
const framebuffer_height: usize = 128;
const framebuffer_bytes: usize = (framebuffer_width * framebuffer_height) / 8;
var framebuffer_pixels: [framebuffer_bytes]u8 = .{0} ** framebuffer_bytes;

const demo_bitmap_a = [_]u8{
    0b00111100,
    0b01000010,
    0b10100101,
    0b10000001,
    0b10100101,
    0b10011001,
    0b01000010,
    0b00111100,
};

const demo_bitmap_b = [_]u8{
    0b11110000,
    0b01110000,
    0b00110000,
    0b00010000,
    0b00011000,
    0b00111100,
    0b01111110,
    0b11111111,
};

fn sd_card_inserted_callback() void {
    log.info("SD card inserted.", .{});
    sd.mount() catch |err| {
        log.err("Failed to mount SD card: {}", .{err});
    };
}

fn sd_card_removed_callback() void {
    log.info("SD card removed.", .{});
    sd.unmount() catch |err| {
        log.err("Failed to unmount SD card: {}", .{err});
    };
}

fn presentAndReport(renderer: *gfx.Renderer, mode: ?gfx.PresentMode, label: []const u8) !void {
    try renderer.present(mode);

    const zones = renderer.dirtyZones();
    log.info("  {s}: {} dirty zones", .{ label, zones.len });
    renderer.clearDirtyZones();
}

fn drawPrimitiveShowcase(renderer: *gfx.Renderer, font_id: anytype) !void {
    var canvas = try renderer.begin();
    const fb_w: i32 = @intCast(framebuffer_width);
    const fb_h: i32 = @intCast(framebuffer_height);
    const pi = std.math.pi;

    try canvas.clear(.white);
    try canvas.clearRect(.{ .x = 220, .y = 0, .width = 76, .height = 18 }, .white);
    try canvas.submit(.{ .nop = {} });

    _ = canvas.setFill(.{ .color = .black });
    _ = canvas.setStroke(.{ .color = .black, .width = 1, .style = .solid });
    _ = canvas.setTextColor(.black);
    _ = canvas.setTextAlign(.left);
    _ = canvas.setTextBaseline(.top);

    try canvas.line(.{ .x = 8, .y = 54 }, .{ .x = 96, .y = 54 }, .{ .color = .black, .width = 1, .style = .solid });
    try canvas.lineWith(.{ .x = 8, .y = 60 }, .{ .x = 96, .y = 78 });

    try canvas.polyline(
        &.{
            .{ .x = 108, .y = 18 },
            .{ .x = 132, .y = 30 },
            .{ .x = 116, .y = 44 },
            .{ .x = 144, .y = 50 },
        },
        .{ .color = .black, .width = 1, .style = .solid },
    );
    try canvas.polylineWith(&.{
        .{ .x = 108, .y = 58 },
        .{ .x = 132, .y = 70 },
        .{ .x = 116, .y = 84 },
        .{ .x = 144, .y = 90 },
    });

    try canvas.quadraticBezier(
        .{ .x = 12, .y = 90 },
        .{ .x = 44, .y = 8 },
        .{ .x = 76, .y = 90 },
        null,
        .{ .color = .black, .width = 1, .style = .solid },
    );
    try canvas.quadraticBezierWith(
        .{ .x = 84, .y = 90 },
        .{ .x = 116, .y = 8 },
        .{ .x = 148, .y = 90 },
    );

    try canvas.cubicBezier(
        .{ .x = 160, .y = 90 },
        .{ .x = 176, .y = 8 },
        .{ .x = 212, .y = 8 },
        .{ .x = 228, .y = 90 },
        null,
        .{ .color = .black, .width = 1, .style = .solid },
    );
    try canvas.cubicBezierWith(
        .{ .x = 232, .y = 90 },
        .{ .x = 248, .y = 8 },
        .{ .x = 284, .y = 8 },
        .{ .x = 292, .y = 90 },
    );

    try canvas.rect(
        .{ .x = 8, .y = 18, .width = 36, .height = 22 },
        .{ .color = .black, .pattern = .solid },
        .{ .color = .black, .width = 1, .style = .solid },
    );
    try canvas.rectWith(.{ .x = 48, .y = 18, .width = 36, .height = 22 });

    _ = canvas.fillColor(.black);
    try canvas.rectFilled(8, 100, 24, 16);
    _ = canvas.strokeColor(.black, 2);
    try canvas.rectOutline(36, 100, 24, 16);

    try canvas.triangle(
        .{ .x = 168, .y = 18 },
        .{ .x = 188, .y = 42 },
        .{ .x = 148, .y = 42 },
        .{ .color = .black, .pattern = .solid },
        .{ .color = .black, .width = 1, .style = .solid },
    );
    try canvas.triangleWith(
        .{ .x = 200, .y = 18 },
        .{ .x = 220, .y = 42 },
        .{ .x = 180, .y = 42 },
    );

    try canvas.circle(
        .{ .x = 252, .y = 30 },
        12,
        .{ .color = .black, .pattern = .solid },
        .{ .color = .black, .width = 1, .style = .solid },
    );
    try canvas.circleWith(.{ .x = 280, .y = 30 }, 12);

    _ = canvas.fillColor(.black);
    try canvas.circleFilled(252, 66, 12);
    _ = canvas.strokeColor(.black, 2);
    try canvas.circleOutline(280, 66, 12);

    try canvas.ellipse(
        .{ .x = 164, .y = 52, .width = 36, .height = 20 },
        .{ .color = .black, .pattern = .solid },
        .{ .color = .black, .width = 1, .style = .solid },
    );
    try canvas.ellipseWith(.{ .x = 204, .y = 52, .width = 36, .height = 20 });

    try canvas.roundedRect(
        .{ .x = 164, .y = 78, .width = 36, .height = 20 },
        4,
        .{ .color = .black, .pattern = .solid },
        .{ .color = .black, .width = 1, .style = .solid },
    );
    try canvas.roundedRectWith(.{ .x = 204, .y = 78, .width = 36, .height = 20 }, 4);

    try canvas.arc(
        .{ .x = 260, .y = 104 },
        14,
        0.0,
        pi,
        null,
        .{ .color = .black, .width = 1, .style = .solid },
    );
    try canvas.arcWith(.{ .x = 288, .y = 104 }, 14, 0.0, pi);

    try canvas.polygon(
        &.{
            .{ .x = 92, .y = 100 },
            .{ .x = 108, .y = 104 },
            .{ .x = 104, .y = 120 },
            .{ .x = 84, .y = 120 },
        },
        .{ .color = .black, .pattern = .solid },
        .{ .color = .black, .width = 1, .style = .solid },
    );
    try canvas.polygonWith(&.{
        .{ .x = 124, .y = 100 },
        .{ .x = 140, .y = 104 },
        .{ .x = 136, .y = 120 },
        .{ .x = 116, .y = 120 },
    });

    _ = canvas.clearState();
    _ = canvas.setTextColor(.black);
    _ = canvas.setTextAlign(.left);
    _ = canvas.setTextBaseline(.top);

    try canvas.point(.{ .x = 16, .y = 16 }, .black);
    try canvas.pointAt(18, 16);

    try canvas.text(.{ .x = fb_w / 2, .y = 12 }, font_id, .black, .center, .middle, "gfx.zig comprehensive demo");
    try canvas.textAt(.{ .x = 8, .y = fb_h - 18 }, font_id, "textAt uses canvas state");
    try canvas.textXY(8, 36, font_id, "textXY convenience");

    try canvas.clipPushXYWH(6, 6, 148, 42);
    try canvas.rectOutline(10, 10, 140, 34);
    try canvas.clipPush(.{ .x = 18, .y = 14, .width = 40, .height = 16 });
    try canvas.rectFilled(18, 14, 40, 16);
    try canvas.clipPop();
    try canvas.clipPop();

    try canvas.transformPush(Matrix3.identity());
    try canvas.transformReplace(Matrix3.translation(12.0, 8.0));
    try canvas.nop();
    try canvas.transformPop();

    try presentAndReport(renderer, null, "primitive showcase");
}

fn drawBitmapShowcase(renderer: *gfx.Renderer) !void {
    var canvas = try renderer.begin();

    try canvas.clearRect(.{ .x = 0, .y = 0, .width = 296, .height = 128 }, .white);

    try canvas.bitmap(
        .{ .x = 16, .y = 16 },
        8,
        8,
        demo_bitmap_a[0..],
        1,
        .msb_first,
        .replace,
    );
    try canvas.bitmapXY(32, 16, 8, 8, demo_bitmap_b[0..], 1, .lsb_first, .xor);

    _ = canvas.fillColor(.black);
    try canvas.rectFilled(72, 16, 18, 18);
    try canvas.blit(
        .{ .x = 72, .y = 16 },
        .{ .x = 96, .y = 16 },
        .{ .width = 18, .height = 18 },
        .copy,
    );

    try canvas.invert(.{ .x = 16, .y = 44, .width = 32, .height = 16 });
    try canvas.invertXYWH(56, 44, 32, 16);

    const partial_mode: gfx.PresentMode = .{ .partial = .{ .x = 0, .y = 0, .width = 128, .height = 64 } };
    try presentAndReport(renderer, partial_mode, "bitmap showcase");
}

fn drawNoopShowcase(renderer: *gfx.Renderer) !void {
    var canvas = try renderer.begin();
    try canvas.submit(.{ .nop = {} });

    const none_mode: gfx.PresentMode = .none;
    try presentAndReport(renderer, none_mode, "no-op showcase");
}

fn drawFinalFullPresent(renderer: *gfx.Renderer) !void {
    var canvas = try renderer.begin();
    try canvas.nop();

    const full_mode: gfx.PresentMode = .full;
    try presentAndReport(renderer, full_mode, "final full present");
}

export fn zig_main() callconv(.c) void {
    log.info("Starting YuReader firmware...", .{});

    log.info("Initializing SD card interface.", .{});
    sd.register_callbacks(
        &sd_card_inserted_callback,
        &sd_card_removed_callback,
    );

    sd.init() catch |err| {
        log.err("SD card initialization failed: {}", .{err});
        return;
    };

    if (sd.card_present()) {
        log.info("SD card detected, mounting...", .{});
        sd.mount() catch |err| {
            log.err("SD card mount failed: {}", .{err});
            return;
        };
        log.info("SD card mounted.", .{});
    } else {
        log.info("No SD card detected.", .{});
    }

    log.info("Initializing buttons.", .{});
    buttons.init() catch |err| {
        log.err("Button initialization failed: {}", .{err});
        return;
    };
    log.info("Buttons ready.", .{});

    log.info("Initializing renderer ({}x{} framebuffer).", .{ framebuffer_width, framebuffer_height });
    var renderer = gfx.Renderer.init(z.allocator(), .{
        .clear_on_begin = .white,
        .default_present_mode = .auto,
        .framebuffer = Framebuffer.init(framebuffer_width, framebuffer_height, framebuffer_pixels[0..]),
    }) catch |err| {
        log.err("Renderer initialization failed: {}", .{err});
        return;
    };

    const font_id = renderer.registerFont(font.getBlob()) catch |err| {
        log.err("Font registration failed: {}", .{err});
        return;
    };
    defer renderer.deinit();

    log.info("Running display demonstrations.", .{});
    
    drawPrimitiveShowcase(&renderer, font_id) catch |err| {
        log.err("Primitive showcase failed: {}", .{err});
        return;
    };

    drawBitmapShowcase(&renderer) catch |err| {
        log.err("Bitmap showcase failed: {}", .{err});
        return;
    };

    drawNoopShowcase(&renderer) catch |err| {
        log.err("No-op showcase failed: {}", .{err});
        return;
    };

    drawFinalFullPresent(&renderer) catch |err| {
        log.err("Final present failed: {}", .{err});
        return;
    };
    
    log.info("Demonstrations completed successfully.", .{});

    while (true) {
        z.k_busy_wait(100);
    }
}
