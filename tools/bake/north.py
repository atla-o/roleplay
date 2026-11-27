#!/usr/bin/env python3
"""Bake a coarse polar-stereographic north for the map and far teleports.

Everything from 45°N to the pole. The projection is spherical polar
stereographic, tangent at the north pole: +X toward 90°E, +Y toward 180°.
Elevation is Mapzen Terrarium (zoom 4). Color is Sentinel-2 cloudless from
EOX, the same source as the measured tiles. Above the Web Mercator cutoff
the pole is ocean, which it is.
"""

from __future__ import annotations

import io
import json
import math
import urllib.request
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "godot" / "data"
R = 6_378_137.0
LAT_LIMIT = 45.0
POSTS = 640
ZOOM = 4
TERRARIUM = "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png"
EOX = "https://tiles.maps.eox.at/wmts/1.0.0/s2cloudless_3857/default/GoogleMapsCompatible/{z}/{y}/{x}.jpg"
UA = {"User-Agent": "roleplay-north-bake/1.0"}


def rho_of(lat_deg: float) -> float:
    lat = math.radians(lat_deg)
    return 2.0 * R * math.tan(math.pi / 4.0 - lat / 2.0)


HALF = rho_of(LAT_LIMIT)


def forward(lat: float, lon: float) -> tuple[float, float]:
    rho = rho_of(lat)
    lon_r = math.radians(lon)
    return rho * math.sin(lon_r), -rho * math.cos(lon_r)


def inverse(x: float, y: float) -> tuple[float, float]:
    rho = math.hypot(x, y)
    lon = math.degrees(math.atan2(x, -y))
    lat = math.degrees(math.pi / 2.0 - 2.0 * math.atan(rho / (2.0 * R)))
    return lat, lon


def mercator_pixel(lat: float, lon: float, zoom: int) -> tuple[float, float]:
    n = 2**zoom * 256
    lat = max(min(lat, 85.05112878), -85.05112878)
    x = (lon + 180.0) / 360.0 * n
    lat_r = math.radians(lat)
    y = (1.0 - math.log(math.tan(lat_r) + 1.0 / math.cos(lat_r)) / math.pi) / 2.0 * n
    return x, y


def utm(lat: float, lon: float, zone: int) -> tuple[float, float]:
    """WGS84 UTM. Used to check the island frame, not the polar grid."""
    a = 6378137.0
    f = 1 / 298.257223563
    b = a * (1 - f)
    e2 = (a * a - b * b) / (a * a)
    ep2 = e2 / (1 - e2)
    k0 = 0.9996
    lat_r = math.radians(lat)
    lon_r = math.radians(lon)
    lon0 = math.radians(zone * 6 - 183)
    N = a / math.sqrt(1 - e2 * math.sin(lat_r) ** 2)
    T = math.tan(lat_r) ** 2
    C = ep2 * math.cos(lat_r) ** 2
    A = math.cos(lat_r) * (lon_r - lon0)
    M = a * (
        (1 - e2 / 4 - 3 * e2**2 / 64 - 5 * e2**3 / 256) * lat_r
        - (3 * e2 / 8 + 3 * e2**2 / 32 + 45 * e2**3 / 1024) * math.sin(2 * lat_r)
        + (15 * e2**2 / 256 + 45 * e2**3 / 1024) * math.sin(4 * lat_r)
        - (35 * e2**3 / 3072) * math.sin(6 * lat_r)
    )
    east = k0 * N * (A + (1 - T + C) * A**3 / 6 + (5 - 18 * T + T * T + 72 * C - 58 * ep2) * A**5 / 120) + 500000.0
    north = k0 * (M + N * math.tan(lat_r) * (A * A / 2 + (5 - T + 9 * C + 4 * C * C) * A**4 / 24 + (61 - 58 * T + T * T + 600 * C - 330 * ep2) * A**6 / 720))
    if lat < 0:
        north += 10000000.0
    return east, north


