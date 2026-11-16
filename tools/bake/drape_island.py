#!/usr/bin/env python3
"""Drape public imagery on the Île René-Levasseur tile.

Colour is the Quebec 2024 ecoforest inventory orthophoto (20 cm source) warped
onto the 2 m HRDEM tile. The tree mask is Sentinel-2 L2A NDVI from
S2B_19UDS_20240829, 10 m. No API key.
"""

from __future__ import annotations

import urllib.parse
import urllib.request

import numpy as np
import rasterio
from PIL import Image
from rasterio.transform import from_bounds, from_origin
from rasterio.warp import reproject, Resampling
from rasterio.windows import Window

ROOT_NOTE = "Run from the repo. Writes godot/data/ile_color.jpg and godot/data/ile_ndvi.png."
WEST, SOUTH, EAST, NORTH = -69.11800772005614, 51.415155574315115, -69.06042436900381, 51.451148628229966
EAST0, NORTH0, SPAN = 491800.0, 5696000.0, 3998.0
WMS = "https://servicesmatriciels.mern.gouv.qc.ca/erdas-iws/ogc/wms/Imagerie_Aeroportee_Forestiere_Historique?"
LAYER = "Inventaire_Ecoforestier_2024_2024_Inv_Ecofor_20cm_RVB"
SENTINEL = "https://sentinel-cogs.s3.us-west-2.amazonaws.com/sentinel-s2-l2a-cogs/19/U/DS/2024/8/S2B_19UDS_20240829_0_L2A/"


def main() -> None:
    print(ROOT_NOTE)
    q = urllib.parse.urlencode({
        "service": "WMS", "request": "GetMap", "version": "1.3.0",
        "layers": LAYER, "styles": "", "crs": "EPSG:4326",
        "bbox": f"{SOUTH},{WEST},{NORTH},{EAST}",
        "width": "3600", "height": "3600", "format": "image/jpeg",
    })
    req = urllib.request.Request(WMS + q, headers={"User-Agent": "roleplay-preview/1.0"})
    raw = urllib.request.urlopen(req, timeout=180).read()
    src = np.array(Image.open(__import__("io").BytesIO(raw)).convert("RGB"))
    h, w, _ = src.shape
    n = 2400
    dst = np.zeros((3, n, n), np.uint8)
    reproject(
        source=src.transpose(2, 0, 1),
        destination=dst,
        src_transform=from_bounds(WEST, SOUTH, EAST, NORTH, w, h),
        src_crs="EPSG:4326",
        dst_transform=from_origin(EAST0, NORTH0 + SPAN, SPAN / n, SPAN / n),
        dst_crs="EPSG:32619",
        resampling=Resampling.bilinear,
    )
    Image.fromarray(np.transpose(dst, (1, 2, 0)), "RGB").save("godot/data/ile_color.jpg", quality=88, optimize=True)
    col = int(round((EAST0 - 399960) / 10))
    row = 0
    win = Window(col, row, 400, 400)
    env = dict(AWS_NO_SIGN_REQUEST="YES", GDAL_DISABLE_READDIR_ON_OPEN="EMPTY_DIR", CPL_VSIL_CURL_USE_HEAD="NO")
    with rasterio.Env(**env):
        with rasterio.open(SENTINEL + "B04.tif") as red_src, rasterio.open(SENTINEL + "B08.tif") as nir_src:
            red = red_src.read(1, window=win).astype(np.float32)
            nir = nir_src.read(1, window=win).astype(np.float32)
    den = nir + red
    ndvi = np.zeros_like(red)
    ok = den > 50
    ndvi[ok] = (nir[ok] - red[ok]) / den[ok]
    img = ((ndvi.clip(-0.2, 0.9) + 0.2) / 1.1 * 255).astype(np.uint8)
    Image.fromarray(img, "L").save("godot/data/ile_ndvi.png", optimize=True)
    print("wrote ile_color.jpg and ile_ndvi.png")


if __name__ == "__main__":
    main()
