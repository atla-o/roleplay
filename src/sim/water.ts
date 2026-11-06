import { DIST8, N8, neighborIndex } from './grid';

export interface WaterConfig {
  microrelief_m: number;
  meltwater_mm: number;
  melt_duration_days: number;
  detention_slope_deg: number;
  detention_max_m: number;
  capture_m: number;
  flow_draw_min_cells: number;
  stream_coeff: number;
  stream_cap_m: number;
  pond_block_m: number;
}

export interface Pond {
  id: number;
  volume_m3: number;
  area_m2: number;
  low: number;
  centroid: { x: number; z: number };
}

export interface WaterField {
  depth: Float32Array;
  stream: Float32Array;
  slope: Float32Array;
  pondId: Int32Array;
  ponds: Pond[];
  ponded_m3: number;
  runoff_m3: number;
  input_m3: number;
  pit_m3: number;
}

const OUT = -2;

/**
 * Surface water on frozen ground.
 * Closed depressions hold a real spill volume. Grades below the detention
 * threshold hold melt that cannot infiltrate permafrost, until a cut channel
 * captures them. Steep cells and surveyed flow paths carry the rest as waterways.
 */
export function solveWater(
  z: Float32Array,
  cols: number,
  rows: number,
  spacing: number,
  cfg: WaterConfig,
  channel: Uint8Array,
  graded: Uint8Array,
): WaterField {
  const n = cols * rows;
  const area = spacing * spacing;
  const melt = (cfg.meltwater_mm / 1000) * area;
  const input = n * melt;
  const slope = computeSlope(z, cols, rows, spacing);
  const dir = flowDir(z, cols, rows, spacing, cfg.microrelief_m);
  const term = terminals(dir, cols, rows);
  const pits = fillPits(z, dir, term, cols, rows, spacing, melt);
  const down = downhill(dir, cols, rows);
  const captured = capture(down, channel, graded, cols, rows, spacing, cfg.capture_m);

  const depth = pits.depth;
  let pitVol = 0;
  for (let i = 0; i < n; i++) pitVol += depth[i] * area;

  let want = 0;
  let freeCells = 0;
  const detention = new Float32Array(n);
  for (let i = 0; i < n; i++) {
    if (channel[i] || graded[i] || captured[i] || pits.catchment[i]) continue;
    if (slope[i] >= cfg.detention_slope_deg) continue;
    freeCells++;
    const t = 1 - slope[i] / cfg.detention_slope_deg;
    detention[i] = cfg.detention_max_m * Math.pow(Math.max(0, t), 1.35);
    want += detention[i];
  }
  const wantVol = want * area;
  const budget = Math.min(Math.max(0, input - pitVol), freeCells * melt);
  const scale = wantVol > budget && wantVol > 0 ? budget / wantVol : 1;
  let detVol = 0;
  for (let i = 0; i < n; i++) {
    const d = detention[i] * scale;
    if (d > depth[i]) depth[i] = d;
    detVol += d * area;
  }

  const counts = accumulation(down, n);
  const stream = new Float32Array(n);
  const stored = pitVol + detVol;
  const runoff = Math.max(0, input - stored);
  const perCellRunoff = runoff / n;
  const seconds = Math.max(1, cfg.melt_duration_days) * 86400;
  for (let i = 0; i < n; i++) {
    if (counts[i] < cfg.flow_draw_min_cells && !channel[i]) continue;
    const q = (counts[i] * perCellRunoff) / seconds;
    const film = Math.min(cfg.stream_cap_m, cfg.stream_coeff * Math.pow(Math.max(q, 0), 0.34));
    stream[i] = film;
    if (channel[i]) stream[i] = Math.max(stream[i], 0.22);
  }

  const ponds = labelPonds(depth, z, cols, rows, spacing, cfg.pond_block_m);
  let ponded = 0;
  for (let i = 0; i < n; i++) ponded += depth[i] * area;

  return {
    depth,
    stream,
    slope,
    pondId: ponds.ids,
    ponds: ponds.ponds,
    ponded_m3: ponded,
    runoff_m3: input - ponded,
    input_m3: input,
    pit_m3: pitVol,
  };
}

