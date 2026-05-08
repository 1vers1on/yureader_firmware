const std = @import("std");
const Matrix3 = @import("util/Matrix3.zig").Matrix3;
const Matrix3Stack = @import("util/Matrix3.zig").Matrix3Stack;
const Vec2 = @import("util/Matrix3.zig").Vec2;

pub const Coord = i16;
pub const Dim = u16;

pub const Color = enum(u1) {
    white = 0,
    black = 1,
};

pub const Point = struct {
    x: Coord,
    y: Coord,
};

pub const Size = struct {
    width: Dim,
    height: Dim,
};

pub const Rect = struct {
    x: Coord,
    y: Coord,
    width: Dim,
    height: Dim,
};

pub const Quad = struct {
    a: Point,
    b: Point,
    c: Point,
    d: Point,
};

pub const StrokeStyle = enum(u8) {
    solid,
    dashed,
    dotted,
};

pub const Stroke = struct {
    color: Color = .black,
    width: u8 = 1,
    style: StrokeStyle = .solid,
};

pub const OrderedDitherPattern = enum(u8) {
    bayer2x2,
    bayer4x4,
    bayer8x8,

    clustered4x4,
    clustered8x8,

    halftone4x4,
};

pub const Dither = struct {
    pattern: OrderedDitherPattern = .bayer2x2,
    weight: u8 = 128, // 0-255, where 0 means no dithering and 255 means full dithering
};

pub const FillPattern = union(enum) {
    solid: void,
    checker: void,
    diagonal: void,
    crosshatch: void,
    dots: void,
    dither: Dither,
};

pub const Fill = struct {
    color: Color = .black,
    pattern: FillPattern = .solid,
};

pub const LineCmd = struct {
    a: Point,
    b: Point,
    stroke: Stroke = .{},
};

pub const RectCmd = struct {
    rect: Rect,
    fill: ?Fill = null,
    stroke: ?Stroke = .{},
};

pub const CircleCmd = struct {
    center: Point,
    radius: Dim,
    fill: ?Fill = null,
    stroke: ?Stroke = .{},
};

pub const TriangleCmd = struct {
    a: Point,
    b: Point,
    c: Point,
    fill: ?Fill = null,
    stroke: ?Stroke = .{},
};

pub const FontId = u16;

pub const TextAlign = enum(u8) {
    left,
    center,
    right,
};

pub const TextBaseline = enum(u8) {
    top,
    middle,
    bottom,
    alphabetic,
};

pub const TextCmd = struct {
    pos: Point,

    text_offset: u32,
    text_len: u16,

    font: FontId,
    color: Color = .black,

    textAlign: TextAlign = .left,
    baseline: TextBaseline = .top,
};

pub const FontMeta = struct {
    width: u16,
    height: u16,
    first_codepoint: u32,
    glyph_count: u16,
    stride_bytes: u16,
    data_offset: u32,
};

// text offset and text len are used to specify text in a seperate buffer

pub const ClearCmd = struct {
    rect: ?Rect = null,
    color: Color = .white,
};

pub const BitmapMode = enum(u8) {
    replace,
    transparent_zero,
    transparent_one,
    xor,
    or_bits,
    and_bits,
};

pub const BitmapBitOrder = enum(u8) {
    msb_first,
    lsb_first,
};

pub const BitmapCmd = struct {
    pos: Point,
    width: Dim,
    height: Dim,

    data_offset: u32,
    data_len: u32,

    stride_bytes: u16 = 0,
    bit_order: BitmapBitOrder = .msb_first,

    mode: BitmapMode = .replace,
};

pub const InvertCmd = struct {
    rect: Rect,
};

pub const ClipCmd = union(enum) {
    push: Rect,
    pop: void,
};

pub const TransformCmd = union(enum) {
    push: Matrix3,
    replace: Matrix3,
    pop: void,
};

pub const PolygonCmd = struct {
    points_offset: u32,
    points_len: u16,
    fill: ?Fill = null,
    stroke: ?Stroke = .{},
};

pub const PolylineCmd = struct {
    points_offset: u32,
    points_len: u16,
    stroke: Stroke = .{},
};

pub const RoundedRectCmd = struct {
    rect: Rect,
    radius: Dim,
    fill: ?Fill = null,
    stroke: ?Stroke = .{},
};

pub const BlitMode = enum(u8) {
    copy,
    xor,
};

pub const BlitCmd = struct {
    src_pos: Point,
    dst_pos: Point,
    size: Size,
    mode: BlitMode,
};

pub const EllipseCmd = struct {
    rect: Rect,
    fill: ?Fill = null,
    stroke: ?Stroke = .{},
};

pub const ArcCmd = struct {
    center: Point,
    radius: Dim,
    start_angle: f64, // in radians
    end_angle: f64, // in radians
    fill: ?Fill = null,
    stroke: ?Stroke = .{},
};

pub const PointCmd = struct {
    point: Point,
    color: Color = .black,
};

pub const QuadraticBezierCmd = struct {
    start: Point,
    control: Point,
    end: Point,
    fill: ?Fill = null,
    stroke: ?Stroke = .{},
};

pub const CubicBezierCmd = struct {
    start: Point,
    control1: Point,
    control2: Point,
    end: Point,
    fill: ?Fill = null,
    stroke: ?Stroke = .{},
};

pub const DrawCmd = union(enum) {
    clear: ClearCmd,

    line: LineCmd,
    rect: RectCmd,
    triangle: TriangleCmd,
    circle: CircleCmd,
    rounded_rect: RoundedRectCmd,
    polygon: PolygonCmd,
    polyline: PolylineCmd,
    ellipse: EllipseCmd,
    arc: ArcCmd,
    text: TextCmd,
    point: PointCmd,
    quadratic_bezier: QuadraticBezierCmd,
    cubic_bezier: CubicBezierCmd,

    blit: BlitCmd,

    bitmap: BitmapCmd,
    invert: InvertCmd,

    clip: ClipCmd,

    transform: TransformCmd,

    nop: void,
};

pub const RefreshMode = enum(u8) {
    full,
    partial,
};

pub const PartialRefreshCmd = struct {
    rect: Rect,
};

pub const DisplayCmd = union(enum) {
    refresh_partial: PartialRefreshCmd,
    refresh_full: void,
};

pub const ZoneId = u16;

pub const RefreshZone = struct {
    id: ZoneId,
    rect: Rect,
};

pub const Scene = struct {
    draw_cmds: std.ArrayListUnmanaged(DrawCmd) = .{},

    text_arena: std.ArrayListUnmanaged(u8) = .{},
    bitmap_arena: std.ArrayListUnmanaged(u8) = .{},
    font_bitmap_arena: std.ArrayListUnmanaged(u8) = .{},
    points_arena: std.ArrayListUnmanaged(Point) = .{},
    fonts: std.ArrayListUnmanaged(FontMeta) = .{},

    zones: std.ArrayListUnmanaged(RefreshZone) = .{},
    display_cmds: std.ArrayListUnmanaged(DisplayCmd) = .{},

    pub fn deinit(self: *Scene, allocator: std.mem.Allocator) void {
        self.draw_cmds.deinit(allocator);
        self.text_arena.deinit(allocator);
        self.bitmap_arena.deinit(allocator);
        self.font_bitmap_arena.deinit(allocator);
        self.points_arena.deinit(allocator);
        self.fonts.deinit(allocator);
        self.zones.deinit(allocator);
        self.display_cmds.deinit(allocator);
    }

    pub fn clearFrame(self: *Scene) void {
        self.draw_cmds.clearRetainingCapacity();
        self.text_arena.clearRetainingCapacity();
        self.bitmap_arena.clearRetainingCapacity();
        self.points_arena.clearRetainingCapacity();
        self.zones.clearRetainingCapacity();
        self.display_cmds.clearRetainingCapacity();
    }

    pub fn dirtyZones(self: *const Scene) []const RefreshZone {
        return self.zones.items;
    }

    pub fn clearDirtyZones(self: *Scene) void {
        self.zones.clearRetainingCapacity();
    }

    pub fn markDirty(self: *Scene, allocator: std.mem.Allocator, rect: Rect) void {
        if (rect.width == 0 or rect.height == 0) return;

        self.zones.append(allocator, .{
            .id = @intCast(self.zones.items.len),
            .rect = rect,
        }) catch {};
    }

    pub fn appendPoints(
        self: *Scene,
        allocator: std.mem.Allocator,
        points: []const Point,
    ) !PolygonCmd {
        if (points.len > std.math.maxInt(u16)) return error.TooManyPoints;
        if (self.points_arena.items.len > std.math.maxInt(u32)) return error.PointArenaTooLarge;

        const offset: u32 = @intCast(self.points_arena.items.len);
        try self.points_arena.appendSlice(allocator, points);

        return .{
            .points_offset = offset,
            .points_len = @intCast(points.len),
        };
    }
};

fn dirtyRectFromPoints(points: []const Point) ?Rect {
    if (points.len == 0) return null;

    var min_x: i32 = @as(i32, points[0].x);
    var max_x: i32 = @as(i32, points[0].x);
    var min_y: i32 = @as(i32, points[0].y);
    var max_y: i32 = @as(i32, points[0].y);

    for (points[1..]) |point| {
        const px: i32 = @as(i32, point.x);
        const py: i32 = @as(i32, point.y);
        if (px < min_x) min_x = px;
        if (px > max_x) max_x = px;
        if (py < min_y) min_y = py;
        if (py > max_y) max_y = py;
    }

    const width = max_x - min_x + 1;
    const height = max_y - min_y + 1;
    if (width <= 0 or height <= 0) return null;

    return .{
        .x = @intCast(min_x),
        .y = @intCast(min_y),
        .width = @intCast(@min(width, std.math.maxInt(Dim))),
        .height = @intCast(@min(height, std.math.maxInt(Dim))),
    };
}

fn expandDirtyRect(rect: Rect, padding: i32) Rect {
    if (padding <= 0) return rect;

    const x = @as(i32, rect.x) - padding;
    const y = @as(i32, rect.y) - padding;
    const width = @as(i32, @intCast(rect.width)) + padding * 2;
    const height = @as(i32, @intCast(rect.height)) + padding * 2;

    return .{
        .x = @intCast(x),
        .y = @intCast(y),
        .width = @intCast(@max(width, 0)),
        .height = @intCast(@max(height, 0)),
    };
}

