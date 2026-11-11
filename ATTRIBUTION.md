# Attribution

Roleplay is a pure digital simulation built from open elevation data with no land claim or ground impact. The basin is framed only as **Northern Canada (Polar Desert Basin, 4 × 4 km)**. It is published with the Creation division at [atlas.rehab](https://atlas.rehab/).

The basin window is EPSG:3413, southwest corner X −1,116,740 m, Y −1,136,008 m, 2000 by 2000 posts at 2 m. The centre is about 75.3971°N, 89.5091°W.

## ArcticDEM v4.1

Elevation on Polar Desert Basin is the public ArcticDEM v4.1 2 m mosaic, tile `29_29_2_2_2m_v4.1`, read at native 2 m. Nothing is invented between those posts. The mesh draws every post within about 240 m of the body and every eighth post farther away, which is 16 m, still the same measurements.

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

The ground picture on both squares, and the globe around them, is Sentinel-2 cloudless 2021 by [EOX IT Services GmbH](https://s2maps.eu) (CC BY 4.0), containing modified Copernicus Sentinel data 2021. The squares use a cropped mosaic of those tiles. The fallback mosaic is Natural Earth II, shipped with CesiumJS and in the public domain. No finer open orthophoto was found for either square under a permissive licence, so nothing sharper than Sentinel-2 is draped.

## Île René-Levasseur

The playable square is inside the Louis-Babel Ecological Reserve, on the island in the Manicouagan reservoir, Quebec. It is research terrain. The reserve sits in the Manicouagan-Uapishka UNESCO Biosphere Reserve and in Nitassinan of the Innu of Pessamit.

Elevation is the NRCan HRDEM 1 m DTM, project `Reserve_Ecologique_Louis_Babel_2024`, tile `dtm_1m_utm19_e_0_169`, NAD83(CSRS) / UTM zone 19N. The committed grid is 2000 by 2000 posts at 2 m: each post is the average of the 1 m posts under it, not a made-up detail. The viewer treats that UTM frame as WGS84, which is about a metre at this latitude. ArcticDEM does not cover 51°N. The 4 km square does not include the reservoir shore; the water of the ring is in the surrounding Sentinel-2 picture, not in this height grid.

Licence: [Open Government Licence – Canada](https://open.canada.ca/en/open-government-licence-canada). Contains information licensed under the Open Government Licence – Canada.

## What is smoother than the source

Sentinel-2 color is about 10 m. Where the mesh asks for a color between those pixels, the picture is bilinear. A faint shading grain, a few metres across, is drawn on top so the ground is not a flat poster. It does not move the posts and it does not repaint the satellite colors into a new map. The outer 80 m of each square eases onto the global DEM so the tile does not end as a cliff. That global DEM is the Mapzen/Tilezen composite below, and it is not the near-field source.

## Species layer

Occurrence points in `public/data/occurrences.json` were retrieved from the [GBIF Occurrence API](https://www.gbif.org) on 2026-11-09. Cite GBIF.org. Each record keeps the licence of its source dataset.

## Viewer

The world is one CesiumJS scene (Apache-2.0). Titan, the robot, and the human stand on the same posts.

The robot is a raycast chassis from [cannon-es](https://github.com/pmndrs/cannon-es) 0.20.0 (MIT). The blade cuts the 2 m posts and lays that volume down ahead of it. Spoil that would stand steeper than the angle of repose slumps sideways, and the volume stays in the field. On the basin that angle is 35° and the bulk density used for the slowing force is 1.8 t/m³, the sandy-gravel range in French, The Periglacial Environment (2007), and in Das, Principles of Geotechnical Engineering. On the island the angle is 32° and the density is 1.7 t/m³, the loose sandy-till end of that same range. These are not a lab sample from either square.

The machine meshes are Kenney's Car Kit (`tractor-shovel.glb`, `tractor.glb`, `garbage-truck.glb`) and the shared `models/Textures/colormap.png` those files reference, [CC0](https://creativecommons.org/publicdomain/zero/1.0/). Credit Kenney, https://kenney.nl/assets/car-kit. No Blender or other GPL program code is included. The texture sits beside the models at the path the glTF asks for, so it resolves under a nested preview base.

[Steel](https://github.com/skild-ai/steel) (Apache-2.0, also in NVIDIA Newton) is a rigid-body solver for batched robot manipulation. Its browser build is WebGPU ([steel-webgpu](https://github.com/skild-ai/steel-webgpu)), not WASM, and it does not sculpt a heightfield. It is not linked into this app.

[TerraForge3D](https://github.com/Jaysmito101/TerraForge3D) (MIT) is a desktop terrain editor. Its erosion filters are C++ and OpenCL tied to that application. They were not copied. The rain control is a short droplet step written here: sediment that is picked up is laid down again.

Three.js (MIT) remains in the repository for the earlier basin viewer. The player-facing world no longer starts that viewer.

Machine rates and the rain step are sim parameters. Elevations start from the measured DEMs.

Roleplay's own code is MIT, copyright Atla LLC, 2026. See `LICENSE`.
