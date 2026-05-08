const std = @import("std");

pub const Vec2 = struct {
    x: f32,
    y: f32,
};

pub const Matrix3 = struct {
    m00: f32,
    m01: f32,
    m02: f32,
    m10: f32,
    m11: f32,
    m12: f32,
    m20: f32,
    m21: f32,
    m22: f32,

    pub fn zero() Matrix3 {
        return .{
            .m00 = 0,
            .m01 = 0,
            .m02 = 0,
            .m10 = 0,
            .m11 = 0,
            .m12 = 0,
            .m20 = 0,
            .m21 = 0,
            .m22 = 0,
        };
    }

    pub fn identity() Matrix3 {
        return Matrix3{
            .m00 = 1,
            .m01 = 0,
            .m02 = 0,
            .m10 = 0,
            .m11 = 1,
            .m12 = 0,
            .m20 = 0,
            .m21 = 0,
            .m22 = 1,
        };
    }

    pub fn fromRows(
        r0: Vec2,
        r0z: f32,
        r1: Vec2,
        r1z: f32,
        r2: Vec2,
        r2z: f32,
    ) Matrix3 {
        return .{
            .m00 = r0.x,
            .m01 = r0.y,
            .m02 = r0z,
            .m10 = r1.x,
            .m11 = r1.y,
            .m12 = r1z,
            .m20 = r2.x,
            .m21 = r2.y,
            .m22 = r2z,
        };
    }

    pub fn fromColumns(
        c0: Vec2,
        c0z: f32,
        c1: Vec2,
        c1z: f32,
        c2: Vec2,
        c2z: f32,
    ) Matrix3 {
        return .{
            .m00 = c0.x,
            .m01 = c1.x,
            .m02 = c2.x,
            .m10 = c0.y,
            .m11 = c1.y,
            .m12 = c2.y,
            .m20 = c0z,
            .m21 = c1z,
            .m22 = c2z,
        };
    }

    pub fn fromArray(a: [9]f32) Matrix3 {
        return .{
            .m00 = a[0],
            .m01 = a[1],
            .m02 = a[2],
            .m10 = a[3],
            .m11 = a[4],
            .m12 = a[5],
            .m20 = a[6],
            .m21 = a[7],
            .m22 = a[8],
        };
    }

    pub fn toArray(self: Matrix3) [9]f32 {
        return .{
            self.m00, self.m01, self.m02,
            self.m10, self.m11, self.m12,
            self.m20, self.m21, self.m22,
        };
    }

    pub fn transpose(self: Matrix3) Matrix3 {
        return .{
            .m00 = self.m00,
            .m01 = self.m10,
            .m02 = self.m20,
            .m10 = self.m01,
            .m11 = self.m11,
            .m12 = self.m21,
            .m20 = self.m02,
            .m21 = self.m12,
            .m22 = self.m22,
        };
    }

    pub fn mul(a: Matrix3, b: Matrix3) Matrix3 {
        return .{
            .m00 = a.m00 * b.m00 + a.m01 * b.m10 + a.m02 * b.m20,
            .m01 = a.m00 * b.m01 + a.m01 * b.m11 + a.m02 * b.m21,
            .m02 = a.m00 * b.m02 + a.m01 * b.m12 + a.m02 * b.m22,

            .m10 = a.m10 * b.m00 + a.m11 * b.m10 + a.m12 * b.m20,
            .m11 = a.m10 * b.m01 + a.m11 * b.m11 + a.m12 * b.m21,
            .m12 = a.m10 * b.m02 + a.m11 * b.m12 + a.m12 * b.m22,

            .m20 = a.m20 * b.m00 + a.m21 * b.m10 + a.m22 * b.m20,
            .m21 = a.m20 * b.m01 + a.m21 * b.m11 + a.m22 * b.m21,
            .m22 = a.m20 * b.m02 + a.m21 * b.m12 + a.m22 * b.m22,
        };
    }

    pub fn determinant(self: Matrix3) f32 {
        return self.m00 * (self.m11 * self.m22 - self.m12 * self.m21) - self.m01 * (self.m10 * self.m22 - self.m12 * self.m20) + self.m02 * (self.m10 * self.m21 - self.m11 * self.m20);
    }

    pub fn inverse(self: Matrix3) ?Matrix3 {
        const det = self.determinant();

        if (@abs(det) <= 0.000001) {
            return null;
        }

        const inv_det = 1.0 / det;

        return .{
            .m00 = (self.m11 * self.m22 - self.m12 * self.m21) * inv_det,
            .m01 = -(self.m01 * self.m22 - self.m02 * self.m21) * inv_det,
            .m02 = (self.m01 * self.m12 - self.m02 * self.m11) * inv_det,

            .m10 = -(self.m10 * self.m22 - self.m12 * self.m20) * inv_det,
            .m11 = (self.m00 * self.m22 - self.m02 * self.m20) * inv_det,
            .m12 = -(self.m00 * self.m12 - self.m02 * self.m10) * inv_det,

            .m20 = (self.m10 * self.m21 - self.m11 * self.m20) * inv_det,
            .m21 = -(self.m00 * self.m21 - self.m01 * self.m20) * inv_det,
            .m22 = (self.m00 * self.m11 - self.m01 * self.m10) * inv_det,
        };
    }

    pub fn transformPoint(self: Matrix3, p: Vec2) Vec2 {
        const x = self.m00 * p.x + self.m01 * p.y + self.m02;
        const y = self.m10 * p.x + self.m11 * p.y + self.m12;
        const w = self.m20 * p.x + self.m21 * p.y + self.m22;

        if (w != 1.0) {
            return .{ .x = x / w, .y = y / w };
        }

        return .{ .x = x, .y = y };
    }

    pub fn transformVector(self: Matrix3, v: Vec2) Vec2 {
        return .{
            .x = self.m00 * v.x + self.m01 * v.y,
            .y = self.m10 * v.x + self.m11 * v.y,
        };
    }

    pub fn translation(tx: f32, ty: f32) Matrix3 {
        return .{
            .m00 = 1,
            .m01 = 0,
            .m02 = tx,
            .m10 = 0,
            .m11 = 1,
            .m12 = ty,
            .m20 = 0,
            .m21 = 0,
            .m22 = 1,
        };
    }

    pub fn rotation(radians: f32) Matrix3 {
        const c = std.math.cos(radians);
        const s = std.math.sin(radians);

        return .{
            .m00 = c,
            .m01 = -s,
            .m02 = 0,
            .m10 = s,
            .m11 = c,
            .m12 = 0,
            .m20 = 0,
            .m21 = 0,
            .m22 = 1,
        };
    }

    pub fn rotationAround(p: Vec2, radians: f32) Matrix3 {
        return translation(p.x, p.y)
            .mul(rotation(radians))
            .mul(translation(-p.x, -p.y));
    }

    pub fn scale(sx: f32, sy: f32) Matrix3 {
        return .{
            .m00 = sx,
            .m01 = 0,
            .m02 = 0,
            .m10 = 0,
            .m11 = sy,
            .m12 = 0,
            .m20 = 0,
            .m21 = 0,
            .m22 = 1,
        };
    }

    pub fn uniformScale(s: f32) Matrix3 {
        return scale(s, s);
    }

    pub fn scaleAround(p: Vec2, sx: f32, sy: f32) Matrix3 {
        return translation(p.x, p.y)
            .mul(scale(sx, sy))
            .mul(translation(-p.x, -p.y));
    }

    pub fn shearX(k: f32) Matrix3 {
        return .{
            .m00 = 1,
            .m01 = k,
            .m02 = 0,
            .m10 = 0,
            .m11 = 1,
            .m12 = 0,
            .m20 = 0,
            .m21 = 0,
            .m22 = 1,
        };
    }

    pub fn shearY(k: f32) Matrix3 {
        return .{
            .m00 = 1,
            .m01 = 0,
            .m02 = 0,
            .m10 = k,
            .m11 = 1,
            .m12 = 0,
            .m20 = 0,
            .m21 = 0,
            .m22 = 1,
        };
    }

    pub fn shear(kx: f32, ky: f32) Matrix3 {
        return .{
            .m00 = 1,
            .m01 = kx,
            .m02 = 0,
            .m10 = ky,
            .m11 = 1,
            .m12 = 0,
            .m20 = 0,
            .m21 = 0,
            .m22 = 1,
        };
    }

    pub fn skewX(radians: f32) Matrix3 {
        return shearX(std.math.tan(radians));
    }

    pub fn skewY(radians: f32) Matrix3 {
        return shearY(std.math.tan(radians));
    }

    pub fn reflectionX() Matrix3 {
        return scale(1, -1);
    }

    pub fn reflectionY() Matrix3 {
        return scale(-1, 1);
    }

    pub fn reflectionOrigin() Matrix3 {
        return scale(-1, -1);
    }

    pub fn reflectionLineThroughOrigin(angle_radians: f32) Matrix3 {
        const c = std.math.cos(2.0 * angle_radians);
        const s = std.math.sin(2.0 * angle_radians);

        return .{
            .m00 = c,
            .m01 = s,
            .m02 = 0,
            .m10 = s,
            .m11 = -c,
            .m12 = 0,
            .m20 = 0,
            .m21 = 0,
            .m22 = 1,
        };
    }

    pub fn reflectionLine(point: Vec2, angle_radians: f32) Matrix3 {
        return translation(point.x, point.y)
            .mul(reflectionLineThroughOrigin(angle_radians))
            .mul(translation(-point.x, -point.y));
    }

    pub fn projectionX() Matrix3 {
        return scale(1, 0);
    }

    pub fn projectionY() Matrix3 {
        return scale(0, 1);
    }

    pub fn projectionLineThroughOrigin(angle_radians: f32) Matrix3 {
        const c = std.math.cos(angle_radians);
        const s = std.math.sin(angle_radians);

        return .{
            .m00 = c * c,
            .m01 = c * s,
            .m02 = 0,
            .m10 = c * s,
            .m11 = s * s,
            .m12 = 0,
            .m20 = 0,
            .m21 = 0,
            .m22 = 1,
        };
    }

    pub fn projectionLine(point: Vec2, angle_radians: f32) Matrix3 {
        return translation(point.x, point.y)
            .mul(projectionLineThroughOrigin(angle_radians))
            .mul(translation(-point.x, -point.y));
    }

    pub fn ortho(left: f32, right: f32, bottom: f32, top: f32) Matrix3 {
        const sx = 2.0 / (right - left);
        const sy = 2.0 / (top - bottom);
        const tx = -(right + left) / (right - left);
        const ty = -(top + bottom) / (top - bottom);

        return .{
            .m00 = sx,
            .m01 = 0,
            .m02 = tx,
            .m10 = 0,
            .m11 = sy,
            .m12 = ty,
            .m20 = 0,
            .m21 = 0,
            .m22 = 1,
        };
    }

    pub fn screenOrtho(width: f32, height: f32) Matrix3 {
        return .{
            .m00 = 2.0 / width,
            .m01 = 0,
            .m02 = -1,
            .m10 = 0,
            .m11 = -2.0 / height,
            .m12 = 1,
            .m20 = 0,
            .m21 = 0,
            .m22 = 1,
        };
    }

    pub fn viewport(x: f32, y: f32, width: f32, height: f32) Matrix3 {
        return .{
            .m00 = width * 0.5,
            .m01 = 0,
            .m02 = x + width * 0.5,
            .m10 = 0,
            .m11 = -height * 0.5,
            .m12 = y + height * 0.5,
            .m20 = 0,
            .m21 = 0,
            .m22 = 1,
        };
    }

    pub fn uvToRect(x: f32, y: f32, width: f32, height: f32) Matrix3 {
        return .{
            .m00 = width,
            .m01 = 0,
            .m02 = x,
            .m10 = 0,
            .m11 = height,
            .m12 = y,
            .m20 = 0,
            .m21 = 0,
            .m22 = 1,
        };
    }

    pub fn rectToUv(x: f32, y: f32, width: f32, height: f32) Matrix3 {
        return .{
            .m00 = 1.0 / width,
            .m01 = 0,
            .m02 = -x / width,
            .m10 = 0,
            .m11 = 1.0 / height,
            .m12 = -y / height,
            .m20 = 0,
            .m21 = 0,
            .m22 = 1,
        };
    }

    pub fn basis(x_axis: Vec2, y_axis: Vec2, origin: Vec2) Matrix3 {
        return .{
            .m00 = x_axis.x,
            .m01 = y_axis.x,
            .m02 = origin.x,
            .m10 = x_axis.y,
            .m11 = y_axis.y,
            .m12 = origin.y,
            .m20 = 0,
            .m21 = 0,
            .m22 = 1,
        };
    }

    pub fn affine(
        a: f32,
        b: f32,
        c: f32,
        d: f32,
        tx: f32,
        ty: f32,
    ) Matrix3 {
        return .{
            .m00 = a,
            .m01 = c,
            .m02 = tx,
            .m10 = b,
            .m11 = d,
            .m12 = ty,
            .m20 = 0,
            .m21 = 0,
            .m22 = 1,
        };
    }

    pub fn projective(
        a: f32,
        b: f32,
        c: f32,
        d: f32,
        e: f32,
        f: f32,
        g: f32,
        h: f32,
    ) Matrix3 {
        return .{
            .m00 = a,
            .m01 = b,
            .m02 = c,
            .m10 = d,
            .m11 = e,
            .m12 = f,
            .m20 = g,
            .m21 = h,
            .m22 = 1,
        };
    }

    pub fn translated(self: Matrix3, tx: f32, ty: f32) Matrix3 {
        return self.mul(translation(tx, ty));
    }

    pub fn rotated(self: Matrix3, radians: f32) Matrix3 {
        return self.mul(rotation(radians));
    }

    pub fn scaled(self: Matrix3, sx: f32, sy: f32) Matrix3 {
        return self.mul(scale(sx, sy));
    }

    pub fn sheared(self: Matrix3, kx: f32, ky: f32) Matrix3 {
        return self.mul(shear(kx, ky));
    }

    pub fn approxEq(a: Matrix3, b: Matrix3, epsilon: f32) bool {
        return @abs(a.m00 - b.m00) <= epsilon and
            @abs(a.m01 - b.m01) <= epsilon and
            @abs(a.m02 - b.m02) <= epsilon and
            @abs(a.m10 - b.m10) <= epsilon and
            @abs(a.m11 - b.m11) <= epsilon and
            @abs(a.m12 - b.m12) <= epsilon and
            @abs(a.m20 - b.m20) <= epsilon and
            @abs(a.m21 - b.m21) <= epsilon and
            @abs(a.m22 - b.m22) <= epsilon;
    }
};