pub const Framebuffer = struct {
    width: Dim,
    height: Dim,
    pixels: []u8,

    pub fn byteIndex(self: *const Framebuffer, x: Dim, y: Dim) usize {
        return (y * self.width + x) / 8;
    }

    pub fn setPixel(self: *Framebuffer, x: Dim, y: Dim, color: Color) void {
        const idx = self.byteIndex(x, y);
        const bit_index = 7 - (x % 8);
        const mask: u8 = @as(u8, 1) << @intCast(bit_index);

        if (color == .black) {
            self.pixels[idx] |= mask;
        } else {
            self.pixels[idx] &= ~mask;
        }
    }

    pub fn getPixel(self: *const Framebuffer, x: Dim, y: Dim) Color {
        const idx = self.byteIndex(x, y);
        const bit_index = 7 - (x % 8);
        const mask: u8 = @as(u8, 1) << @intCast(bit_index);

        return if ((self.pixels[idx] & mask) != 0)
            .black
        else
            .white;
    }
};

pub const Engine = struct {
    fb: Framebuffer,
    scene: Scene,
};

fn toVec2(point: Point) Vec2 {
    return .{
        .x = @floatFromInt(point.x),
        .y = @floatFromInt(point.y),
    };
}

fn toPoint(vec: Vec2) Point {
    return .{
        .x = @intFromFloat(@round(vec.x)),
        .y = @intFromFloat(@round(vec.y)),
    };
}

fn currentMatrix(stack: *Matrix3Stack) Matrix3 {
    return stack.finalMatrix();
}

pub fn checkClipStack(clip_stack: *std.ArrayListUnmanaged(Rect), point: Point) bool {
    for (clip_stack.items) |rect| {
        if (point.x < rect.x or point.x >= rect.x + @as(Coord, @intCast(rect.width)) or
            point.y < rect.y or point.y >= rect.y + @as(Coord, @intCast(rect.height)))
        {
            return false;
        }
    }
    return true;
}

pub fn putPixelClip(engine: *Engine, x: Dim, y: Dim, color: Color, clip_stack: *std.ArrayListUnmanaged(Rect)) void {
    const point = Point{ .x = @intCast(x), .y = @intCast(y) };
    if (checkClipStack(clip_stack, point)) {
        engine.fb.setPixel(x, y, color);
    }
}

fn putPixelClipSigned(engine: *Engine, x: i32, y: i32, color: Color, clip_stack: *std.ArrayListUnmanaged(Rect)) void {
    if (x < 0 or y < 0) return;

    const ux: Dim = @intCast(x);
    const uy: Dim = @intCast(y);

    if (ux >= engine.fb.width or uy >= engine.fb.height) return;

    putPixelClip(engine, ux, uy, color, clip_stack);
}

fn drawStrokePoint(engine: *Engine, x: i32, y: i32, width: u8, color: Color, clip_stack: *std.ArrayListUnmanaged(Rect)) void {
    if (width == 0) return;

    const width_i32: i32 = @intCast(width);
    const start = -@divFloor(width_i32 - 1, 2);
    const end = start + width_i32;

    var offset_y = start;
    while (offset_y < end) : (offset_y += 1) {
        var offset_x = start;
        while (offset_x < end) : (offset_x += 1) {
            putPixelClipSigned(engine, x + offset_x, y + offset_y, color, clip_stack);
        }
    }
}

fn shouldDrawStep(style: StrokeStyle, step: usize) bool {
    return switch (style) {
        .solid => true,

        // 8 pixels on, 4 pixels off
        .dashed => (step % 12) < 8,

        // draw every 3rd pixel
        .dotted => (step % 3) == 0,
    };
}

fn absDiffI32(a: i32, b: i32) i32 {
    const diff: i64 = @as(i64, a) - @as(i64, b);
    return @intCast(if (diff < 0) -diff else diff);
}

pub fn drawLine(x0: Coord, y0: Coord, x1: Coord, y1: Coord, stroke: Stroke, width: u8, clip_stack: *std.ArrayListUnmanaged(Rect), engine: *Engine) void {
    const x0_i32: i32 = @as(i32, x0);
    const y0_i32: i32 = @as(i32, y0);
    const x1_i32: i32 = @as(i32, x1);
    const y1_i32: i32 = @as(i32, y1);

    const dx = absDiffI32(x1_i32, x0_i32);
    const dy = absDiffI32(y1_i32, y0_i32);

    const sx: i32 = if (x0_i32 < x1_i32) 1 else -1;
    const sy: i32 = if (y0_i32 < y1_i32) 1 else -1;

    var err: i32 = if (dx > dy) dx / 2 else -dy / 2;
    var step: usize = 0;

    var x: i32 = x0_i32;
    var y: i32 = y0_i32;

    while (true) {
        if (shouldDrawStep(stroke.style, step)) {
            drawStrokePoint(engine, x, y, width, stroke.color, clip_stack);
        }

        if (x == x1_i32 and y == y1_i32) break;

        const err2 = err;

        if (err2 > -dx) {
            err -= dy;
            x += sx;
        }
        if (err2 < dy) {
            err += dx;
            y += sy;
        }

        step += 1;
    }
}

fn orderedDitherThreshold(pattern: OrderedDitherPattern, x: i32, y: i32) u8 {
    return switch (pattern) {
        .bayer2x2 => blk: {
            const bx: usize = @intCast(@mod(x, 2));
            const by: usize = @intCast(@mod(y, 2));

            const matrix = [_][2]u8{
                .{ 0, 128 },
                .{ 192, 64 },
            };

            break :blk matrix[by][bx];
        },

        .bayer4x4 => blk: {
            const bx: usize = @intCast(@mod(x, 4));
            const by: usize = @intCast(@mod(y, 4));

            const matrix = [_][4]u8{
                .{ 0, 128, 32, 160 },
                .{ 192, 64, 224, 96 },
                .{ 48, 176, 16, 144 },
                .{ 240, 112, 208, 80 },
            };

            break :blk matrix[by][bx];
        },

        .bayer8x8 => blk: {
            const bx: usize = @intCast(@mod(x, 8));
            const by: usize = @intCast(@mod(y, 8));

            const matrix = [_][8]u8{
                .{ 0, 128, 32, 160, 8, 136, 40, 168 },
                .{ 192, 64, 224, 96, 200, 72, 232, 104 },
                .{ 48, 176, 16, 144, 56, 184, 24, 152 },
                .{ 240, 112, 208, 80, 248, 120, 216, 88 },
                .{ 12, 140, 44, 172, 4, 132, 36, 164 },
                .{ 204, 76, 236, 108, 196, 68, 228, 100 },
                .{ 60, 188, 28, 156, 52, 180, 20, 148 },
                .{ 252, 124, 220, 92, 244, 116, 212, 84 },
            };

            break :blk matrix[by][bx];
        },

        .clustered4x4 => blk: {
            const bx: usize = @intCast(@mod(x, 4));
            const by: usize = @intCast(@mod(y, 4));

            const matrix = [_][4]u8{
                .{ 192, 128, 160, 224 },
                .{ 96, 0, 32, 128 },
                .{ 160, 64, 32, 192 },
                .{ 224, 160, 128, 240 },
            };

            break :blk matrix[by][bx];
        },

        .clustered8x8 => blk: {
            const bx: usize = @intCast(@mod(x, 8));
            const by: usize = @intCast(@mod(y, 8));

            const matrix = [_][8]u8{
                .{ 248, 200, 168, 152, 160, 184, 224, 240 },
                .{ 216, 144, 96, 72, 80, 120, 176, 232 },
                .{ 192, 104, 40, 16, 24, 56, 136, 208 },
                .{ 184, 88, 32, 0, 8, 48, 128, 200 },
                .{ 208, 112, 64, 24, 16, 40, 104, 192 },
                .{ 232, 168, 128, 80, 72, 96, 144, 216 },
                .{ 240, 224, 184, 152, 160, 176, 200, 248 },
                .{ 252, 240, 216, 192, 200, 224, 248, 252 },
            };

            break :blk matrix[by][bx];
        },

        .halftone4x4 => blk: {
            const bx: usize = @intCast(@mod(x, 4));
            const by: usize = @intCast(@mod(y, 4));

            const matrix = [_][4]u8{
                .{ 224, 128, 160, 240 },
                .{ 96, 0, 32, 192 },
                .{ 144, 64, 16, 176 },
                .{ 248, 208, 112, 232 },
            };

            break :blk matrix[by][bx];
        },
    };
}

fn invertColor(color: Color) Color {
    return switch (color) {
        .black => .white,
        .white => .black,
    };
}

pub fn fillColor(fill: Fill, x: i32, y: i32) Color {
    const on = switch (fill.pattern) {
        .solid => true,

        .checker => ((@divFloor(x, 4) + @divFloor(y, 4)) & 1) == 0,

        .diagonal => @mod(x + y, 8) < 4,

        .crosshatch => (@mod(x + y, 8) == 0) or (@mod(x - y, 8) == 0),

        .dots => (@mod(x, 6) == 0) and (@mod(y, 6) == 0),

        .dither => |dither| dither.weight > orderedDitherThreshold(dither.pattern, x, y),
    };

    return if (on) fill.color else invertColor(fill.color);
}

fn bitmapStrideBytes(width: Dim, stride_bytes: u16) usize {
    if (stride_bytes != 0) return @intCast(stride_bytes);

    const width_u32: u32 = @intCast(width);
    return @intCast((width_u32 + 7) / 8);
}

fn bitmapBit(data: []const u8, stride_bytes: usize, x: usize, y: usize, bit_order: BitmapBitOrder) ?bool {
    const row_offset = y * stride_bytes;
    const byte_index = x / 8;
    const idx = row_offset + byte_index;
    if (idx >= data.len) return null;

    const bit_index = x % 8;
    const mask: u8 = switch (bit_order) {
        .msb_first => @as(u8, 0x80) >> @intCast(bit_index),
        .lsb_first => @as(u8, 1) << @intCast(bit_index),
    };

    return (data[idx] & mask) != 0;
}

