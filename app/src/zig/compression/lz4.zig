const std = @import("std");


pub const Lz4BlockError = error{
    UnexpectedEof,
    OutputTooSmall,
    OffsetOutOfRange,
    ZeroOffset,
    LengthOverflow,
};