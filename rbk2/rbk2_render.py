#!/usr/bin/env python3
from __future__ import annotations

import argparse
import struct
import sys
import time
import zlib
from dataclasses import dataclass
from enum import IntEnum
from pathlib import Path
from typing import ClassVar

try:
    import google_crc32c  # type: ignore[import-not-found]
except ImportError:  # optional fast path
    google_crc32c = None

try:
    import lz4.block as lz4block  # type: ignore[import-not-found]
except ImportError:  # only needed for lz4-compressed rbk2 files
    lz4block = None

try:
    import heatshrink2  # type: ignore[import-not-found]
except ImportError:  # only needed for heatshrink-compressed rbk2 files
    heatshrink2 = None

RBK_MAGIC = b"RBK2"


class CompressionType(IntEnum):
    NONE = 0
    LZ4 = 1
    HEATSHRINK = 2
    ZLIB = 3
    ZSTD = 4


SUPPORTED_BLOCK_COMPRESSIONS = {
    CompressionType.NONE,
    CompressionType.LZ4,
    CompressionType.HEATSHRINK,
    CompressionType.ZLIB,
}


class ChunkKind:
    META = b"META"
    STRS = b"STRS"
    CHAP = b"CHAP"
    PAGE = b"PAGE"
    BLKI = b"BLKI"
    TEXT = b"TEXT"


def _crc32c_sw(data: bytes) -> int:
    crc = 0xFFFFFFFF
    poly = 0x82F63B78
    for byte in data:
        crc ^= byte
        for _ in range(8):
            mask = -(crc & 1)
            crc = (crc >> 1) ^ (poly & mask)
    return (~crc) & 0xFFFFFFFF


def _crc32c(data: bytes) -> int:
    if google_crc32c is not None:
        return int(google_crc32c.value(data))
    return _crc32c_sw(data)


@dataclass(slots=True)
class RbkHeader:
    FORMAT: ClassVar[str] = "<4sHHHHIQQIIIIHHHHHH16sII48s"
    SIZE: ClassVar[int] = struct.calcsize(FORMAT)

    magic: bytes
    version_major: int
    version_minor: int
    header_size: int
    chunk_entry_size: int
    flags: int
    file_size: int
    chunk_table_offset: int
    chunk_count: int
    page_count: int
    chapter_count: int
    reserved1: int
    screen_width_px: int
    screen_height_px: int
    font_width_px: int
    font_height_px: int
    chars_per_line: int
    lines_per_page: int
    book_id: bytes
    directory_crc32c: int
    header_crc32c: int
    reserved2: bytes

    @classmethod
    def unpack(cls, data: bytes) -> "RbkHeader":
        if len(data) < cls.SIZE:
            raise ValueError("not enough bytes for RBK2 header")
        return cls(*struct.unpack(cls.FORMAT, data[: cls.SIZE]))

    def _pack_for_crc(self) -> bytes:
        return struct.pack(
            self.FORMAT,
            self.magic,
            self.version_major,
            self.version_minor,
            self.header_size,
            self.chunk_entry_size,
            self.flags,
            self.file_size,
            self.chunk_table_offset,
            self.chunk_count,
            self.page_count,
            self.chapter_count,
            self.reserved1,
            self.screen_width_px,
            self.screen_height_px,
            self.font_width_px,
            self.font_height_px,
            self.chars_per_line,
            self.lines_per_page,
            self.book_id,
            self.directory_crc32c,
            0,
            self.reserved2,
        )

    def validate(self, actual_file_size: int) -> None:
        if self.magic != RBK_MAGIC:
            raise ValueError("not an RBK2 file: bad magic")
        if (self.version_major, self.version_minor) != (1, 0):
            raise ValueError(f"unsupported RBK2 version {self.version_major}.{self.version_minor}")
        if self.header_size != self.SIZE:
            raise ValueError("invalid RBK2 header size")
        if self.chunk_entry_size != RbkChunkEntry.SIZE:
            raise ValueError("invalid RBK2 chunk table entry size")
        if self.file_size != actual_file_size:
            raise ValueError(f"file size mismatch: header={self.file_size}, actual={actual_file_size}")
        if self.chunk_table_offset < self.header_size:
            raise ValueError("chunk table overlaps header")
        if self.chunk_count == 0:
            raise ValueError("RBK2 file has no chunks")
        if self.compute_crc32c() != self.header_crc32c:
            raise ValueError("invalid RBK2 header CRC32C")
        for name in (
            "screen_width_px",
            "screen_height_px",
            "font_width_px",
            "font_height_px",
            "chars_per_line",
            "lines_per_page",
        ):
            if getattr(self, name) <= 0:
                raise ValueError(f"invalid RBK2 header: {name} must be positive")

    def compute_crc32c(self) -> int:
        return _crc32c(self._pack_for_crc())


@dataclass(slots=True)
class RbkChunkEntry:
    FORMAT: ClassVar[str] = "<4sIHHQQQI16s"
    SIZE: ClassVar[int] = struct.calcsize(FORMAT)

    kind: bytes
    flags: int
    compression: int
    reserved1: int
    offset: int
    packed_size: int
    unpacked_size: int
    crc32c: int
    reserved2: bytes

    @classmethod
    def unpack(cls, data: bytes) -> "RbkChunkEntry":
        if len(data) < cls.SIZE:
            raise ValueError("not enough bytes for chunk entry")
        return cls(*struct.unpack(cls.FORMAT, data[: cls.SIZE]))

    def validate(self, file_size: int, table_end: int) -> None:
        try:
            compression = CompressionType(self.compression)
        except ValueError as e:
            raise ValueError(f"invalid compression type for chunk {self.kind!r}") from e
        if compression != CompressionType.NONE:
            raise ValueError(f"top-level chunk compression is unsupported: {self.kind!r}")
        if self.packed_size == 0 or self.unpacked_size == 0:
            raise ValueError(f"chunk {self.kind!r} has zero size")
        if self.packed_size != self.unpacked_size:
            raise ValueError(f"uncompressed chunk {self.kind!r} has mismatched sizes")
        if self.offset < table_end:
            raise ValueError(f"chunk {self.kind!r} overlaps chunk table")
        if self.offset > file_size or self.offset + self.packed_size > file_size:
            raise ValueError(f"chunk {self.kind!r} exceeds file size")


@dataclass(slots=True)
class RbkMetaChunkHeader:
    FORMAT: ClassVar[str] = "<4sII16s"
    SIZE: ClassVar[int] = struct.calcsize(FORMAT)

    magic: bytes
    entry_count: int
    entry_size: int
    reserved: bytes

    @classmethod
    def unpack(cls, data: bytes) -> "RbkMetaChunkHeader":
        return cls(*struct.unpack(cls.FORMAT, data[: cls.SIZE]))

    def validate(self, chunk_size: int) -> None:
        if self.magic != ChunkKind.META:
            raise ValueError("invalid META chunk")
        if self.entry_size != RbkMetaEntry.SIZE:
            raise ValueError("invalid META entry size")
        if self.SIZE + self.entry_count * self.entry_size > chunk_size:
            raise ValueError("META entries exceed chunk size")


@dataclass(slots=True)
class RbkMetaEntry:
    FORMAT: ClassVar[str] = "<II"
    SIZE: ClassVar[int] = struct.calcsize(FORMAT)

    key_string: int
    value_string: int

    @classmethod
    def unpack(cls, data: bytes) -> "RbkMetaEntry":
        return cls(*struct.unpack(cls.FORMAT, data[: cls.SIZE]))


@dataclass(slots=True)
class RbkChapterChunkHeader:
    FORMAT: ClassVar[str] = "<4sII16s"
    SIZE: ClassVar[int] = struct.calcsize(FORMAT)

    magic: bytes
    chapter_count: int
    entry_size: int
    reserved: bytes

    @classmethod
    def unpack(cls, data: bytes) -> "RbkChapterChunkHeader":
        return cls(*struct.unpack(cls.FORMAT, data[: cls.SIZE]))

    def validate(self, chunk_size: int) -> None:
        if self.magic != ChunkKind.CHAP:
            raise ValueError("invalid CHAP chunk")
        if self.entry_size != RbkChapterEntry.SIZE:
            raise ValueError("invalid CHAP entry size")
        if self.SIZE + self.chapter_count * self.entry_size > chunk_size:
            raise ValueError("CHAP entries exceed chunk size")