pub fn registerFont(scene: *Scene, allocator: std.mem.Allocator, font_data: []const u8) !FontId {
    const header_size: usize = 18;
    if (font_data.len < header_size) return error.InvalidFont;

    if (!std.mem.eql(u8, font_data[0..4], "YFNT")) return error.InvalidFont;

    const width: u16 =
        @as(u16, font_data[6]) |
        (@as(u16, font_data[7]) << 8);

    const height: u16 =
        @as(u16, font_data[8]) |
        (@as(u16, font_data[9]) << 8);

    const first: u32 =
        @as(u32, font_data[10]) |
        (@as(u32, font_data[11]) << 8) |
        (@as(u32, font_data[12]) << 16) |
        (@as(u32, font_data[13]) << 24);

    const glyph_count: u16 =
        @as(u16, font_data[14]) |
        (@as(u16, font_data[15]) << 8);

    var stride_bytes: u16 =
        @as(u16, font_data[16]) |
        (@as(u16, font_data[17]) << 8);

    if (width == 0 or height == 0 or glyph_count == 0) return error.InvalidFont;

    if (stride_bytes == 0) {
        stride_bytes = @intCast((@as(usize, width) + 7) / 8);
    }

    const glyph_size: usize = @as(usize, stride_bytes) * @as(usize, height);
    const data_len: usize = @as(usize, glyph_count) * glyph_size;

    if (font_data.len < header_size + data_len) return error.InvalidFont;

    const data_offset: u32 = @intCast(scene.font_bitmap_arena.items.len);

    try scene.font_bitmap_arena.appendSlice(
        allocator,
        font_data[header_size .. header_size + data_len],
    );

    const meta: FontMeta = .{
        .width = width,
        .height = height,
        .first_codepoint = first,
        .glyph_count = glyph_count,
        .stride_bytes = stride_bytes,
        .data_offset = data_offset,
    };

    try scene.fonts.append(allocator, meta);
    return @intCast(scene.fonts.items.len - 1);
}

fn getFontMeta(scene: *Scene, id: FontId) ?*FontMeta {
    const idx: usize = @intCast(id);
    if (idx >= scene.fonts.items.len) return null;
    return &scene.fonts.items[idx];
}

fn applyBitmapMode(engine: *Engine, x: i32, y: i32, bit_set: bool, mode: BitmapMode, clip_stack: *std.ArrayListUnmanaged(Rect)) void {
    switch (mode) {
        .replace => {
            const color: Color = if (bit_set) .black else .white;
            putPixelClipSigned(engine, x, y, color, clip_stack);
        },
        .transparent_zero => {
            if (bit_set) {
                putPixelClipSigned(engine, x, y, .black, clip_stack);
            }
        },
        .transparent_one => {
            if (!bit_set) {
                putPixelClipSigned(engine, x, y, .white, clip_stack);
            }
        },
        .xor, .or_bits, .and_bits => {
            if (x < 0 or y < 0) return;

            const ux: Dim = @intCast(x);
            const uy: Dim = @intCast(y);

            if (ux >= engine.fb.width or uy >= engine.fb.height) return;

            const point = Point{ .x = @intCast(x), .y = @intCast(y) };
            if (!checkClipStack(clip_stack, point)) return;

            const current = engine.fb.getPixel(ux, uy);
            const current_bit = current == .black;
            const next_bit = switch (mode) {
                .xor => current_bit != bit_set,
                .or_bits => current_bit or bit_set,
                .and_bits => current_bit and bit_set,
                else => unreachable,
            };
            const next_color: Color = if (next_bit) .black else .white;
            engine.fb.setPixel(ux, uy, next_color);
        },
    }
}

pub fn edge(ax: i32, ay: i32, bx: i32, by: i32, cx: i32, cy: i32) i64 {
    return @as(i64, (cx - ax)) * @as(i64, (by - ay)) - @as(i64, (cy - ay)) * @as(i64, (bx - ax));
}

pub fn drawFilledTriangle(engine: *Engine, ax: i32, ay: i32, bx: i32, by: i32, cx: i32, cy: i32, fill: Fill, clip_stack: *std.ArrayListUnmanaged(Rect)) void {
    const area = edge(ax, ay, bx, by, cx, cy);
    if (area == 0) return;

    var min_x = ax;
    if (bx < min_x) min_x = bx;
    if (cx < min_x) min_x = cx;

    var max_x = ax;
    if (bx > max_x) max_x = bx;
    if (cx > max_x) max_x = cx;

    var min_y = ay;
    if (by < min_y) min_y = by;
    if (cy < min_y) min_y = cy;

    var max_y = ay;
    if (by > max_y) max_y = by;
    if (cy > max_y) max_y = cy;

    if (min_x < 0) min_x = 0;
    if (min_y < 0) min_y = 0;

    const fb_max_x: i32 = @as(i32, @intCast(engine.fb.width)) - 1;
    const fb_max_y: i32 = @as(i32, @intCast(engine.fb.height)) - 1;
    if (max_x > fb_max_x) max_x = fb_max_x;
    if (max_y > fb_max_y) max_y = fb_max_y;

    if (min_x > max_x or min_y > max_y) return;

    const sample_x_offset: i32 = 1;
    const sample_y_offset: i32 = 1;
    const area_is_positive = area > 0;

    var y = min_y;
    while (y <= max_y) : (y += 1) {
        var x = min_x;
        while (x <= max_x) : (x += 1) {
            const px = x * 2 + sample_x_offset;
            const py = y * 2 + sample_y_offset;

            const w0 = edge(bx * 2, by * 2, cx * 2, cy * 2, px, py);
            const w1 = edge(cx * 2, cy * 2, ax * 2, ay * 2, px, py);
            const w2 = edge(ax * 2, ay * 2, bx * 2, by * 2, px, py);

            const inside = if (area_is_positive)
                w0 >= 0 and w1 >= 0 and w2 >= 0
            else
                w0 <= 0 and w1 <= 0 and w2 <= 0;

            if (inside) {
                putPixelClipSigned(engine, x, y, fillColor(fill, x, y), clip_stack);
            }
        }
    }
}

fn angleLess(center: Point, a: Point, b: Point) bool {
    const ax: f64 = @floatFromInt(a.x - center.x);
    const ay: f64 = @floatFromInt(a.y - center.y);
    const bx: f64 = @floatFromInt(b.x - center.x);
    const by: f64 = @floatFromInt(b.y - center.y);

    const angle_a = std.math.atan2(ay, ax);
    const angle_b = std.math.atan2(by, bx);

    return angle_a < angle_b;
}

fn orderQuadrilateralPoints(quad: Quad) Quad {
    const center = Point{
        .x = @intCast((@as(i32, quad.a.x) + @as(i32, quad.b.x) + @as(i32, quad.c.x) + @as(i32, quad.d.x)) / 4),
        .y = @intCast((@as(i32, quad.a.y) + @as(i32, quad.b.y) + @as(i32, quad.c.y) + @as(i32, quad.d.y)) / 4),
    };

    var points = [4]Point{ quad.a, quad.b, quad.c, quad.d };

    // std.sort usage with a context isn't portable here; do a simple insertion sort
    // using angleLess relative to the computed center.
    for (1..points.len) |i| {
        var j: usize = i;
        while (j > 0 and angleLess(center, points[j], points[j - 1])) : (j -= 1) {
            const tmp = points[j - 1];
            points[j - 1] = points[j];
            points[j] = tmp;
        }
    }

    return Quad{
        .a = points[0],
        .b = points[1],
        .c = points[2],
        .d = points[3],
    };
}

fn transformRectToBounds(rect: Rect, matrix: Matrix3) Rect {
    const points = .{
        Point{ .x = rect.x, .y = rect.y },
        Point{ .x = rect.x + @as(Coord, @intCast(rect.width)), .y = rect.y },
        Point{ .x = rect.x + @as(Coord, @intCast(rect.width)), .y = rect.y + @as(Coord, @intCast(rect.height)) },
        Point{ .x = rect.x, .y = rect.y + @as(Coord, @intCast(rect.height)) },
    };

    const p0 = matrix.transformPoint(toVec2(points[0]));
    var min_x = p0.x;
    var max_x = p0.x;
    var min_y = p0.y;
    var max_y = p0.y;

    for (points[1..]) |point| {
        const p = matrix.transformPoint(toVec2(point));
        if (p.x < min_x) min_x = p.x;
        if (p.x > max_x) max_x = p.x;
        if (p.y < min_y) min_y = p.y;
        if (p.y > max_y) max_y = p.y;
    }

    const min_x_i32: i32 = @intFromFloat(@floor(min_x));
    const max_x_i32: i32 = @intFromFloat(@ceil(max_x));
    const min_y_i32: i32 = @intFromFloat(@floor(min_y));
    const max_y_i32: i32 = @intFromFloat(@ceil(max_y));

    const min_coord: i32 = std.math.minInt(Coord);
    const max_coord: i32 = std.math.maxInt(Coord);

    const clamped_min_x = std.math.clamp(min_x_i32, min_coord, max_coord);
    const clamped_max_x = std.math.clamp(max_x_i32, min_coord, max_coord);
    const clamped_min_y = std.math.clamp(min_y_i32, min_coord, max_coord);
    const clamped_max_y = std.math.clamp(max_y_i32, min_coord, max_coord);

    var width_i32 = clamped_max_x - clamped_min_x;
    var height_i32 = clamped_max_y - clamped_min_y;
    if (width_i32 < 0) width_i32 = 0;
    if (height_i32 < 0) height_i32 = 0;

    const max_dim: i32 = std.math.maxInt(Dim);
    if (width_i32 > max_dim) width_i32 = max_dim;
    if (height_i32 > max_dim) height_i32 = max_dim;

    return .{
        .x = @intCast(clamped_min_x),
        .y = @intCast(clamped_min_y),
        .width = @intCast(width_i32),
        .height = @intCast(height_i32),
    };
}

pub fn drawCircle(
    engine: *Engine,
    center_x: i32,
    center_y: i32,
    radius: i32,
    fill: ?Fill,
    stroke: ?Stroke,
    clip_stack: *std.ArrayListUnmanaged(Rect),
) void {
    if (radius <= 0) return;

    const r2 = @as(i64, radius) * @as(i64, radius);

    var y: i32 = -radius;
    while (y <= radius) : (y += 1) {
        var x: i32 = -radius;
        while (x <= radius) : (x += 1) {
            const px = center_x + x;
            const py = center_y + y;
            const d2 = @as(i64, x) * @as(i64, x) + @as(i64, y) * @as(i64, y);

            if (fill) |f| {
                if (d2 <= r2) {
                    putPixelClipSigned(engine, px, py, fillColor(f, px, py), clip_stack);
                }
            }

            if (stroke) |s| {
                const w = @as(i64, s.width);
                if (d2 >= r2 - w * @as(i64, radius) and
                    d2 <= r2 + w * @as(i64, radius))
                {
                    drawStrokePoint(engine, px, py, s.width, s.color, clip_stack);
                }
            }
        }
    }
}

