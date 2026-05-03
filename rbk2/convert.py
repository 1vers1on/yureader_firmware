from __future__ import annotations

from dataclasses import dataclass
from enum import IntEnum
from pathlib import Path
import hashlib
import os
import struct
import time
from typing import ClassVar
import textwrap
import argparse
import re
import sys

try:
    import google_crc32c  # type: ignore[import-not-found]
except ImportError:  # pragma: no cover - depends on local environment
    google_crc32c = None

try:
    import lz4.block as lz4block  # type: ignore[import-not-found]
except ImportError:  # pragma: no cover - depends on local environment
    lz4block = None

import zlib

try:
    import heatshrink2  # type: ignore[import-not-found]
except ImportError:  # pragma: no cover - depends on local environment
    heatshrink2 = None

import zipfile
import xml.etree.ElementTree as ET

import posixpath
from urllib.parse import unquote, urlsplit

from bs4 import BeautifulSoup

RBK_MAGIC = b"RBK2"
RBS_SLOT_MAGIC = b"RSS1"

CONTAINER_NS = "urn:oasis:names:tc:opendocument:xmlns:container"
OPF_NS = "http://www.idpf.org/2007/opf"
DC_NS = "http://purl.org/dc/elements/1.1/"

CONTENT_MEDIA_TYPES = {
    "application/xhtml+xml",
    "text/html",
    "application/x-dtbook+xml",
    "application/xml",
    "text/xml",
}

CONTENT_SUFFIXES = {
    ".xhtml",
    ".html",
    ".htm",
    ".xml",
}

_XML_ENCODING_RE = re.compile(
    br"""<\?xml[^>]*encoding\s*=\s*["']([^"']+)["']""",
    re.IGNORECASE,
)
_HTML_CHARSET_RE = re.compile(
    br"""<meta[^>]+charset\s*=\s*["']?([^\s"'/>;]+)""",
    re.IGNORECASE,
)

_TEXT_PARAGRAPH_BREAK = "\uE000"
_TEXT_LINE_BREAK = "\uE001"

_BLOCK_TAGS = {
    "address", "article", "aside", "blockquote", "dd", "details", "dialog",
    "div", "dl", "dt", "figcaption", "figure", "footer", "form",
    "h1", "h2", "h3", "h4", "h5", "h6",
    "header", "hr", "li", "main", "nav", "ol", "p", "pre",
    "section", "summary", "table", "tbody", "td", "tfoot", "th",
    "thead", "tr", "ul",
}

_STRIP_TRANSLATION = {
    ord("\xa0"): " ",      # non-breaking space
    ord("\u202f"): " ",    # narrow non-breaking space
    ord("\u2007"): " ",    # figure space
    ord("\u00ad"): "",     # soft hyphen
    ord("\u200b"): "",     # zero-width space
    ord("\u200c"): "",     # zero-width non-joiner
    ord("\u200d"): "",     # zero-width joiner
    ord("\ufeff"): "",     # bom / zero-width no-break
}


def _crc32c_sw(data: bytes) -> int:
    """Small pure-python Castagnoli CRC32C fallback.

    google-crc32c is preferred when installed, but this keeps the converter
    usable on clean systems and in CI without native wheels.
    """

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


class _GoogleCrc32cCompat:
    @staticmethod
    def value(data: bytes) -> int:
        return _crc32c_sw(data)


if google_crc32c is None:
    google_crc32c = _GoogleCrc32cCompat()


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
    META = b"META"  # metadata entries
    STRS = b"STRS"  # null-terminated utf-8 string table
    CHAP = b"CHAP"  # chapter table
    PAGE = b"PAGE"  # page table
    BLKI = b"BLKI"  # compressed text block index
    TEXT = b"TEXT"  # compressed text blocks concatenated together

def fourcc(s: str) -> bytes:
    b = s.encode("ascii")
    if len(b) != 4:
        raise ValueError("fourcc must be exactly 4 ascii characters")
    return b

@dataclass(slots=True)
class RbkHeader:
    FORMAT: ClassVar[str] = "<4sHHHHIQQIIIIHHHHHH16sII48s"
    SIZE: ClassVar[int] = struct.calcsize(FORMAT)

    magic: bytes = RBK_MAGIC

    version_major: int = 1
    version_minor: int = 0

    header_size: int = 0

    chunk_entry_size: int = 0

    flags: int = 0

    file_size: int = 0
    chunk_table_offset: int = 0

    chunk_count: int = 0
    page_count: int = 0
    chapter_count: int = 0
    reserved1: int = 0

    screen_width_px: int = 0
    screen_height_px: int = 0
    font_width_px: int = 0
    font_height_px: int = 0
    chars_per_line: int = 0
    lines_per_page: int = 0

    book_id: bytes = b"\x00" * 16

    directory_crc32c: int = 0
    header_crc32c: int = 0

    reserved2: bytes = b"\x00" * 48

    def normalized(self) -> "RbkHeader":
        self.header_size = self.SIZE
        self.chunk_entry_size = RbkChunkEntry.SIZE
        if self.chunk_table_offset == 0:
            self.chunk_table_offset = self.SIZE
        if len(self.book_id) != 16:
            raise ValueError("book_id must be 16 bytes")
        if len(self.reserved2) != 48:
            raise ValueError("reserved must be 48 bytes")
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
            header_crc,
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

    def stored_bytes_for_crc(self) -> bytes:
        """Return CRC input using exactly the fields read from disk."""
        return self._pack_unchecked(crc_field=0)

    def compute_stored_crc32c(self) -> int:
        return _crc32c(self.stored_bytes_for_crc())

    @classmethod
    def unpack(cls, data: bytes) -> "RbkHeader":
        if len(data) < cls.SIZE:
            raise ValueError("not enough bytes for RbkHeader")
        return cls(*struct.unpack(cls.FORMAT, data[:cls.SIZE]))

    def validate(self) -> None:
        if self.magic != RBK_MAGIC:
            raise ValueError("invalid magic")
        if self.version_major != 1:
            raise ValueError("unsupported major version")
        if self.version_minor != 0:
            raise ValueError("unsupported minor version")
        if self.header_size != self.SIZE:
            raise ValueError("invalid header size")
        if self.chunk_entry_size != RbkChunkEntry.SIZE:
            raise ValueError("invalid chunk entry size")
        if self.chunk_table_offset < self.header_size:
            raise ValueError("chunk table offset must be at least header size")
        if self.chunk_count == 0:
            raise ValueError("chunk count must be greater than 0")
        if self.file_size < self.header_size:
            raise ValueError("file size must be at least header size")
        if len(self.book_id) != 16:
            raise ValueError("book_id must be 16 bytes")
        if len(self.reserved2) != 48:
            raise ValueError("reserved must be 48 bytes")
        if self.screen_width_px == 0:
            raise ValueError("screen width must be greater than 0")
        if self.screen_height_px == 0:
            raise ValueError("screen height must be greater than 0")
        if self.font_width_px == 0:
            raise ValueError("font width must be greater than 0")
        if self.font_height_px == 0:
            raise ValueError("font height must be greater than 0")
        if self.chars_per_line == 0:
            raise ValueError("chars per line must be greater than 0")
        if self.lines_per_page == 0:
            raise ValueError("lines per page must be greater than 0")
        if self.compute_stored_crc32c() != self.header_crc32c:
            raise ValueError("invalid header CRC32C")

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
    reserved2: bytes = b"\x00" * 16

    def pack(self) -> bytes:
        if len(self.kind) != 4:
            raise ValueError("chunk kind must be 4 bytes")
        return struct.pack(
            self.FORMAT,
            self.kind,
            self.flags,
            self.compression,
            self.reserved1,
            self.offset,
            self.packed_size,
            self.unpacked_size,
            self.crc32c,
            self.reserved2,
        )

    @classmethod
    def unpack(cls, data: bytes) -> "RbkChunkEntry":
        if len(data) < cls.SIZE:
            raise ValueError("not enough bytes for RbkChunkEntry")
        return cls(*struct.unpack(cls.FORMAT, data[:cls.SIZE]))

    def validate(self, file_size: int) -> None:
        try:
            compression = CompressionType(self.compression)
        except ValueError as e:
            raise ValueError("invalid compression type") from e
        if self.packed_size == 0:
            raise ValueError("packed size must be greater than 0")
        if self.unpacked_size == 0:
            raise ValueError("unpacked size must be greater than 0")
        if compression == CompressionType.NONE and self.packed_size != self.unpacked_size:
            raise ValueError("packed size must equal unpacked size for uncompressed chunk")
        if self.offset > file_size or self.offset + self.packed_size > file_size:
            raise ValueError("chunk data exceeds file size")

