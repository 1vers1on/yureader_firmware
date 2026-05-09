/// Lightweight graphics convenience wrappers built on top of the
/// `renderer` module. This file provides a small, ergonomic `Canvas`
/// API and a `Renderer` wrapper for creating frames, submitting draw
/// commands, and managing common rendering state.
const std = @import("std");
const Render = @import("renderer.zig");
const Matrix3 = @import("util/Matrix3.zig").Matrix3;
const display_module = @import("hardware/display.zig");

/// Presentation mode for how the frame should be presented to the
/// framebuffer.
///
/// - `none`: do not perform a present operation.
/// - `full`: present the full framebuffer.
/// - `partial`: present a sub-rectangle (useful for partial updates).
/// - `auto`: let the renderer choose the most efficient mode.
pub const PresentMode = union(enum) {
    none,
    full,
    partial: Render.Rect,
    auto,
};

/// Options used when creating a `Renderer`.
///
/// - `framebuffer`: the target framebuffer to render into.
/// - `clear_on_begin`: optional clear color emitted at the start of a
///   new frame.
/// - `default_present_mode`: preferred `PresentMode` for new frames.
pub const RendererOptions = struct {
    framebuffer: Render.Framebuffer,

    clear_on_begin: ?Render.Color = null,
    default_present_mode: PresentMode = .auto,
};

