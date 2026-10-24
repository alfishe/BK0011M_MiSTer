#!/usr/bin/env python3
"""ppm2png.py in.ppm out.png - a binary PPM (P6) to PNG, no dependencies."""
import struct, sys, zlib
def read_ppm(path):
    d = open(path, "rb").read()
    parts = d.split(maxsplit=4)
    assert parts[0] == b"P6"
    w, h = int(parts[1]), int(parts[2])
    return w, h, parts[4][:w * h * 3]
def write_png(path, w, h, rgb):
    raw = b"".join(b"\0" + rgb[y * w * 3:(y + 1) * w * 3] for y in range(h))
    def chunk(t, b): return struct.pack(">I", len(b)) + t + b + struct.pack(">I", zlib.crc32(t + b) & 0xffffffff)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b"")
    open(path, "wb").write(png)
w, h, rgb = read_ppm(sys.argv[1]); write_png(sys.argv[2], w, h, rgb)