@dataclass(slots=True)
class RbkMetaChunkHeader:
    FORMAT: ClassVar[str] = "<4sII16s"
    SIZE: ClassVar[int] = struct.calcsize(FORMAT)

    magic: bytes = ChunkKind.META
    entry_count: int = 0
    entry_size: int = 0
    reserved: bytes = b"\x00" * 16

    def pack(self) -> bytes:
        if len(self.reserved) != 16:
            raise ValueError("reserved must be 16 bytes")
        self.magic = ChunkKind.META
        self.entry_size = RbkMetaEntry.SIZE
        return struct.pack(
            self.FORMAT,
            self.magic,
            self.entry_count,
            self.entry_size,
            self.reserved,
        )

    @classmethod
    def unpack(cls, data: bytes) -> "RbkMetaChunkHeader":
        if len(data) < cls.SIZE:
            raise ValueError("not enough bytes for RbkMetaChunkHeader")
        return cls(*struct.unpack(cls.FORMAT, data[:cls.SIZE]))

    def validate(self, chunk_size: int) -> None:
        if self.magic != ChunkKind.META:
            raise ValueError("invalid META chunk magic")
        if self.entry_size != RbkMetaEntry.SIZE:
            raise ValueError("invalid META entry size")
        if self.SIZE + self.entry_count * self.entry_size > chunk_size:
            raise ValueError("META entries exceed chunk size")

@dataclass(slots=True)
class RbkMetaEntry:
    """
    metadata key/value pair.
    key_string and value_string are indexes into STRS.
    """

    FORMAT: ClassVar[str] = "<II"
    SIZE: ClassVar[int] = struct.calcsize(FORMAT)

    key_string: int
    value_string: int

    def pack(self) -> bytes:
        return struct.pack(self.FORMAT, self.key_string, self.value_string)

    @classmethod
    def unpack(cls, data: bytes) -> "RbkMetaEntry":
        if len(data) < cls.SIZE:
            raise ValueError("not enough bytes for RbkMetaEntry")
        return cls(*struct.unpack(cls.FORMAT, data[:cls.SIZE]))

@dataclass(slots=True)
class RbkChapterChunkHeader:
    FORMAT: ClassVar[str] = "<4sII16s"
    SIZE: ClassVar[int] = struct.calcsize(FORMAT)

    magic: bytes = ChunkKind.CHAP
    chapter_count: int = 0
    entry_size: int = 0
    reserved: bytes = b"\x00" * 16

    def pack(self) -> bytes:
        if len(self.reserved) != 16:
            raise ValueError("reserved must be 16 bytes")
        self.magic = ChunkKind.CHAP
        self.entry_size = RbkChapterEntry.SIZE
        return struct.pack(
            self.FORMAT,
            self.magic,
            self.chapter_count,
            self.entry_size,
            self.reserved,
        )

    @classmethod
    def unpack(cls, data: bytes) -> "RbkChapterChunkHeader":
        if len(data) < cls.SIZE:
            raise ValueError("not enough bytes for RbkChapterChunkHeader")
        return cls(*struct.unpack(cls.FORMAT, data[:cls.SIZE]))

    def validate(self, chunk_size: int) -> None:
        if self.magic != ChunkKind.CHAP:
            raise ValueError("invalid CHAP chunk magic")
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
    level: int = 0
    flags: int = 0
    reserved: bytes = b"\x00" * 16

    def pack(self) -> bytes:
        if len(self.reserved) != 16:
            raise ValueError("reserved must be 16 bytes")
        return struct.pack(
            self.FORMAT,
            self.title_string,
            self.first_page,
            self.page_count,
            self.level,
            self.flags,
            self.reserved,
        )

    @classmethod
    def unpack(cls, data: bytes) -> "RbkChapterEntry":
        if len(data) < cls.SIZE:
            raise ValueError("not enough bytes for RbkChapterEntry")
        return cls(*struct.unpack(cls.FORMAT, data[:cls.SIZE]))

@dataclass(slots=True)
class RbkPageChunkHeader:
    FORMAT: ClassVar[str] = "<4sII16s"
    SIZE: ClassVar[int] = struct.calcsize(FORMAT)

    magic: bytes = ChunkKind.PAGE
    page_count: int = 0
    entry_size: int = 0
    reserved: bytes = b"\x00" * 16

    def pack(self) -> bytes:
        if len(self.reserved) != 16:
            raise ValueError("reserved must be 16 bytes")
        self.magic = ChunkKind.PAGE
        self.entry_size = RbkPageEntry.SIZE
        return struct.pack(
            self.FORMAT,
            self.magic,
            self.page_count,
            self.entry_size,
            self.reserved,
        )

    @classmethod
    def unpack(cls, data: bytes) -> "RbkPageChunkHeader":
        if len(data) < cls.SIZE:
            raise ValueError("not enough bytes for RbkPageChunkHeader")
        return cls(*struct.unpack(cls.FORMAT, data[:cls.SIZE]))

    def validate(self, chunk_size: int) -> None:
        if self.magic != ChunkKind.PAGE:
            raise ValueError("invalid PAGE chunk magic")
        if self.entry_size != RbkPageEntry.SIZE:
            raise ValueError("invalid PAGE entry size")
        if self.SIZE + self.page_count * self.entry_size > chunk_size:
            raise ValueError("PAGE entries exceed chunk size")

@dataclass(slots=True)
class RbkPageEntry:
    """
    one display-ready page.

    unpacked_offset/length point into the decompressed text block.
    the bytes there are utf-8 with '\\n' already inserted for line breaks.
    """

    FORMAT: ClassVar[str] = "<IIIIHHI"
    SIZE: ClassVar[int] = struct.calcsize(FORMAT)

    chapter_index: int
    block_index: int
    unpacked_offset: int
    unpacked_length: int
    line_count: int
    reserved0: int = 0
    flags: int = 0

    def pack(self) -> bytes:
        return struct.pack(
            self.FORMAT,
            self.chapter_index,
            self.block_index,
            self.unpacked_offset,
            self.unpacked_length,
            self.line_count,
            self.reserved0,
            self.flags,
        )

    @classmethod
    def unpack(cls, data: bytes) -> "RbkPageEntry":
        if len(data) < cls.SIZE:
            raise ValueError("not enough bytes for RbkPageEntry")
        return cls(*struct.unpack(cls.FORMAT, data[:cls.SIZE]))

@dataclass(slots=True)
class RbkBlockIndexChunkHeader:
    FORMAT: ClassVar[str] = "<4sII16s"
    SIZE: ClassVar[int] = struct.calcsize(FORMAT)

    magic: bytes = ChunkKind.BLKI
    block_count: int = 0
    entry_size: int = 0
    reserved: bytes = b"\x00" * 16

    def pack(self) -> bytes:
        if len(self.reserved) != 16:
            raise ValueError("reserved must be 16 bytes")
        self.magic = ChunkKind.BLKI
        self.entry_size = RbkBlockEntry.SIZE
        return struct.pack(
            self.FORMAT,
            self.magic,
            self.block_count,
            self.entry_size,
            self.reserved,
        )

    @classmethod
    def unpack(cls, data: bytes) -> "RbkBlockIndexChunkHeader":
        if len(data) < cls.SIZE:
            raise ValueError("not enough bytes for RbkBlockIndexChunkHeader")
        return cls(*struct.unpack(cls.FORMAT, data[:cls.SIZE]))

    def validate(self, chunk_size: int) -> None:
        if self.magic != ChunkKind.BLKI:
            raise ValueError("invalid BLKI chunk magic")
        if self.entry_size != RbkBlockEntry.SIZE:
            raise ValueError("invalid BLKI entry size")
        if self.SIZE + self.block_count * self.entry_size > chunk_size:
            raise ValueError("BLKI entries exceed chunk size")

@dataclass(slots=True)
class RbkBlockEntry:
    FORMAT: ClassVar[str] = "<QIIIIIIII16s"
    SIZE: ClassVar[int] = struct.calcsize(FORMAT)

    packed_offset: int  # relative to TEXT data area
    packed_size: int
    unpacked_size: int

    first_page: int
    page_count: int

    crc32c: int

    compression: int = int(CompressionType.LZ4)
    flags: int = 0

    reserved1: int = 0
    reserved2: bytes = b"\x00" * 16

    def pack(self) -> bytes:
        try:
            compression = CompressionType(self.compression)
        except ValueError as e:
            raise ValueError("invalid block compression type") from e
        if compression not in SUPPORTED_BLOCK_COMPRESSIONS:
            raise ValueError(f"unsupported block compression type: {compression.name.lower()}")
        if len(self.reserved2) != 16:
            raise ValueError("reserved2 must be 16 bytes")

        return struct.pack(
            self.FORMAT,
            self.packed_offset,
            self.packed_size,
            self.unpacked_size,
            self.first_page,
            self.page_count,
            self.crc32c,
            self.compression,
            self.flags,
            self.reserved1,
            self.reserved2,
        )

    @classmethod
    def unpack(cls, data: bytes) -> "RbkBlockEntry":
        if len(data) < cls.SIZE:
            raise ValueError("not enough bytes for RbkBlockEntry")
        return cls(*struct.unpack(cls.FORMAT, data[:cls.SIZE]))

    def validate(self, text_data_size: int) -> None:
        try:
            compression = CompressionType(self.compression)
        except ValueError as e:
            raise ValueError("invalid block compression type") from e
        if compression not in SUPPORTED_BLOCK_COMPRESSIONS:
            raise ValueError(f"unsupported block compression type: {compression.name.lower()}")
        if self.packed_size == 0:
            raise ValueError("block packed size must be greater than 0")
        if self.unpacked_size == 0:
            raise ValueError("block unpacked size must be greater than 0")
        if self.page_count == 0:
            raise ValueError("block page count must be greater than 0")
        if self.packed_offset > text_data_size or self.packed_offset + self.packed_size > text_data_size:
            raise ValueError("block exceeds TEXT data")

