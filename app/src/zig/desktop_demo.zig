const std = @import("std");
const gfx = @import("gfx.zig");
const Render = @import("renderer.zig");
const font = @import("font.zig");
const Matrix3 = @import("util/Matrix3.zig").Matrix3;
// pull in desktop display symbol implementations so linker finds zig_display_* symbols
const _ = @import("hardware/display_desktop_impl.zig");
const Framebuffer = @import("renderer.zig").Framebuffer;

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

fn drawTextShowcase(canvas: *gfx.Canvas, font_id: Render.FontId) !void {
    const fb_w: i32 = @intCast(framebuffer_width);
    const fb_h: i32 = @intCast(framebuffer_height);

    try canvas.clear(.white);
    _ = canvas.setTextColor(.black);
    _ = canvas.setTextAlign(.center);
    _ = canvas.setTextBaseline(.middle);

    try canvas.text(.{ .x = fb_w / 2, .y = 20 }, font_id, .black, .center, .middle, "Text Rendering Demo");

    _ = canvas.setTextAlign(.left);
    _ = canvas.setTextBaseline(.top);
    try canvas.textXY(8, 40, font_id, "Left aligned top");

    _ = canvas.setTextAlign(.center);
    _ = canvas.setTextBaseline(.middle);
    try canvas.textAt(.{ .x = fb_w / 2, .y = 60 }, font_id, "Center aligned middle");

    _ = canvas.setTextAlign(.right);
    _ = canvas.setTextBaseline(.bottom);
    try canvas.textXY(fb_w - 8, fb_h - 8, font_id, "Right aligned bottom");
}

fn drawLinesShowcase(canvas: *gfx.Canvas) !void {
    try canvas.clear(.white);
    _ = canvas.setStroke(.{ .color = .black, .width = 1, .style = .solid });

    try canvas.line(.{ .x = 8, .y = 30 }, .{ .x = 96, .y = 30 }, .{ .color = .black, .width = 1, .style = .solid });
    try canvas.lineWith(.{ .x = 8, .y = 50 }, .{ .x = 96, .y = 80 });
    try canvas.line(.{ .x = 150, .y = 20 }, .{ .x = 200, .y = 100 }, .{ .color = .black, .width = 2, .style = .solid });
}

fn drawPolylinesShowcase(canvas: *gfx.Canvas) !void {
    try canvas.clear(.white);
    _ = canvas.setStroke(.{ .color = .black, .width = 1, .style = .solid });

    try canvas.polyline(
        &.{
            .{ .x = 20, .y = 20 },
            .{ .x = 60, .y = 40 },
            .{ .x = 40, .y = 60 },
            .{ .x = 80, .y = 90 },
        },
        .{ .color = .black, .width = 1, .style = .solid },
    );
    try canvas.polylineWith(&.{
        .{ .x = 150, .y = 20 },
        .{ .x = 190, .y = 40 },
        .{ .x = 170, .y = 60 },
        .{ .x = 210, .y = 90 },
    });
}

fn drawQuadraticBezierShowcase(canvas: *gfx.Canvas) !void {
    try canvas.clear(.white);
    _ = canvas.setStroke(.{ .color = .black, .width = 1, .style = .solid });

    try canvas.quadraticBezier(
        .{ .x = 20, .y = 100 },
        .{ .x = 80, .y = 20 },
        .{ .x = 140, .y = 100 },
        null,
        .{ .color = .black, .width = 1, .style = .solid },
    );
    try canvas.quadraticBezierWith(
        .{ .x = 180, .y = 100 },
        .{ .x = 240, .y = 20 },
        .{ .x = 280, .y = 100 },
    );
}

fn drawCubicBezierShowcase(canvas: *gfx.Canvas) !void {
    try canvas.clear(.white);
    _ = canvas.setStroke(.{ .color = .black, .width = 1, .style = .solid });

    try canvas.cubicBezier(
        .{ .x = 20, .y = 100 },
        .{ .x = 60, .y = 20 },
        .{ .x = 120, .y = 20 },
        .{ .x = 160, .y = 100 },
        null,
        .{ .color = .black, .width = 1, .style = .solid },
    );
}

