#!/usr/bin/env python3
"""Bake the Europe and Russia 4 km tiles for the Godot world.

Each tile is ArcticDEM v4.1 at 2 m, with Sentinel-2 cloudless color from EOX.
Row 0 of the float file is the south edge, west to east, matching the Canada tile.
"""

from __future__ import annotations

import io
import json
import math
import os
import urllib.request
from pathlib import Path

import numpy as np
import rasterio
from PIL import Image
from pyproj import Transformer
from rasterio.enums import Resampling
from rasterio.transform import from_origin
from rasterio.warp import reproject

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "godot" / "data"
STAC = "https://stac.pgc.umn.edu/api/v1/search"
COLLECTION = "arcticdem-mosaics-v4.1-2m"
EOX = "https://tiles.maps.eox.at/wmts/1.0.0/s2cloudless-2021_3857/default/GoogleMapsCompatible/{z}/{y}/{x}.jpg"
EOX_FALLBACK = "https://tiles.maps.eox.at/wmts/1.0.0/s2cloudless-2020_3857/default/GoogleMapsCompatible/{z}/{y}/{x}.jpg"

os.environ.setdefault("AWS_NO_SIGN_REQUEST", "YES")
os.environ.setdefault("GDAL_DISABLE_READDIR_ON_OPEN", "EMPTY_DIR")
os.environ.setdefault("CPL_VSIL_CURL_USE_HEAD", "NO")
os.environ.setdefault("GDAL_HTTP_TIMEOUT", "180")


def log(msg: str) -> None:
    print(msg, flush=True)