@dataclass(slots=True)
class RbkStringTableHeader:
    FORMAT: ClassVar[str] = "<4sIIIII16s"
    SIZE: ClassVar[int] = struct.calcsize(FORMAT)

    magic: bytes = ChunkKind.STRS
    string_count: int = 0
    entry_size: int = 0
    entries_offset: int = 0
    data_offset: int = 0
    data_size: int = 0
    reserved: bytes = b"\x00" * 16

    def pack(self) -> bytes:
        if len(self.reserved) != 16:
            raise ValueError("reserved must be 16 bytes")

        self.magic = ChunkKind.STRS
        self.entry_size = RbkStringEntry.SIZE
        self.entries_offset = self.entries_offset or self.SIZE
        self.data_offset = self.data_offset or (
            self.SIZE + self.string_count * RbkStringEntry.SIZE
        )

        return struct.pack(
            self.FORMAT,
            self.magic,
            self.string_count,
            self.entry_size,
            self.entries_offset,
            self.data_offset,
            self.data_size,
            self.reserved,
        )

    @classmethod
    def unpack(cls, data: bytes) -> "RbkStringTableHeader":
        if len(data) < cls.SIZE:
            raise ValueError("not enough bytes for RbkStringTableHeader")
        return cls(*struct.unpack(cls.FORMAT, data[:cls.SIZE]))

    def validate(self, chunk_size: int) -> None:
        if self.magic != ChunkKind.STRS:
            raise ValueError("invalid STRS chunk magic")
        if self.entry_size != RbkStringEntry.SIZE:
            raise ValueError("invalid STRS entry size")

        entries_end = self.entries_offset + self.string_count * self.entry_size
        data_end = self.data_offset + self.data_size

        if self.entries_offset < self.SIZE:
            raise ValueError("invalid STRS entries offset")
        if entries_end > chunk_size:
            raise ValueError("STRS entries exceed chunk size")
        if data_end > chunk_size:
            raise ValueError("STRS data exceeds chunk size")

@dataclass(slots=True)
class RbkStringEntry:
    FORMAT: ClassVar[str] = "<QI"
    SIZE: ClassVar[int] = struct.calcsize(FORMAT)

    offset: int
    length: int

    def pack(self) -> bytes:
        return struct.pack(self.FORMAT, self.offset, self.length)

    @classmethod
    def unpack(cls, data: bytes) -> "RbkStringEntry":
        if len(data) < cls.SIZE:
            raise ValueError("not enough bytes for RbkStringEntry")
        return cls(*struct.unpack(cls.FORMAT, data[:cls.SIZE]))

@dataclass(slots=True)
class RbkTextChunkHeader:
    FORMAT: ClassVar[str] = "<4sIQQII16s"
    SIZE: ClassVar[int] = struct.calcsize(FORMAT)

    magic: bytes = ChunkKind.TEXT

    data_offset: int = 0

    packed_data_size: int = 0
    unpacked_total_size: int = 0

    block_count: int = 0
    flags: int = 0

    reserved: bytes = b"\x00" * 16

    def pack(self) -> bytes:
        if len(self.reserved) != 16:
            raise ValueError("reserved must be 16 bytes")

        self.magic = ChunkKind.TEXT
        self.data_offset = self.data_offset or self.SIZE

        return struct.pack(
            self.FORMAT,
            self.magic,
            self.data_offset,
            self.packed_data_size,
            self.unpacked_total_size,
            self.block_count,
            self.flags,
            self.reserved,
        )

    @classmethod
    def unpack(cls, data: bytes) -> "RbkTextChunkHeader":
        if len(data) < cls.SIZE:
            raise ValueError("not enough bytes for RbkTextChunkHeader")
        return cls(*struct.unpack(cls.FORMAT, data[:cls.SIZE]))

    def validate(self, chunk_size: int) -> None:
        if self.magic != ChunkKind.TEXT:
            raise ValueError("invalid TEXT chunk magic")
        if self.data_offset < self.SIZE:
            raise ValueError("TEXT data offset must be at least header size")
        if self.packed_data_size == 0:
            raise ValueError("TEXT packed data size must be greater than 0")
        if self.unpacked_total_size == 0:
            raise ValueError("TEXT unpacked total size must be greater than 0")
        if self.block_count == 0:
            raise ValueError("TEXT block count must be greater than 0")
        if self.data_offset + self.packed_data_size > chunk_size:
            raise ValueError("TEXT data exceeds chunk size")

@dataclass(slots=True)
class EpubChapter:
    title: str
    text: str


@dataclass(slots=True)
class EpubExtract:
    title: str
    author: str
    language: str
    chapters: list[EpubChapter]


@dataclass(slots=True)
class _ManifestItem:
    href: str
    media_type: str
    properties: set[str]


def _warn(message: str) -> None:
    print(f"warning: {message}", file=sys.stderr)


def _error(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)


def _local_name(tag: str) -> str:
    if "}" in tag:
        return tag.rsplit("}", 1)[1]
    return tag


def _find_child(elem: ET.Element | None, name: str) -> ET.Element | None:
    if elem is None:
        return None

    for child in elem:
        if _local_name(child.tag) == name:
            return child

    return None


def _clean_ws(text: str) -> str:
    return " ".join(text.split())


def _first_text(parent: ET.Element | None, name: str, default: str = "") -> str:
    if parent is None:
        return default

    for elem in parent.iter():
        if _local_name(elem.tag) != name:
            continue

        text = _clean_ws(" ".join(elem.itertext()))
        if text:
            return text

    return default


def _opf_base_dir(opf_path: str) -> str:
    base = posixpath.dirname(opf_path)
    return "" if base == "." else base


def _normalize_zip_path(path: str) -> str:
    path = path.replace("\\", "/")
    path = unquote(urlsplit(path).path)
    path = posixpath.normpath(path).lstrip("/")

    if path == ".":
        return ""

    return path


def _resolve_href(base_dir: str, href: str) -> str:
    # epub hrefs are urls, not raw zip paths.
    path = unquote(urlsplit(href).path)
    path = posixpath.normpath(posixpath.join(base_dir, path)).lstrip("/")

    while path.startswith("../"):
        path = path[3:]

    return path


def _path_key(path: str) -> str:
    return _normalize_zip_path(path).casefold()


def _zip_member_name(z: zipfile.ZipFile, path: str) -> str:
    wanted = _normalize_zip_path(path)

    try:
        return z.getinfo(wanted).filename
    except KeyError:
        pass

    wanted_key = wanted.casefold()

    for name in z.namelist():
        if _normalize_zip_path(name).casefold() == wanted_key:
            return name

    raise KeyError(path)


def _decode_text(data: bytes) -> str:
    encodings: list[str] = []

    match = _XML_ENCODING_RE.search(data[:512])
    if match is not None:
        try:
            encodings.append(match.group(1).decode("ascii"))
        except UnicodeDecodeError:
            pass

    match = _HTML_CHARSET_RE.search(data[:2048])
    if match is not None:
        try:
            encodings.append(match.group(1).decode("ascii"))
        except UnicodeDecodeError:
            pass

    encodings.extend(["utf-8-sig", "utf-8", "cp1252", "latin-1"])

    tried: set[str] = set()

    for encoding in encodings:
        key = encoding.casefold()
        if key in tried:
            continue

        tried.add(key)

        try:
            return data.decode(encoding)
        except (LookupError, UnicodeDecodeError):
            continue

    return data.decode("utf-8", errors="replace")


def read_text_zip(z: zipfile.ZipFile, path: str) -> str:
    member = _zip_member_name(z, path)
    return _decode_text(z.read(member))