fn drawRectangleShowcase(canvas: *gfx.Canvas) !void {
    try canvas.clear(.white);
    _ = canvas.setFill(.{ .color = .black });
    _ = canvas.setStroke(.{ .color = .black, .width = 1, .style = .solid });

    try canvas.rect(
        .{ .x = 8, .y = 18, .width = 36, .height = 22 },
        .{ .color = .black, .pattern = .solid },
        .{ .color = .black, .width = 1, .style = .solid },
    );
    try canvas.rectWith(.{ .x = 48, .y = 18, .width = 36, .height = 22 });
    _ = canvas.fillColor(.black);
    try canvas.rectFilled(88, 18, 24, 22);
    _ = canvas.strokeColor(.black, 2);
    try canvas.rectOutline(116, 18, 24, 22);
}

fn drawCircleShowcase(canvas: *gfx.Canvas) !void {
    try canvas.clear(.white);
    _ = canvas.setFill(.{ .color = .black });
    _ = canvas.setStroke(.{ .color = .black, .width = 1, .style = .solid });

    try canvas.circle(
        .{ .x = 40, .y = 50 },
        15,
        .{ .color = .black, .pattern = .solid },
        .{ .color = .black, .width = 1, .style = .solid },
    );
    try canvas.circleWith(.{ .x = 100, .y = 50 }, 15);
    _ = canvas.fillColor(.black);
    try canvas.circleFilled(160, 50, 15);
    _ = canvas.strokeColor(.black, 2);
    try canvas.circleOutline(220, 50, 15);
}

fn drawTriangleShowcase(canvas: *gfx.Canvas) !void {
    try canvas.clear(.white);
    _ = canvas.setFill(.{ .color = .black });
    _ = canvas.setStroke(.{ .color = .black, .width = 1, .style = .solid });

    try canvas.triangle(
        .{ .x = 40, .y = 30 },
        .{ .x = 70, .y = 80 },
        .{ .x = 10, .y = 80 },
        .{ .color = .black, .pattern = .solid },
        .{ .color = .black, .width = 1, .style = .solid },
    );
    try canvas.triangleWith(
        .{ .x = 150, .y = 30 },
        .{ .x = 180, .y = 80 },
        .{ .x = 120, .y = 80 },
    );
}

fn drawPointShowcase(canvas: *gfx.Canvas) !void {
    try canvas.clear(.white);
    _ = canvas.setTextColor(.black);

    try canvas.point(.{ .x = 50, .y = 40 }, .black);
    try canvas.pointAt(80, 40);
    try canvas.point(.{ .x = 110, .y = 40 }, .black);
    try canvas.pointAt(140, 40);
    try canvas.point(.{ .x = 170, .y = 40 }, .black);
}

fn drawEllipseShowcase(canvas: *gfx.Canvas) !void {
    try canvas.clear(.white);
    _ = canvas.setFill(.{ .color = .black });
    _ = canvas.setStroke(.{ .color = .black, .width = 1, .style = .solid });

    try canvas.ellipse(
        .{ .x = 20, .y = 40, .width = 50, .height = 30 },
        .{ .color = .black, .pattern = .solid },
        .{ .color = .black, .width = 1, .style = .solid },
    );
    try canvas.ellipseWith(.{ .x = 150, .y = 40, .width = 50, .height = 30 });
}

fn drawRoundedRectShowcase(canvas: *gfx.Canvas) !void {
    try canvas.clear(.white);
    _ = canvas.setFill(.{ .color = .black });
    _ = canvas.setStroke(.{ .color = .black, .width = 1, .style = .solid });

    try canvas.roundedRect(
        .{ .x = 20, .y = 30, .width = 50, .height = 40 },
        8,
        .{ .color = .black, .pattern = .solid },
        .{ .color = .black, .width = 1, .style = .solid },
    );
    try canvas.roundedRectWith(.{ .x = 150, .y = 30, .width = 50, .height = 40 }, 8);
}