fn clearRectRegion(engine: *Engine, rect: Rect, color: Color, clip_stack: *std.ArrayListUnmanaged(Rect)) void {
    const rect_x0: i32 = @as(i32, rect.x);
    const rect_y0: i32 = @as(i32, rect.y);
    const rect_w: i32 = @as(i32, @intCast(rect.width));
    const rect_h: i32 = @as(i32, @intCast(rect.height));

    if (rect_w <= 0 or rect_h <= 0) return;

    var x0 = rect_x0;
    var y0 = rect_y0;
    var x1 = rect_x0 + rect_w - 1;
    var y1 = rect_y0 + rect_h - 1;

    if (x0 < 0) x0 = 0;
    if (y0 < 0) y0 = 0;

    const fb_max_x: i32 = @as(i32, @intCast(engine.fb.width)) - 1;
    const fb_max_y: i32 = @as(i32, @intCast(engine.fb.height)) - 1;
    if (x1 > fb_max_x) x1 = fb_max_x;
    if (y1 > fb_max_y) y1 = fb_max_y;

    if (x0 > x1 or y0 > y1) return;

    var y = y0;
    while (y <= y1) : (y += 1) {
        var x = x0;
        while (x <= x1) : (x += 1) {
            putPixelClipSigned(engine, x, y, color, clip_stack);
        }
    }
}

fn invertRectRegion(engine: *Engine, rect: Rect, clip_stack: *std.ArrayListUnmanaged(Rect)) void {
    const rect_x0: i32 = @as(i32, rect.x);
    const rect_y0: i32 = @as(i32, rect.y);
    const rect_w: i32 = @as(i32, @intCast(rect.width));
    const rect_h: i32 = @as(i32, @intCast(rect.height));

    if (rect_w <= 0 or rect_h <= 0) return;

    var x0 = rect_x0;
    var y0 = rect_y0;
    var x1 = rect_x0 + rect_w - 1;
    var y1 = rect_y0 + rect_h - 1;

    if (x0 < 0) x0 = 0;
    if (y0 < 0) y0 = 0;

    const fb_max_x: i32 = @as(i32, @intCast(engine.fb.width)) - 1;
    const fb_max_y: i32 = @as(i32, @intCast(engine.fb.height)) - 1;
    if (x1 > fb_max_x) x1 = fb_max_x;
    if (y1 > fb_max_y) y1 = fb_max_y;

    if (x0 > x1 or y0 > y1) return;

    var y = y0;
    while (y <= y1) : (y += 1) {
        var x = x0;
        while (x <= x1) : (x += 1) {
            const point = Point{ .x = @intCast(x), .y = @intCast(y) };
            if (checkClipStack(clip_stack, point)) {
                const ux: Dim = @intCast(x);
                const uy: Dim = @intCast(y);
                const current = engine.fb.getPixel(ux, uy);
                const next: Color = if (current == .black) .white else .black;
                engine.fb.setPixel(ux, uy, next);
            }
        }
    }
}

fn blitRectRegion(engine: *Engine, src_pos: Point, dst_pos: Point, size: Size, mode: BlitMode, clip_stack: *std.ArrayListUnmanaged(Rect)) void {
    const width: i32 = @as(i32, @intCast(size.width));
    const height: i32 = @as(i32, @intCast(size.height));

    if (width <= 0 or height <= 0) return;

    const src_x0: i32 = @as(i32, src_pos.x);
    const src_y0: i32 = @as(i32, src_pos.y);
    const dst_x0: i32 = @as(i32, dst_pos.x);
    const dst_y0: i32 = @as(i32, dst_pos.y);

    const copy_y_reverse = dst_y0 > src_y0;
    const copy_x_reverse = dst_y0 == src_y0 and dst_x0 > src_x0;

    var y_offset: i32 = if (copy_y_reverse) height - 1 else 0;
    while (if (copy_y_reverse) y_offset >= 0 else y_offset < height) : (y_offset += if (copy_y_reverse) -1 else 1) {
        var x_offset: i32 = if (copy_x_reverse) width - 1 else 0;
        while (if (copy_x_reverse) x_offset >= 0 else x_offset < width) : (x_offset += if (copy_x_reverse) -1 else 1) {
            const src_x = src_x0 + x_offset;
            const src_y = src_y0 + y_offset;
            const dst_x = dst_x0 + x_offset;
            const dst_y = dst_y0 + y_offset;

            if (src_x < 0 or src_y < 0 or dst_x < 0 or dst_y < 0) continue;

            const src_ux: Dim = @intCast(src_x);
            const src_uy: Dim = @intCast(src_y);
            const dst_ux: Dim = @intCast(dst_x);
            const dst_uy: Dim = @intCast(dst_y);

            if (src_ux >= engine.fb.width or src_uy >= engine.fb.height) continue;
            if (dst_ux >= engine.fb.width or dst_uy >= engine.fb.height) continue;

            const dst_point = Point{ .x = @intCast(dst_x), .y = @intCast(dst_y) };
            if (!checkClipStack(clip_stack, dst_point)) continue;

            const src_bit_set = engine.fb.getPixel(src_ux, src_uy) == .black;
            const dst_bit_set = engine.fb.getPixel(dst_ux, dst_uy) == .black;

            const next_bit_set = switch (mode) {
                .copy => src_bit_set,
                .xor => dst_bit_set != src_bit_set,
            };

            engine.fb.setPixel(dst_ux, dst_uy, if (next_bit_set) .black else .white);
        }
    }
}

inline fn cross(ax: i32, ay: i32, bx: i32, by: i32) i64 {
    return @as(i64, ax) * by - @as(i64, ay) * bx;
}

inline fn cross64(ax: i64, ay: i64, bx: i64, by: i64) i64 {
    return ax * by - ay * bx;
}

fn polygonArea(points: []const Point) f64 {
    var area: i64 = 0;
    for (0..points.len) |i| {
        const point = points[i];
        const next = points[@mod(i + 1, points.len)];
        area += cross(@as(i32, point.x), @as(i32, point.y), @as(i32, next.x), @as(i32, next.y));
    }
    return @as(f64, area) / 2.0;
}

fn pointInTriangle(
    px: i32,
    py: i32,
    ax: i32,
    ay: i32,
    bx: i32,
    by: i32,
    cx: i32,
    cy: i32,
) bool {
    const pxx = @as(i64, px);
    const pyy = @as(i64, py);
    const axx = @as(i64, ax);
    const ayy = @as(i64, ay);
    const bxx = @as(i64, bx);
    const byy = @as(i64, by);
    const cxx = @as(i64, cx);
    const cyy = @as(i64, cy);

    const ab = cross64(bxx - axx, byy - ayy, pxx - axx, pyy - ayy);
    const bc = cross64(cxx - bxx, cyy - byy, pxx - bxx, pyy - byy);
    const ca = cross64(axx - cxx, ayy - cyy, pxx - cxx, pyy - cyy);

    const has_neg = ab < 0 or bc < 0 or ca < 0;
    const has_pos = ab > 0 or bc > 0 or ca > 0;

    return !(has_neg and has_pos);
}

// output is a list of vertices in groups of 3 representing triangles that cover the polygon
// output is a list of vertices in groups of 3 representing triangles that cover the polygon.
// caller owns the returned slice and must allocator.free(result).
fn earClipTriangulate(allocator: std.mem.Allocator, points: []const Point) ![]Point {
    if (points.len < 3) return error.InvalidPolygon;

    // remove duplicate adjacent points, and also a repeated closing point if present.
    var raw_indices = try allocator.alloc(usize, points.len);
    defer allocator.free(raw_indices);

    var raw_len: usize = 0;
    for (0..points.len) |i| {
        const p = points[i];
        if (raw_len == 0 or !samePoint(points[raw_indices[raw_len - 1]], p)) {
            raw_indices[raw_len] = i;
            raw_len += 1;
        }
    }

    if (raw_len > 1 and samePoint(points[raw_indices[0]], points[raw_indices[raw_len - 1]])) {
        raw_len -= 1;
    }

    if (raw_len < 3) return error.InvalidPolygon;

    const area2 = polygonArea2Indexed(points, raw_indices[0..raw_len]);
    if (area2 == 0) return error.InvalidPolygon;

    // verts is the active polygon, normalized to ccw order.
    var verts = try allocator.alloc(usize, raw_len);
    defer allocator.free(verts);

    if (area2 > 0) {
        @memcpy(verts, raw_indices[0..raw_len]);
    } else {
        for (0..raw_len) |i| {
            verts[i] = raw_indices[raw_len - 1 - i];
        }
    }

    var remaining = raw_len;

    var triangles = try allocator.alloc(Point, (raw_len - 2) * 3);
    errdefer allocator.free(triangles);

    var out_i: usize = 0;

    while (remaining > 3) {
        var clipped = false;

        for (0..remaining) |i| {
            const prev_i = if (i == 0) remaining - 1 else i - 1;
            const next_i = if (i + 1 == remaining) 0 else i + 1;

            const ai = verts[prev_i];
            const bi = verts[i];
            const ci = verts[next_i];

            const a = points[ai];
            const b = points[bi];
            const c = points[ci];

            if (orient(a, b, c) <= 0) continue;

            var contains_point = false;

            for (0..remaining) |j| {
                if (j == prev_i or j == i or j == next_i) continue;

                const pi = verts[j];
                const p = points[pi];

                if (pointInTriangle(
                    @as(i32, p.x),
                    @as(i32, p.y),
                    @as(i32, a.x),
                    @as(i32, a.y),
                    @as(i32, b.x),
                    @as(i32, b.y),
                    @as(i32, c.x),
                    @as(i32, c.y),
                )) {
                    contains_point = true;
                    break;
                }
            }

            if (contains_point) continue;

            triangles[out_i + 0] = a;
            triangles[out_i + 1] = b;
            triangles[out_i + 2] = c;
            out_i += 3;

            std.mem.copyForwards(
                usize,
                verts[i .. remaining - 1],
                verts[i + 1 .. remaining],
            );

            remaining -= 1;
            clipped = true;
            break;
        }

        if (!clipped) return error.InvalidPolygon;
    }

    const a = points[verts[0]];
    const b = points[verts[1]];
    const c = points[verts[2]];

    if (orient(a, b, c) <= 0) return error.InvalidPolygon;

    triangles[out_i + 0] = a;
    triangles[out_i + 1] = b;
    triangles[out_i + 2] = c;
    out_i += 3;

    return triangles[0..out_i];
}

fn samePoint(a: Point, b: Point) bool {
    return a.x == b.x and a.y == b.y;
}

fn orient(a: Point, b: Point, c: Point) i64 {
    return cross64(
        @as(i64, b.x) - @as(i64, a.x),
        @as(i64, b.y) - @as(i64, a.y),
        @as(i64, c.x) - @as(i64, a.x),
        @as(i64, c.y) - @as(i64, a.y),
    );
}

