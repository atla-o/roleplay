import type { Result, Sim } from './sim';

export interface SuccessionReport {
  ok: boolean;
  reasons: string[];
  look: { x: number; y: number; z: number; distance: number; azimuth: number; altitude: number };
  walk: { x: number; z: number; yaw: number; pitch: number };
}

/** Runs the four phases on the measured basin with the same actions the tools use. */
export function performSuccession(sim: Sim): SuccessionReport {
  const reasons: string[] = [];
  const insetPond = sim.water.ponds.find((p) => inset(sim, p.centroid, 220));
  const plan = sim.planDiversion(insetPond?.id);
  if (!plan) reasons.push('No standing water to divert.');
  let channel = plan?.points ?? [];
  if (plan) {
    let cut = sim.cutPolyline(plan.points, plan.invertStart, 'ditch');
    if (!cut.ok) {
      cut = sim.cutPolyline(plan.points, plan.invertStart - 0.4, 'ditch');
      if (!cut.ok) reasons.push(cut.reason ?? 'Channel was not cut.');
    }
    channel = plan.points;
  }

  const mid = channel[Math.floor(channel.length / 2)] ?? { x: sim.field.width / 2, z: sim.field.height / 2 };
  const next = channel[Math.min(channel.length - 1, Math.floor(channel.length / 2) + 1)] ?? {
    x: mid.x + 8,
    z: mid.z,
  };
  const dx = next.x - mid.x;
  const dz = next.z - mid.z;
  const len = Math.hypot(dx, dz) || 1;
  const px = -dz / len;
  const pz = dx / len;

  const pad = choosePad(sim, channel) ?? { x: sim.field.width * 0.5, z: sim.field.height * 0.46 };
  const graded = sim.grade(pad.x, pad.z, 52);
  if (!graded.ok) reasons.push(graded.reason ?? 'Pad was not graded.');

  const surveyed = sim.survey(pad.x, pad.z);
  if (!surveyed.ok) reasons.push(surveyed.reason ?? 'No reading.');

  const dome = sim.placeDome(pad.x, pad.z);
  if (!dome.ok) reasons.push(dome.reason ?? 'Shelter was not set.');

  const bedAt = sim.domes[0] ? { x: sim.domes[0].x, z: sim.domes[0].z } : pad;
  const bed = sim.placeBed(bedAt.x, bedAt.z);
  if (!bed.ok) {
    const alt = firstDry(sim, bedAt.x, bedAt.z, [4, 8, 12]);
    if (!alt || !sim.placeBed(alt.x, alt.z).ok) reasons.push(bed.reason ?? 'Soil bed was not placed.');
  }

  const bedNow = sim.beds[0] ?? bedAt;
  const barley = deployNear(sim, 'hordeum', bedNow.x, bedNow.z, 'clone', 5);
  if (!barley.ok) reasons.push(barley.reason ?? 'Barley was not cloned.');
  const sax = deployNear(sim, 'saxifraga', bedNow.x + 1.6, bedNow.z + 1.2, 'cultivate', 5);
  if (!sax.ok) reasons.push(sax.reason ?? 'Saxifrage was not cultivated.');

  const willowAt = offsetDry(sim, bedNow, px, pz, 24) ?? { x: bedNow.x + px * 24, z: bedNow.z + pz * 24 };
  const willow = deployNear(sim, 'salix', willowAt.x, willowAt.z, 'cultivate', 8);
  if (!willow.ok) reasons.push(willow.reason ?? 'Willow was not cultivated.');

  const nostocAt = offsetDry(sim, mid, px, pz, 16) ?? { x: mid.x + px * 16, z: mid.z + pz * 16 };
  const film = deployNear(sim, 'nostoc', nostocAt.x, nostocAt.z, 'spawn', 10);
  if (!film.ok) reasons.push(film.reason ?? 'The film was not spawned.');

  sim.setDay(238);
  const hareAt = sim.plantings.find((p) => p.speciesId === 'salix') ?? willowAt;
  const hare = deployNear(sim, 'lepus', hareAt.x + 6, hareAt.z + 4, 'spawn', 8);
  if (!hare.ok) reasons.push(hare.reason ?? 'Hare was not released.');

  const street = sim.buildStreet([
    { x: pad.x - 30, z: pad.z + 24 },
    { x: pad.x + 30, z: pad.z + 24 },
  ]);
  if (!street.ok) reasons.push(street.reason ?? 'The street was not laid.');
  const streetHeading = Math.PI / 2;
  const green = sim.buildStructure('greenhouse', pad.x + 6, pad.z + 40, streetHeading);
  if (!green.ok) reasons.push(green.reason ?? 'Greenhouse was not set.');
  const town = sim.buildStructure('township', pad.x - 16, pad.z + 42, streetHeading);
  if (!town.ok) reasons.push(town.reason ?? 'Township module was not set.');
  const water = sim.buildStructure('waterworks', pad.x + 28, pad.z + 40, streetHeading);
  if (!water.ok) reasons.push(water.reason ?? 'Water works were not set.');

  const pit = {
    x: clampTo(sim, pad.x - 70),
    z: clampToZ(sim, pad.z - 55),
  };
  const mined = sim.mine(pit.x, pit.z);
  if (!mined.ok) reasons.push(mined.reason ?? 'The pit was not opened.');
  const heading = Math.atan2(px, pz);
  sim.park('mass-mover', mid.x + 18, mid.z + 12, heading);
  sim.park('raw-miner', pit.x + 20, pit.z + 8, 0.4);
  sim.park('bio-builder', pad.x - 28, pad.z - 8, 0.8);
  sim.park('weather-manipulator', pad.x + 26, pad.z - 10, -0.4);
  sim.park('ark-rig', pad.x + 4, pad.z - 18, 1.2);
  sim.park('structure-builder', pad.x - 36, pad.z + 8, streetHeading);

  const focus = sim.domes[0] ?? pad;
  const ground = sim.field.sample(focus.x, focus.z);
  const walkFrom = { x: pad.x - 22, z: pad.z + 24 };

  return {
    ok: reasons.length === 0,
    reasons,
    look: {
      x: focus.x,
      y: (Number.isFinite(ground) ? ground : 100) + 4,
      z: focus.z + 10,
      distance: 210,
      azimuth: 210,
      altitude: 22,
    },
    walk: { x: pad.x - 6, z: pad.z + 24, yaw: Math.atan2(12, 18), pitch: -0.06 },
  };
}

