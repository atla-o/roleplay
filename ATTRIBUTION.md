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

The Godot project uses the measured 2 m posts, not the older 120 m island mosaic.

Polar Desert Basin is ArcticDEM v4.1 at native 2 m, southwest corner EPSG:3413 X −1,116,740 m, Y −1,136,008 m, 2000 by 2000 posts. Elevations run from 66.60 m to 279.48 m. The machine starts near 2720 m east and 2700 m north of that corner, on a measured slope where the Sentinel-2 picture has contrast.

Île René-Levasseur is the western shore in NRCan HRDEM project `Lac_Pletipi_2024`, tile `dtm_1m_utm19_w_0_169`, averaged from 1 m to 2 m. Southwest corner UTM zone 19, 491800 E, 5696000 N. Elevations run from 348.29 m to 616.30 m. Posts the lidar left empty are filled with 348.59 m, the median of the measured water surface in this window. The water plane sits 0.55 m above that. Licence: Open Government Licence – Canada.

Color on both squares is Sentinel-2 cloudless from EOX (CC BY 4.0), containing modified Copernicus Sentinel data. The island mosaic is the 2020 cloudless file multiplied by 3 so boreal canopy is not stored as a near-black reflectance value. The basin mosaic is the 2021 file, unchanged.

An apron around each square eases from the measured edge posts toward one sample of the Mapzen/Tilezen terrarium DEM (zoom 5): 144 m at the basin and 348 m at the island. That apron is not a second elevation survey. A repeating shading grain, generated here, is a few centimetres of normal perturbation. It does not move the posts.

Trees and shrubs are meshes built in this repository and instanced where the Sentinel-2 picture is green and the ground is above the reservoir. They are not a stem survey.

The dozer, the human, and Titan are meshes built in this repository. No third-party model is loaded. The dozer is about 3.5 m across the tracks and 4.4 m across the blade.

Soil moved by the blade stays in the field. On the basin the pile may not stand steeper than 35°. On the island the limit is 32°. Those angles are the sandy-gravel and loose-till ranges in French, The Periglacial Environment (2007), and Das, Principles of Geotechnical Engineering. They are not a lab sample from either square. Bulk density is not applied as a force in this build; the blade slows only through the slope and a simple drag term.

Roleplay's own code is MIT, copyright Atla LLC, 2026. See `LICENSE`.
