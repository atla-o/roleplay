# Roleplay

The playable build is the Godot 4.7 project in `godot/`. Desktop play uses the Forward+ renderer. The web preview uses the Compatibility renderer so it can load on GitHub Pages. The earlier Cesium and Three.js viewers are still in this repository.

## Play the Godot world

Controls are the same on Linux and in the browser.

- **Robot.** W throttle, S brake into reverse, A and D steer. Q raises the blade, E lowers it. Hold the left mouse button to lower the blade and the right button to raise it. The mouse, or the right stick, orbits the chase camera. It recenters after about a second and a half.
- **Human.** A 1.8 m person, camera behind them. WASD walks, Shift runs, Space jumps. Walk, run and idle come from the character's animation clips.
- **Settings.** One button, bottom left. It switches Robot and Human, and teleports to named places on the basin and the island. Esc closes it. Nothing else is drawn on screen. `?capture=1` on the web build, or `--capture`, hides the button.
- **Water.** On the island the ground ends at the reservoir. Shallows slow you. Deeper water stops you. There is no wall at the old square.
- **Gamepad.** Left stick drives, triggers throttle and reverse, bumpers move the blade, right stick looks, bottom face button jumps.

```bash
# Godot 4.7.2, from the project folder
godot --path godot
```

`godot --headless --path godot -s res://tests/conservation.gd` checks that a blade cut keeps the volume: cut equals fill, and the sum of the heights does not change.

Export presets are Linux x86_64, Linux arm64 (both Forward+), and Web (Compatibility, no threads). The pull-request workflow exports them. Linux binaries are workflow artifacts. The web build is the preview.

The frame rate is printed to the console every two seconds (`fps N`). On this agent's software OpenGL it was about 2 fps. That number is not a measurement of an M2 MacBook.

## Earlier viewer

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