function composeMachines(
  sim: Sim,
  mid: { x: number; z: number },
  pad: { x: number; z: number },
  pit: { x: number; z: number },
  px: number,
  pz: number,
  heading: number,
): void {
  sim.park('mass-mover', mid.x - px * 8, mid.z - pz * 8, heading);
  sim.park('raw-miner', pit.x + 14, pit.z + 10, 0.6);
  sim.park('bio-builder', pad.x + 22, pad.z - 8, 0.4);
  sim.park('weather-manipulator', pad.x - 22, pad.z + 6, -0.5);
  sim.park('ark-rig', pad.x + 8, pad.z + 20, 1.1);
  sim.park('structure-builder', pad.x + px * 10, pad.z + pz * 10, heading + Math.PI / 2);
}

function layStreet(sim: Sim, mid: { x: number; z: number }, px: number, pz: number): Result {
  let last: Result = { ok: false, reason: 'No dry alignment for the street.' };
  for (const sign of [1, -1]) {
    for (const span of [54, 42, 34]) {
      const a = findDry(sim, mid, px * sign, pz * sign, span);
      const b = findDry(sim, mid, -px * sign, -pz * sign, span);
      if (!a || !b) continue;
      last = sim.buildStreet([a, b]);
      if (last.ok) return last;
    }
  }
  return last;
}

function placeKind(sim: Sim, kind: 'greenhouse' | 'waterworks' | 'township', x: number, z: number, heading: number): Result {
  let last = sim.buildStructure(kind, x, z, heading);
  if (last.ok) return last;
  for (let i = 0; i < 10; i++) {
    const a = (i / 10) * Math.PI * 2;
    const r = 8 + (i % 3) * 6;
    last = sim.buildStructure(kind, x + Math.cos(a) * r, z + Math.sin(a) * r, heading);
    if (last.ok) return last;
  }
  return last;
}

function deployNear(sim: Sim, id: string, x: number, z: number, action: string, reach: number): Result {
  let last = sim.deploy(id, x, z, action);
  if (last.ok) return last;
  for (let i = 0; i < 18; i++) {
    const a = (i / 18) * Math.PI * 2;
    const r = 2 + (i % 5) * (reach / 5);
    last = sim.deploy(id, x + Math.cos(a) * r, z + Math.sin(a) * r, action);
    if (last.ok) return last;
  }
  return last;
}