@dataclass(slots=True)
class RbkChapterEntry:
    FORMAT: ClassVar[str] = "<IIIHH16s"
    SIZE: ClassVar[int] = struct.calcsize(FORMAT)

    title_string: int
    first_page: int
    page_count: int
    level: int
    flags: int
    reserved: bytes

    @classmethod
    def unpack(cls, data: bytes) -> "RbkChapterEntry":
        return cls(*struct.unpack(cls.FORMAT, data[: cls.SIZE]))


@dataclass(slots=True)
class RbkPageChunkHeader:
    FORMAT: ClassVar[str] = "<4sII16s"
    SIZE: ClassVar[int] = struct.calcsize(FORMAT)

    magic: bytes
    page_count: int
    entry_size: int
    reserved: bytes

    @classmethod
    def unpack(cls, data: bytes) -> "RbkPageChunkHeader":
        return cls(*struct.unpack(cls.FORMAT, data[: cls.SIZE]))

    def validate(self, chunk_size: int) -> None:
        if self.magic != ChunkKind.PAGE:
            raise ValueError("invalid PAGE chunk")
        if self.entry_size != RbkPageEntry.SIZE:
            raise ValueError("invalid PAGE entry size")
        if self.SIZE + self.page_count * self.entry_size > chunk_size:
            raise ValueError("PAGE entries exceed chunk size")


@dataclass(slots=True)
class RbkPageEntry:
    FORMAT: ClassVar[str] = "<IIIIHHI"
    SIZE: ClassVar[int] = struct.calcsize(FORMAT)

    chapter_index: int
    block_index: int
    unpacked_offset: int
    unpacked_length: int
    line_count: int
    reserved0: int
    flags: int

    @classmethod
    def unpack(cls, data: bytes) -> "RbkPageEntry":
        return cls(*struct.unpack(cls.FORMAT, data[: cls.SIZE]))


@dataclass(slots=True)
class RbkBlockIndexChunkHeader:
    FORMAT: ClassVar[str] = "<4sII16s"
    SIZE: ClassVar[int] = struct.calcsize(FORMAT)

    magic: bytes
    block_count: int
    entry_size: int
    reserved: bytes

    @classmethod
    def unpack(cls, data: bytes) -> "RbkBlockIndexChunkHeader":
        return cls(*struct.unpack(cls.FORMAT, data[: cls.SIZE]))

    def validate(self, chunk_size: int) -> None:
        if self.magic != ChunkKind.BLKI:
            raise ValueError("invalid BLKI chunk")
        if self.entry_size != RbkBlockEntry.SIZE:
            raise ValueError("invalid BLKI entry size")
        if self.SIZE + self.block_count * self.entry_size > chunk_size:
            raise ValueError("BLKI entries exceed chunk size")


@dataclass(slots=True)
class RbkBlockEntry:
    FORMAT: ClassVar[str] = "<QIIIIIIII16s"
    SIZE: ClassVar[int] = struct.calcsize(FORMAT)

    packed_offset: int
    packed_size: int
    unpacked_size: int
    first_page: int
    page_count: int
    crc32c: int
    compression: int
    flags: int
    reserved1: int
    reserved2: bytes

    @classmethod
    def unpack(cls, data: bytes) -> "RbkBlockEntry":
        return cls(*struct.unpack(cls.FORMAT, data[: cls.SIZE]))

    def validate(self, text_data_size: int) -> None:
        try:
            compression = CompressionType(self.compression)
        except ValueError as e:
            raise ValueError("invalid block compression type") from e
        if compression not in SUPPORTED_BLOCK_COMPRESSIONS:
            raise ValueError(f"unsupported block compression type: {compression.name.lower()}")
        if self.packed_size == 0 or self.unpacked_size == 0:
            raise ValueError("block has zero size")
        if self.page_count == 0:
            raise ValueError("block has no pages")
        if self.packed_offset > text_data_size or self.packed_offset + self.packed_size > text_data_size:
            raise ValueError("block exceeds TEXT data")


@dataclass(slots=True)
class RbkStringTableHeader:
    FORMAT: ClassVar[str] = "<4sIIIII16s"
    SIZE: ClassVar[int] = struct.calcsize(FORMAT)

    magic: bytes
    string_count: int
    entry_size: int
    entries_offset: int
    data_offset: int
    data_size: int
    reserved: bytes

    @classmethod
    def unpack(cls, data: bytes) -> "RbkStringTableHeader":
        return cls(*struct.unpack(cls.FORMAT, data[: cls.SIZE]))

    def validate(self, chunk_size: int) -> None:
        if self.magic != ChunkKind.STRS:
            raise ValueError("invalid STRS chunk")
        if self.entry_size != RbkStringEntry.SIZE:
            raise ValueError("invalid STRS entry size")
        if self.entries_offset < self.SIZE:
            raise ValueError("invalid STRS entries offset")
        if self.entries_offset + self.string_count * self.entry_size > chunk_size:
            raise ValueError("STRS entries exceed chunk size")
        if self.data_offset + self.data_size > chunk_size:
            raise ValueError("STRS data exceeds chunk size")


@dataclass(slots=True)
class RbkStringEntry:
    FORMAT: ClassVar[str] = "<QI"
    SIZE: ClassVar[int] = struct.calcsize(FORMAT)

    offset: int
    length: int

    @classmethod
    def unpack(cls, data: bytes) -> "RbkStringEntry":
        return cls(*struct.unpack(cls.FORMAT, data[: cls.SIZE]))


@dataclass(slots=True)
class RbkTextChunkHeader:
    FORMAT: ClassVar[str] = "<4sIQQII16s"
    SIZE: ClassVar[int] = struct.calcsize(FORMAT)

    magic: bytes
    data_offset: int
    packed_data_size: int
    unpacked_total_size: int
    block_count: int
    flags: int
    reserved: bytes

    @classmethod
    def unpack(cls, data: bytes) -> "RbkTextChunkHeader":
        return cls(*struct.unpack(cls.FORMAT, data[: cls.SIZE]))

    def validate(self, chunk_size: int) -> None:
        if self.magic != ChunkKind.TEXT:
            raise ValueError("invalid TEXT chunk")
        if self.data_offset < self.SIZE:
            raise ValueError("invalid TEXT data offset")
        if self.packed_data_size == 0 or self.unpacked_total_size == 0:
            raise ValueError("TEXT has zero data size")
        if self.block_count == 0:
            raise ValueError("TEXT has no blocks")
        if self.data_offset + self.packed_data_size > chunk_size:
            raise ValueError("TEXT data exceeds chunk size")


@dataclass(slots=True)
class RbkBook:
    header: RbkHeader
    metadata: dict[str, str]
    chapters: list[RbkChapterEntry]
    chapter_titles: list[str]
    pages: list[str]
    page_entries: list[RbkPageEntry]


RBS_MAGIC = b"RBS2"


class StateChunkKind:
    PROG = b"PROG"  # current reading progress
    STAT = b"STAT"  # cumulative reading statistics
    BMKS = b"BMKS"  # bookmarks / highlights table
    SESS = b"SESS"  # reading session log


BOOKMARK_FLAG_BOOKMARK = 1
BOOKMARK_FLAG_HIGHLIGHT = 2