fn drawArcShowcase(canvas: *gfx.Canvas) !void {
    try canvas.clear(.white);
    _ = canvas.setStroke(.{ .color = .black, .width = 1, .style = .solid });

    try canvas.arc(
        .{ .x = 60, .y = 80 },
        30,
        0.0,
        std.math.pi,
        null,
        .{ .color = .black, .width = 1, .style = .solid },
    );
    try canvas.arcWith(.{ .x = 180, .y = 80 }, 30, 0.0, std.math.pi);
}

fn drawPolygonShowcase(canvas: *gfx.Canvas) !void {
    try canvas.clear(.white);
    _ = canvas.setFill(.{ .color = .black });
    _ = canvas.setStroke(.{ .color = .black, .width = 1, .style = .solid });

    try canvas.polygon(
        &.{
            .{ .x = 50, .y = 20 },
            .{ .x = 80, .y = 50 },
            .{ .x = 60, .y = 90 },
            .{ .x = 20, .y = 90 },
        },
        .{ .color = .black, .pattern = .solid },
        .{ .color = .black, .width = 1, .style = .solid },
    );
    try canvas.polygonWith(&.{
        .{ .x = 160, .y = 20 },
        .{ .x = 190, .y = 50 },
        .{ .x = 170, .y = 90 },
        .{ .x = 130, .y = 90 },
    });
}

fn drawClippingShowcase(canvas: *gfx.Canvas) !void {
    try canvas.clear(.white);
    _ = canvas.setFill(.{ .color = .black });
    _ = canvas.setStroke(.{ .color = .black, .width = 1, .style = .solid });

    try canvas.clipPushXYWH(10, 10, 100, 50);
    try canvas.rectOutline(15, 15, 90, 40);
    try canvas.rect(
        .{ .x = 40, .y = 20, .width = 40, .height = 30 },
        .{ .color = .black, .pattern = .solid },
        .{ .color = .black, .width = 1, .style = .solid },
    );
    try canvas.clipPush(.{ .x = 20, .y = 20, .width = 30, .height = 20 });
    try canvas.rectFilled(20, 20, 30, 20);
    try canvas.clipPop();
    try canvas.clipPop();

    try canvas.clipPushXYWH(160, 40, 100, 60);
    _ = canvas.fillColor(.black);
    try canvas.rectFilled(170, 50, 80, 40);
    try canvas.clipPop();
}

fn drawTransformGlyph(canvas: *gfx.Canvas, matrix: Matrix3) !void {
    try canvas.transformPush(Matrix3.identity());
    try canvas.transformReplace(matrix);

    // local-space axes, so rotation/shear/reflection are obvious
    try canvas.lineWith(.{ .x = -4, .y = 0 }, .{ .x = 24, .y = 0 });
    try canvas.lineWith(.{ .x = 0, .y = -4 }, .{ .x = 0, .y = 18 });

    // asymmetric glyph: the filled nub marks local +x/+y orientation
    try canvas.rectOutline(0, 0, 18, 12);
    try canvas.lineWith(.{ .x = 0, .y = 0 }, .{ .x = 18, .y = 12 });
    try canvas.rectFilled(15, 9, 3, 3);

    try canvas.transformPop();
}

fn drawTransformLabel(canvas: *gfx.Canvas, font_id: Render.FontId, x: i32, y: i32, label: []const u8) !void {
    _ = canvas.setTextAlign(.center);
    _ = canvas.setTextBaseline(.top);
    try canvas.textXY(x, y, font_id, label);
}

