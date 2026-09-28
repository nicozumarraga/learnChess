#!/usr/bin/env python3
"""Package the generated PNG icon sizes into a macOS ICNS file."""

from pathlib import Path
import struct
import sys


def chunk(kind: str, image: bytes) -> bytes:
    return kind.encode("ascii") + struct.pack(">I", len(image) + 8) + image


iconset = Path(sys.argv[1])
output = Path(sys.argv[2])
sizes = {
    "icp4": "icon_16x16.png",
    "icp5": "icon_32x32.png",
    "icp6": "icon_32x32@2x.png",
    "ic07": "icon_128x128.png",
    "ic08": "icon_256x256.png",
    "ic09": "icon_512x512.png",
    "ic10": "icon_512x512@2x.png",
    "ic11": "icon_16x16@2x.png",
    "ic12": "icon_32x32@2x.png",
    "ic13": "icon_128x128@2x.png",
    "ic14": "icon_256x256@2x.png",
}
body = b"".join(chunk(kind, (iconset / name).read_bytes()) for kind, name in sizes.items())
output.write_bytes(b"icns" + struct.pack(">I", len(body) + 8) + body)