/// `Canvas` is the primary drawing surface handle used within a frame.
/// It holds transient drawing state (current fill/stroke/text state)
/// and provides convenience methods that enqueue `Render.DrawCmd`
/// objects into the current `Render.Scene`.
pub const Canvas = struct {
    allocator: std.mem.Allocator,
    engine: *Render.Engine,
    current_fill: ?Render.Fill = null,
    current_stroke: ?Render.Stroke = null,
    current_text_color: Render.Color = .black,
    current_text_align: Render.TextAlign = .left,
    current_text_baseline: Render.TextBaseline = .top,

    /// Returns the underlying `Render.Scene` for the current frame.
    fn scene(self: *Canvas) *Render.Scene {
        return &self.engine.scene;
    }

    /// Append a raw `DrawCmd` to the frame's command list.
    ///
    /// This is the lowest-level submission API; most callers should use
    /// the higher-level shape and text helpers instead.
    pub fn submit(self: *Canvas, cmd: Render.DrawCmd) !void {
        try self.scene().draw_cmds.append(self.allocator, cmd);
    }

    /// Set the current fill style used by `*With` drawing helpers.
    ///
    /// Pass `null` to disable filling.
    pub fn setFill(self: *Canvas, fill: ?Render.Fill) *Canvas {
        self.current_fill = fill;
        return self;
    }

    /// Set the current stroke style used by `*With` drawing helpers.
    ///
    /// Pass `null` to disable stroking.
    pub fn setStroke(self: *Canvas, stroke: ?Render.Stroke) *Canvas {
        self.current_stroke = stroke;
        return self;
    }

    /// Set the current text color used by text helpers.
    pub fn setTextColor(self: *Canvas, color: Render.Color) *Canvas {
        self.current_text_color = color;
        return self;
    }

    /// Set the current text horizontal alignment.
    pub fn setTextAlign(self: *Canvas, text_align: Render.TextAlign) *Canvas {
        self.current_text_align = text_align;
        return self;
    }

    /// Set the current text baseline (vertical alignment).
    pub fn setTextBaseline(self: *Canvas, baseline: Render.TextBaseline) *Canvas {
        self.current_text_baseline = baseline;
        return self;
    }

    /// Convenience: set a stroke with `color` and `width`.
    pub fn strokeColor(self: *Canvas, color: Render.Color, width: u8) *Canvas {
        self.current_stroke = .{ .color = color, .width = width };
        return self;
    }

    /// Convenience: set a solid fill with `color`.
    pub fn fillColor(self: *Canvas, color: Render.Color) *Canvas {
        self.current_fill = .{ .color = color };
        return self;
    }

    /// Reset transient drawing state (fill and stroke) to `null`.
    pub fn clearState(self: *Canvas) *Canvas {
        self.current_fill = null;
        self.current_stroke = null;
        return self;
    }

    /// Enqueue a full-frame clear with `color`.
    pub fn clear(self: *Canvas, color: Render.Color) !void {
        try self.submit(.{ .clear = .{ .color = color } });
    }

    /// Enqueue a rectangle clear limited to `clip_rect`.
    pub fn clearRect(self: *Canvas, clip_rect: Render.Rect, color: Render.Color) !void {
        try self.submit(.{ .clear = .{ .rect = clip_rect, .color = color } });
    }

    /// Draw a line from `a` to `b` using the provided `stroke`.
    pub fn line(self: *Canvas, a: Render.Point, b: Render.Point, stroke: Render.Stroke) !void {
        try self.submit(.{ .line = .{ .a = a, .b = b, .stroke = stroke } });
    }

    /// Draw a line using the `current_stroke` if set.
    pub fn lineWith(self: *Canvas, a: Render.Point, b: Render.Point) !void {
        if (self.current_stroke) |stroke| {
            try self.submit(.{ .line = .{ .a = a, .b = b, .stroke = stroke } });
        }
    }

    /// Draw a polyline defined by `points` with the given `stroke`.
    pub fn polyline(self: *Canvas, points: []const Render.Point, stroke: Render.Stroke) !void {
        const points_data = try self.scene().appendPoints(self.allocator, points);
        try self.submit(.{ .polyline = .{
            .points_offset = points_data.points_offset,
            .points_len = points_data.points_len,
            .stroke = stroke,
        } });
    }

    /// Draw a polyline using the `current_stroke` if set.
    pub fn polylineWith(self: *Canvas, points: []const Render.Point) !void {
        if (self.current_stroke) |stroke| {
            const points_data = try self.scene().appendPoints(self.allocator, points);
            try self.submit(.{ .polyline = .{
                .points_offset = points_data.points_offset,
                .points_len = points_data.points_len,
                .stroke = stroke,
            } });
        }
    }

    /// Draw a quadratic Bezier curve with explicit `fill` and `stroke`.
    pub fn quadraticBezier(self: *Canvas, start: Render.Point, control: Render.Point, end: Render.Point, fill: ?Render.Fill, stroke: ?Render.Stroke) !void {
        try self.submit(.{ .quadratic_bezier = .{ .start = start, .control = control, .end = end, .fill = fill, .stroke = stroke } });
    }

    /// Draw a quadratic Bezier using the current fill/stroke state.
    pub fn quadraticBezierWith(self: *Canvas, start: Render.Point, control: Render.Point, end: Render.Point) !void {
        try self.submit(.{ .quadratic_bezier = .{ .start = start, .control = control, .end = end, .fill = self.current_fill, .stroke = self.current_stroke } });
    }

    /// Draw a cubic Bezier curve with explicit `fill` and `stroke`.
    pub fn cubicBezier(self: *Canvas, start: Render.Point, control1: Render.Point, control2: Render.Point, end: Render.Point, fill: ?Render.Fill, stroke: ?Render.Stroke) !void {
        try self.submit(.{ .cubic_bezier = .{ .start = start, .control1 = control1, .control2 = control2, .end = end, .fill = fill, .stroke = stroke } });
    }

    /// Draw a cubic Bezier using the current fill/stroke state.
    pub fn cubicBezierWith(self: *Canvas, start: Render.Point, control1: Render.Point, control2: Render.Point, end: Render.Point) !void {
        try self.submit(.{ .cubic_bezier = .{ .start = start, .control1 = control1, .control2 = control2, .end = end, .fill = self.current_fill, .stroke = self.current_stroke } });
    }

    /// Draw a rectangle defined by `shape_rect` with explicit `fill` and `stroke`.
    pub fn rect(self: *Canvas, shape_rect: Render.Rect, fill: ?Render.Fill, stroke: ?Render.Stroke) !void {
        try self.submit(.{ .rect = .{ .rect = shape_rect, .fill = fill, .stroke = stroke } });
    }

    /// Draw a rectangle using the current fill/stroke state.
    pub fn rectWith(self: *Canvas, shape_rect: Render.Rect) !void {
        try self.submit(.{ .rect = .{ .rect = shape_rect, .fill = self.current_fill, .stroke = self.current_stroke } });
    }

    /// Convenience: draw a filled rectangle at `(x,y)` with size `(w,h)`.
    pub fn rectFilled(self: *Canvas, x: i32, y: i32, w: i32, h: i32) !void {
        try self.submit(.{ .rect = .{ .rect = .{ .x = @intCast(x), .y = @intCast(y), .width = @intCast(w), .height = @intCast(h) }, .fill = self.current_fill, .stroke = null } });
    }

    /// Convenience: draw a rectangle outline at `(x,y)` with size `(w,h)`.
    pub fn rectOutline(self: *Canvas, x: i32, y: i32, w: i32, h: i32) !void {
        try self.submit(.{ .rect = .{ .rect = .{ .x = @intCast(x), .y = @intCast(y), .width = @intCast(w), .height = @intCast(h) }, .fill = null, .stroke = self.current_stroke } });
    }

    /// Draw a triangle with explicit `fill` and `stroke`.
    pub fn triangle(self: *Canvas, a: Render.Point, b: Render.Point, c: Render.Point, fill: ?Render.Fill, stroke: ?Render.Stroke) !void {
        try self.submit(.{ .triangle = .{ .a = a, .b = b, .c = c, .fill = fill, .stroke = stroke } });
    }

    /// Draw a triangle using the current fill/stroke state.
    pub fn triangleWith(self: *Canvas, a: Render.Point, b: Render.Point, c: Render.Point) !void {
        try self.submit(.{ .triangle = .{ .a = a, .b = b, .c = c, .fill = self.current_fill, .stroke = self.current_stroke } });
    }

    /// Draw a circle with given `center` and `radius`.
    pub fn circle(self: *Canvas, center: Render.Point, radius: Render.Dim, fill: ?Render.Fill, stroke: ?Render.Stroke) !void {
        try self.submit(.{ .circle = .{ .center = center, .radius = radius, .fill = fill, .stroke = stroke } });
    }

    /// Draw a circle using the current fill/stroke state.
    pub fn circleWith(self: *Canvas, center: Render.Point, radius: Render.Dim) !void {
        try self.submit(.{ .circle = .{ .center = center, .radius = radius, .fill = self.current_fill, .stroke = self.current_stroke } });
    }

    /// Convenience: draw a filled circle at `(cx, cy)` with radius `r`.
    pub fn circleFilled(self: *Canvas, cx: i32, cy: i32, r: Render.Dim) !void {
        try self.submit(.{ .circle = .{ .center = .{ .x = @intCast(cx), .y = @intCast(cy) }, .radius = r, .fill = self.current_fill, .stroke = null } });
    }

    /// Convenience: draw a circle outline at `(cx, cy)` with radius `r`.
    pub fn circleOutline(self: *Canvas, cx: i32, cy: i32, r: Render.Dim) !void {
        try self.submit(.{ .circle = .{ .center = .{ .x = @intCast(cx), .y = @intCast(cy) }, .radius = r, .fill = null, .stroke = self.current_stroke } });
    }

    /// Draw an ellipse inscribed in `shape_rect`.
    pub fn ellipse(self: *Canvas, shape_rect: Render.Rect, fill: ?Render.Fill, stroke: ?Render.Stroke) !void {
        try self.submit(.{ .ellipse = .{ .rect = shape_rect, .fill = fill, .stroke = stroke } });
    }

    /// Draw an ellipse using the current fill/stroke state.
    pub fn ellipseWith(self: *Canvas, shape_rect: Render.Rect) !void {
        try self.submit(.{ .ellipse = .{ .rect = shape_rect, .fill = self.current_fill, .stroke = self.current_stroke } });
    }

    /// Draw a rounded rectangle with corner `radius`.
    pub fn roundedRect(self: *Canvas, shape_rect: Render.Rect, radius: Render.Dim, fill: ?Render.Fill, stroke: ?Render.Stroke) !void {
        try self.submit(.{ .rounded_rect = .{ .rect = shape_rect, .radius = radius, .fill = fill, .stroke = stroke } });
    }

    /// Draw a rounded rectangle using the current fill/stroke state.
    pub fn roundedRectWith(self: *Canvas, shape_rect: Render.Rect, radius: Render.Dim) !void {
        try self.submit(.{ .rounded_rect = .{ .rect = shape_rect, .radius = radius, .fill = self.current_fill, .stroke = self.current_stroke } });
    }

    /// Draw an arc centered at `center` from `start_angle` to `end_angle`.
    pub fn arc(self: *Canvas, center: Render.Point, radius: Render.Dim, start_angle: f64, end_angle: f64, fill: ?Render.Fill, stroke: ?Render.Stroke) !void {
        try self.submit(.{ .arc = .{ .center = center, .radius = radius, .start_angle = start_angle, .end_angle = end_angle, .fill = fill, .stroke = stroke } });
    }

    /// Draw an arc using the current fill/stroke state.
    pub fn arcWith(self: *Canvas, center: Render.Point, radius: Render.Dim, start_angle: f64, end_angle: f64) !void {
        try self.submit(.{ .arc = .{ .center = center, .radius = radius, .start_angle = start_angle, .end_angle = end_angle, .fill = self.current_fill, .stroke = self.current_stroke } });
    }

    /// Draw a polygon defined by `points` with explicit `fill` and `stroke`.
    pub fn polygon(self: *Canvas, points: []const Render.Point, fill: ?Render.Fill, stroke: ?Render.Stroke) !void {
        const points_data = try self.scene().appendPoints(self.allocator, points);
        try self.submit(.{ .polygon = .{
            .points_offset = points_data.points_offset,
            .points_len = points_data.points_len,
            .fill = fill,
            .stroke = stroke,
        } });
    }

    /// Draw a polygon using the current fill/stroke state.
    pub fn polygonWith(self: *Canvas, points: []const Render.Point) !void {
        const points_data = try self.scene().appendPoints(self.allocator, points);
        try self.submit(.{ .polygon = .{
            .points_offset = points_data.points_offset,
            .points_len = points_data.points_len,
            .fill = self.current_fill,
            .stroke = self.current_stroke,
        } });
    }

    /// Draw a single pixel at `p` using `color`.
    pub fn point(self: *Canvas, p: Render.Point, color: Render.Color) !void {
        try self.submit(.{ .point = .{ .point = p, .color = color } });
    }

    /// Draw a single pixel at `(x,y)` using the current text color.
    pub fn pointAt(self: *Canvas, x: i32, y: i32) !void {
        try self.submit(.{ .point = .{ .point = .{ .x = @intCast(x), .y = @intCast(y) }, .color = self.current_text_color } });
    }

    /// Draw `contents` at `pos` using `font` and explicit color/alignment.
    ///
    /// Returns an error if the text is too long or the text arena is full.
    pub fn text(self: *Canvas, pos: Render.Point, font: Render.FontId, color: Render.Color, textAlign: Render.TextAlign, baseline: Render.TextBaseline, contents: []const u8) !void {
        if (contents.len > std.math.maxInt(u16)) return error.TextTooLong;

        const frame_scene = self.scene();
        if (frame_scene.text_arena.items.len > std.math.maxInt(u32)) return error.TextArenaTooLarge;
        if (contents.len > std.math.maxInt(u32) - frame_scene.text_arena.items.len) return error.TextArenaTooLarge;

        const text_offset: u32 = @intCast(frame_scene.text_arena.items.len);
        try frame_scene.text_arena.appendSlice(self.allocator, contents);

        try self.submit(.{ .text = .{
            .pos = pos,
            .text_offset = text_offset,
            .text_len = @intCast(contents.len),
            .font = font,
            .color = color,
            .textAlign = textAlign,
            .baseline = baseline,
        } });
    }

    /// Draw `contents` at `pos` using `font` and the canvas' text state
    /// (color, align, baseline).
    pub fn textAt(self: *Canvas, pos: Render.Point, font: Render.FontId, contents: []const u8) !void {
        if (contents.len > std.math.maxInt(u16)) return error.TextTooLong;

        const frame_scene = self.scene();
        if (frame_scene.text_arena.items.len > std.math.maxInt(u32)) return error.TextArenaTooLarge;
        if (contents.len > std.math.maxInt(u32) - frame_scene.text_arena.items.len) return error.TextArenaTooLarge;

        const text_offset: u32 = @intCast(frame_scene.text_arena.items.len);
        try frame_scene.text_arena.appendSlice(self.allocator, contents);

        try self.submit(.{ .text = .{
            .pos = pos,
            .text_offset = text_offset,
            .text_len = @intCast(contents.len),
            .font = font,
            .color = self.current_text_color,
            .textAlign = self.current_text_align,
            .baseline = self.current_text_baseline,
        } });
    }

    /// Convenience: draw text at `(x,y)`.
    pub fn textXY(self: *Canvas, x: i32, y: i32, font: Render.FontId, contents: []const u8) !void {
        try self.textAt(.{ .x = @intCast(x), .y = @intCast(y) }, font, contents);
    }

    /// Upload bitmap `data` and enqueue a bitmap draw at `pos`.
    ///
    /// `stride_bytes` and `bit_order` describe the layout of `data`.
    pub fn bitmap(self: *Canvas, pos: Render.Point, width: Render.Dim, height: Render.Dim, data: []const u8, stride_bytes: u16, bit_order: Render.BitmapBitOrder, mode: Render.BitmapMode) !void {
        const frame_scene = self.scene();
        if (frame_scene.bitmap_arena.items.len > std.math.maxInt(u32)) return error.BitmapArenaTooLarge;
        if (data.len > std.math.maxInt(u32)) return error.BitmapTooLarge;
        if (data.len > std.math.maxInt(u32) - frame_scene.bitmap_arena.items.len) return error.BitmapArenaTooLarge;

        const data_offset: u32 = @intCast(frame_scene.bitmap_arena.items.len);
        try frame_scene.bitmap_arena.appendSlice(self.allocator, data);

        try self.submit(.{ .bitmap = .{
            .pos = pos,
            .width = width,
            .height = height,
            .data_offset = data_offset,
            .data_len = @intCast(data.len),
            .stride_bytes = stride_bytes,
            .bit_order = bit_order,
            .mode = mode,
        } });
    }

    /// Convenience: upload and draw a bitmap at `(x,y)`.
    pub fn bitmapXY(self: *Canvas, x: i32, y: i32, width: Render.Dim, height: Render.Dim, data: []const u8, stride_bytes: u16, bit_order: Render.BitmapBitOrder, mode: Render.BitmapMode) !void {
        try self.bitmap(.{ .x = @intCast(x), .y = @intCast(y) }, width, height, data, stride_bytes, bit_order, mode);
    }

    /// Enqueue a blit operation from `src_pos` to `dst_pos` with `size`.
    pub fn blit(self: *Canvas, src_pos: Render.Point, dst_pos: Render.Point, size: Render.Size, mode: Render.BlitMode) !void {
        try self.submit(.{ .blit = .{ .src_pos = src_pos, .dst_pos = dst_pos, .size = size, .mode = mode } });
    }

    /// Invert colors inside `target_rect`.
    pub fn invert(self: *Canvas, target_rect: Render.Rect) !void {
        try self.submit(.{ .invert = .{ .rect = target_rect } });
    }

    /// Invert colors in rectangle `(x,y,w,h)`.
    pub fn invertXYWH(self: *Canvas, x: i32, y: i32, w: i32, h: i32) !void {
        try self.submit(.{ .invert = .{ .rect = .{ .x = @intCast(x), .y = @intCast(y), .width = @intCast(w), .height = @intCast(h) } } });
    }

    /// Push a clipping rectangle on the canvas clip stack.
    pub fn clipPush(self: *Canvas, clip_rect: Render.Rect) !void {
        try self.submit(.{ .clip = .{ .push = clip_rect } });
    }

    /// Push a clipping rectangle `(x,y,w,h)`.
    pub fn clipPushXYWH(self: *Canvas, x: i32, y: i32, w: i32, h: i32) !void {
        try self.submit(.{ .clip = .{ .push = .{ .x = @intCast(x), .y = @intCast(y), .width = @intCast(w), .height = @intCast(h) } } });
    }

    /// Pop the most recent clipping rectangle.
    pub fn clipPop(self: *Canvas) !void {
        try self.submit(.{ .clip = .{ .pop = {} } });
    }

    /// Push a transform matrix to the transform stack.
    pub fn transformPush(self: *Canvas, matrix: Matrix3) !void {
        try self.submit(.{ .transform = .{ .push = matrix } });
    }

    /// Replace the current transform with `matrix`.
    pub fn transformReplace(self: *Canvas, matrix: Matrix3) !void {
        try self.submit(.{ .transform = .{ .replace = matrix } });
    }

    /// Pop the top transform from the transform stack.
    pub fn transformPop(self: *Canvas) !void {
        try self.submit(.{ .transform = .{ .pop = {} } });
    }

    /// No-op command useful for debugging or alignment.
    pub fn nop(self: *Canvas) !void {
        try self.submit(.{ .nop = {} });
    }
};