@dataclass(slots=True)
class RbsHeader:
    FORMAT: ClassVar[str] = "<4sHHHHI16sQQIII48s"
    SIZE: ClassVar[int] = struct.calcsize(FORMAT)

    magic: bytes = RBS_MAGIC
    version_major: int = 1
    version_minor: int = 0
    header_size: int = 0
    chunk_entry_size: int = 0
    flags: int = 0
    book_id: bytes = b"\x00" * 16
    file_size: int = 0
    chunk_table_offset: int = 0
    chunk_count: int = 0
    header_crc32c: int = 0
    reserved1: int = 0
    reserved2: bytes = b"\x00" * 48

    def normalized(self) -> "RbsHeader":
        self.header_size = self.SIZE
        self.chunk_entry_size = RbsChunkEntry.SIZE
        if self.chunk_table_offset == 0:
            self.chunk_table_offset = self.SIZE
        if len(self.book_id) != 16:
            raise ValueError("RBS2 book_id must be 16 bytes")
        if len(self.reserved2) != 48:
            raise ValueError("RBS2 reserved2 must be 48 bytes")
        return self

    def _pack_unchecked(self, *, crc_field: int | None = None) -> bytes:
        header_crc = self.header_crc32c if crc_field is None else crc_field
        return struct.pack(
            self.FORMAT,
            self.magic,
            self.version_major,
            self.version_minor,
            self.header_size,
            self.chunk_entry_size,
            self.flags,
            self.book_id,
            self.file_size,
            self.chunk_table_offset,
            self.chunk_count,
            header_crc,
            self.reserved1,
            self.reserved2,
        )

    def pack(self, *, crc_field: int | None = None) -> bytes:
        self.normalized()
        return self._pack_unchecked(crc_field=crc_field)

    def bytes_for_crc(self) -> bytes:
        self.normalized()
        return self._pack_unchecked(crc_field=0)

    def compute_crc32c(self) -> int:
        return _crc32c(self.bytes_for_crc())

    @classmethod
    def unpack(cls, data: bytes) -> "RbsHeader":
        if len(data) < cls.SIZE:
            raise ValueError("not enough bytes for RBS2 header")
        return cls(*struct.unpack(cls.FORMAT, data[: cls.SIZE]))

    def validate(self, actual_file_size: int) -> None:
        if self.magic != RBS_MAGIC:
            raise ValueError("not an RBS2 file: bad magic")
        if self.version_major != 1:
            raise ValueError(f"unsupported RBS2 version {self.version_major}.{self.version_minor}")
        if self.header_size != self.SIZE:
            raise ValueError("invalid RBS2 header size")
        if self.chunk_entry_size != RbsChunkEntry.SIZE:
            raise ValueError("invalid RBS2 chunk entry size")
        if self.file_size != actual_file_size:
            raise ValueError(f"RBS2 file size mismatch: header={self.file_size}, actual={actual_file_size}")
        if self.chunk_table_offset < self.header_size:
            raise ValueError("RBS2 chunk table overlaps header")
        if self.compute_crc32c() != self.header_crc32c:
            raise ValueError("invalid RBS2 header CRC32C")


@dataclass(slots=True)
class RbsChunkEntry:
    FORMAT: ClassVar[str] = "<4sIQQI12s"
    SIZE: ClassVar[int] = struct.calcsize(FORMAT)

    kind: bytes
    flags: int
    offset: int
    size: int
    crc32c: int
    reserved: bytes = b"\x00" * 12

    def pack(self) -> bytes:
        if len(self.kind) != 4:
            raise ValueError("RBS2 chunk kind must be 4 bytes")
        if len(self.reserved) != 12:
            raise ValueError("RBS2 chunk reserved must be 12 bytes")
        return struct.pack(self.FORMAT, self.kind, self.flags, self.offset, self.size, self.crc32c, self.reserved)

    @classmethod
    def unpack(cls, data: bytes) -> "RbsChunkEntry":
        if len(data) < cls.SIZE:
            raise ValueError("not enough bytes for RBS2 chunk entry")
        return cls(*struct.unpack(cls.FORMAT, data[: cls.SIZE]))

    def validate(self, file_size: int, table_end: int) -> None:
        if len(self.kind) != 4:
            raise ValueError("RBS2 chunk kind must be 4 bytes")
        if self.size == 0:
            raise ValueError(f"RBS2 chunk {self.kind!r} has zero size")
        if self.offset < table_end:
            raise ValueError(f"RBS2 chunk {self.kind!r} overlaps chunk table")
        if self.offset > file_size or self.offset + self.size > file_size:
            raise ValueError(f"RBS2 chunk {self.kind!r} exceeds file size")


@dataclass(slots=True)
class RbsProgressChunk:
    FORMAT: ClassVar[str] = "<4sIIIQII16s"
    SIZE: ClassVar[int] = struct.calcsize(FORMAT)

    magic: bytes = StateChunkKind.PROG
    current_page: int = 0
    current_chapter: int = 0
    current_block: int = 0
    last_read_timestamp: int = 0
    percent_completed_bp: int = 0
    flags: int = 0
    reserved: bytes = b"\x00" * 16

    def pack(self) -> bytes:
        return struct.pack(
            self.FORMAT,
            self.magic,
            self.current_page,
            self.current_chapter,
            self.current_block,
            self.last_read_timestamp,
            self.percent_completed_bp,
            self.flags,
            self.reserved,
        )

    @classmethod
    def unpack(cls, data: bytes) -> "RbsProgressChunk":
        if len(data) < cls.SIZE:
            raise ValueError("not enough bytes for RBS2 PROG chunk")
        value = cls(*struct.unpack(cls.FORMAT, data[: cls.SIZE]))
        if value.magic != StateChunkKind.PROG:
            raise ValueError("invalid RBS2 PROG chunk magic")
        return value


@dataclass(slots=True)
class RbsStatsChunk:
    FORMAT: ClassVar[str] = "<4sQQIIIII16s"
    SIZE: ClassVar[int] = struct.calcsize(FORMAT)

    magic: bytes = StateChunkKind.STAT
    total_reading_seconds: int = 0
    total_pages_flipped: int = 0
    longest_session_seconds: int = 0
    average_seconds_per_page: int = 0
    fast_page_skips: int = 0
    completion_count: int = 0
    time_of_day_preference: int = 0
    reserved: bytes = b"\x00" * 16

    def pack(self) -> bytes:
        return struct.pack(
            self.FORMAT,
            self.magic,
            self.total_reading_seconds,
            self.total_pages_flipped,
            self.longest_session_seconds,
            self.average_seconds_per_page,
            self.fast_page_skips,
            self.completion_count,
            self.time_of_day_preference,
            self.reserved,
        )

    @classmethod
    def unpack(cls, data: bytes) -> "RbsStatsChunk":
        if len(data) < cls.SIZE:
            raise ValueError("not enough bytes for RBS2 STAT chunk")
        value = cls(*struct.unpack(cls.FORMAT, data[: cls.SIZE]))
        if value.magic != StateChunkKind.STAT:
            raise ValueError("invalid RBS2 STAT chunk magic")
        return value


@dataclass(slots=True)
class RbsBookmarkChunkHeader:
    FORMAT: ClassVar[str] = "<4sII16s"
    SIZE: ClassVar[int] = struct.calcsize(FORMAT)

    magic: bytes = StateChunkKind.BMKS
    entry_count: int = 0
    entry_size: int = 0
    reserved: bytes = b"\x00" * 16

    def pack(self) -> bytes:
        self.entry_size = RbsBookmarkEntry.SIZE
        return struct.pack(self.FORMAT, self.magic, self.entry_count, self.entry_size, self.reserved)

    @classmethod
    def unpack(cls, data: bytes) -> "RbsBookmarkChunkHeader":
        if len(data) < cls.SIZE:
            raise ValueError("not enough bytes for RBS2 BMKS header")
        value = cls(*struct.unpack(cls.FORMAT, data[: cls.SIZE]))
        if value.magic != StateChunkKind.BMKS:
            raise ValueError("invalid RBS2 BMKS chunk magic")
        if value.entry_size != RbsBookmarkEntry.SIZE:
            raise ValueError("invalid RBS2 BMKS entry size")
        if cls.SIZE + value.entry_count * value.entry_size > len(data):
            raise ValueError("RBS2 BMKS entries exceed chunk size")
        return value


