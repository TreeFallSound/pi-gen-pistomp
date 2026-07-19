#!/usr/bin/env python3
"""Convert a 320x240 PNG into the raw big-endian RGB565 framebuffer lcd-splash reads.

Stdlib only (zlib + struct) so the build container needs no extra packages.
Handles 8-bit non-interlaced PNGs: truecolour (with or without alpha), greyscale,
and palette.
"""
import struct
import sys
import zlib

LCD_W = 320
LCD_H = 240


def read_png(path):
    """Return (width, height, rows) where each row is a bytes of RGB triples."""
    with open(path, "rb") as f:
        data = f.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path}: not a PNG")

    width = height = bit_depth = colour_type = None
    palette = None
    idat = bytearray()
    pos = 8
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        ctype = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length  # length + type + data + crc

        if ctype == b"IHDR":
            width, height, bit_depth, colour_type, _, _, interlace = struct.unpack(">IIBBBBB", body)
            if bit_depth != 8:
                raise ValueError(f"{path}: only 8-bit PNGs supported (got {bit_depth})")
            if colour_type not in (0, 2, 3, 6):
                raise ValueError(f"{path}: unsupported colour type {colour_type}")
            if interlace:
                raise ValueError(f"{path}: interlaced PNGs not supported")
        elif ctype == b"PLTE":
            palette = body
        elif ctype == b"IDAT":
            idat += body
        elif ctype == b"IEND":
            break

    channels = {0: 1, 2: 3, 3: 1, 6: 4}[colour_type]
    if colour_type == 3 and palette is None:
        raise ValueError(f"{path}: palette PNG without a PLTE chunk")
    raw = zlib.decompress(bytes(idat))
    stride = width * channels

    rows = []
    prev = bytearray(stride)
    pos = 0
    for _ in range(height):
        filt = raw[pos]
        line = bytearray(raw[pos + 1:pos + 1 + stride])
        pos += 1 + stride
        for i in range(stride):
            a = line[i - channels] if i >= channels else 0
            b = prev[i]
            c = prev[i - channels] if i >= channels else 0
            x = line[i]
            if filt == 0:
                pass
            elif filt == 1:
                x += a
            elif filt == 2:
                x += b
            elif filt == 3:
                x += (a + b) // 2
            elif filt == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                x += a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
            else:
                raise ValueError(f"{path}: unknown filter type {filt}")
            line[i] = x & 0xFF
        prev = line
        if colour_type == 2:
            rows.append(bytes(line))
        elif colour_type == 6:
            rows.append(bytes(b for i in range(0, stride, 4) for b in line[i:i + 3]))
        elif colour_type == 0:
            rows.append(bytes(v for v in line for _ in range(3)))
        else:  # palette
            rows.append(bytes(b for v in line for b in palette[v * 3:v * 3 + 3]))
    return width, height, rows


def to_rgb565_be(rows):
    out = bytearray()
    for row in rows:
        for i in range(0, len(row), 3):
            r, g, b = row[i], row[i + 1], row[i + 2]
            v = ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3)
            out += struct.pack(">H", v)
    return bytes(out)


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: png2rgb565.py <in.png> <out.rgb565>")
    src, dst = sys.argv[1], sys.argv[2]

    width, height, rows = read_png(src)
    if (width, height) != (LCD_W, LCD_H):
        sys.exit(f"{src}: expected {LCD_W}x{LCD_H}, got {width}x{height}")

    blob = to_rgb565_be(rows)
    expected = LCD_W * LCD_H * 2
    if len(blob) != expected:
        sys.exit(f"{src}: produced {len(blob)} bytes, expected {expected}")

    with open(dst, "wb") as f:
        f.write(blob)


if __name__ == "__main__":
    main()
