#!/usr/bin/env python3
"""
Simple BDF -> YFNT converter.
YFNT header (little-endian):
4 bytes: 'YFNT'
1 byte: version (1)
1 byte: reserved
2 bytes: width (u16 LE)
2 bytes: height (u16 LE)
4 bytes: first_codepoint (u32 LE)
2 bytes: glyph_count (u16 LE)
2 bytes: stride_bytes (u16 LE) (0 means auto)
followed by glyph_count * (stride_bytes * height) bytes of bitmap data (MSB-first per row)

This script expects a reasonably standard BDF with BITMAP rows of hex per glyph.
It emits fixed-width glyphs using the font bounding box.
"""
import argparse
import struct


def parse_bdf(path):
    glyphs = {}
    bbx = None
    with open(path, "r", encoding="latin1") as f:
        lines = [l.rstrip('\n') for l in f]

    i = 0
    num_lines = len(lines)
    while i < num_lines:
        line = lines[i]
        if line.startswith("FONTBOUNDINGBOX"):
            parts = line.split()
            # width height xoff yoff
            bbx = (int(parts[1]), int(parts[2]), int(parts[3]), int(parts[4]))
            i += 1
            continue

        if line.startswith("STARTCHAR"):
            i += 1
            encoding = None
            bitmap = []
            while i < num_lines:
                l = lines[i]
                if l.startswith("ENCODING"):
                    parts = l.split()
                    encoding = int(parts[1])
                elif l == "BITMAP":
                    i += 1
                    while i < num_lines and not lines[i].startswith("ENDCHAR"):
                        bitmap.append(lines[i])
                        i += 1
                    # ENDCHAR will be consumed by outer loop increment
                    continue
                elif l.startswith("ENDCHAR"):
                    break
                i += 1

            if encoding is not None:
                glyphs[encoding] = bitmap
        else:
            i += 1
    return bbx, glyphs


def pack_glyph_rows(rows, width, stride_bytes):
    # rows: list of hex strings (without 0x), top-to-bottom
    out = bytearray()
    bytes_per_row = stride_bytes
    for r in rows:
        if r == "":
            row_val = 0
        else:
            row_val = int(r, 16)
        # row_val holds bits with MSB being leftmost; we need to emit bytes MSB-first
        bits = []
        for bit in range(width):
            shift = (width - 1 - bit)
            b = (row_val >> shift) & 1
            bits.append(b)
        # pack into bytes
        for byte_i in range(bytes_per_row):
            byte_val = 0
            for bit_in_byte in range(8):
                bit_index = byte_i * 8 + bit_in_byte
                if bit_index < len(bits):
                    byte_val = (byte_val << 1) | bits[bit_index]
                else:
                    byte_val = (byte_val << 1)
            out.append(byte_val)
    return out


def main():
    p = argparse.ArgumentParser(description="Convert BDF to YFNT binary")
    p.add_argument("bdf")
    p.add_argument("out")
    p.add_argument("--first", type=int, default=32)
    p.add_argument("--last", type=int, default=126)
    args = p.parse_args()

    bbx, glyphs = parse_bdf(args.bdf)
    if bbx is None:
        raise SystemExit("BDF missing FONTBOUNDINGBOX")
    width, height, xoff, yoff = bbx

    first = args.first
    last = args.last
    glyph_count = last - first + 1

    stride = (width + 7) // 8

    payload = bytearray()
    for code in range(first, last + 1):
        rows = glyphs.get(code, None)
        if rows is None:
            # blank rows
            rows = ["0"] * height
        # BDF rows may be fewer/greater than bbx height; normalize top/bottom
        if len(rows) < height:
            # pad top with zeros so baseline aligns roughly
            pad_top = height - len(rows)
            rows = (["0"] * pad_top) + rows
        elif len(rows) > height:
            rows = rows[-height:]
        packed = pack_glyph_rows(rows, width, stride)
        payload.extend(packed)

    # header
    header = bytearray()
    header.extend(b"YFNT")
    header.append(1)  # version
    header.append(0)  # reserved
    header.extend(struct.pack("<H", width))
    header.extend(struct.pack("<H", height))
    header.extend(struct.pack("<I", first))
    header.extend(struct.pack("<H", glyph_count))
    header.extend(struct.pack("<H", stride))

    with open(args.out, "wb") as f:
        f.write(header)
        f.write(payload)

    print(f"Wrote {args.out}: {glyph_count} glyphs, {width}x{height}, stride={stride}")

if __name__ == '__main__':
    main()