fn drawTransformShowcase(canvas: *gfx.Canvas, font_id: Render.FontId) !void {
    try canvas.clear(.white);
    _ = canvas.setFill(.{ .color = .black });
    _ = canvas.setStroke(.{ .color = .black, .width = 1, .style = .solid });
    _ = canvas.setTextColor(.black);

    try canvas.text(.{ .x = 148, .y = 1 }, font_id, .black, .center, .top, "Matrix Transform Demo");
    try canvas.lineWith(.{ .x = 0, .y = 14 }, .{ .x = 295, .y = 14 });

    try drawTransformGlyph(
        canvas,
        Matrix3.translation(22.0, 36.0)
            .mul(Matrix3.rotation(0.55)),
    );
    try drawTransformLabel(canvas, font_id, 31, 58, "rot");

    try drawTransformGlyph(
        canvas,
        Matrix3.translation(70.0, 33.0)
            .mul(Matrix3.rotationAround(.{ .x = 9.0, .y = 6.0 }, -0.75)),
    );
    try drawTransformLabel(canvas, font_id, 79, 58, "rot@p");

    try drawTransformGlyph(
        canvas,
        Matrix3.translation(116.0, 31.0)
            .mul(Matrix3.scaleAround(.{ .x = 9.0, .y = 6.0 }, 1.35, 0.65)),
    );
    try drawTransformLabel(canvas, font_id, 125, 58, "scale");

    try drawTransformGlyph(
        canvas,
        Matrix3.translation(164.0, 31.0)
            .mul(Matrix3.shearX(0.65)),
    );
    try drawTransformLabel(canvas, font_id, 173, 58, "shear");

    try drawTransformGlyph(
        canvas,
        Matrix3.translation(214.0, 34.0)
            .mul(Matrix3.reflectionLine(.{ .x = 9.0, .y = 6.0 }, std.math.pi / 6.0)),
    );
    try drawTransformLabel(canvas, font_id, 223, 58, "mirror");

    try drawTransformGlyph(
        canvas,
        Matrix3.translation(263.0, 37.0)
            .mul(Matrix3.projectionLine(.{ .x = 9.0, .y = 6.0 }, std.math.pi / 5.0)),
    );
    try drawTransformLabel(canvas, font_id, 272, 58, "proj");

    try drawTransformGlyph(
        canvas,
        Matrix3.basis(
            .{ .x = 1.10, .y = 0.28 },
            .{ .x = -0.30, .y = 0.90 },
            .{ .x = 26.0, .y = 91.0 },
        ),
    );
    try drawTransformLabel(canvas, font_id, 36, 113, "basis");

    try drawTransformGlyph(
        canvas,
        Matrix3.affine(
            1.0,
            0.35,
            -0.45,
            0.90,
            84.0,
            89.0,
        ),
    );
    try drawTransformLabel(canvas, font_id, 94, 113, "affine");

    try drawTransformGlyph(
        canvas,
        Matrix3.translation(145.0, 89.0)
            .mul(Matrix3.projective(
            1.0,
            0.10,
            0.0,
            0.15,
            1.0,
            0.0,
            0.010,
            0.006,
        )),
    );
    try drawTransformLabel(canvas, font_id, 155, 113, "persp");

    try drawTransformGlyph(
        canvas,
        Matrix3.identity()
            .translated(212.0, 91.0)
            .rotated(-0.45)
            .scaled(1.25, 0.75)
            .sheared(0.35, 0.0),
    );
    try drawTransformLabel(canvas, font_id, 222, 113, "chain");
}

fn drawBitmapShowcase(canvas: *gfx.Canvas) !void {
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
}


fn drawFillSwatch(canvas: *gfx.Canvas, font_id: Render.FontId, x: i32, y: i32, label: []const u8, pattern: Render.FillPattern) !void {
    _ = canvas.setTextAlign(.center);
    _ = canvas.setTextBaseline(.top);
    try canvas.textXY(x + 34, y, font_id, label);

    try canvas.rect(
        .{ .x = @intCast(x + 8), .y = @intCast(y + 14), .width = 52, .height = 28 },
        .{ .color = .black, .pattern = pattern },
        .{ .color = .black, .width = 1, .style = .solid },
    );
}

