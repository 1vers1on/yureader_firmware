extern const font_out: u8;
extern const font_len: c_uint;

pub fn getBlob() []const u8 {
    const ptr: [*]const u8 = @ptrCast(&font_out);
    return ptr[0..@intCast(font_len)];
}