function computeSlope(z: Float32Array, cols: number, rows: number, spacing: number): Float32Array {
  const slope = new Float32Array(z.length);
  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < cols; c++) {
      const cL = Math.max(0, c - 1);
      const cR = Math.min(cols - 1, c + 1);
      const rN = Math.max(0, r - 1);
      const rS = Math.min(rows - 1, r + 1);
      const dzdx = (z[r * cols + cR] - z[r * cols + cL]) / ((cR - cL) * spacing || spacing);
      const dzdn = (z[rN * cols + c] - z[rS * cols + c]) / ((rS - rN) * spacing || spacing);
      slope[r * cols + c] = (Math.atan(Math.hypot(dzdx, dzdn)) * 180) / Math.PI;
    }
  }
  return slope;
}

function flowDir(
  z: Float32Array,
  cols: number,
  rows: number,
  spacing: number,
  epsilon: number,
): Int16Array {
  const n = cols * rows;
  const dir = new Int16Array(n);
  dir.fill(-1);
  for (let r = 0; r < rows; r++) {
    const borderRow = r === 0 || r === rows - 1;
    for (let c = 0; c < cols; c++) {
      const i = r * cols + c;
      const zi = z[i];
      let best = 0;
      let choice = -1;
      for (let k = 0; k < 8; k++) {
        const j = neighborIndex(i, k, cols, rows);
        if (j < 0) continue;
        const drop = zi - z[j];
        if (drop > epsilon) {
          const slope = drop / (DIST8[k] * spacing);
          if (slope > best) {
            best = slope;
            choice = k;
          }
        }
      }
      if (choice >= 0) dir[i] = choice;
      else if (borderRow || c === 0 || c === cols - 1) dir[i] = 8;
    }
  }
  const qx = new Int32Array(n);
  let qh = 0;
  let qt = 0;
  for (let i = 0; i < n; i++) if (dir[i] !== -1) qx[qt++] = i;
  while (qh < qt) {
    const i = qx[qh++];
    const zi = z[i];
    for (let k = 0; k < 8; k++) {
      const j = neighborIndex(i, k, cols, rows);
      if (j < 0 || dir[j] !== -1) continue;
      if (z[j] > zi + epsilon) continue;
      dir[j] = (k + 4) & 7;
      qx[qt++] = j;
    }
  }
  return dir;
}

function terminals(dir: Int16Array, cols: number, rows: number): Int32Array {
  const n = dir.length;
  const term = new Int32Array(n);
  term.fill(-99);
  const stack = new Int32Array(n);
  for (let start = 0; start < n; start++) {
    if (term[start] !== -99) continue;
    let sp = 0;
    let i = start;
    while (term[i] === -99) {
      term[i] = -98;
      stack[sp++] = i;
      const k = dir[i];
      if (k < 0 || k === 8) break;
      const j = neighborIndex(i, k, cols, rows);
      if (j < 0) {
        dir[i] = 8;
        break;
      }
      if (term[j] === -98) {
        dir[i] = -1;
        break;
      }
      i = j;
    }
    let sink: number;
    if (dir[i] === 8) sink = OUT;
    else if (term[i] >= OUT && term[i] !== -98 && term[i] !== -99) sink = term[i];
    else sink = i;
    for (let s = 0; s < sp; s++) term[stack[s]] = sink;
  }
  return term;
}

function downhill(dir: Int16Array, cols: number, rows: number): Int32Array {
  const down = new Int32Array(dir.length);
  down.fill(-1);
  for (let i = 0; i < dir.length; i++) {
    const k = dir[i];
    if (k >= 0 && k < 8) down[i] = neighborIndex(i, k, cols, rows);
  }
  return down;
}

