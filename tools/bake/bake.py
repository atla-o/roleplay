#!/usr/bin/env python3
"""Bake the Roleplay Northern Canada terrain patch.

Windows ArcticDEM v4.1 to a 500×500 post grid on the 4 km EPSG:3413 box
and clips NRCan NHN work unit 10VE001 into local metres. Writes compact
rasters and GeoJSON under public/data/, plus manifest.json.
"""

from __future__ import annotations

import hashlib
import json
import math
import os
import struct
import sys
import urllib.request
import zipfile
import zlib
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import rasterio
from pyproj import CRS, Transformer
from rasterio.enums import Resampling
from rasterio.transform import from_origin
from rasterio.warp import reproject
from shapely import transform as shapely_transform
from shapely.geometry import box, mapping, shape

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "public" / "data"
CACHE = Path(__file__).resolve().parent / "cache"

# Inclusive post corners of the 4 km × 4 km patch. Centre matches
# 75.3971°N, 89.509°W in EPSG:3413.
XMIN, XMAX = -1_116_740.0, -1_112_740.0
YMIN, YMAX = -1_136_011.0, -1_132_011.0
POSTS = 500
WIDTH_M = XMAX - XMIN
HEIGHT_M = YMAX - YMIN
SPACING = WIDTH_M / (POSTS - 1)

STAC = "https://stac.pgc.umn.edu/api/v1"
COLLECTION = "arcticdem-mosaics-v4.1-2m"
NHN_URL = (
    "https://ftp.maps.canada.ca/pub/nrcan_rncan/vector/"
    "geobase_nhn_rhn/shp_en/10/nhn_rhn_10ve001_shp_en.zip"
)
NHN_UNIT = "10VE001"
HYDRO_LAYERS = (
    ("HN_NLFLOW_1", "flowline"),
    ("HD_SLWATER_1", "flowline"),
    ("HD_WATERBODY_2", "waterbody"),
)

N8 = (
    (1, 0),
    (1, 1),
    (0, 1),
    (-1, 1),
    (-1, 0),
    (-1, -1),
    (0, -1),
    (1, -1),
)
DIST8 = (1.0, math.sqrt(2), 1.0, math.sqrt(2), 1.0, math.sqrt(2), 1.0, math.sqrt(2))