fn drawFillShowcase(canvas: *gfx.Canvas, font_id: Render.FontId) !void {
    try canvas.clear(.white);
    _ = canvas.setTextColor(.black);
    _ = canvas.setStroke(.{ .color = .black, .width = 1, .style = .solid });

    _ = canvas.setTextAlign(.center);
    _ = canvas.setTextBaseline(.top);
    try canvas.text(.{ .x = 148, .y = 2 }, font_id, .black, .center, .top, "Fill Pattern Demo");
    try canvas.lineWith(.{ .x = 0, .y = 17 }, .{ .x = 295, .y = 17 });

    const samples = [_]struct {
        label: []const u8,
        pattern: Render.FillPattern,
    }{
        .{ .label = "solid", .pattern = .solid },
        .{ .label = "checker", .pattern = .checker },
        .{ .label = "diagonal", .pattern = .diagonal },
        .{ .label = "crosshatch", .pattern = .crosshatch },
        .{ .label = "dots", .pattern = .dots },
        .{ .label = "dither", .pattern = .{ .dither = .{ .pattern = .bayer4x4, .weight = 140 } } },
    };

    for (samples, 0..) |sample, i| {
        const col: i32 = @intCast(i % 3);
        const row: i32 = @intCast(i / 3);
        try drawFillSwatch(canvas, font_id, 14 + col * 94, 25 + row * 50, sample.label, sample.pattern);
    }
}

fn drawDitherSwatch(canvas: *gfx.Canvas, font_id: Render.FontId, x: i32, y: i32, label: []const u8, pattern: Render.OrderedDitherPattern) !void {
    _ = canvas.setTextAlign(.center);
    _ = canvas.setTextBaseline(.top);
    try canvas.textXY(x + 34, y, font_id, label);

    try canvas.rect(
        .{ .x = @intCast(x + 8), .y = @intCast(y + 14), .width = 52, .height = 28 },
        .{ .color = .black, .pattern = .{ .dither = .{ .pattern = pattern, .weight = 140 } } },
        .{ .color = .black, .width = 1, .style = .solid },
    );
}

fn drawDitherShowcase(canvas: *gfx.Canvas, font_id: Render.FontId) !void {
    try canvas.clear(.white);
    _ = canvas.setTextColor(.black);
    _ = canvas.setStroke(.{ .color = .black, .width = 1, .style = .solid });

    _ = canvas.setTextAlign(.center);
    _ = canvas.setTextBaseline(.top);
    try canvas.text(.{ .x = 148, .y = 2 }, font_id, .black, .center, .top, "Dither Demo weight=140");
    try canvas.lineWith(.{ .x = 0, .y = 17 }, .{ .x = 295, .y = 17 });

    const samples = [_]struct {
        label: []const u8,
        pattern: Render.OrderedDitherPattern,
    }{
        .{ .label = "bayer2", .pattern = .bayer2x2 },
        .{ .label = "bayer4", .pattern = .bayer4x4 },
        .{ .label = "bayer8", .pattern = .bayer8x8 },
        .{ .label = "cluster4", .pattern = .clustered4x4 },
        .{ .label = "cluster8", .pattern = .clustered8x8 },
        .{ .label = "halftone4", .pattern = .halftone4x4 },
    };

    for (samples, 0..) |sample, i| {
        const col: i32 = @intCast(i % 3);
        const row: i32 = @intCast(i / 3);
        try drawDitherSwatch(canvas, font_id, 14 + col * 94, 25 + row * 50, sample.label, sample.pattern);
    }
}


fn drawNoopShowcase(canvas: *gfx.Canvas) !void {
    try canvas.clear(.white);
    try canvas.submit(.{ .nop = {} });
}