fn clampF32(value: f32, min: f32, max: f32) f32 {
    if (value < min) return min;
    if (value > max) return max;
    return value;
}

fn vecLen(vec: Vec2) f32 {
    return std.math.sqrt(vec.x * vec.x + vec.y * vec.y);
}

fn roundedRectRadius(width: Dim, height: Dim, radius: Dim) f32 {
    var r: f32 = @floatFromInt(radius);
    const half_w: f32 = @as(f32, @floatFromInt(width)) / 2.0;
    const half_h: f32 = @as(f32, @floatFromInt(height)) / 2.0;

    if (r > half_w) r = half_w;
    if (r > half_h) r = half_h;

    return r;
}

fn roundedRectSignedDistance(local_x: f32, local_y: f32, width: f32, height: f32, radius: f32) f32 {
    const half_w = width / 2.0;
    const half_h = height / 2.0;

    const qx = @abs(local_x - half_w) - (half_w - radius);
    const qy = @abs(local_y - half_h) - (half_h - radius);

    const outside_x = if (qx > 0.0) qx else 0.0;
    const outside_y = if (qy > 0.0) qy else 0.0;

    const max_q = if (qx > qy) qx else qy;
    const inside = if (max_q < 0.0) max_q else 0.0;

    return std.math.sqrt(outside_x * outside_x + outside_y * outside_y) + inside - radius;
}

fn rectStrokeStep(local_x: f32, local_y: f32, width: f32, height: f32) usize {
    var best = @abs(local_y);
    var side: u8 = 0;

    const right = @abs(local_x - width);
    if (right < best) {
        best = right;
        side = 1;
    }

    const bottom = @abs(local_y - height);
    if (bottom < best) {
        best = bottom;
        side = 2;
    }

    const left = @abs(local_x);
    if (left < best) {
        side = 3;
    }

    var pos: f32 = switch (side) {
        0 => clampF32(local_x, 0.0, width),
        1 => width + clampF32(local_y, 0.0, height),
        2 => width + height + clampF32(width - local_x, 0.0, width),
        else => width + height + width + clampF32(height - local_y, 0.0, height),
    };

    if (pos < 0.0) pos = 0.0;
    return @intFromFloat(@floor(pos));
}

fn roundedRectStrokeStep(local_x: f32, local_y: f32, width: f32, height: f32, radius: f32) usize {
    if (radius <= 0.0) return rectStrokeStep(local_x, local_y, width, height);

    const pi: f32 = std.math.pi;
    const two_pi = pi * 2.0;

    const top_len = width - radius * 2.0;
    const side_len = height - radius * 2.0;
    const arc_len = pi * radius / 2.0;

    const right_x = width - radius;
    const bottom_y = height - radius;

    var pos: f32 = 0.0;

    if (local_y < radius and local_x > right_x) {
        const angle = std.math.atan2(local_y - radius, local_x - right_x);
        const t = clampF32(angle + pi / 2.0, 0.0, pi / 2.0);
        pos = top_len + t * radius;
    } else if (local_x > right_x and local_y > bottom_y) {
        const angle = std.math.atan2(local_y - bottom_y, local_x - right_x);
        const t = clampF32(angle, 0.0, pi / 2.0);
        pos = top_len + arc_len + side_len + t * radius;
    } else if (local_y > bottom_y and local_x < radius) {
        const angle = std.math.atan2(local_y - bottom_y, local_x - radius);
        const t = clampF32(angle - pi / 2.0, 0.0, pi / 2.0);
        pos = top_len + arc_len + side_len + arc_len + top_len + t * radius;
    } else if (local_x < radius and local_y < radius) {
        var angle = std.math.atan2(local_y - radius, local_x - radius);
        if (angle < 0.0) angle += two_pi;
        const t = clampF32(angle - pi, 0.0, pi / 2.0);
        pos = top_len + arc_len + side_len + arc_len + top_len + arc_len + side_len + t * radius;
    } else if (local_y < radius) {
        pos = clampF32(local_x - radius, 0.0, top_len);
    } else if (local_x > right_x) {
        pos = top_len + arc_len + clampF32(local_y - radius, 0.0, side_len);
    } else if (local_y > bottom_y) {
        pos = top_len + arc_len + side_len + arc_len + clampF32(right_x - local_x, 0.0, top_len);
    } else if (local_x < radius) {
        pos = top_len + arc_len + side_len + arc_len + top_len + arc_len + clampF32(bottom_y - local_y, 0.0, side_len);
    } else {
        return rectStrokeStep(local_x, local_y, width, height);
    }

    if (pos < 0.0) pos = 0.0;
    return @intFromFloat(@floor(pos));
}

pub fn drawRoundedRect(
    engine: *Engine,
    rect: Rect,
    radius_dim: Dim,
    fill: ?Fill,
    stroke: ?Stroke,
    matrix: Matrix3,
    clip_stack: *std.ArrayListUnmanaged(Rect),
) void {
    if (rect.width == 0 or rect.height == 0) return;

    const translate = Matrix3.translation(
        @floatFromInt(rect.x),
        @floatFromInt(rect.y),
    );

    const rounded_rect_matrix = Matrix3.mul(matrix, translate);
    const inv = rounded_rect_matrix.inverse() orelse return;

    const bounds = transformRectToBounds(.{
        .x = 0,
        .y = 0,
        .width = rect.width,
        .height = rect.height,
    }, rounded_rect_matrix);

    const bounds_w: i32 = @intCast(bounds.width);
    const bounds_h: i32 = @intCast(bounds.height);
    if (bounds_w <= 0 or bounds_h <= 0) return;

    if (engine.fb.width == 0 or engine.fb.height == 0) return;

    var x0: i32 = @as(i32, bounds.x);
    var y0: i32 = @as(i32, bounds.y);
    var x1: i32 = x0 + bounds_w - 1;
    var y1: i32 = y0 + bounds_h - 1;

    if (x0 < 0) x0 = 0;
    if (y0 < 0) y0 = 0;

    const fb_max_x: i32 = @as(i32, @intCast(engine.fb.width)) - 1;
    const fb_max_y: i32 = @as(i32, @intCast(engine.fb.height)) - 1;

    if (x1 > fb_max_x) x1 = fb_max_x;
    if (y1 > fb_max_y) y1 = fb_max_y;

    if (x0 > x1 or y0 > y1) return;

    const width_f: f32 = @floatFromInt(rect.width);
    const height_f: f32 = @floatFromInt(rect.height);
    const radius = roundedRectRadius(rect.width, rect.height, radius_dim);

    const x_vec = rounded_rect_matrix.transformVector(.{ .x = 1.0, .y = 0.0 });
    const y_vec = rounded_rect_matrix.transformVector(.{ .x = 0.0, .y = 1.0 });

    var stroke_scale = (vecLen(x_vec) + vecLen(y_vec)) / 2.0;
    if (stroke_scale <= 0.0001) stroke_scale = 1.0;

    var y = y0;
    while (y <= y1) : (y += 1) {
        var x = x0;
        while (x <= x1) : (x += 1) {
            const sample = inv.transformPoint(.{
                .x = @as(f32, @floatFromInt(x)) + 0.5,
                .y = @as(f32, @floatFromInt(y)) + 0.5,
            });

            const dist = roundedRectSignedDistance(sample.x, sample.y, width_f, height_f, radius);

            if (fill) |f| {
                if (dist <= 0.0) {
                    putPixelClipSigned(engine, x, y, fillColor(f, x, y), clip_stack);
                }
            }

            if (stroke) |s| {
                if (s.width == 0) continue;

                const half_stroke_width: f32 = @as(f32, @floatFromInt(s.width)) / 2.0;
                const screen_dist = @abs(dist * stroke_scale);

                if (screen_dist <= half_stroke_width and
                    shouldDrawStep(s.style, roundedRectStrokeStep(sample.x, sample.y, width_f, height_f, radius)))
                {
                    putPixelClipSigned(engine, x, y, s.color, clip_stack);
                }
            }
        }
    }
}

fn polygonArea2Indexed(points: []const Point, indices: []const usize) i64 {
    var area2: i64 = 0;

    for (0..indices.len) |i| {
        const idx = indices[i];
        const next_idx = indices[if (i + 1 == indices.len) 0 else i + 1];

        const p = points[idx];
        const q = points[next_idx];

        area2 += cross(
            @as(i32, p.x),
            @as(i32, p.y),
            @as(i32, q.x),
            @as(i32, q.y),
        );
    }

    return area2;
}

fn vec2Mid(a: Vec2, b: Vec2) Vec2 {
    return .{
        .x = (a.x + b.x) / 2.0,
        .y = (a.y + b.y) / 2.0,
    };
}

fn pointLineDistance(point: Vec2, a: Vec2, b: Vec2) f32 {
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    const len = std.math.sqrt(dx * dx + dy * dy);
    if (len <= 0.0001) return vecLen(.{ .x = point.x - a.x, .y = point.y - a.y });

    const cross_value = @abs((point.x - a.x) * dy - (point.y - a.y) * dx);
    return cross_value / len;
}

fn appendUniquePoint(list: *std.ArrayListUnmanaged(Point), allocator: std.mem.Allocator, point: Vec2) !void {
    const rounded = toPoint(point);
    if (list.items.len == 0 or !samePoint(list.items[list.items.len - 1], rounded)) {
        try list.append(allocator, rounded);
    }
}

fn flattenQuadraticBezierRecursive(
    list: *std.ArrayListUnmanaged(Point),
    allocator: std.mem.Allocator,
    p0: Vec2,
    p1: Vec2,
    p2: Vec2,
    tolerance: f32,
    depth: usize,
) !void {
    if (depth == 0 or pointLineDistance(p1, p0, p2) <= tolerance) {
        try appendUniquePoint(list, allocator, p2);
        return;
    }

    const p01 = vec2Mid(p0, p1);
    const p12 = vec2Mid(p1, p2);
    const p012 = vec2Mid(p01, p12);

    try flattenQuadraticBezierRecursive(list, allocator, p0, p01, p012, tolerance, depth - 1);
    try flattenQuadraticBezierRecursive(list, allocator, p012, p12, p2, tolerance, depth - 1);
}

fn flattenQuadraticBezier(
    allocator: std.mem.Allocator,
    start: Vec2,
    control: Vec2,
    end: Vec2,
) !std.ArrayListUnmanaged(Point) {
    var points = std.ArrayListUnmanaged(Point){};
    errdefer points.deinit(allocator);

    try points.append(allocator, toPoint(start));
    try flattenQuadraticBezierRecursive(&points, allocator, start, control, end, 0.5, 12);

    return points;
}

