# Roleplay

Roleplay is the Creation division's interactive 3D view of a polar-desert succession. The ground is a measured 4 × 4 km basin in Northern Canada. Mass movers cut and drain it, a biological monitor and weather manipulator prepare a ninety-day growing season, the Gene Ark deploys a living catalog, and structure builders lay streets that can be walked.

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

`tools/bake/bake.py` rebuilds `public/data/` from ArcticDEM v4.1 and the NRCan National Hydro Network. See `tools/bake/README.md` and `ATTRIBUTION.md`.

## Parameters

Machine specs, the Gene Ark, phase copy, and the support link live in `data/*.json`. Elevations are the measured DEM. Rates, detention, and the growing window are sim parameters, labeled that way in the inspector.

The support link is `data/support.json`. It is an optional gift. It does not mark milestones. Milestones stay in local storage and are earned by the work done on the basin.