fn drawEverythingShowcase(canvas: *gfx.Canvas, font_id: Render.FontId) !void {
    const fb_w: i32 = @intCast(framebuffer_width);

    try canvas.clear(.white);

    // title / text
    _ = canvas.setTextColor(.black);
    _ = canvas.setTextAlign(.center);
    _ = canvas.setTextBaseline(.top);
    try canvas.text(.{ .x = fb_w / 2, .y = 2 }, font_id, .black, .center, .top, "Everything Demo");

    _ = canvas.setStroke(.{ .color = .black, .width = 1, .style = .solid });
    _ = canvas.setFill(.{ .color = .black });

    try canvas.lineWith(.{ .x = 0, .y = 17 }, .{ .x = 295, .y = 17 });

    // text alignment sample
    _ = canvas.setTextAlign(.left);
    _ = canvas.setTextBaseline(.top);
    try canvas.textXY(4, 21, font_id, "txt");

    // points
    try canvas.pointAt(8, 43);
    try canvas.pointAt(13, 43);
    try canvas.pointAt(18, 43);

    // lines and polyline
    try canvas.line(.{ .x = 30, .y = 24 }, .{ .x = 68, .y = 24 }, .{
        .color = .black,
        .width = 1,
        .style = .solid,
    });
    try canvas.lineWith(.{ .x = 30, .y = 31 }, .{ .x = 68, .y = 45 });
    try canvas.polylineWith(&.{
        .{ .x = 30, .y = 50 },
        .{ .x = 42, .y = 42 },
        .{ .x = 54, .y = 50 },
        .{ .x = 68, .y = 40 },
    });

    // rectangles
    try canvas.rectOutline(78, 23, 18, 14);
    try canvas.rectFilled(101, 23, 18, 14);
    try canvas.roundedRectWith(.{ .x = 124, .y = 22, .width = 24, .height = 16 }, 5);

    // circle / ellipse
    try canvas.circleOutline(164, 31, 9);
    try canvas.circleFilled(188, 31, 9);
    try canvas.ellipseWith(.{ .x = 207, .y = 23, .width = 30, .height = 16 });

    // triangle / polygon
    try canvas.triangleWith(
        .{ .x = 254, .y = 22 },
        .{ .x = 242, .y = 42 },
        .{ .x = 266, .y = 42 },
    );

    try canvas.polygonWith(&.{
        .{ .x = 282, .y = 22 },
        .{ .x = 293, .y = 31 },
        .{ .x = 288, .y = 43 },
        .{ .x = 275, .y = 43 },
        .{ .x = 271, .y = 31 },
    });

    // quadratic + cubic bezier curves
    try canvas.quadraticBezier(
        .{ .x = 8, .y = 86 },
        .{ .x = 36, .y = 54 },
        .{ .x = 64, .y = 86 },
        null,
        .{ .color = .black, .width = 1, .style = .solid },
    );

    try canvas.cubicBezier(
        .{ .x = 74, .y = 86 },
        .{ .x = 90, .y = 54 },
        .{ .x = 120, .y = 54 },
        .{ .x = 136, .y = 86 },
        null,
        .{ .color = .black, .width = 1, .style = .solid },
    );

    // arc
    try canvas.arcWith(.{ .x = 158, .y = 82 }, 16, 0.0, std.math.pi);

    // clipping
    try canvas.clipPushXYWH(181, 62, 42, 26);
    try canvas.rectOutline(181, 62, 42, 26);
    try canvas.circleFilled(202, 75, 24);
    try canvas.clipPop();

    // transform
    try canvas.transformPush(Matrix3.identity());
    try canvas.transformReplace(Matrix3.translation(236.0, 63.0));
    try canvas.rect(
        .{ .x = 0, .y = 0, .width = 24, .height = 18 },
        .{ .color = .black, .pattern = .solid },
        .{ .color = .black, .width = 1, .style = .solid },
    );
    try canvas.transformPop();

    // clearRect punch-out
    try canvas.rectFilled(267, 64, 24, 20);
    try canvas.clearRect(.{ .x = 273, .y = 69, .width = 12, .height = 10 }, .white);

    // bitmap drawing
    try canvas.bitmap(
        .{ .x = 8, .y = 104 },
        8,
        8,
        demo_bitmap_a[0..],
        1,
        .msb_first,
        .replace,
    );

    try canvas.bitmapXY(24, 104, 8, 8, demo_bitmap_b[0..], 1, .lsb_first, .xor);

    // blit
    try canvas.rectFilled(48, 103, 15, 15);
    try canvas.blit(
        .{ .x = 48, .y = 103 },
        .{ .x = 70, .y = 103 },
        .{ .width = 15, .height = 15 },
        .copy,
    );

    // invert
    try canvas.rectOutline(98, 102, 34, 18);
    try canvas.invert(.{ .x = 104, .y = 106, .width = 22, .height = 10 });

    // one invisible command so submit/nop is covered too
    try canvas.submit(.{ .nop = {} });
}

