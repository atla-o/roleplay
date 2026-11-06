# Terrain bake

Rebuilds the measured Northern Canada patch committed under `public/data/`. The web build does not run this step.

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r tools/bake/requirements.txt
python tools/bake/bake.py
```

The script windows ArcticDEM v4.1 (2 m mosaic, collection `arcticdem-mosaics-v4.1-2m`) to the 4 km EPSG:3413 box and clips NRCan NHN work unit `10VE001` flowlines and waterbodies into local metres. Slope, closed-depression depth, and D8 flow accumulation are derived from that height grid. Outputs and source dates are recorded in `public/data/manifest.json`.

Cached downloads, if any, stay in `tools/bake/cache/` and are not part of the site.