function capture(
  down: Int32Array,
  channel: Uint8Array,
  graded: Uint8Array,
  cols: number,
  rows: number,
  spacing: number,
  reach: number,
): Uint8Array {
  const n = down.length;
  const out = new Uint8Array(n);
  const maxSteps = Math.max(1, Math.ceil(reach / spacing) + 1);
  for (let start = 0; start < n; start++) {
    if (graded[start]) {
      out[start] = 1;
      continue;
    }
    let i = start;
    let dist = 0;
    for (let step = 0; step < maxSteps; step++) {
      if (channel[i]) {
        out[start] = 1;
        break;
      }
      const j = down[i];
      if (j < 0) break;
      const c0 = i % cols;
      const r0 = (i / cols) | 0;
      const c1 = j % cols;
      const r1 = (j / cols) | 0;
      dist += Math.hypot(c1 - c0, r1 - r0) * spacing;
      if (dist > reach) break;
      i = j;
    }
  }
  return out;
}

function accumulation(down: Int32Array, n: number): Float32Array {
  const indeg = new Int32Array(n);
  for (let i = 0; i < n; i++) if (down[i] >= 0) indeg[down[i]]++;
  const queue = new Int32Array(n);
  let qh = 0;
  let qt = 0;
  for (let i = 0; i < n; i++) if (indeg[i] === 0) queue[qt++] = i;
  const acc = new Float32Array(n);
  for (let i = 0; i < n; i++) acc[i] = 1;
  while (qh < qt) {
    const i = queue[qh++];
    const j = down[i];
    if (j >= 0) {
      acc[j] += acc[i];
      if (--indeg[j] === 0) queue[qt++] = j;
    }
  }
  return acc;
}