def stac(bbox: list[float]) -> list[dict]:
    body = {"collections": [COLLECTION], "bbox": bbox, "limit": 8}
    req = urllib.request.Request(
        STAC,
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json", "Accept": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=90) as resp:
        return json.loads(resp.read().decode()).get("features", [])


def read_dem(bounds_ll: list[float], epsg: int, xmin: float, ymax: float, posts: int, spacing: float) -> np.ndarray:
    dst_transform = from_origin(xmin - spacing / 2, ymax + spacing / 2, spacing, spacing)
    dst = np.full((posts, posts), np.nan, dtype=np.float32)
    pad = 0.08
    bbox = [bounds_ll[0] - pad, bounds_ll[1] - pad, bounds_ll[2] + pad, bounds_ll[3] + pad]
    env = rasterio.Env(
        AWS_NO_SIGN_REQUEST="YES",
        GDAL_DISABLE_READDIR_ON_OPEN="EMPTY_DIR",
        CPL_VSIL_CURL_USE_HEAD="NO",
        GDAL_HTTP_TIMEOUT="180",
    )
    with env:
        for feature in stac(bbox):
            href = feature.get("assets", {}).get("dem", {}).get("href")
            if not href:
                continue
            log(f"  dem {feature.get('id')}")
            with rasterio.open(href) as src:
                tmp = np.full_like(dst, np.nan)
                reproject(
                    source=rasterio.band(src, 1),
                    destination=tmp,
                    src_transform=src.transform,
                    src_crs=src.crs,
                    src_nodata=src.nodata,
                    dst_transform=dst_transform,
                    dst_crs=f"EPSG:{epsg}",
                    dst_nodata=np.nan,
                    resampling=Resampling.bilinear,
                )
                missing = np.isnan(dst)
                dst[missing] = tmp[missing]
    if np.isnan(dst).any():
        fill = float(np.nanmedian(dst))
        dst = np.where(np.isfinite(dst), dst, fill)
    return dst


def window_at(lat: float, lon: float, epsg: int, half_m: float, spacing: float) -> tuple[np.ndarray, float, float, Transformer]:
    to_utm = Transformer.from_crs(4326, epsg, always_xy=True)
    to_ll = Transformer.from_crs(epsg, 4326, always_xy=True)
    cx, cy = to_utm.transform(lon, lat)
    posts = int(round(half_m * 2 / spacing)) + 1
    xmin = cx - (posts - 1) * spacing / 2
    ymax = cy + (posts - 1) * spacing / 2
    ymin = ymax - (posts - 1) * spacing
    corners = [to_ll.transform(x, y) for x, y in ((xmin, ymin), (xmin + (posts - 1) * spacing, ymax))]
    bounds = [
        min(p[0] for p in corners),
        min(p[1] for p in corners),
        max(p[0] for p in corners),
        max(p[1] for p in corners),
    ]
    log(f"window {posts} posts bounds {bounds}")
    dem = read_dem(bounds, epsg, xmin, ymax, posts, spacing)
    return dem, xmin, ymax, to_ll


def choose(dem: np.ndarray, spacing: float, xmin: float, ymax: float, to_ll: Transformer) -> dict:
    sea = float(np.percentile(dem, 10))
    gy, gx = np.gradient(dem, spacing)
    slope = np.hypot(gx, gy)
    posts = dem.shape[0]
    margin = int(550 / spacing)
    best = None
    for r in range(margin, posts - margin, 4):
        for c in range(margin, posts - margin, 4):
            h = float(dem[r, c])
            if h < sea + 3.0:
                continue
            patch = slope[r - 3 : r + 4, c - 3 : c + 4]
            height = dem[r - 3 : r + 4, c - 3 : c + 4]
            if patch.size == 0 or float(patch.max()) > 0.12:
                continue
            if float(height.max() - height.min()) > 1.4:
                continue
            # Prefer ground that can see the water, so the shore is the boundary.
            near = dem[max(0, r - 80) : r + 81, max(0, c - 80) : c + 81]
            wet = float((near < sea + 1.2).mean())
            score = float(patch.mean()) - wet * 0.02
            if best is None or score < best[0]:
                east = xmin + c * spacing
                north = ymax - r * spacing
                lon, lat = to_ll.transform(east, north)
                godot_x = c * spacing
                godot_z = (posts - 1 - r) * spacing
                best = (score, godot_x, godot_z, h, lat, lon, wet)
    if best is None:
        raise SystemExit("no flat ground above the water")
    return {
        "spawn": [round(best[1], 1), round(best[2], 1)],
        "spawn_h": round(best[3], 2),
        "lat": round(best[4], 5),
        "lon": round(best[5], 5),
        "wet_nearby": round(best[6], 3),
        "hmin": round(float(dem.min()), 3),
        "hmax": round(float(dem.max()), 3),
        "water": round(sea + 0.4, 2),
    }


def deg2num(lat: float, lon: float, zoom: int) -> tuple[int, int]:
    n = 2.0 ** zoom
    x = int((lon + 180.0) / 360.0 * n)
    y = int((1.0 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2.0 * n)
    return x, y


def num2deg(x: int, y: int, zoom: int) -> tuple[float, float]:
    n = 2.0 ** zoom
    lon = x / n * 360.0 - 180.0
    lat = math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * y / n))))
    return lat, lon


