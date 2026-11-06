import type { Heightfield } from './grid';

export interface ChannelOptions {
  depth: number;
  grade: number;
  invertWidth: number;
  sideSlopeRad: number;
  /** Invert elevation at the first point. Defaults to ground minus depth. */
  invertStart?: number;
  /** A ditch stays within maxCut of the local ground and outlets at the downstream end. */
  profile?: 'graded' | 'ditch';
  maxCut?: number;
}

export interface CutResult {
  cut_m3: number;
  cells: number;
}

/** Cut a graded invert along a polyline. Only lowers ground. Marks the thalweg as channel. */
export function cutChannel(field: Heightfield, points: { x: number; z: number }[], opts: ChannelOptions): CutResult {
  if (points.length < 2) return { cut_m3: 0, cells: 0 };
  const samples = resample(points, field.spacing * 0.5);
  const stamped =
    opts.profile === 'ditch'
      ? ditchProfile(field, samples, opts.grade, opts.depth, opts.maxCut ?? opts.depth + 0.6)
      : gradedProfile(field, samples, opts);
  return stampInvert(field, stamped, opts.invertWidth * 0.5, opts.sideSlopeRad, true);
}

function gradedProfile(
  field: Heightfield,
  samples: { x: number; z: number }[],
  opts: ChannelOptions,
): { x: number; z: number; invert: number }[] {
  let dist = 0;
  const invert0 = opts.invertStart ?? field.sample(samples[0].x, samples[0].z) - opts.depth;
  const stamped = [{ ...samples[0], invert: invert0 }];
  for (let i = 1; i < samples.length; i++) {
    dist += Math.hypot(samples[i].x - samples[i - 1].x, samples[i].z - samples[i - 1].z);
    stamped.push({ ...samples[i], invert: invert0 - dist * opts.grade });
  }
  return stamped;
}

function ditchProfile(
  field: Heightfield,
  samples: { x: number; z: number }[],
  grade: number,
  depth: number,
  maxCut: number,
): { x: number; z: number; invert: number }[] {
  const ground = samples.map((s) => field.sample(s.x, s.z));
  const invert = new Array<number>(samples.length);
  invert[samples.length - 1] = ground[samples.length - 1] - Math.min(0.3, depth);
  for (let i = samples.length - 2; i >= 0; i--) {
    const step = Math.hypot(samples[i + 1].x - samples[i].x, samples[i + 1].z - samples[i].z);
    const graded = invert[i + 1] + grade * step;
    const shallow = ground[i] - depth;
    const deep = ground[i] - maxCut;
    invert[i] = Math.max(deep, Math.min(shallow, graded));
  }
  return samples.map((s, i) => ({ ...s, invert: invert[i] }));
}

export interface GradeResult {
  cut_m3: number;
  fill_m3: number;
  padZ: number;
  ok: boolean;
  reason?: string;
}

/**
 * Grade a circular pad with a built fall so the surface sheds.
 * `heading` is the downslope direction, 0 = north.
 * Fill cannot exceed the fill already in the bank plus fill produced by the cut.
 */
export function gradePad(
  field: Heightfield,
  cx: number,
  cz: number,
  radius: number,
  fall: number,
  heading: number,
  sideSlopeRad: number,
  availableFill: number,
  fillFraction: number,
): GradeResult {
  const reach = radius + 48;
  const bounds = diskBounds(field, cx, cz, reach);
  if (!bounds) return { ok: false, reason: 'The pad sits off the measured surface.', cut_m3: 0, fill_m3: 0, padZ: 0 };
  const samples: number[] = [];
  for (let r = bounds.r0; r <= bounds.r1; r++) {
    for (let c = bounds.c0; c <= bounds.c1; c++) {
      const p = field.worldOf(c, r);
      if (Math.hypot(p.x - cx, p.z - cz) <= radius) samples.push(field.z[field.idx(c, r)]);
    }
  }
  if (samples.length < 4) return { ok: false, reason: 'The pad sits off the measured surface.', cut_m3: 0, fill_m3: 0, padZ: 0 };
  let lo = Math.min(...samples) - 2;
  let hi = Math.max(...samples) + 2;
  const trial = (padZ: number) => measurePad(field, cx, cz, radius, fall, heading, sideSlopeRad, padZ, bounds);
  let best = trial((lo + hi) / 2);
  for (let i = 0; i < 18; i++) {
    const mid = (lo + hi) / 2;
    best = trial(mid);
    const produced = availableFill + best.cut * fillFraction;
    if (best.cut > best.fill && best.fill <= produced) lo = mid;
    else hi = mid;
  }
  let padZ = (lo + hi) / 2;
  best = trial(padZ);
  // Prefer a higher pad when the bank cannot fund the fill.
  for (let i = 0; i < 16 && best.fill > availableFill + best.cut * fillFraction + 0.5; i++) {
    padZ += 0.15;
    best = trial(padZ);
  }
  if (best.fill > availableFill + best.cut * fillFraction + 1) {
    return { ok: false, reason: 'The fill bank cannot raise this pad. Cut elsewhere first, or choose higher ground.', cut_m3: best.cut, fill_m3: best.fill, padZ };
  }
  applyPad(field, cx, cz, radius, fall, heading, sideSlopeRad, padZ, bounds);
  return { ok: true, cut_m3: best.cut, fill_m3: best.fill, padZ };
}