function fillPits(
  z: Float32Array,
  dir: Int16Array,
  term: Int32Array,
  cols: number,
  rows: number,
  spacing: number,
  melt: number,
): { depth: Float32Array; catchment: Uint8Array } {
  const n = z.length;
  const area = spacing * spacing;
  const pitDepth = new Float32Array(n);
  const catchment = new Uint8Array(n);
  const pitOfCell = new Int32Array(n);
  pitOfCell.fill(-1);
  const pits: number[] = [];
  for (let i = 0; i < n; i++) {
    if (dir[i] < 0) {
      pitOfCell[i] = pits.length;
      pits.push(i);
    }
  }
  const np = pits.length;
  if (np === 0) return { depth: pitDepth, catchment };
  const compact = new Int32Array(n);
  compact.fill(OUT);
  for (let i = 0; i < n; i++) {
    const t = term[i];
    if (t >= 0 && dir[t] < 0) compact[i] = pitOfCell[t];
  }

  const counts = new Int32Array(np);
  for (let i = 0; i < n; i++) if (compact[i] >= 0) counts[compact[i]]++;
  const start = new Int32Array(np);
  let sum = 0;
  for (let i = 0; i < np; i++) {
    start[i] = sum;
    sum += counts[i];
  }
  const cursor = start.slice();
  const catchCells = new Int32Array(sum);
  for (let i = 0; i < n; i++) {
    const t = compact[i];
    if (t >= 0) {
      catchment[i] = 1;
      catchCells[cursor[t]++] = i;
    }
  }

  const OUT_ID = np;
  const parent = new Int32Array(np + 1);
  const linked = new Uint8Array(np + 1);
  const members: number[][] = new Array(np + 1);
  for (let i = 0; i < np; i++) {
    parent[i] = i;
    members[i] = [i];
  }
  parent[OUT_ID] = OUT_ID;
  linked[OUT_ID] = 1;
  members[OUT_ID] = [];

  const find = (x: number) => {
    let r = x;
    while (parent[r] !== r) r = parent[r];
    while (parent[x] !== r) {
      const next = parent[x];
      parent[x] = r;
      x = next;
    }
    return r;
  };
  const union = (a: number, b: number) => {
    a = find(a);
    b = find(b);
    if (a === b) return;
    parent[b] = a;
    const mb = members[b];
    const ma = members[a];
    for (let i = 0; i < mb.length; i++) ma.push(mb[i]);
    members[b] = [];
    if (linked[b]) linked[a] = 1;
  };

  interface Pass {
    a: number;
    b: number;
    spill: number;
    cellA: number;
    cellB: number;
  }
  const passMap = new Map<number, Pass>();
  const span = np + 1;
  for (let i = 0; i < n; i++) {
    const idA = compact[i] < 0 ? OUT_ID : compact[i];
    const c = i % cols;
    const r = (i / cols) | 0;
    for (let k = 0; k < 8; k++) {
      const cc = c + N8[k][0];
      const rr = r + N8[k][1];
      if (cc < 0 || rr < 0 || cc >= cols || rr >= rows) continue;
      const j = rr * cols + cc;
      if (j < i) continue;
      const idB = compact[j] < 0 ? OUT_ID : compact[j];
      if (idA === idB) continue;
      const spill = Math.max(z[i], z[j]);
      const lo = idA < idB ? idA : idB;
      const hi = idA < idB ? idB : idA;
      const key = lo * span + hi;
      const prev = passMap.get(key);
      if (!prev || spill < prev.spill) {
        passMap.set(key, { a: idA, b: idB, spill, cellA: i, cellB: j });
      }
    }
  }
  const passes = [...passMap.values()].sort((p, q) => p.spill - q.spill || p.a - q.a || p.b - q.b);

  const lakeOf = new Int32Array(np);
  lakeOf.fill(-1);
  const outletZ = new Float64Array(np);
  outletZ.fill(Infinity);
  const destLake = new Int32Array(np);
  destLake.fill(-1);
  const passCell = new Int32Array(np);
  passCell.fill(-1);
  let nextLake = 0;

  for (const pass of passes) {
    const aRoot = find(pass.a);
    const bRoot = find(pass.b);
    if (aRoot === bRoot) continue;
    const aOut = linked[aRoot] === 1;
    const bOut = linked[bRoot] === 1;
    if (aOut && bOut) {
      union(aRoot, bRoot);
      continue;
    }
    if (!aOut && !bOut) {
      union(aRoot, bRoot);
      continue;
    }
    const inlandRoot = aOut ? bRoot : aRoot;
    const outerRoot = aOut ? aRoot : bRoot;
    const list = members[inlandRoot].slice();
    const lakeId = nextLake++;
    const outerId = aOut ? pass.a : pass.b;
    const dest = outerId === OUT_ID || lakeOf[outerId] < 0 ? -1 : lakeOf[outerId];
    const inject = aOut ? pass.cellA : pass.cellB;
    for (const pit of list) {
      lakeOf[pit] = lakeId;
      outletZ[pit] = pass.spill;
      destLake[pit] = dest;
      passCell[pit] = inject;
    }
    linked[inlandRoot] = 1;
    union(outerRoot, inlandRoot);
  }

  const endorheicLake = new Map<number, number>();
  for (let pit = 0; pit < np; pit++) {
    if (lakeOf[pit] !== -1) continue;
    const root = find(pit);
    let id = endorheicLake.get(root);
    if (id === undefined) {
      id = nextLake++;
      endorheicLake.set(root, id);
    }
    lakeOf[pit] = id;
    outletZ[pit] = Infinity;
    destLake[pit] = -1;
  }

  const lakeCount = nextLake;
  const lakePits: number[][] = Array.from({ length: lakeCount }, () => []);
  for (let pit = 0; pit < np; pit++) lakePits[lakeOf[pit]].push(pit);
  const lakeInput = new Float64Array(lakeCount);
  for (let pit = 0; pit < np; pit++) lakeInput[lakeOf[pit]] += counts[pit] * melt;

  const order = lakePits.map((_, id) => id).filter((id) => lakePits[id].length > 0);
  order.sort((a, b) => {
    const za = Number.isFinite(outletZ[lakePits[a][0]]) ? outletZ[lakePits[a][0]] : -1;
    const zb = Number.isFinite(outletZ[lakePits[b][0]]) ? outletZ[lakePits[b][0]] : -1;
    return zb - za || b - a;
  });

  const solved = new Uint8Array(lakeCount);
  for (const id of order) {
    const pitsHere = lakePits[id];
    if (!pitsHere.length) continue;
    const spill = outletZ[pitsHere[0]];
    let count = 0;
    for (const pit of pitsHere) count += counts[pit];
    const cells = new Int32Array(count);
    let write = 0;
    for (const pit of pitsHere) {
      const a = start[pit];
      const len = counts[pit];
      cells.set(catchCells.subarray(a, a + len), write);
      write += len;
    }
    const ranked = Array.from(cells);
    ranked.sort((a, b) => z[a] - z[b]);
    const level = waterLevel(ranked, z, lakeInput[id], spill, area);
    for (const cell of ranked) {
      if (z[cell] < level.height) pitDepth[cell] = level.height - z[cell];
    }
    const excess = level.excess;
    const dest = destLake[pitsHere[0]];
    if (excess > 0 && dest >= 0 && !solved[dest]) lakeInput[dest] += excess;
    solved[id] = 1;
  }
  return { depth: pitDepth, catchment };
}