fn flattenCubicBezierRecursive(
    list: *std.ArrayListUnmanaged(Point),
    allocator: std.mem.Allocator,
    p0: Vec2,
    p1: Vec2,
    p2: Vec2,
    p3: Vec2,
    tolerance: f32,
    depth: usize,
) !void {
    const flat_enough = pointLineDistance(p1, p0, p3) <= tolerance and
        pointLineDistance(p2, p0, p3) <= tolerance;

    if (depth == 0 or flat_enough) {
        try appendUniquePoint(list, allocator, p3);
        return;
    }

    const p01 = vec2Mid(p0, p1);
    const p12 = vec2Mid(p1, p2);
    const p23 = vec2Mid(p2, p3);
    const p012 = vec2Mid(p01, p12);
    const p123 = vec2Mid(p12, p23);
    const p0123 = vec2Mid(p012, p123);

    try flattenCubicBezierRecursive(list, allocator, p0, p01, p012, p0123, tolerance, depth - 1);
    try flattenCubicBezierRecursive(list, allocator, p0123, p123, p23, p3, tolerance, depth - 1);
}

fn flattenCubicBezier(
    allocator: std.mem.Allocator,
    start: Vec2,
    control1: Vec2,
    control2: Vec2,
    end: Vec2,
) !std.ArrayListUnmanaged(Point) {
    var points = std.ArrayListUnmanaged(Point){};
    errdefer points.deinit(allocator);

    try points.append(allocator, toPoint(start));
    try flattenCubicBezierRecursive(&points, allocator, start, control1, control2, end, 0.5, 12);

    return points;
}