def find_opf_path(z: zipfile.ZipFile) -> str:
    try:
        container_xml = read_text_zip(z, "META-INF/container.xml")
    except KeyError:
        raise ValueError("invalid epub: missing META-INF/container.xml")

    try:
        root = ET.fromstring(container_xml.lstrip())
    except ET.ParseError as e:
        raise ValueError(f"invalid epub: failed to parse container.xml: {e}") from e

    rootfiles = [
        elem
        for elem in root.iter()
        if _local_name(elem.tag) == "rootfile"
    ]

    if not rootfiles:
        raise ValueError("invalid epub: no rootfile element in container.xml")

    rootfile = next(
        (
            elem
            for elem in rootfiles
            if elem.get("media-type") in {
                None,
                "",
                "application/oebps-package+xml",
            }
        ),
        rootfiles[0],
    )

    media_type = rootfile.get("media-type")
    if media_type not in {None, "", "application/oebps-package+xml"}:
        _warn(f"rootfile media-type is unusual: {media_type}")

    opf_path = rootfile.get("full-path")
    if not opf_path:
        raise ValueError("invalid epub: rootfile element missing full-path attribute")

    return _normalize_zip_path(opf_path)


def _parse_manifest(root: ET.Element, opf_dir: str) -> dict[str, _ManifestItem]:
    manifest_elem = _find_child(root, "manifest")
    if manifest_elem is None:
        raise ValueError("invalid epub: opf is missing manifest")

    manifest: dict[str, _ManifestItem] = {}

    for item in manifest_elem:
        if _local_name(item.tag) != "item":
            continue

        item_id = item.get("id")
        href = item.get("href")

        if not item_id or not href:
            _warn("skipping manifest item with missing id or href")
            continue

        if item_id in manifest:
            _warn(f"duplicate manifest id, keeping later item: {item_id}")

        manifest[item_id] = _ManifestItem(
            href=_resolve_href(opf_dir, href),
            media_type=item.get("media-type", "").split(";", 1)[0].strip().lower(),
            properties=set(item.get("properties", "").split()),
        )

    if not manifest:
        raise ValueError("invalid epub: manifest has no usable items")

    return manifest


def _parse_spine(root: ET.Element) -> tuple[list[str], str | None]:
    spine_elem = _find_child(root, "spine")
    if spine_elem is None:
        _warn("opf is missing spine; will fall back to manifest order")
        return [], None

    toc_id = spine_elem.get("toc")
    idrefs: list[str] = []
    fallback_idrefs: list[str] = []

    for itemref in spine_elem:
        if _local_name(itemref.tag) != "itemref":
            continue

        idref = itemref.get("idref")
        if not idref:
            continue

        fallback_idrefs.append(idref)

        if itemref.get("linear", "yes").strip().lower() != "no":
            idrefs.append(idref)

    return (idrefs or fallback_idrefs), toc_id


def _extract_metadata(root: ET.Element) -> tuple[str, str, str]:
    metadata = _find_child(root, "metadata")

    return (
        _first_text(metadata, "title", "untitled"),
        _first_text(metadata, "creator", "unknown"),
        _first_text(metadata, "language", ""),
    )


def _chapter_title_from_html(html: str) -> str:
    soup = BeautifulSoup(html, "html.parser")

    body = soup.body or soup
    tag = body.find(["h1", "h2", "h3"])

    if tag is None:
        tag = soup.find("title")

    if tag is None:
        return ""

    return _clean_ws(tag.get_text(" ", strip=True))


def _normalize_extracted_text(text: str) -> str:
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = text.translate(_STRIP_TRANSLATION)

    # source html often contains indentation/newlines that should not become prose
    # line breaks. our sentinels survive this because they are not whitespace.
    text = re.sub(r"[ \t\f\v\n]+", " ", text)

    text = text.replace(_TEXT_LINE_BREAK, "\n")
    text = text.replace(_TEXT_PARAGRAPH_BREAK, "\n\n")

    text = re.sub(r"[ \t\f\v]+", " ", text)
    text = re.sub(r" *\n *", "\n", text)
    text = re.sub(r"\n{3,}", "\n\n", text)

    # clean spaces around punctuation caused by split inline tags.
    text = re.sub(r" +([,.;:!?%\)\]\}”’»])", r"\1", text)
    text = re.sub(r"([“‘«\(\[\{]) +", r"\1", text)

    paragraphs = [p.strip() for p in text.split("\n\n")]
    return "\n\n".join(p for p in paragraphs if p)


def _is_pagebreak(tag) -> bool:
    marker = " ".join(
        str(tag.get(attr, ""))
        for attr in ("epub:type", "type", "role", "class")
    ).lower()

    return "pagebreak" in marker or "doc-pagebreak" in marker


def _html_to_text(html: str) -> str:
    soup = BeautifulSoup(html, "html.parser")

    for tag in soup(["script", "style", "svg", "noscript"]):
        tag.decompose()

    for tag in soup.find_all(attrs={"hidden": True}):
        tag.decompose()

    for tag in soup.find_all(attrs={"aria-hidden": re.compile(r"^true$", re.IGNORECASE)}):
        tag.decompose()

    for tag in soup.find_all(style=True):
        style = re.sub(r"\s+", "", tag.get("style", "").lower())
        if "display:none" in style or "visibility:hidden" in style:
            tag.decompose()

    for tag in soup.find_all(_is_pagebreak):
        tag.decompose()

    for nav in soup.find_all("nav"):
        nav.decompose()

    for math in soup.find_all("math"):
        annotation = math.find(
            "annotation",
            attrs={"encoding": re.compile(r"(tex|latex)", re.IGNORECASE)},
        )

        if annotation is not None:
            text = _clean_ws(annotation.get_text(" ", strip=True))
            math.replace_with(f" {text} " if text else " ")
        else:
            math.replace_with(" ")

    for img in soup.find_all("img"):
        alt = _clean_ws(img.get("alt", ""))
        img.replace_with(f" [{alt}] " if alt else " ")

    for tag in soup.find_all("br"):
        tag.replace_with(_TEXT_LINE_BREAK)

    # mark real block boundaries with sentinels. do not use get_text("\n"),
    # because that also splits inline tags like <em>, <span>, <i>, etc.
    for tag in soup.find_all(_BLOCK_TAGS):
        tag.insert_before(_TEXT_PARAGRAPH_BREAK)
        tag.append(_TEXT_PARAGRAPH_BREAK)

    root = soup.body or soup
    return _normalize_extracted_text(root.get_text("", strip=False))

def _is_content_item(item: _ManifestItem) -> bool:
    if "nav" in item.properties:
        return False

    if item.media_type == "application/x-dtbncx+xml":
        return False

    if item.media_type in CONTENT_MEDIA_TYPES:
        return True

    return Path(item.href).suffix.lower() in CONTENT_SUFFIXES


def _parse_epub3_nav_titles(
    z: zipfile.ZipFile,
    manifest: dict[str, _ManifestItem],
) -> dict[str, str]:
    nav_item = next((item for item in manifest.values() if "nav" in item.properties), None)
    if nav_item is None:
        return {}

    try:
        nav_html = read_text_zip(z, nav_item.href)
    except KeyError:
        _warn(f"nav item is missing from zip: {nav_item.href}")
        return {}

    nav_dir = posixpath.dirname(nav_item.href)
    soup = BeautifulSoup(nav_html, "html.parser")

    def is_toc_nav(tag) -> bool:
        if tag.name != "nav":
            return False

        nav_type = " ".join(
            str(tag.get(attr, ""))
            for attr in ("epub:type", "type", "role")
        ).lower()

        return "toc" in nav_type or "doc-toc" in nav_type

    toc_nav = soup.find(is_toc_nav) or soup.find("nav")
    if toc_nav is None:
        return {}

    titles: dict[str, str] = {}

    for a in toc_nav.find_all("a"):
        href = a.get("href")
        if not href:
            continue

        path = _resolve_href(nav_dir, href)
        title = _clean_ws(a.get_text(" ", strip=True))

        if title:
            titles.setdefault(_path_key(path), title)

    return titles


def _parse_epub2_ncx_titles(
    z: zipfile.ZipFile,
    manifest: dict[str, _ManifestItem],
    toc_id: str | None,
) -> dict[str, str]:
    ncx_item: _ManifestItem | None = None

    if toc_id is not None:
        ncx_item = manifest.get(toc_id)

    if ncx_item is None:
        ncx_item = next(
            (
                item
                for item in manifest.values()
                if item.media_type == "application/x-dtbncx+xml"
            ),
            None,
        )

    if ncx_item is None:
        return {}

    try:
        ncx_xml = read_text_zip(z, ncx_item.href)
        root = ET.fromstring(ncx_xml.lstrip())
    except KeyError:
        _warn(f"ncx item is missing from zip: {ncx_item.href}")
        return {}
    except ET.ParseError as e:
        _warn(f"failed to parse ncx {ncx_item.href}: {e}")
        return {}

    ncx_dir = posixpath.dirname(ncx_item.href)
    titles: dict[str, str] = {}

    for nav_point in root.iter():
        if _local_name(nav_point.tag) != "navPoint":
            continue

        label = ""
        src = ""

        nav_label = _find_child(nav_point, "navLabel")
        label = _first_text(nav_label, "text")

        content = _find_child(nav_point, "content")
        if content is not None:
            src = content.get("src", "")

        if label and src:
            path = _resolve_href(ncx_dir, src)
            titles.setdefault(_path_key(path), label)

    return titles


