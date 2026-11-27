#!/usr/bin/env python3
"""Bake Île René-Levasseur surface inputs.

Land cover is NRCan 2020, sampled on the 2 m HRDEM tile. The cover image stores
weights, not class ids, so the shader can filter it. Detail textures and the
spruce, fir, birch, and shrub cards are generated here and are tile-safe.
"""

from __future__ import annotations

import numpy as np
from PIL import Image
from pyproj import Transformer
import rasterio
from rasterio.transform import from_origin
from rasterio.warp import Resampling, reproject

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EAST0 = 491800.0
NORTH0 = 5696000.0
SPAN = 3998.0
WATER = 348.59
HMIN = 348.2874755859375
HMAX = 616.302490234375
N = 512
LAND = "https://datacube-prod-data-public.s3.ca-central-1.amazonaws.com/store/land/landcover/landcover-2020-classification.tif"


def wrap_noise(n: int, cells: int, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    lattice = rng.random((cells, cells))
    ys, xs = np.mgrid[0:n, 0:n]
    xf = xs / n * cells
    yf = ys / n * cells
    xi = np.floor(xf).astype(np.int32)
    yi = np.floor(yf).astype(np.int32)
    fx = xf - xi
    fy = yf - yi
    sx = fx * fx * (3 - 2 * fx)
    sy = fy * fy * (3 - 2 * fy)
    acc = np.zeros((n, n), np.float32)
    for oy in (0, 1):
        for ox in (0, 1):
            v = lattice[(yi + oy) % cells, (xi + ox) % cells]
            wx = sx if ox else (1 - sx)
            wy = sy if oy else (1 - sy)
            acc += v * wx * wy
    return acc


def worley(n: int, cells: int, seed: int) -> tuple[np.ndarray, np.ndarray]:
    rng = np.random.default_rng(seed)
    pts = rng.random((cells, cells, 2)).astype(np.float32)
    ys, xs = np.mgrid[0:n, 0:n]
    xf = xs / n * cells
    yf = ys / n * cells
    xi = np.floor(xf).astype(np.int32)
    yi = np.floor(yf).astype(np.int32)
    fx = (xf - xi).astype(np.float32)
    fy = (yf - yi).astype(np.float32)
    d0 = np.full((n, n), 8.0, np.float32)
    d1 = np.full((n, n), 8.0, np.float32)
    for oy in (-1, 0, 1):
        for ox in (-1, 0, 1):
            px = pts[(yi + oy) % cells, (xi + ox) % cells, 0]
            py = pts[(yi + oy) % cells, (xi + ox) % cells, 1]
            dx = (ox + px) - fx
            dy = (oy + py) - fy
            d = dx * dx + dy * dy
            closer = d < d0
            d1 = np.where(closer, d0, np.minimum(d1, d))
            d0 = np.where(closer, d, d0)
            between = (~closer) & (d < d1)
            d1 = np.where(between, d, d1)
    return np.sqrt(d0), np.sqrt(d1)


def normals_from_height(h: np.ndarray, strength: float) -> np.ndarray:
    gx = np.zeros_like(h)
    gy = np.zeros_like(h)
    gx[:, 1:-1] = h[:, 2:] - h[:, :-2]
    gy[1:-1, :] = h[2:, :] - h[:-2, :]
    nx = -gx * strength
    ny = -gy * strength
    nz = np.ones_like(h)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    rgb = np.stack(((nx / ln + 1) * 0.5, (ny / ln + 1) * 0.5, (nz / ln + 1) * 0.5), axis=-1)
    return (rgb * 255).clip(0, 255).astype(np.uint8)


def save_jpg(path: Path, rgb: np.ndarray, quality: int = 86) -> None:
    img = Image.fromarray(rgb.astype(np.uint8), "RGB")
    img.save(path, quality=quality, optimize=True, subsampling=0)


def save_normal(path: Path, h: np.ndarray, strength: float) -> None:
    save_jpg(path, normals_from_height(h, strength), quality=90)


def build_textures(tex: Path) -> None:
    n = 1024
    moss_n = wrap_noise(n, 96, 3)
    moss_n2 = wrap_noise(n, 28, 9)
    fiber = wrap_noise(n, 8, 11)
    moss = np.zeros((n, n, 3), np.float32)
    moss[:, :, 0] = 0.07 + moss_n * 0.05 + fiber * 0.02
    moss[:, :, 1] = 0.13 + moss_n * 0.10 + moss_n2 * 0.04
    moss[:, :, 2] = 0.05 + moss_n * 0.03
    moss += (wrap_noise(n, 180, 4)[..., None] - 0.5) * 0.03
    save_jpg(tex / "forest_floor_Diffuse.jpg", moss * 255)
    save_normal(tex / "forest_floor_nor_gl.jpg", moss_n * 0.6 + fiber * 0.4, 2.2)

    d0, d1 = worley(n, 36, 5)
    crust = np.clip((d1 - d0) * 3.2, 0, 1)
    pale = wrap_noise(n, 12, 6)
    lichen = np.zeros((n, n, 3), np.float32)
    lichen[:, :, 0] = 0.34 + crust * 0.22 + pale * 0.08
    lichen[:, :, 1] = 0.36 + crust * 0.20 + pale * 0.06
    lichen[:, :, 2] = 0.26 + crust * 0.10
    crack = np.clip(1 - (d1 - d0) * 8, 0, 1)
    lichen *= 1 - crack[..., None] * 0.45
    save_jpg(tex / "forest_leaves_03_Diffuse.jpg", lichen * 255)

    speckle = wrap_noise(n, 140, 2)
    grain = wrap_noise(n, 40, 8)
    vein = wrap_noise(n, 6, 12)
    granite = np.zeros((n, n, 3), np.float32)
    granite[:, :, 0] = 0.28 + grain * 0.10 + speckle * 0.08
    granite[:, :, 1] = 0.29 + grain * 0.09 + speckle * 0.05
    granite[:, :, 2] = 0.30 + grain * 0.08 + speckle * 0.04
    feldspar = speckle > 0.82
    granite[feldspar] = np.array([0.52, 0.40, 0.38])
    biotite = speckle < 0.08
    granite[biotite] *= 0.45
    granite += (vein[..., None] - 0.5) * 0.06
    save_jpg(tex / "rocky_terrain_Diffuse.jpg", granite.clip(0, 1) * 255)
    save_normal(tex / "rocky_terrain_nor_gl.jpg", grain * 0.5 + speckle * 0.5, 3.4)

    gd0, gd1 = worley(n, 42, 15)
    stones = np.clip((gd1 - gd0) * 2.6, 0, 1)
    tone = wrap_noise(n, 42, 16)
    gravel = np.zeros((n, n, 3), np.float32)
    gravel[:, :, 0] = 0.24 + stones * 0.16 + tone * 0.06
    gravel[:, :, 1] = 0.23 + stones * 0.14 + tone * 0.05
    gravel[:, :, 2] = 0.20 + stones * 0.10 + tone * 0.04
    save_jpg(tex / "sandy_gravel_02_Diffuse.jpg", gravel * 255)
    save_normal(tex / "sandy_gravel_02_nor_gl.jpg", stones, 4.5)

    peat_n = wrap_noise(n, 24, 21)
    peat = np.zeros((n, n, 3), np.float32)
    peat[:, :, 0] = 0.05 + peat_n * 0.04
    peat[:, :, 1] = 0.045 + peat_n * 0.035
    peat[:, :, 2] = 0.03 + peat_n * 0.02
    save_jpg(tex / "brown_mud_Diffuse.jpg", peat * 255)
    save_normal(tex / "brown_mud_nor_gl.jpg", peat_n, 1.4)

    ash = wrap_noise(n, 18, 30)
    char = wrap_noise(n, 64, 31)
    burn = np.zeros((n, n, 3), np.float32)
    burn[:, :, 0] = 0.04 + ash * 0.10 + char * 0.03
    burn[:, :, 1] = 0.04 + ash * 0.09
    burn[:, :, 2] = 0.035 + ash * 0.07
    save_jpg(tex / "coast_sand_01_Diffuse.jpg", burn * 255)
    print("textures", tex)


def stamp(img: np.ndarray, x: float, y: float, rad: float, color: tuple[float, float, float, float]) -> None:
    h, w, _ = img.shape
    x0 = max(int(x - rad), 0)
    x1 = min(int(x + rad) + 1, w)
    y0 = max(int(y - rad), 0)
    y1 = min(int(y + rad) + 1, h)
    if x0 >= x1 or y0 >= y1:
        return
    yy, xx = np.mgrid[y0:y1, x0:x1]
    d = ((xx - x) ** 2 + (yy - y) ** 2) / (rad * rad)
    a = np.clip(1 - d, 0, 1) ** 1.4
    patch = img[y0:y1, x0:x1]
    ca = a * color[3]
    for c in range(3):
        patch[:, :, c] = patch[:, :, c] * (1 - ca) + color[c] * ca
    patch[:, :, 3] = np.clip(patch[:, :, 3] + ca, 0, 1)


def paint_conifer(path: Path, seed: int, wide: float, height_frac: float, green: tuple[float, float, float]) -> None:
    h, w = 1024, 512
    grain = np.array(Image.fromarray(wrap_noise(512, 48, seed)).resize((w, h), Image.Resampling.BILINEAR))
    fine = np.array(Image.fromarray(wrap_noise(512, 96, seed + 3)).resize((w, h), Image.Resampling.BILINEAR))
    yy, xx = np.mgrid[0:h, 0:w]
    cx = w * 0.5
    top = h * 0.03
    base = h * 0.97
    t = np.clip((yy - top) / (base - top), 0, 1)
    half = (170 if wide < 0.5 else 230) * np.power(t, 0.82)
    # Whorls of foliage with gaps between them, drooping at the tips.
    whorl = 0.55 + 0.45 * np.sin(t * np.pi * (18 if wide < 0.5 else 11) + grain * 2)
    edge = half * (0.62 + 0.38 * whorl) * (0.82 + 0.28 * grain)
    dx = np.abs(xx - cx)
    body = np.clip((edge - dx) / 10.0, 0, 1) * (yy > top) * (yy < base)
    fringe = np.clip((edge + 14 - dx) / 18.0, 0, 1) * (dx > edge) * (yy < base)
    alpha = np.clip(body * (0.45 + 0.55 * fine) + fringe * 0.35 * fine, 0, 1)
    shade = 0.55 + 0.55 * fine
    # Darker in the crown's heart, a little brighter where light hits the tips.
    tip = np.clip(dx / np.maximum(edge, 1), 0, 1)
    rgb = np.zeros((h, w, 3), np.float32)
    rgb[:, :, 0] = green[0] * shade * (0.7 + 0.5 * tip)
    rgb[:, :, 1] = green[1] * shade * (0.75 + 0.45 * tip)
    rgb[:, :, 2] = green[2] * shade * (0.7 + 0.35 * tip)
    trunk = (dx < (2.2 + t * 3.2)) & (yy > h * 0.62) & (yy < base + 8)
    rgb[trunk] = (0.22, 0.13, 0.06)
    alpha = np.where(trunk, 1.0, alpha)
    out = np.dstack(((rgb * 255).astype(np.uint8), (alpha * 255).astype(np.uint8)))
    Image.fromarray(out, "RGBA").save(path, optimize=True)
    print(path.name, int((alpha > 0.2).mean() * 100), "% filled")


def paint_shrub(path: Path) -> None:
    rng = np.random.default_rng(7)
    h, w = 256, 384
    img = np.zeros((h, w, 4), np.float32)
    for _ in range(420):
        x = rng.uniform(30, w - 30)
        y = rng.uniform(h * 0.35, h * 0.92)
        shade = rng.uniform(0.6, 1.15)
        stamp(img, x, y, rng.uniform(4, 11), (0.09 * shade, 0.18 * shade, 0.08 * shade, 0.85))
    rgb = (img[:, :, :3] * 255).astype(np.uint8)
    a = (img[:, :, 3] * 255).astype(np.uint8)
    Image.fromarray(np.dstack((rgb, a)), "RGBA").save(path, optimize=True)


def paint_birch(path: Path) -> None:
    h, w = 1024, 512
    grain = np.array(Image.fromarray(wrap_noise(512, 24, 4)).resize((w, h), Image.Resampling.BILINEAR))
    yy, xx = np.mgrid[0:h, 0:w]
    cx = w * 0.5
    crown_y = h * 0.34
    dx = (xx - cx) / 150
    dy = (yy - crown_y) / 210
    blob = np.clip(1 - (dx * dx * 1.3 + dy * dy), 0, 1) ** 0.7
    alpha = np.clip(blob * (0.72 + 0.28 * grain), 0, 1)
    rgb = np.zeros((h, w, 3), np.float32)
    rgb[:, :, 0] = 0.22 * (0.75 + 0.4 * grain)
    rgb[:, :, 1] = 0.32 * (0.75 + 0.4 * grain)
    rgb[:, :, 2] = 0.12 * (0.75 + 0.4 * grain)
    trunk = (np.abs(xx - cx) < 5) & (yy > h * 0.28) & (yy < h * 0.98)
    marks = trunk & ((yy // 18) % 5 == 0)
    rgb[trunk] = (0.86, 0.88, 0.82)
    rgb[marks] = (0.16, 0.15, 0.12)
    alpha = np.where(trunk, 1.0, alpha * (yy < h * 0.62))
    out = np.dstack(((rgb * 255).astype(np.uint8), (np.clip(alpha, 0, 1) * 255).astype(np.uint8)))
    Image.fromarray(out, "RGBA").save(path, optimize=True)


def load_classes() -> np.ndarray:
    to_src = Transformer.from_crs(32619, 3979, always_xy=True)
    xs, ys = to_src.transform(
        [EAST0, EAST0 + SPAN, EAST0, EAST0 + SPAN],
        [NORTH0, NORTH0, NORTH0 + SPAN, NORTH0 + SPAN],
    )
    with rasterio.Env(
        AWS_NO_SIGN_REQUEST="YES",
        GDAL_DISABLE_READDIR_ON_OPEN="EMPTY_DIR",
        CPL_VSIL_CURL_USE_HEAD="NO",
        GDAL_HTTP_TIMEOUT="120",
    ):
        with rasterio.open(LAND) as src:
            window = rasterio.windows.from_bounds(min(xs), min(ys), max(xs), max(ys), transform=src.transform)
            window = window.intersection(rasterio.windows.Window(0, 0, src.width, src.height))
            window = rasterio.windows.Window(window.col_off - 2, window.row_off - 2, window.width + 4, window.height + 4)
            raw = src.read(1, window=window, boundless=True, fill_value=0)
            src_transform = rasterio.windows.transform(window, src.transform)
            dst = np.zeros((N, N), np.uint8)
            dst_transform = from_origin(EAST0, NORTH0 + SPAN, SPAN / N, SPAN / N)
            reproject(
                source=raw,
                destination=dst,
                src_transform=src_transform,
                src_crs=src.crs,
                src_nodata=0,
                dst_transform=dst_transform,
                dst_crs="EPSG:32619",
                dst_nodata=0,
                resampling=Resampling.nearest,
            )
    return dst


def build_cover() -> None:
    cls = load_classes()
    raw = np.fromfile(ROOT / "godot/data/ile.u16", dtype="<u2").reshape(2000, 2000)
    dem = HMIN + (raw.astype(np.float32) / 65535.0) * (HMAX - HMIN)
    dem = np.flipud(dem)
    dem_s = np.array(Image.fromarray(dem).resize((N, N), Image.Resampling.BILINEAR))
    slope_x = np.zeros_like(dem_s)
    slope_y = np.zeros_like(dem_s)
    slope_x[:, 1:-1] = np.abs(dem_s[:, 2:] - dem_s[:, :-2]) / (2 * SPAN / N)
    slope_y[1:-1, :] = np.abs(dem_s[2:, :] - dem_s[:-2, :]) / (2 * SPAN / N)
    slope = np.clip(np.sqrt(slope_x**2 + slope_y**2), 0, 1)
    color = np.array(Image.open(ROOT / "godot/data/ile_color.jpg").resize((N, N), Image.Resampling.BILINEAR)).astype(np.float32) / 255
    lum = color.mean(axis=2)
    chroma = color.max(axis=2) - color.min(axis=2)
    above = dem_s - WATER
    tree = np.zeros((N, N), np.float32)
    lichen = np.zeros((N, N), np.float32)
    wet = np.zeros((N, N), np.float32)
    shore = np.clip(1 - above / 2.4, 0, 1) * (above > 0.15)
    tree = np.where(cls == 1, 0.92, tree)
    tree = np.where(cls == 2, 0.62, tree)
    tree = np.where(cls == 6, 0.78, tree)
    tree = np.where(cls == 8, 0.28, tree)
    tree = np.where(cls == 10, 0.08, tree)
    tree = np.where(cls == 14, 0.12, tree)
    wet = np.where(cls == 14, 0.9, wet)
    wet = np.where(cls == 8, np.maximum(wet, 0.25), wet)
    pale = np.clip((lum - 0.22) / 0.28, 0, 1) * np.clip(1 - chroma * 5, 0, 1)
    lichen = np.maximum(pale * (above > 1.5), np.clip((slope - 0.22) / 0.45, 0, 1))
    tree *= (1 - 0.8 * lichen) * (1 - shore)
    tree = np.where(above <= 0.2, 0, tree)
    lichen = np.where(above <= 0.2, 0, lichen)
    # The 30 m map calls some wooded benches water. The photograph and the DEM
    # still show land there, so keep a spruce stand on green land above the shore.
    green = (color[:, :, 1] > color[:, :, 0] + 0.02) & (color[:, :, 1] > 0.08)
    missed = (above > 2.2) & (tree < 0.2) & green & (slope < 0.45)
    tree = np.where(missed, 0.72, tree)
    shore = np.maximum(shore, np.clip((3.2 - above) / 3.2, 0, 1) * (above > 0.15) * (above < 3.2))
    # Feather the 30 m classes so a linear sample does not stairstep.
    def blur(a: np.ndarray) -> np.ndarray:
        p = np.pad(a, 1, mode="edge")
        return (p[:-2, :-2] + p[:-2, 1:-1] + p[:-2, 2:] + p[1:-1, :-2] + p[1:-1, 1:-1] + p[1:-1, 2:] + p[2:, :-2] + p[2:, 1:-1] + p[2:, 2:]) / 9

    tree, lichen, wet, shore = blur(tree), blur(lichen), blur(wet), blur(shore)
    rgba = np.stack((tree, lichen, wet, shore), axis=-1)
    out = (rgba.clip(0, 1) * 255).astype(np.uint8)
    path = ROOT / "godot/data/ile_cover.png"
    Image.fromarray(out, "RGBA").save(path, optimize=True)
    print("cover", path, "tree", f"{(tree > 0.45).mean():.2%}", "shore", f"{(shore > 0.4).mean():.2%}", "lichen", f"{(lichen > 0.35).mean():.2%}")


def main() -> None:
    tex = ROOT / "godot/assets/textures"
    cards = ROOT / "godot/assets/textures"
    build_cover()
    build_textures(tex)
    paint_conifer(cards / "spruce_card.png", 1, wide=0.0, height_frac=0.92, green=(0.07, 0.16, 0.07))
    paint_conifer(cards / "fir_card.png", 2, wide=1.0, height_frac=0.86, green=(0.09, 0.20, 0.08))
    paint_birch(cards / "birch_card.png")
    paint_shrub(cards / "shrub_card.png")


if __name__ == "__main__":
    main()
