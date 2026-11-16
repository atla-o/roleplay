#!/usr/bin/env python3
"""Window Île René-Levasseur for Roleplay.

Playable elevation is the NRCan HRDEM 1 m mosaic DTM (lidar where Quebec
flew it), resampled to a browser grid. A MRDEM-30 window is sampled for the
manifest. Land cover is NRCan 2020. Water is that land-cover water class.
"""

from __future__ import annotations

import json
import math
import struct
import urllib.request
import zlib
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import rasterio
from pyproj import Transformer
from rasterio.enums import Resampling
from rasterio.transform import from_bounds
from rasterio.warp import reproject

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "public" / "data" / "ile"

# Hero box: the annular reservoir and the island, wide enough for the O.
WEST, EAST = -69.25, -68.15
SOUTH, NORTH = 51.00, 51.75
CELL_M = 120.0

HRDEM = "https://canelevation-dem.s3.ca-central-1.amazonaws.com/hrdem-mosaic-1m/9_4-mosaic-1m-dtm.tif"
MRDEM = "https://canelevation-dem.s3.ca-central-1.amazonaws.com/mrdem-30/mrdem-30-dtm.tif"
LAND = "https://datacube-prod-data-public.s3.ca-central-1.amazonaws.com/store/land/landcover/landcover-2020-classification.tif"

# NRCan 2020 Land Cover of Canada class codes.
COVER_NAMES = {
    0: "unclassified",
    1: "temperate or sub-polar needleleaf forest",
    2: "sub-polar taiga needleleaf forest",
    5: "temperate or sub-polar broadleaf deciduous forest",
    6: "mixed forest",
    8: "temperate or sub-polar shrubland",
    10: "temperate or sub-polar grassland",
    14: "wetland",
    15: "cropland",
    16: "barren land",
    17: "urban and built-up",
    18: "water",
    19: "snow and ice",
}
WATER_CLASS = 18


def log(msg: str) -> None:
    print(msg, flush=True)


def grid_shape() -> tuple[int, int, float, float]:
    lat = (SOUTH + NORTH) / 2
    height_m = (NORTH - SOUTH) * 111_320.0
    width_m = (EAST - WEST) * 111_320.0 * math.cos(math.radians(lat))
    cols = int(round(width_m / CELL_M)) + 1
    rows = int(round(height_m / CELL_M)) + 1
    return cols, rows, width_m, height_m


def write_png_rgba(path: Path, samples: np.ndarray) -> None:
    height, width, _ = samples.shape
    raw = np.ascontiguousarray(samples).tobytes()
    stride = width * 4
    rows = bytearray()
    for r in range(height):
        rows.append(0)
        rows.extend(raw[r * stride : (r + 1) * stride])
    compressed = zlib.compress(bytes(rows), 9)

    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", compressed) + chunk(b"IEND", b""))


def write_png_gray(path: Path, samples: np.ndarray) -> None:
    if samples.dtype == np.uint16:
        raw = samples.astype(">u2").tobytes()
        stride = samples.shape[1] * 2
        bit = 16
    elif samples.dtype == np.uint8:
        raw = np.ascontiguousarray(samples).tobytes()
        stride = samples.shape[1]
        bit = 8
    else:
        raise TypeError(str(samples.dtype))
    height, width = samples.shape
    rows = bytearray()
    for r in range(height):
        rows.append(0)
        rows.extend(raw[r * stride : (r + 1) * stride])
    compressed = zlib.compress(bytes(rows), 9)

    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", width, height, bit, 0, 0, 0, 0)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", compressed) + chunk(b"IEND", b""))


def sample(url: str, cols: int, rows: int, resampling: Resampling, dtype: str) -> np.ndarray:
    """Read a coarse window from COG overviews, then warp that array to the tile grid.

    Reprojecting the 1 m mosaic directly pulls native-resolution blocks for an
    ~80 km box. The overview read stays near the 120 m output.
    """
    nodata = np.nan if dtype == "float32" else 0
    dst = np.full((rows, cols), nodata, dtype=dtype)
    dst_transform = from_bounds(WEST, SOUTH, EAST, NORTH, cols, rows)
    with rasterio.Env(
        AWS_NO_SIGN_REQUEST="YES",
        GDAL_DISABLE_READDIR_ON_OPEN="EMPTY_DIR",
        CPL_VSIL_CURL_USE_HEAD="NO",
        GDAL_HTTP_TIMEOUT="120",
        GDAL_HTTP_MULTIRANGE="YES",
        VSI_CACHE="TRUE",
        VSI_CACHE_SIZE="32000000",
    ):
        with rasterio.open(url) as src:
            to_src = Transformer.from_crs("EPSG:4326", src.crs, always_xy=True)
            corners_x, corners_y = to_src.transform(
                [WEST, EAST, WEST, EAST],
                [SOUTH, SOUTH, NORTH, NORTH],
            )
            minx, maxx = min(corners_x), max(corners_x)
            miny, maxy = min(corners_y), max(corners_y)
            window = rasterio.windows.from_bounds(minx, miny, maxx, maxy, transform=src.transform)
            window = window.intersection(rasterio.windows.Window(0, 0, src.width, src.height))
            scale = max(window.width / cols, window.height / rows, 1.0)
            overviews = src.overviews(1) or []
            chosen = 1
            for factor in overviews:
                if factor <= scale:
                    chosen = factor
            log(f"  {src.crs} overviews {overviews or 'none'} using {chosen}× for a {window.width:.0f}×{window.height:.0f} window")
            out_h = max(2, int(math.ceil(window.height / chosen)))
            out_w = max(2, int(math.ceil(window.width / chosen)))
            raw = src.read(1, window=window, out_shape=(out_h, out_w), resampling=resampling, masked=True)
            src_transform = rasterio.windows.transform(window, src.transform) * rasterio.Affine.scale(
                window.width / out_w,
                window.height / out_h,
            )
            src_nodata = src.nodata
            filled = np.array(raw.filled(src_nodata if src_nodata is not None else nodata), dtype="float32")
            reproject(
                source=filled,
                destination=dst,
                src_transform=src_transform,
                src_crs=src.crs,
                src_nodata=src_nodata if src_nodata is not None else nodata,
                dst_transform=dst_transform,
                dst_crs="EPSG:4326",
                dst_nodata=nodata,
                resampling=resampling,
            )
    return dst