def log(msg: str) -> None:
    print(msg, flush=True)


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def write_png_gray(path: Path, samples: np.ndarray) -> None:
    """Write a grayscale PNG. samples is uint8 or uint16, row 0 at the top."""
    if samples.dtype == np.uint16:
        bit_depth = 16
        raw = samples.astype(">u2").tobytes()
        stride = samples.shape[1] * 2
    elif samples.dtype == np.uint8:
        bit_depth = 8
        raw = samples.tobytes()
        stride = samples.shape[1]
    else:
        raise TypeError(str(samples.dtype))
    height, width = samples.shape
    rows = bytearray()
    for r in range(height):
        rows.append(0)
        rows.extend(raw[r * stride : (r + 1) * stride])
    compressed = zlib.compress(bytes(rows), 9)

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    ihdr = struct.pack(">IIBBBBB", width, height, bit_depth, 0, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", compressed) + chunk(b"IEND", b"")
    path.write_bytes(png)


def download(url: str, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists() and dest.stat().st_size > 0:
        log(f"cache {dest.name}")
        return
    log(f"get {url}")
    req = urllib.request.Request(url, headers={"User-Agent": "roleplay-bake/1.0"})
    with urllib.request.urlopen(req, timeout=180) as resp, dest.open("wb") as out:
        while True:
            block = resp.read(1 << 20)
            if not block:
                break
            out.write(block)


def stac_items(lon_min: float, lat_min: float, lon_max: float, lat_max: float) -> list[dict]:
    body = {
        "collections": [COLLECTION],
        "bbox": [lon_min, lat_min, lon_max, lat_max],
        "limit": 20,
    }
    req = urllib.request.Request(
        f"{STAC}/search",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json", "Accept": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        payload = json.loads(resp.read().decode())
    return payload.get("features", [])


def fill_nans(z: np.ndarray) -> int:
    """Replace NaN posts with the mean of seeded neighbors. Returns filled count."""
    nan = np.isnan(z)
    missing = int(nan.sum())
    if missing == 0:
        return 0
    filled = z.copy()
    for _ in range(32):
        if not np.isnan(filled).any():
            break
        acc = np.zeros_like(filled)
        cnt = np.zeros(filled.shape, dtype=np.int16)
        valid = np.isfinite(filled)
        for dr, dc in N8:
            shifted = np.full_like(filled, np.nan)
            src = valid
            rs = slice(max(dr, 0), filled.shape[0] + min(dr, 0))
            cs = slice(max(dc, 0), filled.shape[1] + min(dc, 0))
            rd = slice(max(-dr, 0), filled.shape[0] + min(-dr, 0))
            cd = slice(max(-dc, 0), filled.shape[1] + min(-dc, 0))
            shifted[rd, cd] = np.where(src[rs, cs], filled[rs, cs], np.nan)
            ok = np.isfinite(shifted)
            acc = np.where(ok, acc + shifted, acc)
            cnt = np.where(ok, cnt + 1, cnt)
        hole = np.isnan(filled) & (cnt > 0)
        filled[hole] = acc[hole] / cnt[hole]
    still = int(np.isnan(filled).sum())
    if still:
        # Last resort so the grid stays closed: a regional median, recorded by the caller via the count.
        filled[np.isnan(filled)] = float(np.nanmedian(filled))
    z[:] = filled
    return missing


def priority_flood(z: np.ndarray) -> np.ndarray:
    """Barnes priority-flood. Depth is the fill required to drain every cell to the border."""
    import heapq

    h, w = z.shape
    filled = z.copy()
    seen = np.zeros(z.shape, dtype=bool)
    heap: list[tuple[float, int, int]] = []
    for r in range(h):
        for c in (0, w - 1) if 0 < r < h - 1 else range(w):
            seen[r, c] = True
            heapq.heappush(heap, (float(z[r, c]), r, c))
    while heap:
        elev, r, c = heapq.heappop(heap)
        for dc, dr in N8:
            rr, cc = r + dr, c + dc
            if rr < 0 or cc < 0 or rr >= h or cc >= w or seen[rr, cc]:
                continue
            seen[rr, cc] = True
            fe = max(elev, float(z[rr, cc]))
            filled[rr, cc] = fe
            heapq.heappush(heap, (fe, rr, cc))
    return np.maximum(0.0, filled - z).astype(np.float32)


def flow_direction(z: np.ndarray, epsilon: float = 0.04) -> np.ndarray:
    """D8. 0..7 neighbor, 8 leaves the grid, -1 pit. Shallow microrelief drains onward."""
    h, w = z.shape
    direction = np.full(z.shape, -1, dtype=np.int16)
    for r in range(h):
        for c in range(w):
            zi = float(z[r, c])
            best = 0.0
            choice = -1
            for k, ((dc, dr), dist) in enumerate(zip(N8, DIST8)):
                rr, cc = r + dr, c + dc
                if rr < 0 or cc < 0 or rr >= h or cc >= w:
                    continue
                drop = zi - float(z[rr, cc])
                if drop > epsilon and drop / dist > best:
                    best = drop / dist
                    choice = k
            if choice >= 0:
                direction[r, c] = choice
            elif r == 0 or c == 0 or r == h - 1 or c == w - 1:
                direction[r, c] = 8
    from collections import deque

    q: deque[tuple[int, int]] = deque()
    for r in range(h):
        for c in range(w):
            if direction[r, c] != -1:
                q.append((r, c))
    while q:
        r, c = q.popleft()
        zi = float(z[r, c])
        for k, (dc, dr) in enumerate(N8):
            rr, cc = r + dr, c + dc
            if rr < 0 or cc < 0 or rr >= h or cc >= w:
                continue
            if direction[rr, cc] != -1:
                continue
            if float(z[rr, cc]) > zi + epsilon:
                continue
            direction[rr, cc] = (k + 4) % 8
            q.append((rr, cc))
    return direction


def flow_accumulation(z: np.ndarray, direction: np.ndarray) -> np.ndarray:
    h, w = z.shape
    acc = np.ones(z.shape, dtype=np.float32)
    order = np.argsort(-z, axis=None)
    for idx in order:
        r, c = divmod(int(idx), w)
        k = int(direction[r, c])
        if k < 0 or k == 8:
            continue
        dc, dr = N8[k]
        rr, cc = r + dr, c + dc
        if 0 <= rr < h and 0 <= cc < w:
            acc[rr, cc] += acc[r, c]
    return acc


def trace_flow_lines(acc: np.ndarray, direction: np.ndarray, threshold: float) -> list[list[tuple[float, float]]]:
    """Walk channel cells downstream into local-metre polylines (x east, y north)."""
    h, w = acc.shape
    channel = acc >= threshold
    # Heads: channel cells with no channel upstream.
    upstream = np.zeros_like(channel)
    for r in range(h):
        for c in range(w):
            k = int(direction[r, c])
            if k < 0 or k == 8:
                continue
            dc, dr = N8[k]
            rr, cc = r + dr, c + dc
            if 0 <= rr < h and 0 <= cc < w and channel[r, c]:
                upstream[rr, cc] = True
    lines: list[list[tuple[float, float]]] = []
    seen = np.zeros_like(channel)

    def world(r: int, c: int) -> tuple[float, float]:
        x = c * SPACING
        y = (h - 1 - r) * SPACING
        return (round(x, 1), round(y, 1))

    for r in range(h):
        for c in range(w):
            if not channel[r, c] or upstream[r, c] or seen[r, c]:
                continue
            line = []
            rr, cc = r, c
            guard = 0
            while 0 <= rr < h and 0 <= cc < w and channel[rr, cc] and guard < h * w:
                if seen[rr, cc] and line:
                    break
                seen[rr, cc] = True
                line.append(world(rr, cc))
                k = int(direction[rr, cc])
                if k < 0 or k == 8:
                    break
                dc, dr = N8[k]
                rr, cc = rr + dr, cc + dc
                guard += 1
            if len(line) >= 4:
                lines.append(line)
    return lines


def load_dem(items: list[dict]) -> tuple[np.ndarray, list[dict], int]:
    spacing = SPACING
    dst_transform = from_origin(XMIN - spacing / 2, YMAX + spacing / 2, spacing, spacing)
    dst = np.full((POSTS, POSTS), np.nan, dtype=np.float32)
    used = []
    os.environ.setdefault("AWS_NO_SIGN_REQUEST", "YES")
    os.environ.setdefault("GDAL_DISABLE_READDIR_ON_OPEN", "EMPTY_DIR")
    os.environ.setdefault("CPL_VSIL_CURL_USE_HEAD", "NO")
    os.environ.setdefault("GDAL_HTTP_TIMEOUT", "180")
    env = rasterio.Env(
        AWS_NO_SIGN_REQUEST="YES",
        GDAL_DISABLE_READDIR_ON_OPEN="EMPTY_DIR",
        CPL_VSIL_CURL_USE_HEAD="NO",
        GDAL_HTTP_TIMEOUT="180",
        GDAL_HTTP_MERGE_CONSECUTIVE_RANGES="YES",
    )
    with env:
        for feature in items:
            href = feature.get("assets", {}).get("dem", {}).get("href")
            if not href:
                continue
            log(f"open {feature.get('id')}")
            with rasterio.open(href) as src:
                b = src.bounds
                if XMAX < b.left or XMIN > b.right or YMAX < b.bottom or YMIN > b.top:
                    log("  no overlap")
                    continue
                tmp = np.full((POSTS, POSTS), np.nan, dtype=np.float32)
                reproject(
                    source=rasterio.band(src, 1),
                    destination=tmp,
                    src_transform=src.transform,
                    src_crs=src.crs,
                    src_nodata=src.nodata,
                    dst_transform=dst_transform,
                    dst_crs="EPSG:3413",
                    dst_nodata=np.nan,
                    resampling=Resampling.bilinear,
                )
                take = np.isnan(dst) & np.isfinite(tmp)
                dst[take] = tmp[take]
                used.append(
                    {
                        "id": feature.get("id"),
                        "href": href,
                        "crs": str(src.crs),
                        "nodata": src.nodata,
                        "native_res_m": src.res[0],
                    }
                )
                log(f"  posts filled {int(np.isfinite(dst).sum())}/{POSTS * POSTS}")
    if not np.isfinite(dst).any():
        raise SystemExit("ArcticDEM window is empty. Check STAC coverage and network access.")
    missing = fill_nans(dst)
    if missing:
        log(f"filled {missing} nodata posts")
    dst = dst.astype(np.float32)
    dst.flags.writeable = True
    return dst, used, missing


def clip_hydro() -> tuple[dict, dict]:
    import shapefile

    zip_path = CACHE / "nhn_rhn_10ve001_shp_en.zip"
    download(NHN_URL, zip_path)
    extract = CACHE / "nhn_10ve001"
    if not extract.exists():
        log("unzip NHN")
        with zipfile.ZipFile(zip_path) as zf:
            zf.extractall(extract)
    back = Transformer.from_crs(3413, 4326, always_xy=True)
    corners = [(XMIN, YMIN), (XMAX, YMIN), (XMAX, YMAX), (XMIN, YMAX)]
    lons, lats = zip(*[back.transform(x, y) for x, y in corners])
    pad = 0.02
    lon0, lon1 = min(lons) - pad, max(lons) + pad
    lat0, lat1 = min(lats) - pad, max(lats) + pad
    clipper = box(XMIN, YMIN, XMAX, YMAX)
    features = []
    counts: dict[str, int] = {}
    prj_name = ""
    for stem, kind in HYDRO_LAYERS:
        matches = list(extract.glob(f"*{stem}.shp"))
        if not matches:
            log(f"missing layer {stem}")
            counts[stem] = 0
            continue
        shp_path = matches[0]
        prj = shp_path.with_suffix(".prj").read_text()
        prj_name = prj.split(",")[0]
        crs = CRS.from_wkt(prj)
        to_3413 = Transformer.from_crs(crs, 3413, always_xy=True)
        reader = shapefile.Reader(str(shp_path))
        field_names = [f[0] for f in reader.fields[1:]]
        kept = 0
        for rec, shp in zip(reader.iterRecords(), reader.iterShapes()):
            bx0, by0, bx1, by1 = shp.bbox
            if bx1 < lon0 or bx0 > lon1 or by1 < lat0 or by0 > lat1:
                continue
            geom = shape(shp.__geo_interface__)
            if geom.is_empty:
                continue

            def _project(coords, _fwd=to_3413):
                xy = np.asarray(coords, dtype=np.float64)
                east, north = _fwd.transform(xy[:, 0], xy[:, 1])
                return np.column_stack((east, north))

            projected = shapely_transform(geom, _project)
            clipped = projected.intersection(clipper)
            if clipped.is_empty:
                continue
            simplified = clipped.simplify(6.0, preserve_topology=True)
            if simplified.is_empty:
                continue
            attrs = dict(zip(field_names, rec))
            name = ""
            for key in ("NAME_1", "LAKENAME_1", "RIVNAME_1"):
                value = attrs.get(key) or ""
                if isinstance(value, str) and value.strip():
                    name = value.strip()
                    break
            props = {
                "source": "NRCan NHN",
                "work_unit": NHN_UNIT,
                "layer": stem,
                "kind": kind,
                "type_text": (attrs.get("TYPE_TEXT") or "").strip() if isinstance(attrs.get("TYPE_TEXT"), str) else "",
                "nid": (attrs.get("NID") or "").strip() if isinstance(attrs.get("NID"), str) else "",
            }
            if name:
                props["name"] = name
            for numeric in ("DEFINITION", "PERMANENCY", "TYPE"):
                if numeric in attrs and attrs[numeric] not in ("", None):
                    props[numeric.lower()] = attrs[numeric]
            gj = mapping(simplified)
            gj["coordinates"] = _local_coords(gj["coordinates"])
            features.append({"type": "Feature", "properties": props, "geometry": gj})
            kept += 1
        counts[stem] = kept
        log(f"{stem} clipped {kept}")
    # Derived drainage, tagged so it is never confused with the survey.
    return {"type": "FeatureCollection", "features": features}, {
        "work_unit": NHN_UNIT,
        "url": NHN_URL,
        "crs_wkt_prefix": prj_name,
        "clipped_counts": counts,
        "licence": "Open Government Licence – Canada",
        "licence_url": "https://open.canada.ca/en/open-government-licence-canada",
    }


def _local_coords(node):
    if isinstance(node, (list, tuple)):
        if len(node) >= 2 and isinstance(node[0], (int, float)) and isinstance(node[1], (int, float)):
            x = round(float(node[0]) - XMIN, 1)
            y = round(float(node[1]) - YMIN, 1)
            return [x, y]
        return [_local_coords(child) for child in node]
    return node


def georef_grid(step: int = 5) -> dict:
    back = Transformer.from_crs(3413, 4326, always_xy=True)
    lats = []
    lons = []
    # Row-major, north to south, west to east. Matches the PNG.
    for ry in range(step):
        north = YMAX - (HEIGHT_M * ry / (step - 1))
        for cx in range(step):
            east = XMIN + (WIDTH_M * cx / (step - 1))
            lon, lat = back.transform(east, north)
            lons.append(round(lon, 6))
            lats.append(round(lat, 6))
    return {"cols": step, "rows": step, "order": "north_to_south_row_major", "lat": lats, "lon": lons}


def encode_u16(values: np.ndarray, vmin: float, vmax: float) -> np.ndarray:
    span = max(vmax - vmin, 1e-6)
    scaled = np.clip((values - vmin) / span, 0, 1)
    return np.round(scaled * 65535).astype(np.uint16)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    CACHE.mkdir(parents=True, exist_ok=True)
    back = Transformer.from_crs(3413, 4326, always_xy=True)
    corners_ll = [back.transform(x, y) for x, y in ((XMIN, YMIN), (XMAX, YMIN), (XMAX, YMAX), (XMIN, YMAX))]
    lon_min = min(p[0] for p in corners_ll)
    lon_max = max(p[0] for p in corners_ll)
    lat_min = min(p[1] for p in corners_ll)
    lat_max = max(p[1] for p in corners_ll)
    log(f"window lon {lon_min:.4f}..{lon_max:.4f} lat {lat_min:.4f}..{lat_max:.4f}")
    items = stac_items(lon_min, lat_min, lon_max, lat_max)
    log(f"STAC items {len(items)}")
    if not items:
        raise SystemExit("STAC returned no ArcticDEM v4.1 tiles for this window.")
    elevation, used, nodata_filled = load_dem(items)
    zmin = float(elevation.min())
    zmax = float(elevation.max())
    log(f"elevation {zmin:.2f} .. {zmax:.2f} m")

    log("slope, depressions, flow")
    dzdy, dzdx = np.gradient(elevation, SPACING)
    # Row 0 is north, so image-row gradient points south. Slope magnitude is unaffected.
    slope = np.degrees(np.arctan(np.hypot(dzdx, dzdy))).astype(np.float32)
    depression = priority_flood(elevation)
    direction = flow_direction(elevation)
    accumulation = flow_accumulation(elevation, direction)
    lines = trace_flow_lines(accumulation, direction, threshold=max(80.0, float(np.percentile(accumulation, 99.2))))
    log(f"derived flow lines {len(lines)}")

    hydro, hydro_meta = clip_hydro()
    for line in lines:
        hydro["features"].append(
            {
                "type": "Feature",
                "properties": {
                    "source": "derived-flow-accumulation",
                    "kind": "flowpath",
                    "note": "D8 accumulation on the baked height grid. Not an NHN feature.",
                },
                "geometry": {"type": "LineString", "coordinates": line},
            }
        )

    height_u16 = encode_u16(elevation, zmin, zmax)
    slope_u16 = encode_u16(slope, 0.0, 90.0)
    dep_max = float(min(65.0, max(0.5, float(depression.max()))))
    dep_mm = np.clip(depression * 1000.0, 0, dep_max * 1000.0)
    dep_u16 = encode_u16(dep_mm, 0.0, dep_max * 1000.0)
    acc_max = float(accumulation.max())
    flow_log = np.log2(accumulation + 1.0)
    flow_u16 = encode_u16(flow_log, 0.0, math.log2(acc_max + 1.0))

    write_png_gray(OUT / "height.png", height_u16)
    write_png_gray(OUT / "slope.png", slope_u16)
    write_png_gray(OUT / "depression.png", dep_u16)
    write_png_gray(OUT / "flow.png", flow_u16)
    (OUT / "hydro.geojson").write_text(json.dumps(hydro, separators=(",", ":")))

    center_lon, center_lat = back.transform((XMIN + XMAX) / 2, (YMIN + YMAX) / 2)
    terrain = {
        "frame": "Northern Canada (Polar Desert Basin, 4 × 4 km)",
        "crs": "EPSG:3413",
        "bounds_3413": {"xmin": XMIN, "ymin": YMIN, "xmax": XMAX, "ymax": YMAX},
        "center_wgs84": {"lat": round(center_lat, 6), "lon": round(center_lon, 6)},
        "width_m": WIDTH_M,
        "height_m": HEIGHT_M,
        "cols": POSTS,
        "rows": POSTS,
        "spacing_m": SPACING,
        "row_order": "north_to_south",
        "origin": "southwest",
        "world": {
            "x": "metres east of xmin",
            "z": "metres north of ymin",
            "y": "elevation metres",
        },
        "elevation_m": {"min": zmin, "max": zmax, "encoding": "uint16 linear"},
        "slope_deg": {"min": 0, "max": 90, "encoding": "uint16 linear"},
        "depression_mm": {"min": 0, "max": dep_max * 1000.0, "encoding": "uint16 linear"},
        "flow_log2": {"min": 0, "max": math.log2(acc_max + 1.0), "encoding": "uint16 linear"},
        "georef": georef_grid(),
        "files": {
            "height": "height.png",
            "slope": "slope.png",
            "depression": "depression.png",
            "flow": "flow.png",
            "hydro": "hydro.geojson",
        },
        "labels": {
            "elevation": "measured DEM",
            "slope": "derived from measured DEM",
            "depression": "derived from measured DEM",
            "flow": "derived from measured DEM",
        },
    }
    (OUT / "terrain.json").write_text(json.dumps(terrain, indent=2))

    files = {}
    total = 0
    for path in sorted(OUT.iterdir()):
        if path.name == "manifest.json" or not path.is_file():
            continue
        size = path.stat().st_size
        total += size
        files[path.name] = {"bytes": size, "sha256": sha256(path)}
    manifest = {
        "product": "roleplay-terrain",
        "frame": terrain["frame"],
        "baked_at": datetime.now(timezone.utc).isoformat(),
        "statement": (
            "Roleplay is a pure digital simulation built from open elevation data "
            "with no land claim or ground impact."
        ),
        "elevation": {
            "title": "ArcticDEM v4.1",
            "collection": COLLECTION,
            "stac": STAC,
            "mosaic": "2 m",
            "resampling": f"bilinear to {POSTS}×{POSTS} posts, spacing {SPACING:.6f} m",
            "items": used,
            "license": "CC-BY-4.0",
            "license_url": "https://creativecommons.org/licenses/by/4.0/",
            "credit": "Polar Geospatial Center, University of Minnesota",
            "citation": "Porter et al. 2023. ArcticDEM, Version 4.1.",
            "doi": "https://doi.org/10.7910/DVN/3VDC4W",
            "retrieved_elevation_m": {"min": round(zmin, 3), "max": round(zmax, 3)},
            "nodata_posts_filled": nodata_filled,
        },
        "hydrography": hydro_meta,
        "derived": {
            "slope": "Finite difference on the baked posts, degrees.",
            "depression": "Priority-flood depth to the border outlet, millimetres.",
            "flow": "D8 accumulation, stored as log2(cells + 1).",
            "derived_flow_lines": len(lines),
        },
        "software": {
            "python": sys.version.split()[0],
            "rasterio": rasterio.__version__,
            "numpy": np.__version__,
        },
        "files": files,
        "total_bytes": total,
    }
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2))
    # Recount with the manifest included.
    grand = sum(p.stat().st_size for p in OUT.iterdir() if p.is_file())
    log(f"wrote {OUT} ({grand/1e6:.2f} MB)")
    if grand > 5_000_000:
        raise SystemExit(f"baked data is {grand} bytes, over the 5 MB budget")


if __name__ == "__main__":
    main()
