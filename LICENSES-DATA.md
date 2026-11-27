# Terrain and imagery data

Each source below is what the build actually reads. Anything marked
**swap before sales** is fine for this preview and for local play, and must be
replaced or separately licensed before the game is sold.

## Île René-Levasseur elevation

- Source: Natural Resources Canada HRDEM DTM mosaic, the existing 2 m tile `godot/data/ile.u16`.
- License: Open Government Licence – Canada.
- The reservoir surface in this tile is 348.6 m. That is the shoreline used in game.

## Île René-Levasseur colour

- Source: Ministère des Ressources naturelles et des Forêts (Quebec), Inventaire écoforestier du Québec méridional, 2024 orthophoto, 20 cm, layer `Inventaire_Ecoforestier_2024_2024_Inv_Ecofor_20cm_RVB`, resampled to about 1.7 m and draped on the HRDEM tile (`godot/data/ile_color.jpg`).
- License: Creative Commons Attribution 4.0 (CC BY 4.0).
- Credit: Ministère des Ressources naturelles et des Forêts, Imagerie orthorectifiée / inventaire écoforestier.

## Sentinel-2 tree mask

- Source: Copernicus Sentinel-2 L2A, scene `S2B_19UDS_20240829_0_L2A` (29 August 2024), bands B04 and B08 at 10 m, via the public AWS Sentinel COG bucket. Stored as NDVI in `godot/data/ile_ndvi.png` and used with NRCan Land Cover 2020 to place trees.
- License: Copernicus Sentinel data, free to use with attribution (EU law).
- Credit: Contains modified Copernicus Sentinel data (2024).

## Land cover

- Source: Natural Resources Canada, 2020 Land Cover of Canada, 30 m, windowed onto the island tile (`godot/data/ile_cover.png`).
- License: Open Government Licence – Canada.

## Streamed north

- Elevation: Mapzen Terrarium on the public AWS bucket, `https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png`.
- Imagery: EOX Sentinel-2 cloudless 2016, layer `s2cloudless_3857`. License: CC BY 4.0, commercial use allowed with credit. Credit: Sentinel-2 cloudless 2016 by EOX IT Services GmbH (https://cloudless.eox.at), contains modified Copernicus Sentinel data 2016. The 2018 and later mosaics are CC BY-NC-SA 4.0 and are not used. The free endpoint has no SLA and a fair-use policy, which the capped disk cache respects.
- Roads, water, and settlements: OpenFreeMap vector tiles (`https://tiles.openfreemap.org/planet/latest/{z}/{x}/{y}.pbf`), OpenMapTiles schema, data from OpenStreetMap. License: ODbL for the OSM data. Credit OpenFreeMap, OpenMapTiles, and OpenStreetMap contributors.
- Coverage in game is 45°N and north. Tiles are cached under `user://stream` with a file cap.

## Northern low-resolution backdrop

- Source: the polar grid (`godot/data/north.u16`, `godot/data/north_color.jpg`) baked by `tools/bake/north.py` from Mapzen Terrarium elevation and EOX Sentinel-2 cloudless 2016.
- Elevation tiles: https://s3.amazonaws.com/elevation-tiles-prod/terrarium/ (public AWS terrain tiles, Mapzen/Tilezen schema).
- Imagery: EOX Sentinel-2 cloudless 2016, CC BY 4.0 (commercial use allowed with credit).
- License: terrain tiles are the public AWS terrain-tiles dataset.

## Square colour (Canada basin, Europe, Russia)

- Source: EOX Sentinel-2 cloudless 2016 at zoom 15 (`godot/data/basin_color.jpg`, `europe_color.jpg`, `russia_color.jpg`), rebaked by `tools/bake/recolor.py`.
- License: CC BY 4.0. Credit as above.

No Google imagery and no paid API keys are used.
