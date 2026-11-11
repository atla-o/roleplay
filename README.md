# Roleplay

Roleplay is a 1:1 ground you can walk and drive. Polar Desert Basin is a 4 km square of ArcticDEM at 2 m. Île René-Levasseur is a 4 km square of Canada's 1 m HRDEM on the western shore, stored as the 2 m mean of those posts, with the reservoir drawn as water at the measured surface. Sentinel-2 colors the ground. A robot on that ground cuts and pushes soil. Cut and fill stay equal.

There is no HUD. One button in the corner opens two choices: viewpoint (Titan, Robot, Human) and place (the two sites). Esc closes it. `?capture=1` hides the button. Controls are listed below, not drawn on the screen.

It is a static site. `base` is `./`, so `dist/` can sit at the root of a host, on a subpath such as `https://atlas.rehab/creation/roleplay/`, or on a subdomain such as `https://roleplay.atlas.rehab/`.

Creation is one of six equal divisions of Atla LLC. Physics: Products, Modified, Creation. Biology: Consumed, Wellness, Covenant.

## Run

```bash
npm install
npm run build
npm run preview
```

`npm run typecheck` is included in the build. The baked rasters in `public/data/` are already committed, so the site does not need Python or GDAL at build time.

`?capture=1` hides the corner button. Nothing else is drawn on the picture.

## Controls

The corner button switches body and place. Esc closes that panel. Changing place keeps the edits and moves you to the middle of the other ground. A short camera move, under two seconds on a machine that holds 60 fps, carries you there.

**Robot.** You start in the machine. W is throttle, S brakes into reverse. A and D steer. The mouse, or the right stick, orbits the chase camera and it recenters behind the machine after about 1.5 seconds. Q raises the blade, E lowers it; hold either one. On a gamepad the right trigger is throttle, the left trigger is reverse, the left stick steers, and the bumpers raise and lower the blade. The blade is a height relative to the tracks. Lowered, it planes the posts in front of it and piles that soil ahead. The pile slumps to the angle of repose. Freshly cut ground is darker than the satellite picture. The machine slows as the cut gets heavier.

**Human.** Eye height is 1.8 m. WASD walks, the mouse looks (click the picture to capture the pointer), Shift runs, Space jumps. On a gamepad the left stick walks, the right stick looks, the right trigger runs, and the bottom face button jumps.

**Titan.** The same walk as a human, at 48 times the size, so a 4 km ground is a few minutes on foot. The stride is heavy and slow. Relief is not exaggerated.

Terrain edits are remembered in the browser. There is no menu that edits the ground.

## Bake

`tools/bake/bake.py` rebuilds the Polar Desert Basin rasters from ArcticDEM v4.1 and the NRCan National Hydro Network. The island square committed under `public/data/ile` is the shore window described in `ATTRIBUTION.md`. `tools/bake/ile.py` still builds the older wide mosaic. See `tools/bake/README.md` and `ATTRIBUTION.md`.

## Parameters

Machine specs, the Gene Ark, phase copy, and the support link live in `data/*.json`. Elevations are the measured DEM. Rates, detention, and the growing window are sim parameters, labeled that way in the inspector.

The support link is `data/support.json`. It is an optional gift. It does not mark milestones. Milestones stay in local storage and are earned by the work done on the basin.
