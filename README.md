# Roleplay

Roleplay is the Creation division's world map and measured terrain. The map is a CesiumJS globe (Apache-2.0) split into Tier 1 cold squares, north first: Northern Canada, the United States including North Dakota, Northern Europe, Russia, and Antarctica, plus the Côte-Nord square. Two squares open measured ground. Polar Desert Basin is the 4 × 4 km Arctic surface: ArcticDEM and NHN, cold-method drainage, the ninety-day window, and a 1.7 m walk. Île René-Levasseur is the island in the Manicouagan ring reservoir. On the globe the ring reads as an O. That square is research terrain, not land to reshape: mass movers stay off it, and the crew there is a survey.

At globe scale the player is a giant. Swarm orders move mass movers, then the bio builder and weather manipulator, then structure builders, across a selected square. Cut and fill on that view are conserved sim parameters. They do not rewrite the measured basin.

The globe does not use Cesium ion. Imagery is Sentinel-2 cloudless from EOX over the Natural Earth II mosaic shipped with CesiumJS. Species dots are a thin GBIF occurrence layer. The Gene Ark catalog is still what gets deployed inside the basin.

It is a static site. `base` is `./`, so `dist/` can sit at the root of a host, on a subpath such as `https://atlas.rehab/creation/roleplay/`, or on a subdomain such as `https://roleplay.atlas.rehab/`.

Creation is one of six equal divisions of Atla LLC. Physics: Products, Modified, Creation. Biology: Consumed, Wellness, Covenant.

## Run

```bash
npm install
npm run build
npm run preview
```

`npm run typecheck` is included in the build. The baked rasters in `public/data/` are already committed, so the site does not need Python or GDAL at build time.

## Bake

`tools/bake/bake.py` rebuilds the Polar Desert Basin rasters from ArcticDEM v4.1 and the NRCan National Hydro Network. `tools/bake/ile.py` rebuilds the Île René-Levasseur window from the NRCan HRDEM mosaic, MRDEM-30, 2020 land cover, and a GBIF occurrence seed. See `tools/bake/README.md` and `ATTRIBUTION.md`.

## Parameters

Machine specs, the Gene Ark, phase copy, and the support link live in `data/*.json`. Elevations are the measured DEM. Rates, detention, and the growing window are sim parameters, labeled that way in the inspector.

The support link is `data/support.json`. It is an optional gift. It does not mark milestones. Milestones stay in local storage and are earned by the work done on the basin.