def _make_chapter_title(
    zip_path: str,
    html: str,
    nav_titles: dict[str, str],
    index: int,
) -> str:
    title = nav_titles.get(_path_key(zip_path))
    if title:
        return title

    title = _chapter_title_from_html(html)
    if title:
        return title

    stem = Path(zip_path).stem.replace("_", " ").replace("-", " ")
    stem = _clean_ws(stem).title()

    return stem or f"chapter {index + 1}"


def _read_chapter(
    z: zipfile.ZipFile,
    item: _ManifestItem,
    nav_titles: dict[str, str],
    index: int,
) -> EpubChapter | None:
    if not _is_content_item(item):
        return None

    try:
        html = read_text_zip(z, item.href)
    except KeyError:
        _warn(f"manifest item is missing from zip: {item.href}")
        return None

    text = _html_to_text(html)
    if not text:
        return None

    return EpubChapter(
        title=_make_chapter_title(item.href, html, nav_titles, index),
        text=text,
    )


def parse_epub(input_epub: Path) -> EpubExtract:
    try:
        zf = zipfile.ZipFile(input_epub, "r")
    except zipfile.BadZipFile as e:
        raise ValueError("invalid epub: file is not a valid zip archive") from e

    with zf as z:
        opf_path = find_opf_path(z)

        try:
            opf_data = read_text_zip(z, opf_path)
        except KeyError as e:
            raise ValueError(f"invalid epub: opf file is missing from zip: {opf_path}") from e

        try:
            root = ET.fromstring(opf_data.lstrip())
        except ET.ParseError as e:
            raise ValueError(f"invalid epub: failed to parse opf {opf_path}: {e}") from e

        opf_dir = _opf_base_dir(opf_path)

        book_title, author, language = _extract_metadata(root)
        manifest = _parse_manifest(root, opf_dir)
        spine_ids, toc_id = _parse_spine(root)

        nav_titles = _parse_epub3_nav_titles(z, manifest)

        # ncx is usually epub 2, but some epub 3 files still include it.
        # only fills missing titles; epub 3 nav wins.
        for path, title in _parse_epub2_ncx_titles(z, manifest, toc_id).items():
            nav_titles.setdefault(path, title)

        chapters: list[EpubChapter] = []
        seen_paths: set[str] = set()

        for idref in spine_ids:
            item = manifest.get(idref)

            if item is None:
                _warn(f"spine references missing manifest item: {idref}")
                continue

            seen_paths.add(_path_key(item.href))

            chapter = _read_chapter(z, item, nav_titles, len(chapters))
            if chapter is not None:
                chapters.append(chapter)

        if not chapters:
            _warn("spine produced no readable chapters; falling back to manifest order")

            for item in manifest.values():
                key = _path_key(item.href)
                if key in seen_paths:
                    continue

                chapter = _read_chapter(z, item, nav_titles, len(chapters))
                if chapter is not None:
                    chapters.append(chapter)

        return EpubExtract(
            title=book_title,
            author=author,
            language=language,
            chapters=chapters,
        )



UINT16_MAX = (1 << 16) - 1
UINT32_MAX = (1 << 32) - 1
UINT64_MAX = (1 << 64) - 1
DEFAULT_SCREEN_WIDTH_PX = 296
DEFAULT_SCREEN_HEIGHT_PX = 128
DEFAULT_FONT_WIDTH_PX = 6
DEFAULT_FONT_HEIGHT_PX = 12
DEFAULT_TEXT_BLOCK_UNPACKED_LIMIT = 64 * 1024