@dataclass(slots=True)
class RbsBookmarkEntry:
    FORMAT: ClassVar[str] = "<IIIIQI64s"
    SIZE: ClassVar[int] = struct.calcsize(FORMAT)

    page_index: int
    chapter_index: int
    text_offset: int
    text_length: int
    timestamp: int
    flags: int
    label: bytes = b"\x00" * 64

    def pack(self) -> bytes:
        if len(self.label) != 64:
            raise ValueError("RBS2 bookmark label must be exactly 64 bytes")
        return struct.pack(
            self.FORMAT,
            self.page_index,
            self.chapter_index,
            self.text_offset,
            self.text_length,
            self.timestamp,
            self.flags,
            self.label,
        )

    @classmethod
    def unpack(cls, data: bytes) -> "RbsBookmarkEntry":
        if len(data) < cls.SIZE:
            raise ValueError("not enough bytes for RBS2 bookmark entry")
        return cls(*struct.unpack(cls.FORMAT, data[: cls.SIZE]))

    def label_text(self) -> str:
        return self.label.split(b"\x00", 1)[0].decode("utf-8", errors="replace")


@dataclass(slots=True)
class RbsSessionChunkHeader:
    FORMAT: ClassVar[str] = "<4sII16s"
    SIZE: ClassVar[int] = struct.calcsize(FORMAT)

    magic: bytes = StateChunkKind.SESS
    entry_count: int = 0
    entry_size: int = 0
    reserved: bytes = b"\x00" * 16

    def pack(self) -> bytes:
        self.entry_size = RbsSessionEntry.SIZE
        return struct.pack(self.FORMAT, self.magic, self.entry_count, self.entry_size, self.reserved)

    @classmethod
    def unpack(cls, data: bytes) -> "RbsSessionChunkHeader":
        if len(data) < cls.SIZE:
            raise ValueError("not enough bytes for RBS2 SESS header")
        value = cls(*struct.unpack(cls.FORMAT, data[: cls.SIZE]))
        if value.magic != StateChunkKind.SESS:
            raise ValueError("invalid RBS2 SESS chunk magic")
        if value.entry_size != RbsSessionEntry.SIZE:
            raise ValueError("invalid RBS2 SESS entry size")
        if cls.SIZE + value.entry_count * value.entry_size > len(data):
            raise ValueError("RBS2 SESS entries exceed chunk size")
        return value


@dataclass(slots=True)
class RbsSessionEntry:
    FORMAT: ClassVar[str] = "<QIIII"
    SIZE: ClassVar[int] = struct.calcsize(FORMAT)

    start_timestamp: int
    duration_seconds: int
    pages_read_count: int
    starting_page_index: int
    flags: int = 0

    def pack(self) -> bytes:
        return struct.pack(
            self.FORMAT,
            self.start_timestamp,
            self.duration_seconds,
            self.pages_read_count,
            self.starting_page_index,
            self.flags,
        )

    @classmethod
    def unpack(cls, data: bytes) -> "RbsSessionEntry":
        if len(data) < cls.SIZE:
            raise ValueError("not enough bytes for RBS2 session entry")
        return cls(*struct.unpack(cls.FORMAT, data[: cls.SIZE]))


@dataclass(slots=True)
class RbsState:
    progress: RbsProgressChunk
    stats: RbsStatsChunk
    bookmarks: list[RbsBookmarkEntry]
    sessions: list[RbsSessionEntry]

    @classmethod
    def fresh(cls) -> "RbsState":
        return cls(RbsProgressChunk(), RbsStatsChunk(), [], [])


def _rbs_label_bytes(label: str) -> bytes:
    raw = label.encode("utf-8")[:63]
    return raw + b"\x00" * (64 - len(raw))


def _pack_bookmark_chunk(bookmarks: list[RbsBookmarkEntry]) -> bytes:
    header = RbsBookmarkChunkHeader(entry_count=len(bookmarks))
    return header.pack() + b"".join(bookmark.pack() for bookmark in bookmarks)


def _pack_session_chunk(sessions: list[RbsSessionEntry]) -> bytes:
    header = RbsSessionChunkHeader(entry_count=len(sessions))
    return header.pack() + b"".join(session.pack() for session in sessions)


def _unpack_bookmark_chunk(data: bytes) -> list[RbsBookmarkEntry]:
    header = RbsBookmarkChunkHeader.unpack(data)
    entries = []
    for i in range(header.entry_count):
        start = header.SIZE + i * header.entry_size
        entries.append(RbsBookmarkEntry.unpack(data[start : start + header.entry_size]))
    return entries


def _unpack_session_chunk(data: bytes) -> list[RbsSessionEntry]:
    header = RbsSessionChunkHeader.unpack(data)
    entries = []
    for i in range(header.entry_count):
        start = header.SIZE + i * header.entry_size
        entries.append(RbsSessionEntry.unpack(data[start : start + header.entry_size]))
    return entries


def read_rbs2_state(path: Path, expected_book_id: bytes, *, page_count: int | None = None) -> RbsState:
    if not path.exists():
        return RbsState.fresh()

    data = path.read_bytes()
    header = RbsHeader.unpack(data)
    header.validate(len(data))
    if header.book_id != expected_book_id:
        raise ValueError("RBS2 state belongs to a different RBK2 book_id")

    table_start = header.chunk_table_offset
    table_end = table_start + header.chunk_count * header.chunk_entry_size
    if table_end > len(data):
        raise ValueError("RBS2 chunk table exceeds file size")

    chunks: dict[bytes, bytes] = {}
    spans: list[tuple[int, int, bytes]] = []
    for i in range(header.chunk_count):
        off = table_start + i * header.chunk_entry_size
        entry = RbsChunkEntry.unpack(data[off : off + header.chunk_entry_size])
        entry.validate(len(data), table_end)
        if entry.kind in chunks:
            raise ValueError(f"duplicate RBS2 chunk kind: {entry.kind!r}")
        payload = data[entry.offset : entry.offset + entry.size]
        if _crc32c(payload) != entry.crc32c:
            raise ValueError(f"invalid RBS2 CRC32C for chunk {entry.kind!r}")
        chunks[entry.kind] = payload
        spans.append((entry.offset, entry.offset + entry.size, entry.kind))

    for (prev_start, prev_end, prev_kind), (start, _end, kind) in zip(sorted(spans), sorted(spans)[1:]):
        if start < prev_end:
            raise ValueError(f"RBS2 chunk {kind!r} overlaps chunk {prev_kind!r}")

    state = RbsState.fresh()
    if StateChunkKind.PROG in chunks:
        state.progress = RbsProgressChunk.unpack(chunks[StateChunkKind.PROG])
    if StateChunkKind.STAT in chunks:
        state.stats = RbsStatsChunk.unpack(chunks[StateChunkKind.STAT])
    if StateChunkKind.BMKS in chunks:
        state.bookmarks = _unpack_bookmark_chunk(chunks[StateChunkKind.BMKS])
    if StateChunkKind.SESS in chunks:
        state.sessions = _unpack_session_chunk(chunks[StateChunkKind.SESS])

    if page_count is not None:
        state.progress.current_page = max(0, min(state.progress.current_page, max(0, page_count - 1)))
        state.bookmarks = [b for b in state.bookmarks if b.page_index < page_count]
    return state


def write_rbs2_state(path: Path, book_id: bytes, state: RbsState) -> None:
    if len(book_id) != 16:
        raise ValueError("RBS2 book_id must be 16 bytes")

    chunks = [
        (StateChunkKind.PROG, state.progress.pack()),
        (StateChunkKind.STAT, state.stats.pack()),
        (StateChunkKind.BMKS, _pack_bookmark_chunk(state.bookmarks)),
        (StateChunkKind.SESS, _pack_session_chunk(state.sessions)),
    ]

    header = RbsHeader(book_id=book_id, chunk_table_offset=RbsHeader.SIZE, chunk_count=len(chunks))
    table_size = len(chunks) * RbsChunkEntry.SIZE
    offset = header.chunk_table_offset + table_size
    entries: list[RbsChunkEntry] = []
    payloads: list[bytes] = []

    for kind, payload in chunks:
        entries.append(RbsChunkEntry(kind=kind, flags=0, offset=offset, size=len(payload), crc32c=_crc32c(payload)))
        payloads.append(payload)
        offset += len(payload)

    header.file_size = offset
    header.header_crc32c = header.compute_crc32c()
    blob = header.pack() + b"".join(entry.pack() for entry in entries) + b"".join(payloads)
    if len(blob) != header.file_size:
        raise AssertionError("internal RBS2 pack size mismatch")

    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f".{path.name}.tmp")
    tmp.write_bytes(blob)
    tmp.replace(path)