pub const Matrix3Stack = struct {
    matrices: std.ArrayListUnmanaged(Matrix3) = .{},

    pub fn deinit(self: *Matrix3Stack, allocator: std.mem.Allocator) void {
        self.matrices.deinit(allocator);
    }

    pub fn clear(self: *Matrix3Stack) void {
        self.matrices.clearRetainingCapacity();
    }

    pub fn len(self: Matrix3Stack) usize {
        return self.matrices.items.len;
    }

    pub fn isEmpty(self: Matrix3Stack) bool {
        return self.matrices.items.len == 0;
    }

    pub fn push(self: *Matrix3Stack, allocator: std.mem.Allocator, matrix: Matrix3) !void {
        try self.matrices.append(allocator, matrix);
    }

    pub fn pop(self: *Matrix3Stack) ?Matrix3 {
        if (self.matrices.items.len == 0) return null;

        const index = self.matrices.items.len - 1;
        const matrix = self.matrices.items[index];
        self.matrices.items.len = index;
        return matrix;
    }

    pub fn replace(self: *Matrix3Stack, matrix: Matrix3) bool {
        if (self.matrices.items.len == 0) return false;

        self.matrices.items[self.matrices.items.len - 1] = matrix;
        return true;
    }

    pub fn finalMatrix(self: Matrix3Stack) Matrix3 {
        var result = Matrix3.identity();

        for (self.matrices.items) |matrix| {
            result = result.mul(matrix);
        }

        return result;
    }
};
