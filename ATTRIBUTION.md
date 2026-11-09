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

## Species layer

Occurrence points in `public/data/occurrences.json` were retrieved from the [GBIF Occurrence API](https://www.gbif.org) on 2026-11-09. Cite GBIF.org. Each record keeps the licence of its source dataset.

## Viewer

The world map uses [CesiumJS](https://cesium.com/cesiumjs/) (Apache-2.0). The basin uses [Three.js](https://threejs.org/) (MIT). Machine rates, permafrost detention, swarm volumes, and the ninety-day growing window are sim parameters. Elevations in the basin are the measured DEM.

Roleplay's own code is MIT, copyright Atla LLC, 2026. See `LICENSE`.