class Tiles:
    def __init__(self) -> None:
        self.cache: dict[tuple, Image.Image] = {}

    def get(self, url: str, key: tuple) -> Image.Image | None:
        if key in self.cache:
            return self.cache[key]
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=40) as resp:
                img = Image.open(io.BytesIO(resp.read())).convert("RGB")
        except Exception as exc:
            print(f"  miss {url} ({exc})", flush=True)
            img = None
        self.cache[key] = img
        return img

    def sample(self, pattern: str, zoom: int, px: float, py: float) -> tuple[int, int, int] | None:
        n = 2**zoom
        if px < 0 or py < 0 or px >= n * 256 or py >= n * 256:
            return None
        tx, ty = int(px // 256), int(py // 256)
        img = self.get(pattern.format(z=zoom, x=tx, y=ty), (pattern, zoom, tx, ty))
        if img is None:
            return None
        ix = int(px) % 256
        iy = int(py) % 256
        return img.getpixel((ix, iy))


def main() -> None:
    tiles = Tiles()
    elev = np.full((POSTS, POSTS), -80.0, dtype=np.float32)
    color = np.zeros((POSTS, POSTS, 3), dtype=np.uint8)
    color[:] = (18, 42, 64)
    span = 2.0 * HALF
    step = span / (POSTS - 1)
    print(f"half {HALF:.1f} m  step {step:.1f} m", flush=True)
    for row in range(POSTS):
        # Image row 0 is the top of the map, maximum projected Y.
        y = HALF - row * step
        for col in range(POSTS):
            x = -HALF + col * step
            lat, lon = inverse(x, y)
            if lat < LAT_LIMIT:
                continue
            if lat > 85.0:
                elev[row, col] = -20.0
                color[row, col] = (150, 168, 176)
                continue
            px, py = mercator_pixel(lat, lon, ZOOM)
            sample = tiles.sample(TERRARIUM, ZOOM, px, py)
            if sample is not None:
                r, g, b = sample
                elev[row, col] = (r * 256 + g + b / 256.0) - 32768.0
            paint = tiles.sample(EOX, ZOOM, px, py)
            if paint is not None:
                color[row, col] = paint
        if row % 80 == 0:
            print(f"  row {row}", flush=True)
    hmin = float(elev.min())
    hmax = float(elev.max())
    span_h = max(hmax - hmin, 0.001)
    # South-first, matching the other height tiles: file row 0 is minimum Y.
    south = np.flipud(elev)
    u = np.round(np.clip((south - hmin) / span_h, 0, 1) * 65535).astype("<u2")
    (OUT / "north.u16").write_bytes(np.ascontiguousarray(u).tobytes())
    Image.fromarray(color, "RGB").save(OUT / "north_color.jpg", quality=80)
    meta = {
        "posts": POSTS,
        "half_m": HALF,
        "step_m": step,
        "lat_limit": LAT_LIMIT,
        "water": 0.0,
        "hmin": hmin,
        "hmax": hmax,
        "heights": "north.u16",
        "color": "north_color.jpg",
        "image_row0": "max_y",
        "heights_row0": "min_y",
        "projection": "polar stereographic, sphere 6378137 m, tangent at the north pole",
    }
    (OUT / "north.json").write_text(json.dumps(meta, indent=2) + "\n")
    print("tiles", len(tiles.cache), "h", hmin, hmax, flush=True)
    # A few known places, image row/col.
    for name, lat, lon in (
        ("island", 51.4332, -69.0892),
        ("svalbard", 78.04862, 13.6441),
        ("yamal", 70.49304, 67.91264),
        ("basin", 75.3971, -89.5091),
        ("pole", 89.0, 0.0),
        ("reykjavik", 64.15, -21.94),
    ):
        x, y = forward(lat, lon)
        col = int(round((x + HALF) / step))
        row = int(round((HALF - y) / step))
        print(f"  {name:10} elev {elev[row, col]:7.1f}  rgb {tuple(int(v) for v in color[row, col])}", flush=True)
    # Island spawn in UTM zone 19, local origin of the 2 m tile.
    east, north = utm(51.4332, -69.0892, 19)
    print(f"utm check island latlon -> {east:.1f} E {north:.1f} N", flush=True)


if __name__ == "__main__":
    main()