fn writePbm(path: []const u8, framebuffer: *const Render.Framebuffer) !void {
    const cwd = std.fs.cwd();
    if (std.fs.path.dirname(path)) |dir| {
        try cwd.makePath(dir);
    }

    var file = try cwd.createFile(path, .{ .truncate = true });
    defer file.close();

    var header_buf: [64]u8 = undefined;
    const header = try std.fmt.bufPrint(&header_buf, "P4\n{} {}\n", .{ framebuffer.width, framebuffer.height });
    try file.writeAll(header);
    try file.writeAll(framebuffer.pixels);
}

pub fn main() !void {
    std.log.info("Starting desktop rendering demo...", .{});

    var renderer = try gfx.Renderer.init(std.heap.page_allocator, .{
        .clear_on_begin = .white,
        .default_present_mode = .none,
        .framebuffer = Framebuffer.init(framebuffer_width, framebuffer_height, framebuffer_pixels[0..]),
    });
    defer renderer.deinit();

    const font_id = try renderer.registerFont(font.getBlob());

    // Text demo
    var canvas = try renderer.begin();
    try drawTextShowcase(&canvas, font_id);
    try renderer.present(.none);
    try writePbm("desktop-demo-output/text.pbm", renderer.framebuffer());
    std.log.info("wrote text.pbm", .{});

    // Lines demo
    canvas = try renderer.begin();
    try drawLinesShowcase(&canvas);
    try renderer.present(.none);
    try writePbm("desktop-demo-output/lines.pbm", renderer.framebuffer());
    std.log.info("wrote lines.pbm", .{});

    // Polylines demo
    canvas = try renderer.begin();
    try drawPolylinesShowcase(&canvas);
    try renderer.present(.none);
    try writePbm("desktop-demo-output/polylines.pbm", renderer.framebuffer());
    std.log.info("wrote polylines.pbm", .{});

    // Quadratic Bezier demo
    canvas = try renderer.begin();
    try drawQuadraticBezierShowcase(&canvas);
    try renderer.present(.none);
    try writePbm("desktop-demo-output/quadratic_bezier.pbm", renderer.framebuffer());
    std.log.info("wrote quadratic_bezier.pbm", .{});

    // Cubic Bezier demo
    canvas = try renderer.begin();
    try drawCubicBezierShowcase(&canvas);
    try renderer.present(.none);
    try writePbm("desktop-demo-output/cubic_bezier.pbm", renderer.framebuffer());
    std.log.info("wrote cubic_bezier.pbm", .{});

    // Rectangle demo
    canvas = try renderer.begin();
    try drawRectangleShowcase(&canvas);
    try renderer.present(.none);
    try writePbm("desktop-demo-output/rectangle.pbm", renderer.framebuffer());
    std.log.info("wrote rectangle.pbm", .{});

    // Circle demo
    canvas = try renderer.begin();
    try drawCircleShowcase(&canvas);
    try renderer.present(.none);
    try writePbm("desktop-demo-output/circle.pbm", renderer.framebuffer());
    std.log.info("wrote circle.pbm", .{});

    // Triangle demo
    canvas = try renderer.begin();
    try drawTriangleShowcase(&canvas);
    try renderer.present(.none);
    try writePbm("desktop-demo-output/triangle.pbm", renderer.framebuffer());
    std.log.info("wrote triangle.pbm", .{});

    // Point demo
    canvas = try renderer.begin();
    try drawPointShowcase(&canvas);
    try renderer.present(.none);
    try writePbm("desktop-demo-output/point.pbm", renderer.framebuffer());
    std.log.info("wrote point.pbm", .{});

    // Ellipse demo
    canvas = try renderer.begin();
    try drawEllipseShowcase(&canvas);
    try renderer.present(.none);
    try writePbm("desktop-demo-output/ellipse.pbm", renderer.framebuffer());
    std.log.info("wrote ellipse.pbm", .{});

    // Rounded rectangle demo
    canvas = try renderer.begin();
    try drawRoundedRectShowcase(&canvas);
    try renderer.present(.none);
    try writePbm("desktop-demo-output/rounded_rect.pbm", renderer.framebuffer());
    std.log.info("wrote rounded_rect.pbm", .{});

    // Arc demo
    canvas = try renderer.begin();
    try drawArcShowcase(&canvas);
    try renderer.present(.none);
    try writePbm("desktop-demo-output/arc.pbm", renderer.framebuffer());
    std.log.info("wrote arc.pbm", .{});

    // Polygon demo
    canvas = try renderer.begin();
    try drawPolygonShowcase(&canvas);
    try renderer.present(.none);
    try writePbm("desktop-demo-output/polygon.pbm", renderer.framebuffer());
    std.log.info("wrote polygon.pbm", .{});

    // Clipping demo
    canvas = try renderer.begin();
    try drawClippingShowcase(&canvas);
    try renderer.present(.none);
    try writePbm("desktop-demo-output/clipping.pbm", renderer.framebuffer());
    std.log.info("wrote clipping.pbm", .{});

    // Transform demo
    canvas = try renderer.begin();
    try drawTransformShowcase(&canvas, font_id);
    try renderer.present(.none);
    try writePbm("desktop-demo-output/transform.pbm", renderer.framebuffer());
    std.log.info("wrote transform.pbm", .{});

    // Bitmap demo
    canvas = try renderer.begin();
    try drawBitmapShowcase(&canvas);
    try renderer.present(.none);
    try writePbm("desktop-demo-output/bitmap.pbm", renderer.framebuffer());
    std.log.info("wrote bitmap.pbm", .{});

    // Fill pattern demo
    canvas = try renderer.begin();
    try drawFillShowcase(&canvas, font_id);
    try renderer.present(.none);
    try writePbm("desktop-demo-output/fills.pbm", renderer.framebuffer());
    std.log.info("wrote fills.pbm", .{});

    // Dither pattern demo
    canvas = try renderer.begin();
    try drawDitherShowcase(&canvas, font_id);
    try renderer.present(.none);
    try writePbm("desktop-demo-output/dithers.pbm", renderer.framebuffer());
    std.log.info("wrote dithers.pbm", .{});

    // No-op demo
    canvas = try renderer.begin();
    try drawNoopShowcase(&canvas);
    try renderer.present(.none);
    try writePbm("desktop-demo-output/noop.pbm", renderer.framebuffer());
    std.log.info("wrote noop.pbm", .{});

    // Everything combined demo
    canvas = try renderer.begin();
    try drawEverythingShowcase(&canvas, font_id);
    try renderer.present(.none);
    try writePbm("desktop-demo-output/everything.pbm", renderer.framebuffer());
    std.log.info("wrote everything.pbm", .{});

    std.log.info("Desktop demo complete.", .{});
}
