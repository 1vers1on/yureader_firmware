from __future__ import annotations

import struct
import zlib
from dataclasses import dataclass
from typing import ClassVar
from enum import IntEnum
import google_crc32c

def _crc32c(data: bytes) -> int:
    return google_crc32c.value(data)

RBS_MAGIC = b"RBS2"

class StateChunkKind:
    PROG = b"PROG"  # Current reading progress (Overwritten on save)
    STAT = b"STAT"  # Advanced statistics (Overwritten/Updated)
    BMKS = b"BMKS"  # Bookmarks & Highlights (Appendable table)
    SESS = b"SESS"  # Reading sessions log (Appendable table)

def fourcc(s: str) -> bytes:
    b = s.encode("ascii")
    if len(b) != 4:
        raise ValueError("fourcc must be exactly 4 ascii characters")
    return b

@dataclass(slots=True)
class RbsHeader:
    # magic(4), v_maj(2), v_min(2), hdr_size(2), chunk_entry_size(2)
    # flags(4), book_id(16), file_size(8), chunk_table_offset(8)
    # chunk_count(4), crc32c(4), reserved1(4), reserved2(48)
    FORMAT: ClassVar[str] = "<4sHHHHI16sQQIII48s"
    SIZE: ClassVar[int] = struct.calcsize(FORMAT)

    magic: bytes = RBS_MAGIC

    version_major: int = 1
    version_minor: int = 0

    header_size: int = 0
    chunk_entry_size: int = 0
    flags: int = 0

    # Links this state file to the specific rbk2 book
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
            raise ValueError("book_id must be 16 bytes")
        if len(self.reserved2) != 48:
            raise ValueError("reserved2 must be 48 bytes")
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
            raise ValueError("not enough bytes for RbsHeader")
        return cls(*struct.unpack(cls.FORMAT, data[:cls.SIZE]))

    def validate(self) -> None:
        if self.magic != RBS_MAGIC:
            raise ValueError("invalid magic")
        if self.version_major != 1:
            raise ValueError("unsupported major version")
        if self.chunk_entry_size != RbsChunkEntry.SIZE:
            raise ValueError("invalid chunk entry size")
        if self.compute_crc32c() != self.header_crc32c:
            raise ValueError("invalid header CRC32C")

@dataclass(slots=True)
class RbsChunkEntry:
    # kind(4), flags(4), offset(8), size(8), crc32c(4), reserved(12)
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
            raise ValueError("chunk kind must be 4 bytes")
        if len(self.reserved) != 12:
            raise ValueError("reserved must be 12 bytes")
        return struct.pack(
            self.FORMAT,
            self.kind,
            self.flags,
            self.offset,
            self.size,
            self.crc32c,
            self.reserved,
        )

    @classmethod
    def unpack(cls, data: bytes) -> "RbsChunkEntry":
        if len(data) < cls.SIZE:
            raise ValueError("not enough bytes for RbsChunkEntry")
        return cls(*struct.unpack(cls.FORMAT, data[:cls.SIZE]))

    def validate(self, file_size: int) -> None:
        if self.size == 0:
            raise ValueError("chunk size must be greater than 0")
        if self.offset > file_size or self.offset + self.size > file_size:
            raise ValueError("chunk data exceeds file size")

# ---------------------------------------------------------
# PROG: Reading Progress
# ---------------------------------------------------------

@dataclass(slots=True)
class RbsProgressChunk:
    """Stores where the user last left off."""
    # magic(4), current_page(4), current_chapter(4), current_block(4), 
    # last_read_timestamp(8), percent_completed_bp(4), flags(4), reserved(16)
    FORMAT: ClassVar[str] = "<4sIIIQII16s"
    SIZE: ClassVar[int] = struct.calcsize(FORMAT)

    magic: bytes = StateChunkKind.PROG
    current_page: int = 0
    current_chapter: int = 0
    current_block: int = 0
    
    last_read_timestamp: int = 0 # UNIX epoch
    percent_completed_bp: int = 0 # Basis points (0-10000) for UI progress bars
    
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
            raise ValueError("not enough bytes for RbsProgressChunk")
        return cls(*struct.unpack(cls.FORMAT, data[:cls.SIZE]))

# ---------------------------------------------------------
# STAT: Advanced Reading Statistics
# ---------------------------------------------------------

@dataclass(slots=True)
class RbsStatsChunk:
    """Global statistics tracking for this specific book."""
    # magic(4), total_seconds(8), total_pages(8), longest_session(4),
    # avg_sec_per_page(4), fast_skips(4), completions(4), time_of_day_pref(4), reserved(16)
    FORMAT: ClassVar[str] = "<4sQQIIIII16s"
    SIZE: ClassVar[int] = struct.calcsize(FORMAT)

    magic: bytes = StateChunkKind.STAT
    
    total_reading_seconds: int = 0
    total_pages_flipped: int = 0
    
    longest_session_seconds: int = 0
    average_seconds_per_page: int = 0
    
    fast_page_skips: int = 0 # Track how many times they flipped < 1s (skimming)
    completion_count: int = 0 # How many times they finished the book entirely
    time_of_day_preference: int = 0 # 0=Morning, 1=Afternoon, 2=Evening, 3=Night
    
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
            raise ValueError("not enough bytes for RbsStatsChunk")
        return cls(*struct.unpack(cls.FORMAT, data[:cls.SIZE]))

# ---------------------------------------------------------
# BMKS: Bookmarks & Highlights (Table)
# ---------------------------------------------------------

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
        return struct.pack(
            self.FORMAT,
            self.magic,
            self.entry_count,
            self.entry_size,
            self.reserved,
        )

    @classmethod
    def unpack(cls, data: bytes) -> "RbsBookmarkChunkHeader":
        return cls(*struct.unpack(cls.FORMAT, data[:cls.SIZE]))

@dataclass(slots=True)
class RbsBookmarkEntry:
    # page_idx(4), chapter_idx(4), offset_in_page(4), length(4),
    # timestamp(8), flags(4), label(64s)
    FORMAT: ClassVar[str] = "<IIIIQI64s"
    SIZE: ClassVar[int] = struct.calcsize(FORMAT)

    page_index: int
    chapter_index: int
    
    # Optional offsets for specific text highlights. 0 if just a standard page bookmark.
    text_offset: int 
    text_length: int
    
    timestamp: int # UNIX epoch
    flags: int # e.g. 1=Bookmark, 2=Highlight
    
    label: bytes = b"\x00" * 64 # Inline fixed-length string for user notes

    def pack(self) -> bytes:
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
        return cls(*struct.unpack(cls.FORMAT, data[:cls.SIZE]))

# ---------------------------------------------------------
# SESS: Session Logs (Table)
# ---------------------------------------------------------

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
        return cls(*struct.unpack(cls.FORMAT, data[:cls.SIZE]))

@dataclass(slots=True)
class RbsSessionEntry:
    # Log individual reading sessions to generate heatmaps or charts
    # start_ts(8), duration_sec(4), pages_read(4), starting_page(4), flags(4)
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
        return cls(*struct.unpack(cls.FORMAT, data[:cls.SIZE]))