export function digPit(
  field: Heightfield,
  cx: number,
  cz: number,
  radius: number,
  depth: number,
  sideSlopeRad: number,
): CutResult {
  const floor = field.sample(cx, cz);
  if (!Number.isFinite(floor)) return { cut_m3: 0, cells: 0 };
  const targetFloor = floor - depth;
  const reach = radius + depth / Math.tan(sideSlopeRad) + field.spacing;
  const bounds = diskBounds(field, cx, cz, reach);
  if (!bounds) return { cut_m3: 0, cells: 0 };
  const area = field.spacing * field.spacing;
  let cut = 0;
  let cells = 0;
  for (let r = bounds.r0; r <= bounds.r1; r++) {
    for (let c = bounds.c0; c <= bounds.c1; c++) {
      const p = field.worldOf(c, r);
      const d = Math.hypot(p.x - cx, p.z - cz);
      const limit = d <= radius ? targetFloor : targetFloor + (d - radius) * Math.tan(sideSlopeRad);
      const i = field.idx(c, r);
      if (limit < field.z[i] - 0.01) {
        cut += (field.z[i] - limit) * area;
        field.z[i] = limit;
        field.edited[i] = 1;
        cells++;
      }
    }
  }
  return { cut_m3: cut, cells };
}

function resample(points: { x: number; z: number }[], step: number): { x: number; z: number }[] {
  const out: { x: number; z: number }[] = [{ ...points[0] }];
  for (let i = 1; i < points.length; i++) {
    const a = points[i - 1];
    const b = points[i];
    const len = Math.hypot(b.x - a.x, b.z - a.z);
    const n = Math.max(1, Math.ceil(len / step));
    for (let s = 1; s <= n; s++) {
      const t = s / n;
      out.push({ x: a.x + (b.x - a.x) * t, z: a.z + (b.z - a.z) * t });
    }
  }
  return out;
}

function stampInvert(
  field: Heightfield,
  samples: { x: number; z: number; invert: number }[],
  halfFlat: number,
  sideSlopeRad: number,
  markChannel: boolean,
): CutResult {
  const across = new Float32Array(field.z.length);
  across.fill(Infinity);
  const invertAt = new Float32Array(field.z.length);
  const reach = halfFlat + 28;
  const rad = Math.ceil(reach / field.spacing) + 1;
  for (const sample of samples) {
    if (!Number.isFinite(sample.invert)) continue;
    const rc = field.rcOf(sample.x, sample.z);
    const c0 = clamp(Math.floor(rc.c) - rad, 0, field.cols - 1);
    const c1 = clamp(Math.ceil(rc.c) + rad, 0, field.cols - 1);
    const r0 = clamp(Math.floor(rc.r) - rad, 0, field.rows - 1);
    const r1 = clamp(Math.ceil(rc.r) + rad, 0, field.rows - 1);
    for (let r = r0; r <= r1; r++) {
      for (let c = c0; c <= c1; c++) {
        const p = field.worldOf(c, r);
        const d = Math.hypot(p.x - sample.x, p.z - sample.z);
        const i = field.idx(c, r);
        if (d < across[i]) {
          across[i] = d;
          invertAt[i] = sample.invert;
        }
      }
    }
  }
  const area = field.spacing * field.spacing;
  const tan = Math.tan(sideSlopeRad);
  let cut = 0;
  let cells = 0;
  for (let i = 0; i < across.length; i++) {
    if (across[i] > reach) continue;
    const target = across[i] <= halfFlat ? invertAt[i] : invertAt[i] + (across[i] - halfFlat) * tan;
    if (target < field.z[i] - 0.015) {
      cut += (field.z[i] - target) * area;
      field.z[i] = target;
      field.edited[i] = 1;
      cells++;
      if (markChannel && across[i] <= halfFlat + field.spacing * 0.6) field.channel[i] = 1;
    }
  }
  return { cut_m3: cut, cells };
}