def fetch_color(bounds: list[float], posts: int) -> Image.Image:
    zoom = 15
    lon0, lat0, lon1, lat1 = bounds
    x0, y0 = deg2num(lat1, lon0, zoom)
    x1, y1 = deg2num(lat0, lon1, zoom)
    x0, x1 = min(x0, x1), max(x0, x1)
    y0, y1 = min(y0, y1), max(y0, y1)
    tiles = []
    for y in range(y0, y1 + 1):
        row = []
        for x in range(x0, x1 + 1):
            blob = None
            for pattern in (EOX, EOX_FALLBACK):
                url = pattern.format(z=zoom, x=x, y=y)
                try:
                    with urllib.request.urlopen(url, timeout=40) as resp:
                        blob = resp.read()
                    break
                except Exception:
                    continue
            if blob is None:
                row.append(Image.new("RGB", (256, 256), (40, 48, 42)))
            else:
                row.append(Image.open(io.BytesIO(blob)).convert("RGB"))
        tiles.append(row)
    sheet = Image.new("RGB", ((x1 - x0 + 1) * 256, (y1 - y0 + 1) * 256))
    for j, row in enumerate(tiles):
        for i, tile in enumerate(row):
            sheet.paste(tile, (i * 256, j * 256))
    north, west = num2deg(x0, y0, zoom)
    south, east = num2deg(x1 + 1, y1 + 1, zoom)
    # Crop to the tile bounds. Image y grows south.
    def px(lon: float, lat: float) -> tuple[int, int]:
        u = (lon - west) / (east - west)
        v = (north - lat) / (north - south)
        return int(u * sheet.width), int(v * sheet.height)

    left, top = px(lon0, lat1)
    right, bottom = px(lon1, lat0)
    crop = sheet.crop((max(0, left), max(0, top), min(sheet.width, right), min(sheet.height, bottom)))
    crop = crop.resize((posts, posts), Image.Resampling.LANCZOS)
    arr = np.asarray(crop).astype(np.float32)
    mean = float(arr.mean())
    if mean < 48:
        arr = np.clip(arr * (72.0 / max(mean, 1.0)), 0, 255)
        crop = Image.fromarray(arr.astype(np.uint8))
    return crop


def soften_edge(dem: np.ndarray, water: float, spacing: float = 2.0) -> np.ndarray:
    """Drop the outer survey square toward the water along a wandering shore."""
    posts = dem.shape[0]
    span = (posts - 1) * spacing
    cc, rr = np.meshgrid(np.arange(posts), np.arange(posts))
    x = cc * spacing
    z = (posts - 1 - rr) * spacing
    wander = np.sin(x * 0.0028 + z * 0.0011) * 110.0 + np.cos(z * 0.0022 - x * 0.0007) * 80.0
    inset = np.minimum(np.minimum(x, z), np.minimum(span - x, span - z))
    edge = inset + wander * 0.22
    t = np.clip(edge / 420.0, 0.0, 1.0)
    t = t * t * (3.0 - 2.0 * t)
    floor = water - 5.0
    out = dem.copy()
    mask = edge < 420.0
    out[mask] = floor * (1.0 - t[mask]) + dem[mask] * t[mask]
    return out.astype(np.float32)


def bake(name: str, center_lat: float, center_lon: float, epsg: int) -> dict:
    log(f"== {name}")
    dem, xmin, ymax, to_ll = window_at(center_lat, center_lon, epsg, 1999.0, 2.0)
    posts = dem.shape[0]
    ymin = ymax - (posts - 1) * 2.0
    xmax = xmin + (posts - 1) * 2.0
    info = choose(dem, 2.0, xmin, ymax, to_ll)
    dem = soften_edge(dem, info["water"])
    info["hmin"] = round(float(dem.min()), 3)
    info["hmax"] = round(float(dem.max()), 3)
    # South row first, to match the Canada tile.
    south_first = np.flipud(dem).astype("<f4")
    (OUT / f"{name}.f32").write_bytes(south_first.tobytes())
    corners = [to_ll.transform(x, y) for x, y in ((xmin, ymin), (xmax, ymax))]
    bounds = [
        min(p[0] for p in corners),
        min(p[1] for p in corners),
        max(p[0] for p in corners),
        max(p[1] for p in corners),
    ]
    log(f"  color {bounds}")
    color = fetch_color(bounds, 1024)
    color.save(OUT / f"{name}_color.jpg", quality=82)
    info.update({
        "cols": posts,
        "rows": posts,
        "spacing": 2.0,
        "center_lat": center_lat,
        "center_lon": center_lon,
        "epsg": epsg,
    })
    log(f"  {info}")
    return info


def main() -> None:
    europe = bake("europe", 78.04862, 13.6441, 32633)
    russia = bake("russia", 70.49304, 67.91264, 32642)
    meta = Path(__file__).resolve().parent / "regions_bake.json"
    meta.write_text(json.dumps({"europe": europe, "russia": russia}, indent=2))
    log(f"wrote {meta}")


if __name__ == "__main__":
    main()
