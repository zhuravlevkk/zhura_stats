#!/usr/bin/env python3
"""Generate centered white ref-arrow TGAs (vertex-color tintable) for ZhuraStats."""

from __future__ import annotations

import struct
from pathlib import Path

SIZE = 32
MEDIA_DIR = Path(__file__).resolve().parent.parent / "Media"


def point_in_triangle(px: float, py: float, ax: float, ay: float, bx: float, by: float, cx: float, cy: float) -> bool:
    def sign(p1x, p1y, p2x, p2y, p3x, p3y):
        return (p1x - p3x) * (p2y - p3y) - (p2x - p3x) * (p1y - p3y)

    d1 = sign(px, py, ax, ay, bx, by)
    d2 = sign(px, py, bx, by, cx, cy)
    d3 = sign(px, py, cx, cy, ax, ay)
    has_neg = (d1 < 0) or (d2 < 0) or (d3 < 0)
    has_pos = (d1 > 0) or (d2 > 0) or (d3 > 0)
    return not (has_neg and has_pos)


def raster_triangle(size: int, up: bool) -> list[tuple[int, int, int, int]]:
    cx = (size - 1) / 2.0
    margin = 5
    tip_y = margin if up else size - 1 - margin
    base_y = size - 1 - margin if up else margin
    half_base = size * 0.36
    ax, ay = cx, tip_y
    bx, by = cx - half_base, base_y
    cx2, cy2 = cx + half_base, base_y

    pixels: list[tuple[int, int, int, int]] = []
    for y in range(size):
        for x in range(size):
            if point_in_triangle(x + 0.5, y + 0.5, ax, ay, bx, by, cx2, cy2):
                pixels.append((255, 255, 255, 255))
            else:
                pixels.append((0, 0, 0, 0))
    return pixels


def write_tga_rgba(path: Path, size: int, rgba: list[tuple[int, int, int, int]]) -> None:
    # Uncompressed 32-bit BGRA TGA (type 2), origin top-left.
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, size, size, 32, 0x28)
    rows = []
    for y in range(size - 1, -1, -1):
        row = b""
        for x in range(size):
            r, g, b, a = rgba[y * size + x]
            row += struct.pack("BBBB", b, g, r, a)
        rows.append(row)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(header + b"".join(rows))


def main() -> None:
    write_tga_rgba(MEDIA_DIR / "RefArrowUp.tga", SIZE, raster_triangle(SIZE, True))
    write_tga_rgba(MEDIA_DIR / "RefArrowDown.tga", SIZE, raster_triangle(SIZE, False))
    print(f"Wrote {MEDIA_DIR / 'RefArrowUp.tga'}")
    print(f"Wrote {MEDIA_DIR / 'RefArrowDown.tga'}")


if __name__ == "__main__":
    main()