@dataclass(slots=True)
class RbkBuildOptions:
    screen_width_px: int = DEFAULT_SCREEN_WIDTH_PX
    screen_height_px: int = DEFAULT_SCREEN_HEIGHT_PX
    font_width_px: int = DEFAULT_FONT_WIDTH_PX
    font_height_px: int = DEFAULT_FONT_HEIGHT_PX
    chars_per_line: int | None = None
    lines_per_page: int | None = None
    text_block_unpacked_limit: int = DEFAULT_TEXT_BLOCK_UNPACKED_LIMIT
    compression: CompressionType | None = None

    def normalized(self) -> "RbkBuildOptions":
        _require_int_range("screen_width_px", self.screen_width_px, 1, UINT16_MAX)
        _require_int_range("screen_height_px", self.screen_height_px, 1, UINT16_MAX)
        _require_int_range("font_width_px", self.font_width_px, 1, UINT16_MAX)
        _require_int_range("font_height_px", self.font_height_px, 1, UINT16_MAX)

        if self.chars_per_line is None:
            self.chars_per_line = max(1, self.screen_width_px // self.font_width_px)

        if self.lines_per_page is None:
            self.lines_per_page = max(1, self.screen_height_px // self.font_height_px)

        _require_int_range("chars_per_line", self.chars_per_line, 1, UINT16_MAX)
        _require_int_range("lines_per_page", self.lines_per_page, 1, UINT16_MAX)
        _require_int_range(
            "text_block_unpacked_limit",
            self.text_block_unpacked_limit,
            256,
            UINT32_MAX,
        )

        # A single page can be larger than the preferred block limit when the
        # user picks a very wide/tall display. Make sure every page can still
        # fit in one block; the block packer never splits a page.
        min_block_size = max(256, self.chars_per_line * self.lines_per_page * 4 + self.lines_per_page)
        if self.text_block_unpacked_limit < min_block_size:
            self.text_block_unpacked_limit = min_block_size

        return self


@dataclass(slots=True)
class _PagePlan:
    chapter_index: int
    text: str
    encoded: bytes
    line_count: int


@dataclass(slots=True)
class _BlockBuild:
    entry: RbkBlockEntry
    packed: bytes
    unpacked: bytes


class _StringTableBuilder:
    def __init__(self) -> None:
        self._index: dict[str, int] = {}
        self._strings: list[str] = []

    def add(self, value: object) -> int:
        text = "" if value is None else str(value)
        if text in self._index:
            return self._index[text]

        index = len(self._strings)
        self._index[text] = index
        self._strings.append(text)
        return index

    def build(self) -> bytes:
        entries: list[RbkStringEntry] = []
        data = bytearray()

        for text in self._strings:
            encoded = text.encode("utf-8")
            _require_int_range("string byte length", len(encoded), 0, UINT32_MAX)
            _require_int_range("string data offset", len(data), 0, UINT64_MAX)
            entries.append(RbkStringEntry(offset=len(data), length=len(encoded)))
            data.extend(encoded)
            data.append(0)

        header = RbkStringTableHeader(
            string_count=len(entries),
            data_size=len(data),
        )
        parts = [header.pack()]
        parts.extend(entry.pack() for entry in entries)
        parts.append(bytes(data))
        return b"".join(parts)

    @property
    def count(self) -> int:
        return len(self._strings)


@dataclass(slots=True)
class RbkBuildStats:
    output_path: Path | None
    title: str
    author: str
    language: str
    chapter_count: int
    page_count: int
    block_count: int
    file_size: int
    compression: str
    chars_per_line: int
    lines_per_page: int


def _require_int_range(name: str, value: int | None, minimum: int, maximum: int) -> None:
    if not isinstance(value, int):
        raise ValueError(f"{name} must be an integer")
    if value < minimum or value > maximum:
        raise ValueError(f"{name} must be in range [{minimum}, {maximum}], got {value}")


def _checked_count(name: str, value: int) -> int:
    _require_int_range(name, value, 0, UINT32_MAX)
    return value


def _sanitize_display_text(text: str) -> str:
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = text.replace("\x00", "")

    cleaned: list[str] = []
    for ch in text:
        code = ord(ch)
        if ch in "\n\t" or code >= 0x20:
            cleaned.append(ch)
        elif ch == "\f":
            cleaned.append("\n\n")

    return "".join(cleaned).strip()


def _wrap_text_to_lines(text: str, width: int) -> list[str]:
    text = _sanitize_display_text(text)
    if not text:
        return [""]

    lines: list[str] = []
    paragraphs = re.split(r"\n{2,}", text)

    for paragraph_index, paragraph in enumerate(paragraphs):
        if paragraph_index > 0 and lines and lines[-1] != "":
            lines.append("")

        logical_lines = paragraph.split("\n") or [""]
        for logical_line in logical_lines:
            logical_line = re.sub(r"[ \t\f\v]+", " ", logical_line).strip()
            if not logical_line:
                lines.append("")
                continue

            wrapped = textwrap.wrap(
                logical_line,
                width=width,
                expand_tabs=True,
                replace_whitespace=True,
                drop_whitespace=True,
                break_long_words=True,
                break_on_hyphens=False,
            )
            lines.extend(wrapped or [""])

    while len(lines) > 1 and lines[0] == "":
        lines.pop(0)
    while len(lines) > 1 and lines[-1] == "":
        lines.pop()

    return lines or [""]


def _paginate_chapter(chapter_index: int, text: str, options: RbkBuildOptions) -> list[_PagePlan]:
    lines = _wrap_text_to_lines(text, options.chars_per_line or 1)
    lines_per_page = options.lines_per_page or 1
    pages: list[_PagePlan] = []

    for start in range(0, len(lines), lines_per_page):
        page_lines = lines[start:start + lines_per_page]
        page_text = "\n".join(page_lines) + "\n"
        encoded = page_text.encode("utf-8")
        if not encoded:
            encoded = b"\n"
            page_text = "\n"

        _require_int_range("page byte length", len(encoded), 1, UINT32_MAX)
        _require_int_range("page line count", len(page_lines), 1, UINT16_MAX)
        pages.append(
            _PagePlan(
                chapter_index=chapter_index,
                text=page_text,
                encoded=encoded,
                line_count=len(page_lines),
            )
        )

    return pages or [_PagePlan(chapter_index, "\n", b"\n", 1)]


def _compression_available(compression: CompressionType) -> bool:
    if compression == CompressionType.NONE:
        return True
    if compression == CompressionType.LZ4:
        return lz4block is not None
    if compression == CompressionType.HEATSHRINK:
        return heatshrink2 is not None
    if compression == CompressionType.ZLIB:
        return True
    return False


def _default_compression() -> CompressionType:
    if _compression_available(CompressionType.LZ4):
        return CompressionType.LZ4
    return CompressionType.ZLIB


def _compression_from_cli(name: str) -> CompressionType | None:
    normalized = name.strip().lower()
    if normalized == "auto":
        return None
    if normalized == "none":
        return CompressionType.NONE
    if normalized == "lz4":
        return CompressionType.LZ4
    if normalized == "zlib":
        return CompressionType.ZLIB
    if normalized == "heatshrink":
        return CompressionType.HEATSHRINK
    raise ValueError(f"unknown compression: {name}")


def _compress_block(data: bytes, compression: CompressionType) -> bytes:
    if compression == CompressionType.NONE:
        return data

    if compression == CompressionType.LZ4:
        if lz4block is None:
            raise ValueError("lz4 compression requested but lz4.block is not installed")
        return lz4block.compress(data, store_size=False)

    if compression == CompressionType.HEATSHRINK:
        if heatshrink2 is None:
            raise ValueError("heatshrink compression requested but heatshrink2 is not installed")
        return heatshrink2.compress(data)

    if compression == CompressionType.ZLIB:
        return zlib.compress(data, level=9)

    raise ValueError(f"unsupported compression type for writing: {compression}")


def _decompress_block(data: bytes, compression: CompressionType, unpacked_size: int) -> bytes:
    if compression == CompressionType.NONE:
        unpacked = data
    elif compression == CompressionType.LZ4:
        if lz4block is None:
            raise ValueError("cannot verify lz4 block because lz4.block is not installed")
        unpacked = lz4block.decompress(data, uncompressed_size=unpacked_size)
    elif compression == CompressionType.HEATSHRINK:
        if heatshrink2 is None:
            raise ValueError("cannot verify heatshrink block because heatshrink2 is not installed")
        unpacked = heatshrink2.decompress(data)
    elif compression == CompressionType.ZLIB:
        unpacked = zlib.decompress(data)
    else:
        raise ValueError(f"unsupported compression type: {compression}")

    if len(unpacked) != unpacked_size:
        raise ValueError(
            f"decompressed block size mismatch: expected {unpacked_size}, got {len(unpacked)}"
        )
    return unpacked


def _compress_block_best_effort(data: bytes, requested: CompressionType) -> tuple[bytes, CompressionType]:
    if requested != CompressionType.NONE and not _compression_available(requested):
        raise ValueError(f"requested compression is not available: {requested.name.lower()}")

    packed = _compress_block(data, requested)

    # Tiny or already-compressed blocks can grow. Store those raw; the per-block
    # compression field keeps mixed blocks valid and simple to read.
    if requested != CompressionType.NONE and len(packed) >= len(data):
        return data, CompressionType.NONE

    return packed, requested


def _make_book_id(epub: EpubExtract) -> bytes:
    h = hashlib.blake2b(digest_size=16)
    for value in (epub.title, epub.author, epub.language):
        h.update(value.encode("utf-8", errors="replace"))
        h.update(b"\x00")
    for chapter in epub.chapters:
        h.update(chapter.title.encode("utf-8", errors="replace"))
        h.update(b"\x00")
        h.update(chapter.text.encode("utf-8", errors="replace"))
        h.update(b"\x00")
    return h.digest()


def _pack_meta_chunk(entries: list[RbkMetaEntry]) -> bytes:
    header = RbkMetaChunkHeader(entry_count=len(entries))
    return b"".join([header.pack(), *(entry.pack() for entry in entries)])


def _pack_chapter_chunk(entries: list[RbkChapterEntry]) -> bytes:
    header = RbkChapterChunkHeader(chapter_count=len(entries))
    return b"".join([header.pack(), *(entry.pack() for entry in entries)])


def _pack_page_chunk(entries: list[RbkPageEntry]) -> bytes:
    header = RbkPageChunkHeader(page_count=len(entries))
    return b"".join([header.pack(), *(entry.pack() for entry in entries)])


def _pack_block_index_chunk(entries: list[RbkBlockEntry]) -> bytes:
    header = RbkBlockIndexChunkHeader(block_count=len(entries))
    return b"".join([header.pack(), *(entry.pack() for entry in entries)])


def _pack_text_chunk(blocks: list[_BlockBuild]) -> bytes:
    packed_data = b"".join(block.packed for block in blocks)
    unpacked_total_size = sum(len(block.unpacked) for block in blocks)
    _require_int_range("TEXT packed data size", len(packed_data), 1, UINT64_MAX)
    _require_int_range("TEXT unpacked total size", unpacked_total_size, 1, UINT64_MAX)

    header = RbkTextChunkHeader(
        packed_data_size=len(packed_data),
        unpacked_total_size=unpacked_total_size,
        block_count=len(blocks),
    )
    return header.pack() + packed_data


def _build_pages_and_blocks(
    epub: EpubExtract,
    options: RbkBuildOptions,
) -> tuple[list[RbkPageEntry], list[_BlockBuild], list[tuple[int, int]]]:
    requested_compression = options.compression if options.compression is not None else _default_compression()

    all_pages: list[_PagePlan] = []
    chapter_ranges: list[tuple[int, int]] = []

    for chapter_index, chapter in enumerate(epub.chapters):
        first_page = len(all_pages)
        chapter_pages = _paginate_chapter(chapter_index, chapter.text, options)
        all_pages.extend(chapter_pages)
        chapter_ranges.append((first_page, len(chapter_pages)))

    if not all_pages:
        raise ValueError("epub contains no readable pages")

    _checked_count("page count", len(all_pages))

    blocks: list[_BlockBuild] = []
    page_entries: list[RbkPageEntry] = []

    current = bytearray()
    current_pages: list[tuple[int, _PagePlan, int]] = []
    first_page_in_block = 0
    packed_offset = 0

    def flush_block() -> None:
        nonlocal current, current_pages, first_page_in_block, packed_offset

        if not current_pages:
            return

        block_index = len(blocks)
        unpacked = bytes(current)
        packed, compression = _compress_block_best_effort(unpacked, requested_compression)

        _require_int_range("block packed offset", packed_offset, 0, UINT64_MAX)
        _require_int_range("block packed size", len(packed), 1, UINT32_MAX)
        _require_int_range("block unpacked size", len(unpacked), 1, UINT32_MAX)

        entry = RbkBlockEntry(
            packed_offset=packed_offset,
            packed_size=len(packed),
            unpacked_size=len(unpacked),
            first_page=first_page_in_block,
            page_count=len(current_pages),
            crc32c=_crc32c(unpacked),
            compression=int(compression),
        )

        for _global_page_index, page, page_offset in current_pages:
            _require_int_range("page unpacked offset", page_offset, 0, UINT32_MAX)
            page_entries.append(
                RbkPageEntry(
                    chapter_index=page.chapter_index,
                    block_index=block_index,
                    unpacked_offset=page_offset,
                    unpacked_length=len(page.encoded),
                    line_count=page.line_count,
                )
            )

        blocks.append(_BlockBuild(entry=entry, packed=packed, unpacked=unpacked))
        packed_offset += len(packed)
        current = bytearray()
        current_pages = []
        first_page_in_block = len(page_entries)

    for global_page_index, page in enumerate(all_pages):
        if len(page.encoded) > UINT32_MAX:
            raise ValueError(f"page {global_page_index} is too large")

        would_exceed = (
            current_pages
            and len(current) + len(page.encoded) > (options.text_block_unpacked_limit or DEFAULT_TEXT_BLOCK_UNPACKED_LIMIT)
        )
        if would_exceed:
            flush_block()

        if not current_pages:
            first_page_in_block = global_page_index

        page_offset = len(current)
        current.extend(page.encoded)
        current_pages.append((global_page_index, page, page_offset))

    flush_block()

    if len(page_entries) != len(all_pages):
        raise ValueError("internal error: page table count does not match pagination")

    _checked_count("block count", len(blocks))
    return page_entries, blocks, chapter_ranges


def build_rbk2(epub: EpubExtract, options: RbkBuildOptions | None = None) -> tuple[bytes, RbkBuildStats]:
    options = (options or RbkBuildOptions()).normalized()

    if not epub.chapters:
        raise ValueError("epub contains no readable chapters")

    page_entries, blocks, chapter_ranges = _build_pages_and_blocks(epub, options)

    strings = _StringTableBuilder()
    title_index = strings.add("title")
    author_index = strings.add("author")
    language_index = strings.add("language")
    page_count_index = strings.add("page_count")
    chapter_count_index = strings.add("chapter_count")
    chars_per_line_index = strings.add("chars_per_line")
    lines_per_page_index = strings.add("lines_per_page")
    compression_index = strings.add("compression")
    created_unix_index = strings.add("created_unix")

    chapter_title_indexes = [strings.add(chapter.title) for chapter in epub.chapters]

    requested_compression = options.compression if options.compression is not None else _default_compression()
    actual_compressions = sorted({CompressionType(block.entry.compression).name.lower() for block in blocks})
    compression_summary = "+".join(actual_compressions) if actual_compressions else requested_compression.name.lower()

    meta_pairs = [
        (title_index, strings.add(epub.title)),
        (author_index, strings.add(epub.author)),
        (language_index, strings.add(epub.language)),
        (page_count_index, strings.add(str(len(page_entries)))),
        (chapter_count_index, strings.add(str(len(epub.chapters)))),
        (chars_per_line_index, strings.add(str(options.chars_per_line))),
        (lines_per_page_index, strings.add(str(options.lines_per_page))),
        (compression_index, strings.add(compression_summary)),
        (created_unix_index, strings.add(str(int(time.time())))),
    ]
    meta_entries = [RbkMetaEntry(k, v) for k, v in meta_pairs]

    chapter_entries: list[RbkChapterEntry] = []
    for chapter_index, (first_page, page_count) in enumerate(chapter_ranges):
        _require_int_range("chapter first page", first_page, 0, UINT32_MAX)
        _require_int_range("chapter page count", page_count, 1, UINT32_MAX)
        chapter_entries.append(
            RbkChapterEntry(
                title_string=chapter_title_indexes[chapter_index],
                first_page=first_page,
                page_count=page_count,
                level=0,
            )
        )

    strs_chunk = strings.build()
    chunks: list[tuple[bytes, bytes]] = [
        (ChunkKind.META, _pack_meta_chunk(meta_entries)),
        (ChunkKind.STRS, strs_chunk),
        (ChunkKind.CHAP, _pack_chapter_chunk(chapter_entries)),
        (ChunkKind.PAGE, _pack_page_chunk(page_entries)),
        (ChunkKind.BLKI, _pack_block_index_chunk([block.entry for block in blocks])),
        (ChunkKind.TEXT, _pack_text_chunk(blocks)),
    ]

    _checked_count("chunk count", len(chunks))
    table_size = len(chunks) * RbkChunkEntry.SIZE
    data_offset = RbkHeader.SIZE + table_size
    current_offset = data_offset
    chunk_entries: list[RbkChunkEntry] = []

    for kind, chunk_data in chunks:
        _require_int_range("chunk offset", current_offset, 0, UINT64_MAX)
        _require_int_range("chunk size", len(chunk_data), 1, UINT64_MAX)
        chunk_entries.append(
            RbkChunkEntry(
                kind=kind,
                flags=0,
                compression=int(CompressionType.NONE),
                reserved1=0,
                offset=current_offset,
                packed_size=len(chunk_data),
                unpacked_size=len(chunk_data),
                crc32c=_crc32c(chunk_data),
            )
        )
        current_offset += len(chunk_data)

    file_size = current_offset
    _require_int_range("file size", file_size, 1, UINT64_MAX)

    chunk_table = b"".join(entry.pack() for entry in chunk_entries)
    header = RbkHeader(
        file_size=file_size,
        chunk_table_offset=RbkHeader.SIZE,
        chunk_count=len(chunks),
        page_count=len(page_entries),
        chapter_count=len(chapter_entries),
        screen_width_px=options.screen_width_px,
        screen_height_px=options.screen_height_px,
        font_width_px=options.font_width_px,
        font_height_px=options.font_height_px,
        chars_per_line=options.chars_per_line or 1,
        lines_per_page=options.lines_per_page or 1,
        book_id=_make_book_id(epub),
        directory_crc32c=_crc32c(chunk_table),
    )
    header.header_crc32c = header.compute_crc32c()

    rbk_bytes = b"".join(
        [
            header.pack(),
            chunk_table,
            *(chunk_data for _kind, chunk_data in chunks),
        ]
    )

    if len(rbk_bytes) != file_size:
        raise ValueError(f"internal error: file size mismatch {len(rbk_bytes)} != {file_size}")

    stats = RbkBuildStats(
        output_path=None,
        title=epub.title,
        author=epub.author,
        language=epub.language,
        chapter_count=len(chapter_entries),
        page_count=len(page_entries),
        block_count=len(blocks),
        file_size=file_size,
        compression=compression_summary,
        chars_per_line=options.chars_per_line or 1,
        lines_per_page=options.lines_per_page or 1,
    )
    return rbk_bytes, stats


def write_rbk2(
    epub: EpubExtract,
    output_path: Path,
    options: RbkBuildOptions | None = None,
    *,
    verify: bool = True,
) -> RbkBuildStats:
    rbk_bytes, stats = build_rbk2(epub, options)

    output_path = output_path.expanduser()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = output_path.with_name(f".{output_path.name}.{os.getpid()}.tmp")

    try:
        temp_path.write_bytes(rbk_bytes)
        if verify:
            validate_rbk2_file(temp_path)
        os.replace(temp_path, output_path)
    finally:
        try:
            if temp_path.exists():
                temp_path.unlink()
        except OSError:
            pass

    stats.output_path = output_path
    return stats


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
        start = i * header.chunk_entry_size
        entry = RbkChunkEntry.unpack(table[start:start + header.chunk_entry_size])
        entry.validate(header.file_size)
        if entry.kind in chunks:
            raise ValueError(f"duplicate chunk kind: {entry.kind!r}")

        begin = int(entry.offset)
        end = begin + int(entry.packed_size)
        if begin < table_end:
            raise ValueError(f"chunk {entry.kind!r} overlaps the chunk table")
        spans.append((begin, end, entry.kind))

        packed = data[begin:end]
        if entry.compression != CompressionType.NONE:
            raise ValueError(f"top-level chunk compression is unsupported: {entry.kind!r}")
        if _crc32c(packed) != entry.crc32c:
            raise ValueError(f"invalid CRC32C for chunk {entry.kind!r}")
        chunks[entry.kind] = packed

    for (prev_start, prev_end, prev_kind), (start, end, kind) in zip(sorted(spans), sorted(spans)[1:]):
        if start < prev_end:
            raise ValueError(f"chunk {kind!r} overlaps chunk {prev_kind!r}")

    return chunks


def _read_string_table(chunk: bytes) -> list[str]:
    header = RbkStringTableHeader.unpack(chunk)
    header.validate(len(chunk))
    strings: list[str] = []
    data = chunk[header.data_offset:header.data_offset + header.data_size]

    for i in range(header.string_count):
        entry_offset = header.entries_offset + i * header.entry_size
        entry = RbkStringEntry.unpack(chunk[entry_offset:entry_offset + header.entry_size])
        start = int(entry.offset)
        end = start + int(entry.length)
        if end > len(data):
            raise ValueError("string entry exceeds STRS data")
        if end >= len(data) or data[end:end + 1] != b"\x00":
            raise ValueError("string entry is not null-terminated")
        try:
            strings.append(data[start:end].decode("utf-8"))
        except UnicodeDecodeError as e:
            raise ValueError(f"string entry {i} is not valid UTF-8") from e

    return strings


def _parse_fixed_entries(chunk: bytes, header_size: int, entry_size: int, count: int, cls):
    entries_end = header_size + count * entry_size
    if entries_end > len(chunk):
        raise ValueError("fixed entries exceed chunk size")

    entries = []
    for i in range(count):
        offset = header_size + i * entry_size
        entries.append(cls.unpack(chunk[offset:offset + entry_size]))
    return entries


def validate_rbk2_bytes(data: bytes) -> RbkBuildStats:
    if len(data) < RbkHeader.SIZE:
        raise ValueError("file is too small to be an RBK2 file")

    header = RbkHeader.unpack(data)
    header.validate()

    if header.file_size != len(data):
        raise ValueError(f"file size mismatch: header={header.file_size}, actual={len(data)}")

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
    for entry in meta_entries:
        if entry.key_string >= len(strings) or entry.value_string >= len(strings):
            raise ValueError("META string index out of range")

    chap_header = RbkChapterChunkHeader.unpack(chunks[ChunkKind.CHAP])
    chap_header.validate(len(chunks[ChunkKind.CHAP]))
    if chap_header.chapter_count != header.chapter_count:
        raise ValueError("chapter count mismatch")
    chapter_entries = _parse_fixed_entries(
        chunks[ChunkKind.CHAP],
        RbkChapterChunkHeader.SIZE,
        chap_header.entry_size,
        chap_header.chapter_count,
        RbkChapterEntry,
    )

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

    text_data_start = text_header.data_offset
    text_data = chunks[ChunkKind.TEXT][text_data_start:text_data_start + text_header.packed_data_size]

    unpacked_blocks: list[bytes] = []
    block_spans: list[tuple[int, int, int]] = []
    for block_index, block in enumerate(block_entries):
        block.validate(len(text_data))
        begin = int(block.packed_offset)
        end = begin + int(block.packed_size)
        block_spans.append((begin, end, block_index))
        packed = text_data[begin:end]
        unpacked = _decompress_block(
            packed,
            CompressionType(block.compression),
            block.unpacked_size,
        )
        if _crc32c(unpacked) != block.crc32c:
            raise ValueError("invalid CRC32C for text block")
        unpacked_blocks.append(unpacked)

    expected_text_offset = 0
    for start, end, index in sorted(block_spans):
        if start < expected_text_offset:
            raise ValueError(f"text block {index} overlaps a previous text block")
        if start != expected_text_offset:
            raise ValueError("TEXT packed data contains unused bytes between blocks")
        expected_text_offset = end

    if expected_text_offset != len(text_data):
        raise ValueError("TEXT packed data contains unused trailing bytes")

    if sum(len(block) for block in unpacked_blocks) != text_header.unpacked_total_size:
        raise ValueError("TEXT unpacked total size mismatch")

    for block_index, block in enumerate(block_entries):
        if block.first_page + block.page_count > len(page_entries):
            raise ValueError(f"block {block_index} page range exceeds PAGE table")
        for page_index in range(block.first_page, block.first_page + block.page_count):
            if page_entries[page_index].block_index != block_index:
                raise ValueError(f"page {page_index} is not assigned to expected block {block_index}")

    for chapter_index, chapter in enumerate(chapter_entries):
        if chapter.title_string >= len(strings):
            raise ValueError("CHAP title string index out of range")
        if chapter.page_count == 0:
            raise ValueError("CHAP page_count must be greater than 0")
        if chapter.first_page + chapter.page_count > len(page_entries):
            raise ValueError(f"chapter {chapter_index} page range exceeds PAGE table")

    for page_index, page in enumerate(page_entries):
        if page.chapter_index >= len(chapter_entries):
            raise ValueError(f"page {page_index} chapter index out of range")
        if page.block_index >= len(unpacked_blocks):
            raise ValueError(f"page {page_index} block index out of range")
        block = unpacked_blocks[page.block_index]
        if page.unpacked_length == 0:
            raise ValueError(f"page {page_index} has zero length")
        if page.unpacked_offset + page.unpacked_length > len(block):
            raise ValueError(f"page {page_index} exceeds its text block")
        block[page.unpacked_offset:page.unpacked_offset + page.unpacked_length].decode("utf-8")

    title = ""
    author = ""
    language = ""
    metadata = {strings[e.key_string]: strings[e.value_string] for e in meta_entries}
    title = metadata.get("title", "")
    author = metadata.get("author", "")
    language = metadata.get("language", "")
    compression = metadata.get("compression", "")

    return RbkBuildStats(
        output_path=None,
        title=title,
        author=author,
        language=language,
        chapter_count=header.chapter_count,
        page_count=header.page_count,
        block_count=block_header.block_count,
        file_size=header.file_size,
        compression=compression,
        chars_per_line=header.chars_per_line,
        lines_per_page=header.lines_per_page,
    )


def validate_rbk2_file(path: Path) -> RbkBuildStats:
    stats = validate_rbk2_bytes(path.read_bytes())
    stats.output_path = path
    return stats


def convert_epub_to_rbk2(
    input_epub: Path,
    output_path: Path | None = None,
    options: RbkBuildOptions | None = None,
    *,
    verify: bool = True,
) -> RbkBuildStats:
    if not input_epub.is_file():
        raise ValueError(f"input EPUB file does not exist: {input_epub}")

    output_path = output_path or input_epub.with_suffix(".rbk2")
    if input_epub.resolve() == output_path.resolve():
        raise ValueError("output path must be different from input EPUB path")

    epub = parse_epub(input_epub)
    return write_rbk2(epub, output_path, options, verify=verify)


def _write_debug_text(epub: EpubExtract, output_path: Path) -> None:
    output_path = output_path.expanduser()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8") as f:
        for chapter in epub.chapters:
            f.write(chapter.title + "\n\n")
            f.write(chapter.text + "\n\n")


def main() -> int:
    parser = argparse.ArgumentParser(description="Convert an EPUB file to RBK2 format")
    parser.add_argument("input_epub", type=Path, help="input EPUB file")
    parser.add_argument("-o", "--output", type=Path, help="output RBK2 file; defaults to input name with .rbk2")
    parser.add_argument("--screen-width", type=int, default=DEFAULT_SCREEN_WIDTH_PX, help="target screen width in pixels")
    parser.add_argument("--screen-height", type=int, default=DEFAULT_SCREEN_HEIGHT_PX, help="target screen height in pixels")
    parser.add_argument("--font-width", type=int, default=DEFAULT_FONT_WIDTH_PX, help="monospace font cell width in pixels")
    parser.add_argument("--font-height", type=int, default=DEFAULT_FONT_HEIGHT_PX, help="monospace font cell height in pixels")
    parser.add_argument("--chars-per-line", type=int, help="override derived characters per line")
    parser.add_argument("--lines-per-page", type=int, help="override derived lines per page")
    parser.add_argument("--block-size", type=int, default=DEFAULT_TEXT_BLOCK_UNPACKED_LIMIT, help="preferred uncompressed text block size in bytes")
    parser.add_argument(
        "--compression",
        choices=["auto", "none", "lz4", "zlib", "heatshrink"],
        default="auto",
        help="per-text-block compression; auto prefers lz4 when installed",
    )
    parser.add_argument("--no-verify", action="store_true", help="skip post-write RBK2 validation")
    parser.add_argument("--dump-text", type=Path, help="also write extracted text for debugging")
    args = parser.parse_args()

    try:
        options = RbkBuildOptions(
            screen_width_px=args.screen_width,
            screen_height_px=args.screen_height,
            font_width_px=args.font_width,
            font_height_px=args.font_height,
            chars_per_line=args.chars_per_line,
            lines_per_page=args.lines_per_page,
            text_block_unpacked_limit=args.block_size,
            compression=_compression_from_cli(args.compression),
        )

        if not args.input_epub.is_file():
            raise ValueError(f"input EPUB file does not exist: {args.input_epub}")

        output = args.output or args.input_epub.with_suffix(".rbk2")
        if args.input_epub.resolve() == output.resolve():
            raise ValueError("output path must be different from input EPUB path")

        epub = parse_epub(args.input_epub)
        if not epub.chapters:
            raise ValueError("EPUB contains no readable chapters")

        stats = write_rbk2(epub, output, options, verify=not args.no_verify)

        if args.dump_text is not None:
            _write_debug_text(epub, args.dump_text)

    except Exception as e:
        _error(str(e))
        return 1

    print(f"wrote: {stats.output_path}")
    print(f"title: {stats.title}")
    print(f"author: {stats.author}")
    print(f"language: {stats.language}")
    print(f"chapters: {stats.chapter_count}")
    print(f"pages: {stats.page_count}")
    print(f"blocks: {stats.block_count}")
    print(f"layout: {stats.chars_per_line} chars/line, {stats.lines_per_page} lines/page")
    print(f"compression: {stats.compression}")
    print(f"bytes: {stats.file_size}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