function waterLevel(
  ranked: number[],
  z: Float32Array,
  input: number,
  outlet: number,
  area: number,
): { height: number; excess: number } {
  const count = ranked.length;
  if (!count || input <= 0) return { height: count ? z[ranked[0]] : 0, excess: Math.max(0, input) };
  let remaining = input;
  let height = z[ranked[0]];
  for (let i = 0; i < count; i++) {
    const here = z[ranked[i]];
    const next = i + 1 < count ? z[ranked[i + 1]] : Number.POSITIVE_INFINITY;
    const capZ = Math.min(next, outlet);
    if (!(capZ > here)) continue;
    const footprint = (i + 1) * area;
    const room = (capZ - here) * footprint;
    if (remaining <= room) {
      height = here + remaining / footprint;
      remaining = 0;
      break;
    }
    remaining -= room;
    height = capZ;
    if (height >= outlet) break;
  }
  if (remaining < 1e-6) remaining = 0;
  return { height, excess: remaining };
}

function labelPonds(
  depth: Float32Array,
  z: Float32Array,
  cols: number,
  rows: number,
  spacing: number,
  minDepth: number,
): { ids: Int32Array; ponds: Pond[] } {
  const n = depth.length;
  const ids = new Int32Array(n);
  ids.fill(-1);
  const ponds: Pond[] = [];
  const stack = new Int32Array(n);
  for (let start = 0; start < n; start++) {
    if (ids[start] !== -1 || depth[start] < minDepth) continue;
    const id = ponds.length;
    let sp = 0;
    stack[sp++] = start;
    ids[start] = id;
    let volume = 0;
    let area = 0;
    let low = start;
    let sx = 0;
    let sz = 0;
    let count = 0;
    while (sp) {
      const i = stack[--sp];
      volume += depth[i] * spacing * spacing;
      area += spacing * spacing;
      if (z[i] < z[low]) low = i;
      const c = i % cols;
      const r = (i / cols) | 0;
      sx += c * spacing;
      sz += (rows - 1 - r) * spacing;
      count++;
      for (let k = 0; k < 8; k++) {
        const j = neighborIndex(i, k, cols, rows);
        if (j < 0 || ids[j] !== -1 || depth[j] < minDepth) continue;
        ids[j] = id;
        stack[sp++] = j;
      }
    }
    ponds.push({
      id,
      volume_m3: volume,
      area_m2: area,
      low,
      centroid: { x: sx / count, z: sz / count },
    });
  }
  ponds.sort((a, b) => b.volume_m3 - a.volume_m3);
  return { ids, ponds };
}
