#!/usr/bin/env python3
"""One-shot import of the designer's boot mockups into debpkgs/lcd-splash/images/.

The mockups carry a baked-in caption in the bottom band; lcd-splash draws its own
text there, so the band (y >= MSG_REGION_TOP) is blanked to black. Aborts if the
first row of the band is not already background — that would mean the band starts
inside artwork and we would be clipping it.
"""
import os
import struct
import sys
import zlib

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "debpkgs", "lcd-splash", "src"))
from png2rgb565 import read_png  # noqa: E402

MSG_REGION_TOP = 160  # must match lcd-splash.c
INK_THRESHOLD = 30    # sum of r+g+b above which a pixel counts as non-background

# designer's filename -> the boot stage it belongs to
MAPPING = {
    "PiStomp start 1.png": "splash-start.png",
    "PiStomp start 2.png": "splash-jack.png",
    "PiStomp start 3.png": "splash-mod-host.png",
    "PiStomp start 4.png": "splash-mod-ui.png",
    "PiStomp start 5.png": "splash-pedalboard.png",
    "PiStomp boot 1.png": "splash-firstboot.png",
    "PiStomp boot 2.png": "splash-wifi.png",
    "PiStomp boot 3.png": "splash-expandfs.png",
    "PiStomp boot 4.png": "splash-reboot.png",
    "PiStomp shutdown 1.png": "splash-shutdown.png",
    "PiStomp shutdown 2.png": "splash-poweroff.png",
}


def write_png(path, width, height, rows):
    raw = b"".join(b"\x00" + row for row in rows)
    def chunk(ctype, body):
        c = ctype + body
        return struct.pack(">I", len(body)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        f.write(chunk(b"IEND", b""))


def main():
    src_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/Downloads")
    out_dir = os.path.join(os.path.dirname(__file__), "..", "debpkgs", "lcd-splash", "images")
    os.makedirs(out_dir, exist_ok=True)

    for src_name, out_name in MAPPING.items():
        src = os.path.join(src_dir, src_name)
        width, height, rows = read_png(src)

        boundary = rows[MSG_REGION_TOP]
        ink = sum(1 for i in range(0, len(boundary), 3) if sum(boundary[i:i + 3]) > INK_THRESHOLD)
        if ink:
            sys.exit(f"{src_name}: row {MSG_REGION_TOP} has {ink} non-background pixels — "
                     f"blanking from there would clip artwork")

        blank = bytes(width * 3)
        rows = rows[:MSG_REGION_TOP] + [blank] * (height - MSG_REGION_TOP)
        write_png(os.path.join(out_dir, out_name), width, height, rows)
        print(f"{src_name} -> {out_name}")


if __name__ == "__main__":
    main()