pub fn renderScene(engine: *Engine, allocator: std.mem.Allocator) void {
    var clip_stack = std.ArrayListUnmanaged(Rect){};
    defer clip_stack.deinit(allocator);

    var stack = Matrix3Stack{};
    defer stack.deinit(allocator);

    for (engine.scene.draw_cmds.items) |cmd| {
        switch (cmd) {
            .clear => |clear_cmd| {
                if (clear_cmd.rect) |rect| {
                    clearRectRegion(engine, rect, clear_cmd.color, &clip_stack);
                    engine.scene.markDirty(allocator, rect);
                } else if (clip_stack.items.len == 0) {
                    const fill_value: u8 = if (clear_cmd.color == .black) 0xFF else 0x00;
                    for (engine.fb.pixels) |*pixel| {
                        pixel.* = fill_value;
                    }
                    engine.scene.markDirty(allocator, .{
                        .x = 0,
                        .y = 0,
                        .width = engine.fb.width,
                        .height = engine.fb.height,
                    });
                } else {
                    clearRectRegion(engine, .{
                        .x = 0,
                        .y = 0,
                        .width = engine.fb.width,
                        .height = engine.fb.height,
                    }, clear_cmd.color, &clip_stack);
                    engine.scene.markDirty(allocator, .{
                        .x = 0,
                        .y = 0,
                        .width = engine.fb.width,
                        .height = engine.fb.height,
                    });
                }
            },
            .transform => |transform_cmd| {
                switch (transform_cmd) {
                    .push => |matrix| {
                        stack.push(allocator, matrix) catch {};
                    },
                    .replace => |matrix| {
                        if (!stack.replace(matrix)) {
                            stack.push(allocator, matrix) catch {};
                        }
                    },
                    .pop => {
                        _ = stack.pop();
                    },
                }
            },
            .clip => |clip_cmd| {
                switch (clip_cmd) {
                    .push => |rect| {
                        const clip_rect = transformRectToBounds(rect, currentMatrix(&stack));
                        clip_stack.append(allocator, clip_rect) catch {};
                    },
                    .pop => {
                        if (clip_stack.items.len > 0) {
                            _ = clip_stack.pop();
                        }
                    },
                }
            },
            .nop => {},
            .line => |line_cmd| {
                const m = currentMatrix(&stack);
                const a = toPoint(m.transformPoint(toVec2(line_cmd.a)));
                const b = toPoint(m.transformPoint(toVec2(line_cmd.b)));
                drawLine(a.x, a.y, b.x, b.y, line_cmd.stroke, line_cmd.stroke.width, &clip_stack, engine);

                if (dirtyRectFromPoints(&.{ a, b })) |bounds| {
                    engine.scene.markDirty(allocator, expandDirtyRect(bounds, @as(i32, line_cmd.stroke.width)));
                }
            },
            .rect => |rect_cmd| {
                const m = currentMatrix(&stack);

                const r = rect_cmd.rect;
                const points = .{
                    Point{ .x = r.x, .y = r.y },
                    Point{ .x = r.x + @as(Coord, @intCast(r.width)), .y = r.y },
                    Point{ .x = r.x + @as(Coord, @intCast(r.width)), .y = r.y + @as(Coord, @intCast(r.height)) },
                    Point{ .x = r.x, .y = r.y + @as(Coord, @intCast(r.height)) },
                };

                var transformed_points: [4]Point = undefined;
                for (0..points.len) |i| {
                    const point = points[i];
                    transformed_points[i] = toPoint(m.transformPoint(toVec2(point)));
                }

                const quad = orderQuadrilateralPoints(Quad{
                    .a = transformed_points[0],
                    .b = transformed_points[1],
                    .c = transformed_points[2],
                    .d = transformed_points[3],
                });

                if (rect_cmd.fill) {
                    drawFilledTriangle(engine, quad.a.x, quad.a.y, quad.b.x, quad.b.y, quad.c.x, quad.c.y, rect_cmd.fill.?, &clip_stack);
                    drawFilledTriangle(engine, quad.a.x, quad.a.y, quad.c.x, quad.c.y, quad.d.x, quad.d.y, rect_cmd.fill.?, &clip_stack);
                }

                if (rect_cmd.stroke) {
                    const stroke = rect_cmd.stroke.?;
                    drawLine(quad.a.x, quad.a.y, quad.b.x, quad.b.y, stroke, stroke.width, &clip_stack, engine);
                    drawLine(quad.b.x, quad.b.y, quad.c.x, quad.c.y, stroke, stroke.width, &clip_stack, engine);
                    drawLine(quad.c.x, quad.c.y, quad.d.x, quad.d.y, stroke, stroke.width, &clip_stack, engine);
                    drawLine(quad.d.x, quad.d.y, quad.a.x, quad.a.y, stroke, stroke.width, &clip_stack, engine);
                }

                if (dirtyRectFromPoints(&transformed_points)) |bounds| {
                    const padding: i32 = if (rect_cmd.stroke) |stroke| @as(i32, stroke.width) else 0;
                    engine.scene.markDirty(allocator, expandDirtyRect(bounds, padding));
                }
            },
            .triangle => |triangle_cmd| {
                const m = currentMatrix(&stack);
                const a = toPoint(m.transformPoint(toVec2(triangle_cmd.a)));
                const b = toPoint(m.transformPoint(toVec2(triangle_cmd.b)));
                const c = toPoint(m.transformPoint(toVec2(triangle_cmd.c)));

                if (triangle_cmd.fill) {
                    drawFilledTriangle(engine, a.x, a.y, b.x, b.y, c.x, c.y, triangle_cmd.fill.?, &clip_stack);
                }

                if (triangle_cmd.stroke) {
                    const stroke = triangle_cmd.stroke.?;
                    drawLine(a.x, a.y, b.x, b.y, stroke, stroke.width, &clip_stack, engine);
                    drawLine(b.x, b.y, c.x, c.y, stroke, stroke.width, &clip_stack, engine);
                    drawLine(c.x, c.y, a.x, a.y, stroke, stroke.width, &clip_stack, engine);
                }

                if (dirtyRectFromPoints(&.{ a, b, c })) |bounds| {
                    const padding: i32 = if (triangle_cmd.stroke) |stroke| @as(i32, stroke.width) else 0;
                    engine.scene.markDirty(allocator, expandDirtyRect(bounds, padding));
                }
            },
            .quadratic_bezier => |quadratic_cmd| {
                const m = currentMatrix(&stack);
                const start = m.transformPoint(toVec2(quadratic_cmd.start));
                const control = m.transformPoint(toVec2(quadratic_cmd.control));
                const end = m.transformPoint(toVec2(quadratic_cmd.end));

                var points = flattenQuadraticBezier(allocator, start, control, end) catch continue;
                defer points.deinit(allocator);

                if (quadratic_cmd.fill) |fill| {
                    if (points.items.len >= 3) {
                        if (earClipTriangulate(allocator, points.items)) |triangles| {
                            defer allocator.free(triangles);

                            var i: usize = 0;
                            while (i + 2 < triangles.len) : (i += 3) {
                                const a = triangles[i + 0];
                                const b = triangles[i + 1];
                                const c = triangles[i + 2];

                                drawFilledTriangle(
                                    engine,
                                    a.x,
                                    a.y,
                                    b.x,
                                    b.y,
                                    c.x,
                                    c.y,
                                    fill,
                                    &clip_stack,
                                );
                            }
                        } else |_| {
                            // invalid or degenerate curve fill; skip it
                        }
                    }
                }

                if (quadratic_cmd.stroke) |stroke| {
                    if (points.items.len >= 2) {
                        var i: usize = 0;
                        while (i + 1 < points.items.len) : (i += 1) {
                            const a = points.items[i];
                            const b = points.items[i + 1];

                            drawLine(
                                a.x,
                                a.y,
                                b.x,
                                b.y,
                                stroke,
                                stroke.width,
                                &clip_stack,
                                engine,
                            );
                        }
                    }
                }

                if (dirtyRectFromPoints(points.items)) |bounds| {
                    const padding: i32 = if (quadratic_cmd.stroke) |stroke| @as(i32, stroke.width) else 0;
                    engine.scene.markDirty(allocator, expandDirtyRect(bounds, padding));
                }
            },
            .cubic_bezier => |cubic_cmd| {
                const m = currentMatrix(&stack);
                const start = m.transformPoint(toVec2(cubic_cmd.start));
                const control1 = m.transformPoint(toVec2(cubic_cmd.control1));
                const control2 = m.transformPoint(toVec2(cubic_cmd.control2));
                const end = m.transformPoint(toVec2(cubic_cmd.end));

                var points = flattenCubicBezier(allocator, start, control1, control2, end) catch continue;
                defer points.deinit(allocator);

                if (cubic_cmd.fill) |fill| {
                    if (points.items.len >= 3) {
                        if (earClipTriangulate(allocator, points.items)) |triangles| {
                            defer allocator.free(triangles);

                            var i: usize = 0;
                            while (i + 2 < triangles.len) : (i += 3) {
                                const a = triangles[i + 0];
                                const b = triangles[i + 1];
                                const c = triangles[i + 2];

                                drawFilledTriangle(
                                    engine,
                                    a.x,
                                    a.y,
                                    b.x,
                                    b.y,
                                    c.x,
                                    c.y,
                                    fill,
                                    &clip_stack,
                                );
                            }
                        } else |_| {
                            // invalid or degenerate curve fill; skip it
                        }
                    }
                }

                if (cubic_cmd.stroke) |stroke| {
                    if (points.items.len >= 2) {
                        var i: usize = 0;
                        while (i + 1 < points.items.len) : (i += 1) {
                            const a = points.items[i];
                            const b = points.items[i + 1];

                            drawLine(
                                a.x,
                                a.y,
                                b.x,
                                b.y,
                                stroke,
                                stroke.width,
                                &clip_stack,
                                engine,
                            );
                        }
                    }
                }

                if (dirtyRectFromPoints(points.items)) |bounds| {
                    const padding: i32 = if (cubic_cmd.stroke) |stroke| @as(i32, stroke.width) else 0;
                    engine.scene.markDirty(allocator, expandDirtyRect(bounds, padding));
                }
            },
            .circle => |circle_cmd| {
                const m = currentMatrix(&stack);
                const center = m.transformPoint(toVec2(circle_cmd.center));

                const radius_vec = m.transformVector(.{
                    .x = @floatFromInt(circle_cmd.radius),
                    .y = 0,
                });
                const radius_len = std.math.sqrt(radius_vec.x * radius_vec.x + radius_vec.y * radius_vec.y);
                const radius: i32 = @intFromFloat(@round(radius_len));

                drawCircle(
                    engine,
                    @as(i32, @intFromFloat(@round(center.x))),
                    @as(i32, @intFromFloat(@round(center.y))),
                    radius,
                    circle_cmd.fill,
                    circle_cmd.stroke,
                    &clip_stack,
                );

                if (dirtyRectFromPoints(&.{
                    Point{ .x = @as(Coord, @intCast(@as(i32, @intFromFloat(@round(center.x))) - radius)), .y = @as(Coord, @intCast(@as(i32, @intFromFloat(@round(center.y))) - radius)) },
                    Point{ .x = @as(Coord, @intCast(@as(i32, @intFromFloat(@round(center.x))) + radius)), .y = @as(Coord, @intCast(@as(i32, @intFromFloat(@round(center.y))) + radius)) },
                })) |bounds| {
                    const padding: i32 = if (circle_cmd.stroke) |stroke| @as(i32, stroke.width) else 0;
                    engine.scene.markDirty(allocator, expandDirtyRect(bounds, padding));
                }
            },
            .blit => |blit_cmd| {
                blitRectRegion(engine, blit_cmd.src_pos, blit_cmd.dst_pos, blit_cmd.size, blit_cmd.mode, &clip_stack);

                engine.scene.markDirty(allocator, .{
                    .x = blit_cmd.dst_pos.x,
                    .y = blit_cmd.dst_pos.y,
                    .width = blit_cmd.size.width,
                    .height = blit_cmd.size.height,
                });
            },
            .bitmap => |bitmap_cmd| {
                if (bitmap_cmd.width == 0 or bitmap_cmd.height == 0) continue;

                const data = engine.scene.bitmap_arena.items;
                if (bitmap_cmd.data_offset >= data.len) continue;

                const data_end = std.math.min(@as(usize, bitmap_cmd.data_offset) + @as(usize, bitmap_cmd.data_len), data.len);
                if (data_end <= bitmap_cmd.data_offset) continue;

                const bitmap_data = data[bitmap_cmd.data_offset..data_end];

                const m = currentMatrix(&stack);
                const translate = Matrix3.translation(@floatFromInt(bitmap_cmd.pos.x), @floatFromInt(bitmap_cmd.pos.y));
                const bitmap_matrix = Matrix3.mul(m, translate);
                const inv = bitmap_matrix.inverse() orelse continue;

                const bounds = transformRectToBounds(.{
                    .x = 0,
                    .y = 0,
                    .width = bitmap_cmd.width,
                    .height = bitmap_cmd.height,
                }, bitmap_matrix);

                const bounds_w: i32 = @as(i32, @intCast(bounds.width));
                const bounds_h: i32 = @as(i32, @intCast(bounds.height));
                if (bounds_w <= 0 or bounds_h <= 0) continue;

                const stride_bytes = bitmapStrideBytes(bitmap_cmd.width, bitmap_cmd.stride_bytes);

                const x0: i32 = @as(i32, bounds.x);
                const y0: i32 = @as(i32, bounds.y);
                const x1: i32 = x0 + bounds_w - 1;
                const y1: i32 = y0 + bounds_h - 1;

                var y: i32 = y0;
                while (y <= y1) : (y += 1) {
                    var x: i32 = x0;
                    while (x <= x1) : (x += 1) {
                        const sample = inv.transformPoint(.{
                            .x = @as(f32, @floatFromInt(x)) + 0.5,
                            .y = @as(f32, @floatFromInt(y)) + 0.5,
                        });
                        const src_x: i32 = @intFromFloat(@floor(sample.x));
                        const src_y: i32 = @intFromFloat(@floor(sample.y));

                        if (src_x < 0 or src_y < 0) continue;
                        if (src_x >= @as(i32, @intCast(bitmap_cmd.width)) or
                            src_y >= @as(i32, @intCast(bitmap_cmd.height)))
                        {
                            continue;
                        }

                        const bit_set = bitmapBit(
                            bitmap_data,
                            stride_bytes,
                            @intCast(src_x),
                            @intCast(src_y),
                            bitmap_cmd.bit_order,
                        ) orelse continue;

                        applyBitmapMode(engine, x, y, bit_set, bitmap_cmd.mode, &clip_stack);
                    }
                }

                engine.scene.markDirty(allocator, bounds);
            },
            .text => |text_cmd| {
                const m = currentMatrix(&stack);

                const meta_ptr = getFontMeta(&engine.scene, text_cmd.font);
                if (meta_ptr == null) continue;
                const meta = meta_ptr.*;

                const text_arena = engine.scene.text_arena.items;
                const start_off: usize = @intCast(text_cmd.text_offset);
                const requested_end = start_off + @as(usize, @intCast(text_cmd.text_len));
                if (start_off >= text_arena.len) continue;
                const end_off = if (requested_end > text_arena.len) text_arena.len else requested_end;
                const txt = text_arena[start_off..end_off];
                if (txt.len == 0) continue;

                const width_i32: i32 = @as(i32, meta.width);
                const height_i32: i32 = @as(i32, meta.height);
                const total_w: i32 = width_i32 * @as(i32, txt.len);

                const origin = m.transformPoint(toVec2(text_cmd.pos));
                const ox: i32 = @intFromFloat(@round(origin.x));
                const oy: i32 = @intFromFloat(@round(origin.y));

                var start_x: i32 = ox;
                switch (text_cmd.textAlign) {
                    .left => start_x = ox,
                    .center => start_x = ox - (total_w / 2),
                    .right => start_x = ox - total_w,
                }

                var base_y: i32 = oy;
                switch (text_cmd.baseline) {
                    .top => base_y = oy,
                    .middle => base_y = oy - (height_i32 / 2),
                    .bottom => base_y = oy - height_i32,
                    .alphabetic => base_y = oy - height_i32 + (height_i32 / 4),
                }

                const stride: usize = @intCast(meta.stride_bytes);
                const glyph_size = stride * @as(usize, @intCast(meta.height));
                const bitmap_all = engine.scene.font_bitmap_arena.items;

                var cursor_x: i32 = start_x;
                for (txt) |b| {
                    const code: u32 = @intCast(b);
                    if (code < meta.first_codepoint) {
                        cursor_x += width_i32;
                        continue;
                    }

                    const glyph_index: usize = @intCast(code - meta.first_codepoint);
                    if (glyph_index >= @as(usize, @intCast(meta.glyph_count))) {
                        cursor_x += width_i32;
                        continue;
                    }

                    const glyph_offset_bytes: usize = @as(usize, @intCast(meta.data_offset)) + glyph_index * glyph_size;
                    if (glyph_offset_bytes + glyph_size > bitmap_all.len) {
                        cursor_x += width_i32;
                        continue;
                    }

                    const glyph_data = bitmap_all[glyph_offset_bytes .. glyph_offset_bytes + glyph_size];

                    var gy: usize = 0;
                    while (gy < @as(usize, @intCast(meta.height))) : (gy += 1) {
                        var gx: usize = 0;
                        while (gx < @as(usize, @intCast(meta.width))) : (gx += 1) {
                            const bit = bitmapBit(glyph_data, stride, gx, gy, .msb_first) orelse false;
                            if (bit) {
                                putPixelClipSigned(engine, cursor_x + @as(i32, gx), base_y + @as(i32, gy), text_cmd.color, &clip_stack);
                            }
                        }
                    }

                    cursor_x += width_i32;
                }

                engine.scene.markDirty(allocator, .{
                    .x = @intCast(start_x),
                    .y = @intCast(base_y),
                    .width = @intCast(@max(total_w, 0)),
                    .height = @intCast(@max(height_i32, 0)),
                });
            },
            .invert => |invert_cmd| {
                const m = currentMatrix(&stack);
                const rect = transformRectToBounds(invert_cmd.rect, m);
                invertRectRegion(engine, rect, &clip_stack);

                engine.scene.markDirty(allocator, rect);
            },
            .rounded_rect => |rounded_rect_cmd| {
                drawRoundedRect(
                    engine,
                    rounded_rect_cmd.rect,
                    rounded_rect_cmd.radius,
                    rounded_rect_cmd.fill,
                    rounded_rect_cmd.stroke,
                    currentMatrix(&stack),
                    &clip_stack,
                );

                engine.scene.markDirty(allocator, rounded_rect_cmd.rect);
            },
            .ellipse => |ellipse_cmd| {
                const m = currentMatrix(&stack);
                const translate = Matrix3.translation(@floatFromInt(ellipse_cmd.rect.x), @floatFromInt(ellipse_cmd.rect.y));
                const ellipse_matrix = Matrix3.mul(m, translate);
                const inv = ellipse_matrix.inverse() orelse continue;

                const bounds = transformRectToBounds(.{
                    .x = 0,
                    .y = 0,
                    .width = ellipse_cmd.rect.width,
                    .height = ellipse_cmd.rect.height,
                }, ellipse_matrix);

                const bounds_w: i32 = @intCast(bounds.width);
                const bounds_h: i32 = @intCast(bounds.height);
                if (bounds_w <= 0 or bounds_h <= 0) continue;

                if (engine.fb.width == 0 or engine.fb.height == 0) continue;

                var x0: i32 = @as(i32, bounds.x);
                var y0: i32 = @as(i32, bounds.y);
                var x1: i32 = x0 + bounds_w - 1;
                var y1: i32 = y0 + bounds_h - 1;

                if (x0 < 0) x0 = 0;
                if (y0 < 0) y0 = 0;

                const fb_max_x: i32 = @as(i32, @intCast(engine.fb.width)) - 1;
                const fb_max_y: i32 = @as(i32, @intCast(engine.fb.height)) - 1;

                if (x1 > fb_max_x) x1 = fb_max_x;
                if (y1 > fb_max_y) y1 = fb_max_y;

                if (x0 > x1 or y0 > y1) continue;

                const width_f: f32 = @floatFromInt(ellipse_cmd.rect.width);
                const height_f: f32 = @floatFromInt(ellipse_cmd.rect.height);
                if (width_f <= 0.0 or height_f <= 0.0) continue;

                const rx: f32 = width_f / 2.0;
                const ry: f32 = height_f / 2.0;

                const x_vec = ellipse_matrix.transformVector(.{ .x = 1.0, .y = 0.0 });
                const y_vec = ellipse_matrix.transformVector(.{ .x = 0.0, .y = 1.0 });

                var stroke_scale = (vecLen(x_vec) + vecLen(y_vec)) / 2.0;
                if (stroke_scale <= 0.0001) stroke_scale = 1.0;

                const pi: f32 = std.math.pi;
                const two_pi: f32 = pi * 2.0;

                const perimeter: f32 = std.math.pi * (3.0 * (rx + ry) - std.math.sqrt((3.0 * rx + ry) * (rx + 3.0 * ry)));

                var y = y0;
                while (y <= y1) : (y += 1) {
                    var x = x0;
                    while (x <= x1) : (x += 1) {
                        const sample = inv.transformPoint(.{
                            .x = @as(f32, @floatFromInt(x)) + 0.5,
                            .y = @as(f32, @floatFromInt(y)) + 0.5,
                        });

                        const dx = sample.x - rx;
                        const dy = sample.y - ry;

                        const norm = (dx * dx) / (rx * rx) + (dy * dy) / (ry * ry);

                        if (ellipse_cmd.fill) |f| {
                            if (norm <= 1.0) {
                                putPixelClipSigned(engine, x, y, fillColor(f, x, y), &clip_stack);
                            }
                        }

                        if (ellipse_cmd.stroke) |s| {
                            if (s.width == 0) continue;

                            const dist = std.math.sqrt(norm) - 1.0;
                            const screen_dist = @abs(dist * stroke_scale);

                            const half_stroke_width: f32 = @as(f32, @floatFromInt(s.width)) / 2.0;

                            if (screen_dist <= half_stroke_width) {
                                var angle = std.math.atan2(dy / ry, dx / rx);
                                if (angle < 0.0) angle += two_pi;

                                const pos = angle / two_pi * perimeter;
                                const step: usize = @intFromFloat(@floor(pos));

                                if (shouldDrawStep(s.style, step)) {
                                    putPixelClipSigned(engine, x, y, s.color, &clip_stack);
                                }
                            }
                        }
                    }
                }

                engine.scene.markDirty(allocator, bounds);
            },
            .polygon => |polygon_cmd| {
                if (polygon_cmd.points_len == 0) continue;

                const arena = engine.scene.points_arena.items;
                const start: usize = @intCast(polygon_cmd.points_offset);

                if (start >= arena.len) continue;

                const requested_end = start + @as(usize, polygon_cmd.points_len);
                const end = @min(requested_end, arena.len);

                const raw_points = arena[start..end];
                if (raw_points.len < 2) continue;

                const m = currentMatrix(&stack);

                var transformed_points = allocator.alloc(Point, raw_points.len) catch continue;
                defer allocator.free(transformed_points);

                for (0..raw_points.len) |i| {
                    const point = raw_points[i];
                    transformed_points[i] = toPoint(m.transformPoint(toVec2(point)));
                }

                if (polygon_cmd.fill) |fill| {
                    if (transformed_points.len >= 3) {
                        if (earClipTriangulate(allocator, transformed_points)) |triangles| {
                            defer allocator.free(triangles);

                            var i: usize = 0;
                            while (i + 2 < triangles.len) : (i += 3) {
                                const a = triangles[i + 0];
                                const b = triangles[i + 1];
                                const c = triangles[i + 2];

                                drawFilledTriangle(
                                    engine,
                                    a.x,
                                    a.y,
                                    b.x,
                                    b.y,
                                    c.x,
                                    c.y,
                                    fill,
                                    &clip_stack,
                                );
                            }
                        } else |_| {
                            // invalid/self-intersecting/degenerate polygon; skip fill
                        }
                    }
                }

                if (polygon_cmd.stroke) |stroke| {
                    if (transformed_points.len >= 2) {
                        var i: usize = 0;
                        while (i < transformed_points.len) : (i += 1) {
                            const a = transformed_points[i];
                            const b = transformed_points[if (i + 1 == transformed_points.len) 0 else i + 1];

                            drawLine(
                                a.x,
                                a.y,
                                b.x,
                                b.y,
                                stroke,
                                stroke.width,
                                &clip_stack,
                                engine,
                            );
                        }
                    }
                }

                if (dirtyRectFromPoints(transformed_points)) |bounds| {
                    const padding: i32 = if (polygon_cmd.stroke) |stroke| @as(i32, stroke.width) else 0;
                    engine.scene.markDirty(allocator, expandDirtyRect(bounds, padding));
                }
            },
            .polyline => |polyline_cmd| {
                if (polyline_cmd.points_len < 2) continue;

                const arena = engine.scene.points_arena.items;
                const start: usize = @intCast(polyline_cmd.points_offset);

                if (start >= arena.len) continue;

                const requested_end = start + @as(usize, polyline_cmd.points_len);
                const end = @min(requested_end, arena.len);

                const raw_points = arena[start..end];
                if (raw_points.len < 2) continue;

                const m = currentMatrix(&stack);

                var transformed_points = allocator.alloc(Point, raw_points.len) catch continue;
                defer allocator.free(transformed_points);

                for (0..raw_points.len) |i| {
                    const point = raw_points[i];
                    transformed_points[i] = toPoint(m.transformPoint(toVec2(point)));
                }

                if (polyline_cmd.stroke.width > 0) {
                    var i: usize = 0;
                    while (i + 1 < transformed_points.len) : (i += 1) {
                        const a = transformed_points[i];
                        const b = transformed_points[i + 1];

                        drawLine(
                            a.x,
                            a.y,
                            b.x,
                            b.y,
                            polyline_cmd.stroke,
                            polyline_cmd.stroke.width,
                            &clip_stack,
                            engine,
                        );
                    }
                }

                if (dirtyRectFromPoints(transformed_points)) |bounds| {
                    engine.scene.markDirty(allocator, expandDirtyRect(bounds, @as(i32, polyline_cmd.stroke.width)));
                }
            },
            .arc => |arc_cmd| {
                const m = currentMatrix(&stack);

                const center_world = m.transformPoint(toVec2(arc_cmd.center));

                const x_vec = m.transformVector(.{ .x = 1.0, .y = 0.0 });
                const y_vec = m.transformVector(.{ .x = 0.0, .y = 1.0 });

                const start_angle = @as(f64, arc_cmd.start_angle);
                const end_angle = @as(f64, arc_cmd.end_angle);

                const radius_f: f32 = @floatFromInt(arc_cmd.radius);

                const two_pi = std.math.pi * 2.0;
                var span: f64 = end_angle - start_angle;
                if (span <= 0.0) span += two_pi;

                const segments_f = span * 16.0; // 16 segments per radian
                var segments = @as(usize, @intCast(@as(f64, @intFromFloat(@ceil(segments_f)))));
                if (segments < 4) segments = 4;

                var points = allocator.alloc(Point, segments + 1) catch continue;
                defer allocator.free(points);

                var i: usize = 0;
                while (i <= segments) : (i += 1) {
                    const t = @as(f64, i) / @as(f64, segments);
                    const angle = start_angle + t * span;

                    const ca = @as(f32, std.math.cos(angle));
                    const sa = @as(f32, std.math.sin(angle));

                    const world: Vec2 = .{
                        .x = center_world.x + ca * (x_vec.x * radius_f) + sa * (y_vec.x * radius_f),
                        .y = center_world.y + ca * (x_vec.y * radius_f) + sa * (y_vec.y * radius_f),
                    };

                    points[i] = toPoint(world);
                }

                if (arc_cmd.fill) |f| {
                    const center_pt = toPoint(center_world);
                    var j: usize = 0;
                    while (j + 1 <= segments) : (j += 1) {
                        const a = points[j];
                        const b = points[j + 1];

                        drawFilledTriangle(
                            engine,
                            center_pt.x,
                            center_pt.y,
                            a.x,
                            a.y,
                            b.x,
                            b.y,
                            f,
                            &clip_stack,
                        );
                    }
                }

                if (arc_cmd.stroke) |s| {
                    var k: usize = 0;
                    while (k + 1 <= segments) : (k += 1) {
                        const a = points[k];
                        const b = points[k + 1];

                        drawLine(
                            a.x,
                            a.y,
                            b.x,
                            b.y,
                            s,
                            s.width,
                            &clip_stack,
                            engine,
                        );
                    }
                }

                if (dirtyRectFromPoints(points)) |bounds| {
                    const padding: i32 = if (arc_cmd.stroke) |stroke| @as(i32, stroke.width) else 0;
                    engine.scene.markDirty(allocator, expandDirtyRect(bounds, padding));
                }
            },
            .point => |point_cmd| {
                const m = currentMatrix(&stack);
                const p = m.transformPoint(toVec2(point_cmd.point));

                putPixelClipSigned(
                    engine,
                    @as(i32, @intFromFloat(p.x)),
                    @as(i32, @intFromFloat(p.y)),
                    point_cmd.color,
                    &clip_stack,
                );

                engine.scene.markDirty(allocator, .{
                    .x = @intCast(@as(i32, @intFromFloat(p.x))),
                    .y = @intCast(@as(i32, @intFromFloat(p.y))),
                    .width = 1,
                    .height = 1,
                });
            },
        }
    }
}