pub const Renderer = struct {
    allocator: std.mem.Allocator,
    engine: Render.Engine,
    clear_on_begin: ?Render.Color,
    default_present_mode: PresentMode,

    /// Initialize a `Renderer` with `opts`.
    ///
    /// The returned `Renderer` owns a small `Render.Engine` initialized to
    /// target `opts.framebuffer`.
    pub fn init(allocator: std.mem.Allocator, opts: RendererOptions) !Renderer {
        return .{
            .allocator = allocator,
            .engine = .{
                .fb = opts.framebuffer,
                .scene = .{},
            },
            .clear_on_begin = opts.clear_on_begin,
            .default_present_mode = opts.default_present_mode,
        };
    }

    /// Begin a new frame and return a `Canvas` bound to that frame.
    ///
    /// This clears frame-local scene state and emits an optional clear
    /// command if `clear_on_begin` was configured.
    pub fn begin(self: *Renderer) !Canvas {
        self.engine.scene.clearFrame();

        if (self.clear_on_begin) |color| {
            try self.engine.scene.draw_cmds.append(self.allocator, .{ .clear = .{ .color = color } });
        }

        return .{
            .allocator = self.allocator,
            .engine = &self.engine,
            .current_fill = null,
            .current_stroke = null,
            .current_text_color = .black,
            .current_text_align = .left,
            .current_text_baseline = .top,
        };
    }

    /// Deinitialize the renderer and free scene resources.
    pub fn deinit(self: *Renderer) void {
        self.engine.scene.deinit(self.allocator);
    }

    /// Return the accumulated dirty regions for the current frame.
    pub fn dirtyZones(self: *const Renderer) []const Render.RefreshZone {
        return self.engine.scene.dirtyZones();
    }

    /// Clear any accumulated dirty regions.
    pub fn clearDirtyZones(self: *Renderer) void {
        self.engine.scene.clearDirtyZones();
    }

    /// Register a font from `data` and return a `FontId` for use with text
    /// draw calls.
    pub fn registerFont(self: *Renderer, data: []const u8) !Render.FontId {
        return Render.registerFont(&self.engine.scene, self.allocator, data);
    }

    /// Clip a framebuffer rectangle to the display bounds.
    fn clipToFramebuffer(self: *Renderer, rect: Render.Rect) ?Render.Rect {
        const fb = &self.engine.fb;

        const x0 = @max(@as(i32, rect.x), 0);
        const y0 = @max(@as(i32, rect.y), 0);
        const x1 = @min(@as(i32, rect.x) + @as(i32, rect.width), @as(i32, fb.width));
        const y1 = @min(@as(i32, rect.y) + @as(i32, rect.height), @as(i32, fb.height));

        if (x0 >= x1 or y0 >= y1) return null;

        return .{
            .x = @intCast(x0),
            .y = @intCast(y0),
            .width = @intCast(x1 - x0),
            .height = @intCast(y1 - y0),
        };
    }

    /// Helper: perform a full write of the framebuffer.
    fn doFullWrite(self: *Renderer) !void {
        const fb = &self.engine.fb;
        const disp = display_module.get_display();
        try disp.set_mono01();
        const pitch_bytes: usize = (@as(usize, fb.width) + 7) / 8;
        try disp.write(0, 0, @as(u16, fb.width), @as(u16, fb.height), @as(u16, @intCast(pitch_bytes)), fb.pixels.ptr, fb.pixels.len);
    }

    /// Helper: write a rectangular region (copies bits into a temporary byte buffer).
    fn doPartialRect(self: *Renderer, rect: Render.Rect) !void {
        const clipped = self.clipToFramebuffer(rect) orelse return;
        const fb = &self.engine.fb;
        const dst_row_bytes = (@as(usize, clipped.width) + 7) / 8;
        const rows = @as(usize, clipped.height);
        const buf_size = dst_row_bytes * rows;
        var buf = try self.allocator.alloc(u8, buf_size);
        @memset(buf, 0);
        defer self.allocator.free(buf);

        var r: usize = 0;
        while (r < rows) : (r += 1) {
            const y: Render.Dim = @intCast(@as(i32, clipped.y) + @as(i32, @intCast(r)));
            var c: usize = 0;
            while (c < @as(usize, clipped.width)) : (c += 1) {
                const x: Render.Dim = @intCast(@as(i32, clipped.x) + @as(i32, @intCast(c)));
                const col = fb.getPixel(x, y);
                if (col == Render.Color.black) {
                    const byte_idx = r * dst_row_bytes + (c / 8);
                    const bit = 7 - (c % 8);
                    buf[byte_idx] |= @as(u8, 1) << @as(u3, @intCast(bit));
                }
            }
        }

        const disp = display_module.get_display();
        try disp.set_mono01();
        try disp.write(@intCast(clipped.x), @intCast(clipped.y), @intCast(clipped.width), @intCast(clipped.height), @as(u16, @intCast(dst_row_bytes)), buf.ptr, buf_size);
    }

    /// Render the current scene and present it to the display.
    ///
    /// If `mode` is `null` the renderer's `default_present_mode` is used.
    pub fn present(self: *Renderer, mode: ?PresentMode) !void {
        Render.renderScene(&self.engine, self.allocator);

        const selected = if (mode) |m| m else self.default_present_mode;

        switch (selected) {
            .none => return,

            .full => {
                try self.doFullWrite();
            },

            .partial => |rect| {
                try self.doPartialRect(rect);
            },

            .auto => {
                const zones = self.engine.scene.dirtyZones();
                if (zones.len == 0) return;

                var total_dirty: usize = 0;
                for (zones) |z| {
                    if (self.clipToFramebuffer(z.rect)) |clipped| {
                        total_dirty += @as(usize, clipped.width) * @as(usize, clipped.height);
                    }
                }

                const fb = &self.engine.fb;
                const total_area = @as(usize, fb.width) * @as(usize, fb.height);
                if (total_dirty * 4 <= total_area) {
                    for (zones) |z| {
                        try self.doPartialRect(z.rect);
                    }
                } else {
                    try self.doFullWrite();
                }
            },
        }
    }
};
