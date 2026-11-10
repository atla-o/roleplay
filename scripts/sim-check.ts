import { commandSwarm, emptyBook } from '../src/world/books';
import { PLAYABLE, RING_TILE, TILES } from '../src/world/tiles';
import { readFileSync } from 'node:fs';
import { decodeGrayPng } from '../src/load/png';
import { Heightfield } from '../src/sim/grid';
import { solveWater, type WaterConfig } from '../src/sim/water';
import { cutChannel } from '../src/sim/works';

const cfg: WaterConfig = {
  microrelief_m: 0.04,
  meltwater_mm: 40,
  melt_duration_days: 18,
  detention_slope_deg: 0.85,
  detention_max_m: 0.42,
  capture_m: 80,
  flow_draw_min_cells: 40,
  stream_coeff: 0.62,
  stream_cap_m: 0.65,
  pond_block_m: 0.12,
};

function assert(cond: unknown, message: string): void {
  if (!cond) throw new Error(message);
}

function bowl(): Heightfield {
  const cols = 70;
  const rows = 80;
  const spacing = 10;
  const z = new Float32Array(cols * rows);
  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < cols; c++) {
      let h = 90 - r * 0.08;
      const dx = c - 34;
      const dy = r - 28;
      const dist = Math.hypot(dx, dy);
      if (dist < 10) h -= (10 - dist) * 0.55;
      if (r >= 36 && r <= 40 && c >= 24 && c <= 44) h += 3.2;
      z[r * cols + c] = h;
    }
  }
  return new Heightfield(cols, rows, spacing, z);
}

const basin = bowl();
const before = solveWater(basin.z, basin.cols, basin.rows, basin.spacing, cfg, basin.channel, basin.graded);
assert(before.ponded_m3 > 200, `bowl should pond, got ${before.ponded_m3}`);
assert(before.ponded_m3 <= before.input_m3 * 1.02, 'ponded volume exceeds melt');
const low = before.ponds[0];
assert(low, 'expected a pond');
const bowlDepth = before.depth[low.low];
const start = basin.worldOf(low.low % basin.cols, (low.low / basin.cols) | 0);
cutChannel(basin, [start, { x: start.x, z: 0 }], {
  depth: 1.2,
  grade: 0.008,
  invertWidth: 8,
  sideSlopeRad: (28 * Math.PI) / 180,
  invertStart: basin.z[low.low] - 0.5,
});
const after = solveWater(basin.z, basin.cols, basin.rows, basin.spacing, cfg, basin.channel, basin.graded);
assert(after.depth[low.low] < bowlDepth * 0.35, `outlet should empty the bowl (${bowlDepth.toFixed(2)} m -> ${after.depth[low.low].toFixed(2)} m)`);
assert(after.ponded_m3 < before.ponded_m3, `standing water should fall (${before.ponded_m3} -> ${after.ponded_m3})`);
assert(Math.abs(after.ponded_m3 + after.runoff_m3 - after.input_m3) < after.input_m3 * 0.02, 'water was not conserved');

assert(TILES.length > 20, 'the world should be split into squares');
assert(PLAYABLE.playable && PLAYABLE.id === 'polar-desert-basin', 'the measured basin square is missing');
assert(RING_TILE.mode === 'observe' && RING_TILE.playable, 'the ring tile should be an observation square');
assert(RING_TILE.south <= 51.44 && RING_TILE.north >= 51.44 && RING_TILE.west <= -68.74 && RING_TILE.east >= -68.74, 'the ring square misses the island');
const ilePng = readFileSync(new URL('../public/data/ile/height.png', import.meta.url));
const ileMeta = JSON.parse(readFileSync(new URL('../public/data/ile/terrain.json', import.meta.url), 'utf8'));
const ileDecoded = await decodeGrayPng(ilePng.buffer.slice(ilePng.byteOffset, ilePng.byteOffset + ilePng.byteLength));
assert(ileDecoded.width === ileMeta.cols && ileDecoded.height === ileMeta.rows, 'ring raster does not match its grid');
assert(ileMeta.elevation_m.min > 300 && ileMeta.elevation_m.max > 900 && ileMeta.elevation_m.max < 1200, 'ring elevation is outside the measured window');
assert(commandSwarm(emptyBook(), 'survey').ok, 'a monitoring crew does not need a cut');
assert(PLAYABLE.west <= -89.509 && PLAYABLE.east > -89.509, 'basin longitude is outside its square');
const book = emptyBook();
assert(!commandSwarm(book, 'bio').ok, 'bio swarm should wait for drainage');
commandSwarm(book, 'mass');
commandSwarm(book, 'mass');
assert(book.fill_m3 === book.cut_m3, 'swarm cut and fill must match');
assert(commandSwarm(book, 'bio').ok, 'bio swarm should open after drainage');
assert(commandSwarm(book, 'structure').ok, 'structure swarm should spend stone');
assert(book.stone_m3 < book.cut_m3 * 0.38, 'structure swarm should draw the stone bank');

const png = readFileSync(new URL('../public/data/height.png', import.meta.url));
const meta = JSON.parse(readFileSync(new URL('../public/data/terrain.json', import.meta.url), 'utf8'));
const decoded = await decodeGrayPng(png.buffer.slice(png.byteOffset, png.byteOffset + png.byteLength));
assert(decoded.width === 500 && decoded.height === 500, 'height raster is not 500×500');
const z = new Float32Array(decoded.samples.length);
const span = meta.elevation_m.max - meta.elevation_m.min;
for (let i = 0; i < z.length; i++) z[i] = meta.elevation_m.min + (decoded.samples[i] / 65535) * span;
assert(z[0] > 60 && z[0] < 290, 'decoded elevation is outside the measured range');
const t0 = performance.now();
const real = solveWater(z, 500, 500, meta.spacing_m, { ...cfg, flow_draw_min_cells: 260, capture_m: 100 }, new Uint8Array(z.length), new Uint8Array(z.length));
const ms = performance.now() - t0;
assert(real.ponded_m3 > 1000, `measured basin should hold meltwater, got ${real.ponded_m3}`);
assert(real.ponded_m3 <= real.input_m3 * 1.02, 'measured ponding exceeds the melt budget');
console.log(
  `sim-check ok  bowl ${before.ponded_m3.toFixed(0)} -> ${after.ponded_m3.toFixed(0)} m3  basin ${real.ponded_m3.toFixed(0)} m3 in ${ms.toFixed(0)} ms`,
);
