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

The world is one CesiumJS scene (Apache-2.0). Orbit, the site overview, and the driver camera read the same heightfield. There is no second scene and no reload when the camera flies from orbit to the ground.

Vehicles are a raycast chassis from [cannon-es](https://github.com/pmndrs/cannon-es) 0.20.0 (MIT). The dozer pushes soil ahead of the blade. The excavator holds soil in a bucket. The hauler dumps it. Cut volume, fill volume, and the load in the machines are the same soil.

The machine meshes are Kenney's Car Kit (`tractor-shovel.glb`, `tractor.glb`, `garbage-truck.glb`) and the shared `models/Textures/colormap.png` those files reference, [CC0](https://creativecommons.org/publicdomain/zero/1.0/). Credit Kenney, https://kenney.nl/assets/car-kit. No Blender or other GPL program code is included. The texture sits beside the models at the path the glTF asks for, so it resolves under a nested preview base.

[Steel](https://github.com/skild-ai/steel) (Apache-2.0, also in NVIDIA Newton) is a rigid-body solver for batched robot manipulation. Its browser build is WebGPU ([steel-webgpu](https://github.com/skild-ai/steel-webgpu)), not WASM, and it does not sculpt a heightfield. It is not linked into this app.

[TerraForge3D](https://github.com/Jaysmito101/TerraForge3D) (MIT) is a desktop terrain editor. Its erosion filters are C++ and OpenCL tied to that application. They were not copied. The rain control is a short droplet step written here: sediment that is picked up is laid down again.

Three.js (MIT) remains in the repository for the earlier basin viewer. The player-facing world no longer starts that viewer.

Machine rates and the rain step are sim parameters. Elevations start from the measured DEMs.

Roleplay's own code is MIT, copyright Atla LLC, 2026. See `LICENSE`.