def default_rbs2_path(rbk2_path: Path) -> Path:
    return rbk2_path.with_suffix(".rbs2")


def _format_duration(seconds: int) -> str:
    seconds = max(0, int(seconds))
    hours, rem = divmod(seconds, 3600)
    minutes, secs = divmod(rem, 60)
    if hours:
        return f"{hours}h {minutes}m"
    if minutes:
        return f"{minutes}m {secs}s"
    return f"{secs}s"


def _time_of_day_bucket(timestamp: int | None = None) -> int:
    hour = time.localtime(timestamp or time.time()).tm_hour
    if 5 <= hour < 12:
        return 0
    if 12 <= hour < 17:
        return 1
    if 17 <= hour < 22:
        return 2
    return 3


def dump_state(book: RbkBook, state_path: Path) -> None:
    state = read_rbs2_state(state_path, book.header.book_id, page_count=len(book.pages))
    progress = state.progress
    stats = state.stats
    print(f"state: {state_path}")
    print(f"last page: {progress.current_page + 1}/{len(book.pages)} ({progress.percent_completed_bp / 100:.2f}%)")
    print(f"last read: {time.ctime(progress.last_read_timestamp) if progress.last_read_timestamp else 'never'}")
    print(f"total reading time: {_format_duration(stats.total_reading_seconds)}")
    print(f"pages flipped: {stats.total_pages_flipped}")
    print(f"average seconds/page: {stats.average_seconds_per_page}")
    print(f"fast skips: {stats.fast_page_skips}")
    print(f"completions: {stats.completion_count}")
    print(f"sessions: {len(state.sessions)}")
    print(f"bookmarks: {len(state.bookmarks)}")
    for i, bookmark in enumerate(state.bookmarks, start=1):
        label = bookmark.label_text()
        suffix = f" — {label}" if label else ""
        print(f"  {i}. page {bookmark.page_index + 1}{suffix}")


@dataclass(slots=True)
class Glyph:
    encoding: int
    dwidth: int
    bbx_width: int
    bbx_height: int
    xoff: int
    yoff: int
    bitmap_rows: list[tuple[int, int]]  # (row bits, number of bits stored in row)