def fill_nans(z: np.ndarray) -> int:
    missing = int(np.isnan(z).sum())
    if missing == 0:
        return 0
    filled = z.copy()
    for _ in range(24):
        if not np.isnan(filled).any():
            break
        acc = np.zeros_like(filled)
        cnt = np.zeros(filled.shape, dtype=np.int16)
        valid = np.isfinite(filled)
        for dr, dc in ((0, 1), (1, 0), (0, -1), (-1, 0)):
            shifted = np.full_like(filled, np.nan)
            rs = slice(max(dr, 0), filled.shape[0] + min(dr, 0))
            cs = slice(max(dc, 0), filled.shape[1] + min(dc, 0))
            rd = slice(max(-dr, 0), filled.shape[0] + min(-dr, 0))
            cd = slice(max(-dc, 0), filled.shape[1] + min(-dc, 0))
            shifted[rd, cd] = np.where(valid[rs, cs], filled[rs, cs], np.nan)
            ok = np.isfinite(shifted)
            acc = np.where(ok, acc + shifted, acc)
            cnt = np.where(ok, cnt + 1, cnt)
        hole = np.isnan(filled) & (cnt > 0)
        filled[hole] = acc[hole] / cnt[hole]
    if np.isnan(filled).any():
        filled[np.isnan(filled)] = float(np.nanmedian(filled))
    z[:] = filled
    return missing


def georef() -> dict:
    to_ll = Transformer.from_crs(4326, 4326, always_xy=True)
    del to_ll
    lats = []
    lons = []
    step = 5
    for ry in range(step):
        lat = NORTH - (NORTH - SOUTH) * ry / (step - 1)
        for cx in range(step):
            lon = WEST + (EAST - WEST) * cx / (step - 1)
            lons.append(round(lon, 6))
            lats.append(round(lat, 6))
    return {"cols": step, "rows": step, "order": "north_to_south_row_major", "lat": lats, "lon": lons}