function choosePad(sim: Sim, channel: { x: number; z: number }[]): { x: number; z: number } | null {
  const seeds = channel.filter((p, i) => i % 5 === 0 && inset(sim, p, 140));
  const pool = seeds.length ? seeds : channel.filter((_, i) => i % 5 === 0);
  let best: { x: number; z: number } | null = null;
  let score = Infinity;
  for (const seed of pool) {
    for (let radius = 28; radius <= 220; radius += 32) {
      for (let k = 0; k < 8; k++) {
        const a = (k / 8) * Math.PI * 2;
        const x = seed.x + Math.cos(a) * radius;
        const z = seed.z + Math.sin(a) * radius;
        if (!inset(sim, { x, z }, 70)) continue;
        const info = sim.readingAt(x, z);
        if (!info || info.moisture === 'ponded' || info.slope > 6) continue;
        const s = info.slope + radius * 0.004;
        if (s < score) {
          score = s;
          best = { x, z };
        }
      }
    }
  }
  return best;
}

function layOnPad(sim: Sim, pad: { x: number; z: number }): Result {
  let last: Result = { ok: false, reason: 'The pad has no dry line for a street.' };
  for (const heading of [0, 0.6, 1.2, 2.1]) {
    const dx = Math.sin(heading);
    const dz = Math.cos(heading);
    last = sim.buildStreet(
      [
        { x: pad.x - dx * 24, z: pad.z - dz * 24 },
        { x: pad.x + dx * 24, z: pad.z + dz * 24 },
      ],
    );
    if (last.ok) return last;
  }
  return last;
}

function inset(sim: Sim, p: { x: number; z: number }, margin: number): boolean {
  return p.x > margin && p.z > margin && p.x < sim.field.width - margin && p.z < sim.field.height - margin;
}

function pickPad(sim: Sim, mid: { x: number; z: number }, px: number, pz: number): { x: number; z: number } {
  let best = { x: mid.x + px * 48, z: mid.z + pz * 48 };
  let bestScore = Infinity;
  for (const sign of [1, -1]) {
    for (const dist of [40, 70, 110, 160]) {
      for (const along of [-40, 0, 40]) {
        const x = mid.x + px * sign * dist + along * pz;
        const z = mid.z + pz * sign * dist - along * px;
        const info = sim.readingAt(x, z);
        if (!info || info.moisture === 'ponded' || info.slope > 7) continue;
        const score = info.slope + dist * 0.01;
        if (score < bestScore) {
          bestScore = score;
          best = { x, z };
        }
      }
    }
  }
  return { x: clampTo(sim, best.x), z: clampToZ(sim, best.z) };
}

function findDry(sim: Sim, origin: { x: number; z: number }, dx: number, dz: number, dist: number): { x: number; z: number } | null {
  for (let d = dist; d >= 18; d -= 6) {
    const x = origin.x + dx * d;
    const z = origin.z + dz * d;
    const info = sim.readingAt(x, z);
    if (info && info.moisture !== 'ponded' && info.slope < 12) return { x, z };
  }
  return null;
}

function offsetDry(sim: Sim, origin: { x: number; z: number }, px: number, pz: number, dist: number): { x: number; z: number } | null {
  return findDry(sim, origin, px, pz, dist) ?? findDry(sim, origin, -px, -pz, dist);
}

function firstDry(sim: Sim, x: number, z: number, radii: number[]): { x: number; z: number } | null {
  for (const r of radii) {
    if (r === 0) {
      const info = sim.readingAt(x, z);
      if (info && info.moisture !== 'ponded') return { x, z };
      continue;
    }
    for (let i = 0; i < 8; i++) {
      const a = (i / 8) * Math.PI * 2;
      const px = x + Math.cos(a) * r;
      const pz = z + Math.sin(a) * r;
      const info = sim.readingAt(px, pz);
      if (info && info.moisture !== 'ponded' && info.slope < 10) return { x: px, z: pz };
    }
  }
  return null;
}

function clampTo(sim: Sim, x: number): number {
  return Math.max(30, Math.min(sim.field.width - 30, x));
}
function clampToZ(sim: Sim, z: number): number {
  return Math.max(30, Math.min(sim.field.height - 30, z));
}
