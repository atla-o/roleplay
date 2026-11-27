#!/usr/bin/env python3
"""Bake hemi-octahedral impostor atlases for the spruce and fir crowns.

Each cell is the tree as seen from the octahedral direction at that cell.
The shader in godot/shaders/impostor.gdshader uses the same mapping.
"""

import math
import struct
import zlib
from pathlib import Path

COLS = 8
ROWS = 4
CELL = 32
WIDTH = COLS * CELL
HEIGHT = ROWS * CELL
# Quad in the engine is x in [-1.7, 1.7], y in [0, 7.6].
X0, X1 = -1.7, 1.7
Y0, Y1 = 0.0, 7.6


def clamp(v, a, b):
    return max(a, min(b, v))


def normalize(v):
    l = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]) or 1.0
    return (v[0] / l, v[1] / l, v[2] / l)


def cross(a, b):
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def oct_decode(u, v):
    # u, v in 0..1. Same diamond as hemi_oct() in the impostor shader.
    x = u * 2.0 - 1.0
    z = v * 2.0 - 1.0
    y = 1.0 - abs(x) - abs(z)
    if y < 0.0:
        ox = x
        x = (1.0 - abs(z)) * (1.0 if ox >= 0.0 else -1.0)
        z = (1.0 - abs(ox)) * (1.0 if z >= 0.0 else -1.0)
        y = -y
    return normalize((x, y, z))


def add_cone(tris, y0, y1, r0, r1, color, sides=8):
    for i in range(sides):
        a0 = math.tau * i / sides
        a1 = math.tau * (i + 1) / sides
        b0 = (math.cos(a0) * r0, y0, math.sin(a0) * r0)
        b1 = (math.cos(a1) * r0, y0, math.sin(a1) * r0)
        t0 = (math.cos(a0) * r1, y1, math.sin(a0) * r1)
        t1 = (math.cos(a1) * r1, y1, math.sin(a1) * r1)
        tris.append((b0, t0, b1, color))
        tris.append((b1, t0, t1, color))


def spruce():
    tris = []
    bark = (92, 58, 32)
    add_cone(tris, 0.0, 1.2, 0.12, 0.05, bark, 6)
    for i in range(8):
        t = i / 7.0
        y0 = 0.7 + t * 6.2
        rad = 1.15 * (1.0 - t) + 0.08 * t
        green = (
            int(28 + 40 * t),
            int(70 + 50 * t),
            int(32 + 18 * t),
        )
        add_cone(tris, y0, y0 + (1.35 * (1.0 - t) + 0.7 * t), rad, rad * 0.12, green, 8)
    return tris


def fir():
    tris = []
    bark = (102, 64, 36)
    add_cone(tris, 0.0, 1.1, 0.16, 0.07, bark, 6)
    for i in range(6):
        t = i / 5.0
        y0 = 0.6 + t * 5.4
        rad = 1.55 * (1.0 - t) + 0.16 * t
        green = (
            int(24 + 30 * t),
            int(58 + 40 * t),
            int(28 + 16 * t),
        )
        add_cone(tris, y0, y0 + (1.7 * (1.0 - t) + 0.9 * t), rad, rad * 0.2, green, 8)
    return tris


def raster(tris, direction):
    forward = (-direction[0], -direction[1], -direction[2])
    up_ref = (0.0, 1.0, 0.0) if abs(direction[1]) < 0.92 else (0.0, 0.0, 1.0)
    right = normalize(cross(forward, up_ref))
    up = normalize(cross(right, forward))
    eye = (direction[0] * 30.0, direction[1] * 30.0, direction[2] * 30.0)
    color = [0] * (CELL * CELL * 4)
    depth = [1e9] * (CELL * CELL)

    def project(p):
        rel = (p[0] - eye[0], p[1] - eye[1], p[2] - eye[2])
        x = dot(rel, right)
        y = dot(rel, up)
        z = dot(rel, forward)
        px = (x - X0) / (X1 - X0) * (CELL - 1)
        py = (y - Y0) / (Y1 - Y0) * (CELL - 1)
        return px, py, z

    for a, b, c, rgb in tris:
        pa, pb, pc = project(a), project(b), project(c)
        minx = int(clamp(math.floor(min(pa[0], pb[0], pc[0])), 0, CELL - 1))
        maxx = int(clamp(math.ceil(max(pa[0], pb[0], pc[0])), 0, CELL - 1))
        miny = int(clamp(math.floor(min(pa[1], pb[1], pc[1])), 0, CELL - 1))
        maxy = int(clamp(math.ceil(max(pa[1], pb[1], pc[1])), 0, CELL - 1))
        den = (pb[1] - pc[1]) * (pa[0] - pc[0]) + (pc[0] - pb[0]) * (pa[1] - pc[1])
        if abs(den) < 1e-8:
            continue
        for y in range(miny, maxy + 1):
            for x in range(minx, maxx + 1):
                w0 = ((pb[1] - pc[1]) * (x - pc[0]) + (pc[0] - pb[0]) * (y - pc[1])) / den
                w1 = ((pc[1] - pa[1]) * (x - pc[0]) + (pa[0] - pc[0]) * (y - pc[1])) / den
                w2 = 1.0 - w0 - w1
                if w0 < -0.001 or w1 < -0.001 or w2 < -0.001:
                    continue
                z = w0 * pa[2] + w1 * pb[2] + w2 * pc[2]
                idx = y * CELL + x
                if z < depth[idx]:
                    depth[idx] = z
                    o = idx * 4
                    shade = 0.55 + 0.45 * clamp(w0, 0.0, 1.0)
                    color[o] = int(rgb[0] * shade)
                    color[o + 1] = int(rgb[1] * shade)
                    color[o + 2] = int(rgb[2] * shade)
                    color[o + 3] = 255
    return color


def write_png(path, rgba):
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    raw = bytearray()
    stride = WIDTH * 4
    for row in range(HEIGHT - 1, -1, -1):
        raw.append(0)
        raw.extend(rgba[row * stride:(row + 1) * stride])
    ihdr = struct.pack(">IIBBBBB", WIDTH, HEIGHT, 8, 6, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")
    path.write_bytes(png)


def bake(tris, path):
    atlas = bytearray(WIDTH * HEIGHT * 4)
    for iy in range(ROWS):
        for ix in range(COLS):
            u = (ix + 0.5) / COLS
            v = (iy + 0.5) / ROWS
            cell = raster(tris, oct_decode(u, v))
            for y in range(CELL):
                dy = iy * CELL + y
                src = y * CELL * 4
                dst = (dy * WIDTH + ix * CELL) * 4
                atlas[dst:dst + CELL * 4] = cell[src:src + CELL * 4]
    write_png(path, atlas)
    print(path, path.stat().st_size)


def main():
    root = Path(__file__).resolve().parents[2] / "godot" / "assets" / "textures"
    bake(spruce(), root / "spruce_octa.png")
    bake(fir(), root / "fir_octa.png")


if __name__ == "__main__":
    main()