@dataclass(slots=True)
class BdfFont:
    glyphs: dict[int, Glyph]
    default_glyph: Glyph
    bbox_width: int
    bbox_height: int
    bbox_xoff: int
    bbox_yoff: int
    ascent: int
    descent: int

    @classmethod
    def load(cls, path: Path) -> "BdfFont":
        if not path.is_file():
            raise FileNotFoundError(f"font not found: {path}")

        glyphs: dict[int, Glyph] = {}
        bbox_width = 6
        bbox_height = 12
        bbox_xoff = 0
        bbox_yoff = 0
        ascent = 10
        descent = 2

        lines = path.read_text(encoding="ascii", errors="replace").splitlines()
        i = 0
        while i < len(lines):
            line = lines[i].strip()
            parts = line.split()
            if not parts:
                i += 1
                continue

            if parts[0] == "FONTBOUNDINGBOX" and len(parts) >= 5:
                bbox_width, bbox_height, bbox_xoff, bbox_yoff = map(int, parts[1:5])
                # Good fallback when properties are missing.
                ascent = max(1, bbox_height + bbox_yoff)
                descent = max(0, -bbox_yoff)
                i += 1
                continue

            if parts[0] == "FONT_ASCENT" and len(parts) >= 2:
                ascent = int(parts[1])
                i += 1
                continue

            if parts[0] == "FONT_DESCENT" and len(parts) >= 2:
                descent = int(parts[1])
                i += 1
                continue

            if parts[0] != "STARTCHAR":
                i += 1
                continue

            encoding = -1
            dwidth = bbox_width
            bbx = (bbox_width, bbox_height, bbox_xoff, bbox_yoff)
            bitmap_hex: list[str] = []
            in_bitmap = False
            i += 1

            while i < len(lines):
                gline = lines[i].strip()
                gparts = gline.split()
                if not gparts:
                    i += 1
                    continue
                if gparts[0] == "ENDCHAR":
                    break
                if in_bitmap:
                    bitmap_hex.append(gline)
                    i += 1
                    continue
                if gparts[0] == "ENCODING" and len(gparts) >= 2:
                    encoding = int(gparts[1])
                elif gparts[0] == "DWIDTH" and len(gparts) >= 2:
                    dwidth = int(gparts[1])
                elif gparts[0] == "BBX" and len(gparts) >= 5:
                    bbx = tuple(map(int, gparts[1:5]))  # type: ignore[assignment]
                elif gparts[0] == "BITMAP":
                    in_bitmap = True
                i += 1

            if encoding >= 0:
                bbx_width_g, bbx_height_g, xoff, yoff = bbx
                rows: list[tuple[int, int]] = []
                for hx in bitmap_hex[:bbx_height_g]:
                    hx = hx.strip()
                    rows.append((int(hx or "0", 16), len(hx) * 4))
                while len(rows) < bbx_height_g:
                    rows.append((0, max(1, ((bbx_width_g + 7) // 8) * 8)))
                glyphs[encoding] = Glyph(
                    encoding=encoding,
                    dwidth=dwidth,
                    bbx_width=bbx_width_g,
                    bbx_height=bbx_height_g,
                    xoff=xoff,
                    yoff=yoff,
                    bitmap_rows=rows,
                )
            i += 1

        if not glyphs:
            raise ValueError(f"BDF font has no glyphs: {path}")

        default_glyph = glyphs.get(ord("?")) or glyphs.get(0) or next(iter(glyphs.values()))
        return cls(
            glyphs=glyphs,
            default_glyph=default_glyph,
            bbox_width=bbox_width,
            bbox_height=bbox_height,
            bbox_xoff=bbox_xoff,
            bbox_yoff=bbox_yoff,
            ascent=ascent,
            descent=descent,
        )

    def glyph_for(self, ch: str) -> Glyph:
        return self.glyphs.get(ord(ch), self.default_glyph)


def _parse_fixed_entries(chunk: bytes, header_size: int, entry_size: int, count: int, cls):
    end = header_size + count * entry_size
    if end > len(chunk):
        raise ValueError("fixed entries exceed chunk size")
    return [cls.unpack(chunk[header_size + i * entry_size : header_size + (i + 1) * entry_size]) for i in range(count)]


def _chunk_map(data: bytes, header: RbkHeader) -> dict[bytes, bytes]:
    table_start = header.chunk_table_offset
    table_end = table_start + header.chunk_count * header.chunk_entry_size
    if table_end > len(data):
        raise ValueError("chunk table exceeds file size")

    table = data[table_start:table_end]
    if _crc32c(table) != header.directory_crc32c:
        raise ValueError("invalid chunk table CRC32C")

    chunks: dict[bytes, bytes] = {}
    spans: list[tuple[int, int, bytes]] = []
    for i in range(header.chunk_count):
        entry = RbkChunkEntry.unpack(table[i * header.chunk_entry_size : (i + 1) * header.chunk_entry_size])
        entry.validate(header.file_size, table_end)
        if entry.kind in chunks:
            raise ValueError(f"duplicate chunk kind: {entry.kind!r}")
        begin = int(entry.offset)
        end = begin + int(entry.packed_size)
        payload = data[begin:end]
        if _crc32c(payload) != entry.crc32c:
            raise ValueError(f"invalid CRC32C for chunk {entry.kind!r}")
        chunks[entry.kind] = payload
        spans.append((begin, end, entry.kind))

    for (prev_start, prev_end, prev_kind), (start, _end, kind) in zip(sorted(spans), sorted(spans)[1:]):
        if start < prev_end:
            raise ValueError(f"chunk {kind!r} overlaps chunk {prev_kind!r}")
    return chunks


def _read_string_table(chunk: bytes) -> list[str]:
    header = RbkStringTableHeader.unpack(chunk)
    header.validate(len(chunk))
    strings: list[str] = []
    string_data = chunk[header.data_offset : header.data_offset + header.data_size]

    for i in range(header.string_count):
        off = header.entries_offset + i * header.entry_size
        entry = RbkStringEntry.unpack(chunk[off : off + header.entry_size])
        start = int(entry.offset)
        end = start + int(entry.length)
        if end > len(string_data):
            raise ValueError("string entry exceeds STRS data")
        if end >= len(string_data) or string_data[end : end + 1] != b"\x00":
            raise ValueError("string entry is not null terminated")
        strings.append(string_data[start:end].decode("utf-8"))
    return strings


def _decompress_block(data: bytes, compression: CompressionType, unpacked_size: int) -> bytes:
    if compression == CompressionType.NONE:
        unpacked = data
    elif compression == CompressionType.LZ4:
        if lz4block is None:
            raise RuntimeError("this rbk2 uses lz4; install python-lz4 or rebuild with --compression zlib/none")
        unpacked = lz4block.decompress(data, uncompressed_size=unpacked_size)
    elif compression == CompressionType.HEATSHRINK:
        if heatshrink2 is None:
            raise RuntimeError("this rbk2 uses heatshrink; install heatshrink2 or rebuild with --compression zlib/none")
        unpacked = heatshrink2.decompress(data)
    elif compression == CompressionType.ZLIB:
        unpacked = zlib.decompress(data)
    else:
        raise ValueError(f"unsupported block compression: {compression}")

    if len(unpacked) != unpacked_size:
        raise ValueError(f"decompressed size mismatch: expected {unpacked_size}, got {len(unpacked)}")
    return unpacked


def read_rbk2(path: Path) -> RbkBook:
    data = path.read_bytes()
    header = RbkHeader.unpack(data)
    header.validate(len(data))
    chunks = _chunk_map(data, header)

    required = {ChunkKind.META, ChunkKind.STRS, ChunkKind.CHAP, ChunkKind.PAGE, ChunkKind.BLKI, ChunkKind.TEXT}
    missing = required - set(chunks)
    if missing:
        names = ", ".join(kind.decode("ascii") for kind in sorted(missing))
        raise ValueError(f"missing required chunks: {names}")

    strings = _read_string_table(chunks[ChunkKind.STRS])

    meta_header = RbkMetaChunkHeader.unpack(chunks[ChunkKind.META])
    meta_header.validate(len(chunks[ChunkKind.META]))
    meta_entries = _parse_fixed_entries(
        chunks[ChunkKind.META],
        RbkMetaChunkHeader.SIZE,
        meta_header.entry_size,
        meta_header.entry_count,
        RbkMetaEntry,
    )
    metadata: dict[str, str] = {}
    for entry in meta_entries:
        if entry.key_string >= len(strings) or entry.value_string >= len(strings):
            raise ValueError("META string index out of range")
        metadata[strings[entry.key_string]] = strings[entry.value_string]

    chap_header = RbkChapterChunkHeader.unpack(chunks[ChunkKind.CHAP])
    chap_header.validate(len(chunks[ChunkKind.CHAP]))
    if chap_header.chapter_count != header.chapter_count:
        raise ValueError("chapter count mismatch")
    chapters = _parse_fixed_entries(
        chunks[ChunkKind.CHAP],
        RbkChapterChunkHeader.SIZE,
        chap_header.entry_size,
        chap_header.chapter_count,
        RbkChapterEntry,
    )
    chapter_titles: list[str] = []
    for i, chapter in enumerate(chapters):
        if chapter.title_string >= len(strings):
            raise ValueError("CHAP title string index out of range")
        if chapter.page_count == 0:
            raise ValueError(f"chapter {i} has no pages")
        if chapter.first_page + chapter.page_count > header.page_count:
            raise ValueError(f"chapter {i} page range exceeds PAGE table")
        chapter_titles.append(strings[chapter.title_string])

    page_header = RbkPageChunkHeader.unpack(chunks[ChunkKind.PAGE])
    page_header.validate(len(chunks[ChunkKind.PAGE]))
    if page_header.page_count != header.page_count:
        raise ValueError("page count mismatch")
    page_entries = _parse_fixed_entries(
        chunks[ChunkKind.PAGE],
        RbkPageChunkHeader.SIZE,
        page_header.entry_size,
        page_header.page_count,
        RbkPageEntry,
    )

    block_header = RbkBlockIndexChunkHeader.unpack(chunks[ChunkKind.BLKI])
    block_header.validate(len(chunks[ChunkKind.BLKI]))
    block_entries = _parse_fixed_entries(
        chunks[ChunkKind.BLKI],
        RbkBlockIndexChunkHeader.SIZE,
        block_header.entry_size,
        block_header.block_count,
        RbkBlockEntry,
    )

    text_header = RbkTextChunkHeader.unpack(chunks[ChunkKind.TEXT])
    text_header.validate(len(chunks[ChunkKind.TEXT]))
    if text_header.block_count != block_header.block_count:
        raise ValueError("TEXT/BLKI block count mismatch")
    text_data = chunks[ChunkKind.TEXT][text_header.data_offset : text_header.data_offset + text_header.packed_data_size]

    unpacked_blocks: list[bytes] = []
    expected_text_offset = 0
    for i, block in enumerate(block_entries):
        block.validate(len(text_data))
        if block.packed_offset != expected_text_offset:
            raise ValueError(f"block {i} packed offset is not contiguous")
        packed = text_data[block.packed_offset : block.packed_offset + block.packed_size]
        unpacked = _decompress_block(packed, CompressionType(block.compression), block.unpacked_size)
        if _crc32c(unpacked) != block.crc32c:
            raise ValueError(f"invalid CRC32C for text block {i}")
        unpacked_blocks.append(unpacked)
        expected_text_offset += block.packed_size
    if expected_text_offset != len(text_data):
        raise ValueError("TEXT packed data contains unused trailing bytes")
    if sum(len(block) for block in unpacked_blocks) != text_header.unpacked_total_size:
        raise ValueError("TEXT unpacked total size mismatch")

    for block_index, block in enumerate(block_entries):
        if block.first_page + block.page_count > len(page_entries):
            raise ValueError(f"block {block_index} page range exceeds PAGE table")
        for page_index in range(block.first_page, block.first_page + block.page_count):
            if page_entries[page_index].block_index != block_index:
                raise ValueError(f"page {page_index} is not assigned to block {block_index}")

    pages: list[str] = []
    for i, page in enumerate(page_entries):
        if page.chapter_index >= len(chapters):
            raise ValueError(f"page {i} chapter index out of range")
        if page.block_index >= len(unpacked_blocks):
            raise ValueError(f"page {i} block index out of range")
        block = unpacked_blocks[page.block_index]
        if page.unpacked_length == 0:
            raise ValueError(f"page {i} has zero length")
        if page.unpacked_offset + page.unpacked_length > len(block):
            raise ValueError(f"page {i} exceeds text block")
        pages.append(block[page.unpacked_offset : page.unpacked_offset + page.unpacked_length].decode("utf-8"))

    return RbkBook(
        header=header,
        metadata=metadata,
        chapters=chapters,
        chapter_titles=chapter_titles,
        pages=pages,
        page_entries=page_entries,
    )


class PageRasterizer:
    def __init__(
        self,
        font: BdfFont,
        width_px: int,
        height_px: int,
        cell_width: int,
        cell_height: int,
        fg: str,
        bg: str,
        scale: int,
    ) -> None:
        self.font = font
        self.width_px = width_px
        self.height_px = height_px
        self.cell_width = cell_width
        self.cell_height = cell_height
        self.fg = fg
        self.bg = bg
        self.scale = scale

    def rasterize(self, text: str):
        # tkinter is imported lazily so --dump-text still works on headless systems.
        import tkinter as tk  # noqa: F401

        img = tk.PhotoImage(width=self.width_px, height=self.height_px)
        img.put(self.bg, to=(0, 0, self.width_px, self.height_px))

        lines = text.rstrip("\n").split("\n")
        for row, line in enumerate(lines):
            y = row * self.cell_height
            if y >= self.height_px:
                break
            for col, ch in enumerate(line):
                x = col * self.cell_width
                if x >= self.width_px:
                    break
                self._draw_glyph(img, x, y, ch)

        if self.scale > 1:
            return img.zoom(self.scale, self.scale)
        return img

    def _draw_glyph(self, img, x: int, y: int, ch: str) -> None:
        glyph = self.font.glyph_for(ch)
        draw_x0 = x + glyph.xoff
        draw_y0 = y + (self.font.ascent - glyph.yoff - glyph.bbx_height)

        for gy, (row_bits, bit_count) in enumerate(glyph.bitmap_rows):
            py = draw_y0 + gy
            if py < 0 or py >= self.height_px:
                continue
            run_start: int | None = None
            for gx in range(glyph.bbx_width):
                px = draw_x0 + gx
                bit = (row_bits >> (bit_count - 1 - gx)) & 1 if bit_count > gx else 0
                in_bounds = 0 <= px < self.width_px
                if bit and in_bounds and run_start is None:
                    run_start = px
                elif (not bit or not in_bounds) and run_start is not None:
                    img.put(self.fg, to=(run_start, py, px, py + 1))
                    run_start = None
            if run_start is not None:
                img.put(self.fg, to=(run_start, py, min(draw_x0 + glyph.bbx_width, self.width_px), py + 1))


class ReaderApp:
    def __init__(self, book: RbkBook, font: BdfFont, args: argparse.Namespace, state: RbsState, state_path: Path | None) -> None:
        import tkinter as tk

        self.tk = tk
        self.book = book
        self.state = state
        self.state_path = state_path
        self._closed = False
        self._session_start_timestamp = int(time.time())
        self._session_start_monotonic = time.monotonic()
        self._last_stats_monotonic = self._session_start_monotonic
        self._pending_stats_seconds = 0.0
        self._last_page_change_monotonic = self._session_start_monotonic
        self._session_start_page = 0
        self._session_pages_moved = 0
        self._completion_counted_this_session = False

        if args.start_page is not None:
            initial_page = args.start_page - 1
        elif state_path is not None:
            initial_page = state.progress.current_page
        else:
            initial_page = 0
        self.page_index = max(0, min(initial_page, len(book.pages) - 1))
        self._session_start_page = self.page_index

        self.root = tk.Tk()
        self.root.title(book.metadata.get("title") or "rbk2 reader")

        cell_width = args.cell_width or book.header.font_width_px or font.bbox_width
        cell_height = args.cell_height or book.header.font_height_px or font.bbox_height
        width_px = args.width or book.header.screen_width_px or book.header.chars_per_line * cell_width
        height_px = args.height or book.header.screen_height_px or book.header.lines_per_page * cell_height

        self.rasterizer = PageRasterizer(
            font=font,
            width_px=width_px,
            height_px=height_px,
            cell_width=cell_width,
            cell_height=cell_height,
            fg=args.fg,
            bg=args.bg,
            scale=args.scale,
        )
        self.canvas = tk.Canvas(
            self.root,
            width=width_px * args.scale,
            height=height_px * args.scale,
            highlightthickness=0,
            bg=args.bg,
        )
        self.canvas.pack()
        self.status = tk.Label(self.root, anchor="w", justify="left")
        self.status.pack(fill="x")
        self.image = None

        for key in ("<Right>", "<space>", "<Next>", "l", "n"):
            self.root.bind(key, lambda _e: self.goto_page(self.page_index + 1))
        for key in ("<Left>", "<BackSpace>", "<Prior>", "h", "p"):
            self.root.bind(key, lambda _e: self.goto_page(self.page_index - 1))
        self.root.bind("<Home>", lambda _e: self.goto_page(0))
        self.root.bind("<End>", lambda _e: self.goto_page(len(self.book.pages) - 1))
        self.root.bind("]", lambda _e: self.goto_chapter(+1))
        self.root.bind("[", lambda _e: self.goto_chapter(-1))
        self.root.bind("b", lambda _e: self.add_bookmark(""))
        self.root.bind("m", lambda _e: self.prompt_bookmark())
        self.root.bind("o", lambda _e: self.open_bookmark_list())
        self.root.bind("x", lambda _e: self.remove_bookmark_current_page())
        self.root.bind("s", lambda _e: self.save_state())
        self.root.bind("q", lambda _e: self.close())
        self.root.bind("<Escape>", lambda _e: self.close())
        self.root.protocol("WM_DELETE_WINDOW", self.close)

        self.update_progress_only()
        self.render()
        self.save_state()

    def chapter_for_page(self, page_index: int) -> int:
        entry = self.book.page_entries[page_index]
        return entry.chapter_index

    def bookmark_for_page(self, page_index: int) -> RbsBookmarkEntry | None:
        for bookmark in self.state.bookmarks:
            if bookmark.page_index == page_index and bookmark.flags & BOOKMARK_FLAG_BOOKMARK:
                return bookmark
        return None

    def goto_page(self, page_index: int) -> None:
        page_index = max(0, min(page_index, len(self.book.pages) - 1))
        if page_index != self.page_index:
            self.record_page_move(page_index)
            self.page_index = page_index
            if self.page_index == len(self.book.pages) - 1 and not self._completion_counted_this_session:
                self.state.stats.completion_count += 1
                self._completion_counted_this_session = True
            self.render()
            self.save_state()

    def goto_chapter(self, delta: int) -> None:
        current_chapter = self.chapter_for_page(self.page_index)
        target = max(0, min(current_chapter + delta, len(self.book.chapters) - 1))
        self.goto_page(self.book.chapters[target].first_page)

    def record_page_move(self, new_page_index: int) -> None:
        now = time.monotonic()
        moved = abs(new_page_index - self.page_index)
        if moved:
            self.state.stats.total_pages_flipped += moved
            self._session_pages_moved += moved
            if now - self._last_page_change_monotonic < 1.0:
                self.state.stats.fast_page_skips += moved
        self._last_page_change_monotonic = now
        self._accumulate_reading_seconds(now)

    def _accumulate_reading_seconds(self, now: float | None = None) -> None:
        now = time.monotonic() if now is None else now
        if now < self._last_stats_monotonic:
            self._last_stats_monotonic = now
            return
        self._pending_stats_seconds += now - self._last_stats_monotonic
        whole_seconds = int(self._pending_stats_seconds)
        if whole_seconds > 0:
            self.state.stats.total_reading_seconds += whole_seconds
            self._pending_stats_seconds -= whole_seconds
        self._last_stats_monotonic = now

    def update_progress_only(self) -> None:
        chapter_index = self.chapter_for_page(self.page_index)
        page_entry = self.book.page_entries[self.page_index]
        page_count = max(1, len(self.book.pages))
        self.state.progress.current_page = self.page_index
        self.state.progress.current_chapter = chapter_index
        self.state.progress.current_block = page_entry.block_index
        self.state.progress.last_read_timestamp = int(time.time())
        self.state.progress.percent_completed_bp = min(10000, max(0, int(((self.page_index + 1) * 10000) / page_count)))

    def finalize_stats_for_save(self) -> None:
        self._accumulate_reading_seconds()
        stats = self.state.stats
        if stats.total_pages_flipped:
            stats.average_seconds_per_page = int(stats.total_reading_seconds / stats.total_pages_flipped)
        else:
            stats.average_seconds_per_page = 0
        stats.time_of_day_preference = _time_of_day_bucket()
        duration = int(time.monotonic() - self._session_start_monotonic)
        stats.longest_session_seconds = max(stats.longest_session_seconds, duration)

    def save_state(self) -> None:
        if self.state_path is None:
            return
        self.update_progress_only()
        self.finalize_stats_for_save()
        try:
            write_rbs2_state(self.state_path, self.book.header.book_id, self.state)
        except Exception as e:
            print(f"warning: could not save RBS2 state: {e}", file=sys.stderr)

    def add_bookmark(self, label: str) -> None:
        now = int(time.time())
        chapter_index = self.chapter_for_page(self.page_index)
        label_bytes = _rbs_label_bytes(label)
        for i, bookmark in enumerate(self.state.bookmarks):
            if (
                bookmark.page_index == self.page_index
                and bookmark.text_offset == 0
                and bookmark.text_length == 0
                and bookmark.flags & BOOKMARK_FLAG_BOOKMARK
            ):
                self.state.bookmarks[i] = RbsBookmarkEntry(
                    page_index=self.page_index,
                    chapter_index=chapter_index,
                    text_offset=0,
                    text_length=0,
                    timestamp=now,
                    flags=BOOKMARK_FLAG_BOOKMARK,
                    label=label_bytes,
                )
                self.render()
                self.save_state()
                return

        self.state.bookmarks.append(
            RbsBookmarkEntry(
                page_index=self.page_index,
                chapter_index=chapter_index,
                text_offset=0,
                text_length=0,
                timestamp=now,
                flags=BOOKMARK_FLAG_BOOKMARK,
                label=label_bytes,
            )
        )
        self.render()
        self.save_state()

    def prompt_bookmark(self) -> None:
        from tkinter import simpledialog

        label = simpledialog.askstring("bookmark", "bookmark label:", parent=self.root)
        if label is not None:
            self.add_bookmark(label)

    def remove_bookmark_current_page(self) -> None:
        before = len(self.state.bookmarks)
        self.state.bookmarks = [
            bookmark
            for bookmark in self.state.bookmarks
            if not (
                bookmark.page_index == self.page_index
                and bookmark.text_offset == 0
                and bookmark.text_length == 0
                and bookmark.flags & BOOKMARK_FLAG_BOOKMARK
            )
        ]
        if len(self.state.bookmarks) != before:
            self.render()
            self.save_state()

    def open_bookmark_list(self) -> None:
        top = self.tk.Toplevel(self.root)
        top.title("bookmarks")
        listbox = self.tk.Listbox(top, width=80, height=min(20, max(5, len(self.state.bookmarks))))
        listbox.pack(fill="both", expand=True)

        sorted_bookmarks = sorted(self.state.bookmarks, key=lambda b: (b.page_index, b.timestamp))
        for bookmark in sorted_bookmarks:
            chapter = self.book.chapter_titles[bookmark.chapter_index] if bookmark.chapter_index < len(self.book.chapter_titles) else ""
            label = bookmark.label_text()
            suffix = f" — {label}" if label else ""
            listbox.insert("end", f"page {bookmark.page_index + 1}: {chapter}{suffix}")

        def open_selected(_event=None) -> None:
            selection = listbox.curselection()
            if not selection:
                return
            self.goto_page(sorted_bookmarks[selection[0]].page_index)
            top.destroy()

        listbox.bind("<Double-Button-1>", open_selected)
        listbox.bind("<Return>", open_selected)
        if sorted_bookmarks:
            listbox.focus_set()
            listbox.selection_set(0)

    def render(self) -> None:
        self.image = self.rasterizer.rasterize(self.book.pages[self.page_index])
        self.canvas.delete("all")
        self.canvas.create_image(0, 0, anchor="nw", image=self.image)

        chapter_index = self.chapter_for_page(self.page_index)
        chapter = self.book.chapter_titles[chapter_index] if chapter_index < len(self.book.chapter_titles) else ""
        title = self.book.metadata.get("title") or "untitled"
        author = self.book.metadata.get("author") or "unknown"
        bookmark = self.bookmark_for_page(self.page_index)
        bookmark_text = " | bookmarked" if bookmark is not None else ""
        state_text = f" | state: {self.state_path.name}" if self.state_path is not None else " | state off"
        self.status.config(
            text=(
                f"{title} — {author} | "
                f"page {self.page_index + 1}/{len(self.book.pages)} | "
                f"chapter {chapter_index + 1}/{len(self.book.chapters)}: {chapter}"
                f"{bookmark_text}{state_text} | "
                f"read {_format_duration(self.state.stats.total_reading_seconds)}, "
                f"flips {self.state.stats.total_pages_flipped} | "
                "←/→ page, [/ ] chapter, b bookmark, m named, o list, x remove, s save, q quit"
            )
        )

    def close(self) -> None:
        if self._closed:
            return
        self._closed = True
        if self.state_path is not None:
            duration = max(0, int(time.monotonic() - self._session_start_monotonic))
            self.state.sessions.append(
                RbsSessionEntry(
                    start_timestamp=self._session_start_timestamp,
                    duration_seconds=duration,
                    pages_read_count=self._session_pages_moved,
                    starting_page_index=self._session_start_page,
                    flags=0,
                )
            )
            self.save_state()
        self.root.destroy()

    def run(self) -> None:
        self.root.mainloop()


def dump_text(book: RbkBook, out: Path | None) -> None:
    parts: list[str] = []
    last_chapter = -1
    for i, page in enumerate(book.pages):
        chapter = book.page_entries[i].chapter_index
        if chapter != last_chapter:
            title = book.chapter_titles[chapter] if chapter < len(book.chapter_titles) else f"chapter {chapter + 1}"
            parts.append(f"\n\n# {title}\n")
            last_chapter = chapter
        parts.append(page.rstrip("\n"))
        parts.append("\n\n--- page break ---\n")
    text = "".join(parts).lstrip()
    if out is None:
        sys.stdout.write(text)
    else:
        out.write_text(text, encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="render/read an RBK2 file with spleen-6x12.bdf")
    parser.add_argument("rbk2", type=Path, help="input .rbk2 file")
    parser.add_argument("--font", type=Path, default=Path("spleen-6x12.bdf"), help="BDF font path; default: ./spleen-6x12.bdf")
    parser.add_argument("--scale", type=int, default=3, help="integer display scale for the tiny screen")
    parser.add_argument("--start-page", type=int, help="1-based page number to open; overrides saved RBS2 progress")
    parser.add_argument("--state", type=Path, help="RBS2 state file path; default: input file with .rbs2 suffix")
    parser.add_argument("--no-state", action="store_true", help="disable RBS2 progress/stat/bookmark persistence")
    parser.add_argument("--reset-state", action="store_true", help="ignore any existing RBS2 file and start fresh")
    parser.add_argument("--dump-state", action="store_true", help="print saved RBS2 progress/stats/bookmarks and exit")
    parser.add_argument("--fg", default="#000000", help="foreground color")
    parser.add_argument("--bg", default="#f6f3e8", help="background color")
    parser.add_argument("--width", type=int, help="override rendered screen width in pixels")
    parser.add_argument("--height", type=int, help="override rendered screen height in pixels")
    parser.add_argument("--cell-width", type=int, help="override font cell width in pixels")
    parser.add_argument("--cell-height", type=int, help="override font cell height in pixels")
    parser.add_argument("--dump-text", nargs="?", const="-", help="dump decoded text instead of opening the reader; optional output path")
    args = parser.parse_args(argv)

    try:
        if args.scale < 1:
            raise ValueError("--scale must be >= 1")
        if args.start_page is not None and args.start_page < 1:
            raise ValueError("--start-page must be >= 1")

        book = read_rbk2(args.rbk2)
        state_path = None if args.no_state else (args.state or default_rbs2_path(args.rbk2))

        if args.dump_text is not None:
            dump_text(book, None if args.dump_text == "-" else Path(args.dump_text))
            return 0

        if args.dump_state:
            if state_path is None:
                raise ValueError("--dump-state needs state enabled")
            dump_state(book, state_path)
            return 0

        if state_path is None or args.reset_state:
            state = RbsState.fresh()
        else:
            try:
                state = read_rbs2_state(state_path, book.header.book_id, page_count=len(book.pages))
            except Exception as e:
                print(f"warning: ignoring unreadable RBS2 state {state_path}: {e}", file=sys.stderr)
                state = RbsState.fresh()

        font = BdfFont.load(args.font)
        if (font.bbox_width, font.bbox_height) != (6, 12):
            print(
                f"warning: font bounding box is {font.bbox_width}x{font.bbox_height}, not 6x12",
                file=sys.stderr,
            )
        app = ReaderApp(book, font, args, state, state_path)
        app.run()
        return 0
    except Exception as e:
        print(f"error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
