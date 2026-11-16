# Attribution

Roleplay is a pure digital simulation built from open elevation data with no land claim or ground impact. The basin is framed only as **Northern Canada (Polar Desert Basin, 4 × 4 km)**. It is published with the Creation division at [atlas.rehab](https://atlas.rehab/).

The measured window is EPSG:3413, X −1,116,740 m to −1,112,740 m, Y −1,136,011 m to −1,132,011 m. The centre is 75.3971°N, 89.509°W.

## ArcticDEM v4.1

Elevation is the public ArcticDEM v4.1 2 m mosaic (collection `arcticdem-mosaics-v4.1-2m`, STAC `https://stac.pgc.umn.edu/api/v1`), resampled to a 500 × 500 post grid.

Porter et al. 2023. ArcticDEM, Version 4.1. Polar Geospatial Center, University of Minnesota. https://doi.org/10.7910/DVN/3VDC4W

Licence: [CC-BY-4.0](https://creativecommons.org/licenses/by/4.0/).

## National Hydro Network

Flowlines and waterbodies are clipped from Natural Resources Canada National Hydro Network work unit `10VE001`.

Licence: [Open Government Licence – Canada](https://open.canada.ca/en/open-government-licence-canada).

Slope, closed-depression depth, and D8 flow accumulation are derived from the measured elevation grid. Derived flow lines in `hydro.geojson` are marked `derived-flow-accumulation` and are not NHN features.

## World imagery

Sentinel-2 cloudless by [EOX IT Services GmbH](https://s2maps.eu) (CC BY 4.0), containing modified Copernicus Sentinel data 2021. The fallback mosaic is Natural Earth II, shipped with CesiumJS and in the public domain.

## Île René-Levasseur

The second measured square is the island in the Manicouagan ring reservoir, Quebec. It is research terrain and an emblem of the O, not land to reshape.

Place: Louis-Babel Ecological Reserve, Réserve de biodiversité de la Météorite, Manicouagan-Uapishka UNESCO Biosphere Reserve, and Nitassinan of the Innu of Pessamit. The reservoir is held by Hydro-Québec's Daniel-Johnson Dam. Mont de Babel is about 952 m.

Elevation on the tile is the NRCan HRDEM mosaic 1 m DTM, resampled. Licence: Open Government Licence – Canada. ArcticDEM does not cover 51°N. NRCan MRDEM-30 is sampled on the same window for the coarser national surface (Open Government Licence – Canada; Copernicus GLO-30 is an input to MRDEM). Quebec's own 1 m LiDAR sheets (CC BY 4.0, Données Québec) were not downloaded one by one; the HRDEM mosaic is the lidar-derived national surface over this island.

Water on the tile is the water class of NRCan 2020 Land Cover of Canada (Open Government Licence – Canada). GRHQ and NHN lines were not clipped into this build.

## Species layer

Occurrence points in `public/data/occurrences.json` were retrieved from the [GBIF Occurrence API](https://www.gbif.org) on 2026-11-09. Cite GBIF.org. Each record keeps the licence of its source dataset.

## Viewer

The earlier world map uses [CesiumJS](https://cesium.com/cesiumjs/) (Apache-2.0). The earlier basin viewer uses [Three.js](https://threejs.org/) (MIT). Both stay in the repository.

The playable build in `godot/` is [Godot Engine](https://godotengine.org/) 4.7 (MIT). Desktop exports use the Forward+ renderer. The web preview uses the Compatibility renderer, single-threaded, so GitHub Pages does not need cross-origin isolation headers.

## Godot ground

The playable world is three 2 m tiles. The outer few hundred metres of each square are lowered toward the water along a wandering line so the horizon is a shore. That fringe is not a second survey. The interior posts are the measured DEM.

Northern 1 — Canada is ArcticDEM v4.1 at native 2 m, southwest corner EPSG:3413 X −1,116,740 m, Y −1,136,008 m, 2000 by 2000 posts. The machine starts on a flat bench inland of the water, near 1936 m east and 1568 m north of that corner.

Northern 2 — Europe is ArcticDEM v4.1 at 2 m on the west coast of Svalbard, a 4 km window in EPSG:32633 centred near 78.049°N, 13.644°E (mosaic tiles `34_51_1_2_2m_v4.1` and `34_52_1_1_2m_v4.1`). The machine starts on the coastal flat.

Northern 3 — Russia is ArcticDEM v4.1 at 2 m on the west coast of Yamal, a 4 km window in EPSG:32642 centred near 70.493°N, 67.913°E (mosaic tile `49_60_1_2_2m_v4.1`). The machine starts on the tundra above the sea.

Color on the three tiles is Sentinel-2 cloudless from EOX (CC BY 4.0), containing modified Copernicus Sentinel data. Canada uses the 2021 file. Europe and Russia use the 2021 tiles, with the 2020 file as a fallback if a tile is missing.

An apron around each square eases from the measured edge posts toward one sample of the Mapzen/Tilezen terrarium DEM (zoom 5): 144 m at the basin and 348 m at the island. That apron is not a second elevation survey. A repeating shading grain, generated here, is a few centimetres of normal perturbation. It does not move the posts.

Trees and shrubs are meshes built in this repository and instanced where the Sentinel-2 picture is green and the ground is above the reservoir. They are not a stem survey.

The dozer is "Tracked bulldozer with raising and angling blade" from 3DAssets.dev, CC0 1.0, https://3dassets.dev/assets/demolition-and-site-clearance-demolition-and-site-clea-b80ffe3a . The blade clip raises and lowers. Digging stays on this project's collider. The human is Quaternius Ultimate Modular Characters, the Worker, CC0, with Idle, Walk and Run. Trees, grass, bush and the boulder are Quaternius Stylized Nature Megakit, CC0 (pine_1, pine_3, grass_common_short, grass_wispy_tall, bush_common, rock_medium_1). Birch trees are Quaternius Nature Pack, CC0 (BirchTree_1, BirchTree_2, BirchTree_4). Far trees are a generated stand-in, not a scanned stem.

Ground detail textures are Poly Haven CC0, 1K: sandy_gravel_02, rocky_terrain, forest_floor, forest_leaves_03, coast_sand_01, brown_mud. https://polyhaven.com . The API asks for a Poly Haven credit, which this line is.

Soil moved by the blade stays in the field. On the basin the pile may not stand steeper than 35°. On the island the limit is 32°. Those angles are the sandy-gravel and loose-till ranges in French, The Periglacial Environment (2007), and Das, Principles of Geotechnical Engineering. They are not a lab sample from either square. Bulk density is not applied as a force in this build; the blade slows only through the slope and a simple drag term.

Roleplay's own code is MIT, copyright Atla LLC, 2026. See `LICENSE`.
