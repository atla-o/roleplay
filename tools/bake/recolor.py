#!/usr/bin/env python3
"""Rebake the colour of the three 2 m squares from Sentinel-2 cloudless 2016.

Only the 2016 EOX mosaic is CC BY 4.0. Every output pixel is a post of the
square's own grid (row 0 is maximum Y, column 0 is minimum X), projected to
latitude and longitude and sampled from the zoom 15 Web Mercator tiles, so
the colour sits on the same grid as the heights.

Needs numpy, pillow and pyproj.
"""

from __future__ import annotations

import io
import math
import sys
import urllib.request
from pathlib import Path

import numpy as np
from PIL import Image
from pyproj import Transformer

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "godot" / "data"
EOX = "https://tiles.maps.eox.at/wmts/1.0.0/s2cloudless_3857/default/GoogleMapsCompatible/{z}/{y}/{x}.jpg"
UA = {"User-Agent": "roleplay-recolor/1.0"}
ZOOM = 15
SPAN = 3998.0  # 2000 posts at 2 m

# name, epsg, (xmin, ymin) of the square, output size
SQUARES = {
    # ArcticDEM tile corner from ATTRIBUTION.md.
    "basin": (3413, None, (-1_116_740.0, -1_136_008.0), 1024),
    # Centred windows from regions.py.
    "europe": (32633, (78.04862, 13.6441), None, 1024),
    "russia": (32642, (70.49304, 67.91264), None, 1024),
}

_cache: dict[tuple[int, int], np.ndarray] = {}


def tile(x: int, y: int) -> np.ndarray:
    key = (x, y)
    if key not in _cache:
        url = EOX.format(z=ZOOM, x=x, y=y)
        for _ in range(3):
            try:
                req = urllib.request.Request(url, headers=UA)
                with urllib.request.urlopen(req, timeout=40) as resp:
                    _cache[key] = np.asarray(Image.open(io.BytesIO(resp.read())).convert("RGB"))
                break
            except Exception:
                continue
        else:
            _cache[key] = np.full((256, 256, 3), (40, 48, 42), np.uint8)
    return _cache[key]


def bake(name: str) -> None:
    epsg, centre, corner, size = SQUARES[name]
    to_ll = Transformer.from_crs(epsg, 4326, always_xy=True)
    if corner is None:
        cx, cy = Transformer.from_crs(4326, epsg, always_xy=True).transform(centre[1], centre[0])
        xmin, ymin = cx - SPAN / 2, cy - SPAN / 2
    else:
        xmin, ymin = corner
    u = (np.arange(size) + 0.5) / size
    gx, gy = np.meshgrid(xmin + u * SPAN, ymin + SPAN - u * SPAN)
    lon, lat = to_ll.transform(gx, gy)
    n = 2 ** ZOOM * 256
    px = (lon + 180.0) / 360.0 * n
    lat_r = np.radians(lat)
    py = (1.0 - np.log(np.tan(lat_r) + 1.0 / np.cos(lat_r)) / math.pi) / 2.0 * n
    out = np.zeros((size, size, 3), np.float32)
    x0, y0 = np.floor(px).astype(np.int64), np.floor(py).astype(np.int64)
    fx, fy = (px - x0)[..., None], (py - y0)[..., None]

    def at(xx: np.ndarray, yy: np.ndarray) -> np.ndarray:
        res = np.zeros(xx.shape + (3,), np.float32)
        tx, ty = xx // 256, yy // 256
        for key in set(zip(tx.ravel().tolist(), ty.ravel().tolist())):
            m = (tx == key[0]) & (ty == key[1])
            res[m] = tile(*key)[yy[m] % 256, xx[m] % 256]
        return res

    out = (at(x0, y0) * (1 - fx) * (1 - fy) + at(x0 + 1, y0) * fx * (1 - fy)
           + at(x0, y0 + 1) * (1 - fx) * fy + at(x0 + 1, y0 + 1) * fx * fy)
    img = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGB")
    img.save(OUT / f"{name}_color.jpg", quality=85)
    print(f"{name}: {len(_cache)} tiles, lat {lat.min():.4f}..{lat.max():.4f} lon {lon.min():.4f}..{lon.max():.4f}", flush=True)


if __name__ == "__main__":
    for name in sys.argv[1:] or SQUARES:
        bake(name)