function measurePad(
  field: Heightfield,
  cx: number,
  cz: number,
  radius: number,
  fall: number,
  heading: number,
  sideSlopeRad: number,
  padZ: number,
  bounds: Bounds,
): { cut: number; fill: number } {
  const area = field.spacing * field.spacing;
  const sin = Math.sin(heading);
  const cos = Math.cos(heading);
  const tan = Math.tan(sideSlopeRad);
  let cut = 0;
  let fill = 0;
  for (let r = bounds.r0; r <= bounds.r1; r++) {
    for (let c = bounds.c0; c <= bounds.c1; c++) {
      const i = field.idx(c, r);
      if (field.channel[i]) continue;
      const p = field.worldOf(c, r);
      const target = padTarget(p.x, p.z, cx, cz, radius, fall, sin, cos, tan, padZ, field.z[i]);
      if (target === null) continue;
      const d = target - field.z[i];
      if (d < -0.01) cut += -d * area;
      else if (d > 0.01) fill += d * area;
    }
  }
  return { cut, fill };
}

function applyPad(
  field: Heightfield,
  cx: number,
  cz: number,
  radius: number,
  fall: number,
  heading: number,
  sideSlopeRad: number,
  padZ: number,
  bounds: Bounds,
): void {
  const sin = Math.sin(heading);
  const cos = Math.cos(heading);
  const tan = Math.tan(sideSlopeRad);
  for (let r = bounds.r0; r <= bounds.r1; r++) {
    for (let c = bounds.c0; c <= bounds.c1; c++) {
      const i = field.idx(c, r);
      if (field.channel[i]) continue;
      const p = field.worldOf(c, r);
      const target = padTarget(p.x, p.z, cx, cz, radius, fall, sin, cos, tan, padZ, field.z[i]);
      if (target === null || Math.abs(target - field.z[i]) < 0.01) continue;
      field.z[i] = target;
      field.edited[i] = 1;
      if (Math.hypot(p.x - cx, p.z - cz) <= radius) field.graded[i] = 1;
    }
  }
}

function padTarget(
  x: number,
  z: number,
  cx: number,
  cz: number,
  radius: number,
  fall: number,
  sin: number,
  cos: number,
  tan: number,
  padZ: number,
  ground: number,
): number | null {
  const dx = x - cx;
  const dz = z - cz;
  const d = Math.hypot(dx, dz);
  const along = dx * sin + dz * cos;
  const plane = padZ - fall * along;
  if (d <= radius) return plane;
  const allow = (d - radius) * tan;
  if (ground > plane + allow) return plane + allow;
  if (ground < plane - allow) return plane - allow;
  return null;
}

interface Bounds {
  c0: number;
  c1: number;
  r0: number;
  r1: number;
}

function diskBounds(field: Heightfield, cx: number, cz: number, radius: number): Bounds | null {
  return boxBounds(field, cx - radius, cx + radius, cz - radius, cz + radius);
}

function boxBounds(field: Heightfield, minX: number, maxX: number, minZ: number, maxZ: number): Bounds | null {
  const a = field.rcOf(minX, maxZ);
  const b = field.rcOf(maxX, minZ);
  const c0 = clamp(Math.floor(Math.min(a.c, b.c)), 0, field.cols - 1);
  const c1 = clamp(Math.ceil(Math.max(a.c, b.c)), 0, field.cols - 1);
  const r0 = clamp(Math.floor(Math.min(a.r, b.r)), 0, field.rows - 1);
  const r1 = clamp(Math.ceil(Math.max(a.r, b.r)), 0, field.rows - 1);
  if (c1 < c0 || r1 < r0) return null;
  return { c0, c1, r0, r1 };
}

function clamp(v: number, lo: number, hi: number): number {
  return Math.max(lo, Math.min(hi, v));
}
