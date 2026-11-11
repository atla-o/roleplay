# Roleplay

Roleplay is the Creation division's measured world. One CesiumJS globe holds both playable grounds. The camera flies from orbit down onto the same heightfield the driver sees. Polar Desert Basin is the 4 km Arctic surface from ArcticDEM. Île René-Levasseur is the island in the Manicouagan ring, from the NRCan HRDEM mosaic. A mass mover, an excavator, and a hauler drive on that ground. The blade pushes soil, the bucket holds it, and a dump puts it back. Cut and fill are the same earth.

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

Open `?capture=1` to hide the header, panels, minimap, and prompts for a clean frame. C shows or hides the small title card. There is no scripted tour.

You start beside the mass mover on the Polar Desert Basin. Hold E to get in, drive with WASD or a gamepad's left stick, and lower the blade with F or the right trigger. The first job is a 40 m pad. Fuel is in the header. Let off the throttle beside the fuel stake to refill. X puts the machine back on its tracks at the depot. Reset site restores that ground and its jobs.

## Bake

`tools/bake/bake.py` rebuilds the Polar Desert Basin rasters from ArcticDEM v4.1 and the NRCan National Hydro Network. `tools/bake/ile.py` rebuilds the Île René-Levasseur window from the NRCan HRDEM mosaic, MRDEM-30, 2020 land cover, and a GBIF occurrence seed. See `tools/bake/README.md` and `ATTRIBUTION.md`.

## Parameters

Machine specs, the Gene Ark, phase copy, and the support link live in `data/*.json`. Elevations are the measured DEM. Rates, detention, and the growing window are sim parameters, labeled that way in the inspector.

The support link is `data/support.json`. It is an optional gift. It does not mark milestones. Milestones stay in local storage and are earned by the work done on the basin.