def fetch_gbif() -> list[dict]:
    geom = "POLYGON((-69.25 51.00,-68.15 51.00,-68.15 51.75,-69.25 51.75,-69.25 51.00))"
    url = (
        "https://api.gbif.org/v1/occurrence/search?hasCoordinate=true&limit=80&geometry="
        + urllib.request.quote(geom)
    )
    req = urllib.request.Request(url, headers={"User-Agent": "roleplay-bake/1.0 (atlas.rehab)"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        payload = json.load(resp)
    seen: set[str] = set()
    records = []
    for rec in payload.get("results", []):
        name = rec.get("species") or rec.get("scientificName")
        if not name or name in seen:
            continue
        seen.add(name)
        records.append(
            {
                "region": "rene-levasseur",
                "species": rec.get("species") or "",
                "scientificName": rec.get("scientificName") or name,
                "kingdom": rec.get("kingdom") or "",
                "lat": rec.get("decimalLatitude"),
                "lon": rec.get("decimalLongitude"),
                "year": rec.get("year"),
                "dataset": rec.get("datasetName") or "",
                "gbif": f"https://www.gbif.org/occurrence/{rec.get('key')}",
            }
        )
        if len(records) >= 24:
            break
    log(f"GBIF stored {len(records)} of {payload.get('count')} occurrences in the ring box")
    return records


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    cols, rows, width_m, height_m = grid_shape()
    log(f"grid {cols} x {rows}  {width_m:.0f} x {height_m:.0f} m")
    log("HRDEM 1 m DTM window")
    elevation = sample(HRDEM, cols, rows, Resampling.bilinear, "float32")
    missing = fill_nans(elevation)
    log(f"elevation {float(np.nanmin(elevation)):.1f} .. {float(np.nanmax(elevation)):.1f}  filled {missing}")
    log("MRDEM-30 window (stats)")
    mrdem = sample(MRDEM, cols, rows, Resampling.bilinear, "float32")
    mr_ok = int(np.isfinite(mrdem).sum())
    log(f"MRDEM finite {mr_ok} min {np.nanmin(mrdem):.1f} max {np.nanmax(mrdem):.1f}")
    log("land cover 2020")
    cover_f = sample(LAND, cols, rows, Resampling.nearest, "float32")
    cover = np.nan_to_num(cover_f, nan=0).astype(np.uint8)
    classes, counts = np.unique(cover, return_counts=True)
    log("classes " + ", ".join(f"{int(c)}:{int(n)}" for c, n in zip(classes, counts)))
    water = (cover == WATER_CLASS).astype(np.uint8) * 255

    zmin = float(np.min(elevation))
    zmax = float(np.max(elevation))
    span = max(zmax - zmin, 1e-3)
    height_u16 = np.round(np.clip((elevation - zmin) / span, 0, 1) * 65535).astype(np.uint16)
    # PNG row 0 is north. rasterio reproject into EPSG:4326 with north-up transform
    # already stores row 0 at the north edge.
    write_png_gray(OUT / "height.png", height_u16)
    write_png_gray(OUT / "cover.png", cover)
    write_png_gray(OUT / "water.png", water)
    ring = np.zeros((rows, cols, 4), dtype=np.uint8)
    ring[water > 0] = (58, 156, 196, 225)
    write_png_rgba(OUT / "ring.png", ring)

    spacing = CELL_M
    terrain = {
        "id": "rene-levasseur",
        "frame": "Île René-Levasseur, Manicouagan ring, Quebec",
        "mode": "observe",
        "crs_note": "Posts are a regular geographic window. Local metres use 120 m cells, north-up.",
        "bounds_wgs84": {"west": WEST, "south": SOUTH, "east": EAST, "north": NORTH},
        "center_wgs84": {"lat": round((SOUTH + NORTH) / 2, 6), "lon": round((WEST + EAST) / 2, 6)},
        "width_m": round(width_m, 1),
        "height_m": round(height_m, 1),
        "cols": cols,
        "rows": rows,
        "spacing_m": spacing,
        "row_order": "north_to_south",
        "origin": "southwest",
        "world": {"x": "metres east of the west edge", "z": "metres north of the south edge", "y": "elevation metres"},
        "elevation_m": {"min": zmin, "max": zmax, "encoding": "uint16 linear"},
        "georef": georef(),
        "cover_classes": {str(k): v for k, v in COVER_NAMES.items()},
        "water_class": WATER_CLASS,
        "labels": {"elevation": "measured DTM", "cover": "measured land cover", "water": "land-cover water"},
    }
    (OUT / "terrain.json").write_text(json.dumps(terrain, indent=2))

    records = fetch_gbif()
    occ_path = ROOT / "public" / "data" / "occurrences.json"
    doc = json.loads(occ_path.read_text()) if occ_path.exists() else {"records": []}
    doc["records"] = [r for r in doc.get("records", []) if r.get("region") != "rene-levasseur"] + records
    occ_path.write_text(json.dumps(doc, indent=2))

    manifest = {
        "tile": "rene-levasseur",
        "baked_at": datetime.now(timezone.utc).isoformat(),
        "statement": "Measured research terrain. The ring is an emblem of the O. This tile is not land to reshape.",
        "elevation": {
            "product": "NRCan HRDEM Mosaic 1 m DTM",
            "href": HRDEM,
            "licence": "Open Government Licence – Canada",
            "resampling": f"bilinear to {cols}×{rows} posts at {CELL_M:.0f} m",
            "nodata_posts_filled": missing,
            "min_m": round(zmin, 2),
            "max_m": round(zmax, 2),
        },
        "mrdem_30": {
            "product": "NRCan MRDEM-30 DTM",
            "href": MRDEM,
            "licence": "Open Government Licence – Canada",
            "note": "Sampled on the same grid for globe-scale comparison. Copernicus GLO-30 is an input to MRDEM.",
            "finite_posts": mr_ok,
            "min_m": None if not np.isfinite(mrdem).any() else round(float(np.nanmin(mrdem)), 2),
            "max_m": None if not np.isfinite(mrdem).any() else round(float(np.nanmax(mrdem)), 2),
        },
        "land_cover": {
            "product": "NRCan 2020 Land Cover of Canada",
            "href": LAND,
            "licence": "Open Government Licence – Canada",
            "resampling": "nearest",
            "class_counts": {str(int(c)): int(n) for c, n in zip(classes, counts)},
        },
        "water": "NRCan 2020 land-cover class 18 (water). GRHQ and NHN vectors were not clipped into this repo; the reservoir ring is the water class.",
        "quebec_lidar": "Individual Quebec 1 m MNT sheets were not downloaded. The HRDEM 1 m mosaic is the national lidar-derived surface that covers this island.",
        "not_used": "ArcticDEM does not cover 51°N.",
    }
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2))
    total = sum(p.stat().st_size for p in OUT.iterdir())
    log(f"wrote {OUT} ({total/1e6:.2f} MB)")


if __name__ == "__main__":
    main()
