const std = @import("std");

pub const CompressionType = enum(u8) {
    None = 0,
    LZ4 = 1,
    HEATSHRINK = 2,
    ZLIB = 3,
    ZSTD = 4,
};

