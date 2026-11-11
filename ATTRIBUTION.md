# Attribution

Roleplay is a pure digital simulation built from open elevation data with no land claim or ground impact. The basin is framed only as **Northern Canada (Polar Desert Basin, 4 × 4 km)**. It is published with the Creation division at [atlas.rehab](https://atlas.rehab/).

The basin window is EPSG:3413, southwest corner X −1,116,740 m, Y −1,136,008 m, 2000 by 2000 posts at 2 m. The centre is about 75.3971°N, 89.5091°W.

## ArcticDEM v4.1

Elevation on Polar Desert Basin is the public ArcticDEM v4.1 2 m mosaic, tile `29_29_2_2_2m_v4.1`, read at native 2 m. Nothing is invented between those posts. The mesh draws every post within 160 m of the body, every second post out to about 540 m, and every eighth post beyond that. Those coarser posts are the same measurements, 4 m and 16 m apart. A short skirt covers the seam so the rings do not show the globe through a crack. Another skirt drops from the outer posts so the tile edge is not a hole. The surface is opaque. There is no second, transparent terrain layer.

Porter et al. 2023. ArcticDEM, Version 4.1. Polar Geospatial Center, University of Minnesota. https://doi.org/10.7910/DVN/3VDC4W

DEMs were created from DigitalGlobe, Inc. imagery and funded under National Science Foundation awards 1043681, 1559691, and 1542736.

Licence: [CC-BY-4.0](https://creativecommons.org/licenses/by/4.0/).

## National Hydro Network

Flowlines and waterbodies are clipped from Natural Resources Canada National Hydro Network work unit `10VE001`.

Licence: [Open Government Licence – Canada](https://open.canada.ca/en/open-government-licence-canada).

Slope, closed-depression depth, and D8 flow accumulation are derived from the measured elevation grid. Derived flow lines in `hydro.geojson` are marked `derived-flow-accumulation` and are not NHN features.

## Ground between the measured tiles

The globe between Polar Desert Basin and Île René-Levasseur is the Mapzen/Tilezen terrarium elevation, copied into `public/dem/terrarium` because the public bucket `s3://elevation-tiles-prod` does not send CORS headers a browser can read. Zoom 3 covers the whole earth. Zoom 5 covers the corridor from about 46°N to 80°N and 102°W to 52°W, which is the walk from the basin to the ring. The app loads only the tiles in view.

The tiles are a composite. The sources used for this corridor, and the credit each one asks for:

- ArcticDEM. DEMs were created from DigitalGlobe, Inc. imagery and funded under National Science Foundation awards 1043681, 1559691, and 1542736.
- ETOPO1. U.S. National Oceanic and Atmospheric Administration. Public domain in the United States. Not for navigation.
- GMTED2010, SRTM, and 3DEP. Courtesy of the U.S. Geological Survey. Public domain.
- Canada. Contains information licensed under the [Open Government Licence – Canada](https://open.canada.ca/en/open-government-licence-canada).
- Europe. Produced using Copernicus data and information funded by the European Union (EU-DEM).

Oceans are held at sea level so the giant walks the water surface rather than the seabed. The full terrarium attribution list is the one published with [joerd](https://github.com/tilezen/joerd/blob/master/docs/attribution.md).

## World imagery

The ground picture on the basin, and the globe around both squares, is Sentinel-2 cloudless 2021 by [EOX IT Services GmbH](https://s2maps.eu) (CC BY 4.0), containing modified Copernicus Sentinel data 2021. The island square uses the same publisher's cloudless 2020 mosaic, because the 2021 tiles there are a flatter, darker file of the same forest. Those JPEGs sit near surface reflectance, so boreal canopy is only a few percent bright. The island mosaic is multiplied by 3 before it is saved, a display gain in the neighbourhood of the Sentinel Hub true-color gain of 2.5, so the canopy is green on screen instead of a black mat. The basin mosaic is unchanged. The fallback globe is Natural Earth II, shipped with CesiumJS and in the public domain. No finer open orthophoto was found for either square under a permissive licence, so nothing sharper than Sentinel-2 is draped.

## Île René-Levasseur

The playable square is the western shore of Île René-Levasseur, where the forest meets the Manicouagan reservoir, Quebec. The island sits in the Manicouagan-Uapishka UNESCO Biosphere Reserve and in Nitassinan of the Innu of Pessamit. It is research terrain.

Elevation is the NRCan HRDEM 1 m DTM, project `Lac_Pletipi_2024`, tile `dtm_1m_utm19_w_0_169`, NAD83(CSRS) / UTM zone 19N. The window is source pixels x 1800 to 5800 and y 0 to 4000 of that tile. The committed grid is 2000 by 2000 posts at 2 m: each post is the mean of the four 1 m posts under it. Southwest corner 491800 E, 5696000 N. The viewer treats that UTM frame as WGS84, which is about a metre at this latitude. ArcticDEM does not cover 51°N.

Posts the lidar left empty over the reservoir are filled with 348.59 m, the median of the measured water surface in this window (returns between 348.0 m and 350.5 m). That is the lidar surface, not a published pool elevation and not a guessed 350 m. A flat water plane is drawn 0.35 m above it, only where the posts are at that surface, so the reservoir reads as water and the forest stays ground. Simple cone trees, 7 to 16 m tall, stand on land above that level. They are not a survey of stems. They are there so the canopy has a height.

Licence: [Open Government Licence – Canada](https://open.canada.ca/en/open-government-licence-canada). Contains information licensed under the Open Government Licence – Canada.

## What is smoother than the source

Sentinel-2 color is about 10 m. Where the mesh asks for a color between those pixels, the picture is bilinear. Shading comes from the slope and curvature of the same 2 m posts, stored as a normal map. It does not move the posts and it does not invent ridges. Horizontal placement of each post is a bilinear of the four corner coordinates. Against the projection that error stays under 1.5 m on the basin and under 0.4 m on the island, inside one post. The tile does not blend into the global DEM. The Mapzen/Tilezen composite below is only the globe between the two squares.

## Species layer

Occurrence points in `public/data/occurrences.json` were retrieved from the [GBIF Occurrence API](https://www.gbif.org) on 2026-11-09. Cite GBIF.org. Each record keeps the licence of its source dataset.

## Viewer

The world is one CesiumJS scene (Apache-2.0). Titan, the robot, and the human stand on the same posts.

The machine starts about 500 m north of the basin centre, still on the measured posts, where the valley floor rises toward the hills. That is a spawn, not a change to the elevation.

The robot is a raycast chassis from [cannon-es](https://github.com/pmndrs/cannon-es) 0.20.0 (MIT). The blade cuts the 2 m posts and lays that volume down ahead of it. Spoil that would stand steeper than the angle of repose slumps sideways, and the volume stays in the field. On the basin that angle is 35° and the bulk density used for the slowing force is 1.8 t/m³, the sandy-gravel range in French, The Periglacial Environment (2007), and in Das, Principles of Geotechnical Engineering. On the island the angle is 32° and the density is 1.7 t/m³, the loose sandy-till end of that same range. These are not a lab sample from either square.

The machine on screen is built from boxes in this repository (`src/drive/dozer.ts`). It is about 3.5 m across the outsides of the tracks and 3.7 m across the blade, which matches the chassis width. No third-party mesh is loaded. Kenney's Car Kit remains in `public/models` from earlier passes and is not drawn. That kit is [CC0](https://creativecommons.org/publicdomain/zero/1.0/), credit Kenney, https://kenney.nl/assets/car-kit. No Blender or other GPL program code is included.

[Steel](https://github.com/skild-ai/steel) (Apache-2.0, also in NVIDIA Newton) is a rigid-body solver for batched robot manipulation. Its browser build is WebGPU ([steel-webgpu](https://github.com/skild-ai/steel-webgpu)), not WASM, and it does not sculpt a heightfield. It is not linked into this app.

[TerraForge3D](https://github.com/Jaysmito101/TerraForge3D) (MIT) is a desktop terrain editor. Its erosion filters are C++ and OpenCL tied to that application. They were not copied. The rain control is a short droplet step written here: sediment that is picked up is laid down again.

Three.js (MIT) remains in the repository for the earlier basin viewer. The player-facing world no longer starts that viewer.

Machine rates and the rain step are sim parameters. Elevations start from the measured DEMs.

Roleplay's own code is MIT, copyright Atla LLC, 2026. See `LICENSE`.
