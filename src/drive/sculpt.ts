import type { Field } from './field';

/**
 * Soil stays in the field. A push raises the ground ahead by the same volume it cuts.
 *
 * Polar desert pavement (basin) is treated as loose sandy gravel: friction angle 35°,
 * bulk density 1.8 t/m³, cohesion taken as 0 for a dry scrape.
 * French, H. M. 2007. The Periglacial Environment. Wiley. Gravelly polar-desert
 * surfaces sit in the sandy-gravel range; Das, Principles of Geotechnical
 * Engineering, gives loose gravel a friction angle of about 34–40°.
 *
 * The island surface is glacial till under boreal cover: friction angle 32°,
 * bulk density 1.7 t/m³. Same textbook range for loose sandy till.
 * The pile may not stand steeper than tan(phi). That is the angle of repose used below.
 */

function cellsIn(field: Field, east: number, north: number, along: number, side: number, fx: number, fn: number): number[] {
  const found: number[] = [];
  const minC = Math.max(0, Math.floor((east - side - field.spacing) / field.spacing));
  const maxC = Math.min(field.cols - 1, Math.ceil((east + side + field.spacing) / field.spacing));
  const minR = Math.max(0, Math.floor((north - side - field.spacing) / field.spacing));
  const maxR = Math.min(field.rows - 1, Math.ceil((north + side + field.spacing) / field.spacing));
  for (let r = minR; r <= maxR; r++) {
    for (let c = minC; c <= maxC; c++) {
      const px = (c + 0.5) * field.spacing;
      const pn = (r + 0.5) * field.spacing;
      const dx = px - east;
      const dn = pn - north;
      const a = dx * fx + dn * fn;
      const s = dx * fn - dn * fx;
      if (a >= -along && a <= along && Math.abs(s) <= side) found.push(field.index(c, r));
    }
  }
  return found;
}

/** Cut a bite under the blade and lay that soil one cell ahead. Returns cubic metres moved. */
export function pushBlade(field: Field, east: number, north: number, heading: number, width: number, bite: number): number {
  if (bite <= 0.0001) return 0;
  const fx = Math.sin(heading);
  const fn = Math.cos(heading);
  const area = field.spacing * field.spacing;
  const under = cellsIn(field, east, north, field.spacing * 0.85, Math.max(width / 2, field.spacing * 0.7), fx, fn);
  let moved = 0;
  const dh = Math.min(bite, 0.35);
  for (const i of under) {
    field.heights[i] = (field.heights[i] ?? 0) - dh;
    field.channel[i] = 1;
    field.mark(i);
    moved += dh * area;
  }
  if (moved <= 0) return 0;
  const ahead = cellsIn(field, east + fx * field.spacing * 2.1, north + fn * field.spacing * 2.1, field.spacing * 0.85, Math.max(width / 2, field.spacing * 0.7), fx, fn);
  const pile = ahead.length ? ahead : under;
  const lift = moved / (pile.length * area);
  for (const i of pile) {
    field.heights[i] = (field.heights[i] ?? 0) + lift;
    field.mark(i);
  }
  slump(field, pile);
  field.cutM3 += moved;
  field.fillM3 += moved;
  field.dirty = true;
  return moved;
}

/** Take soil into a bucket. The volume leaves the ground and is not placed yet. */
export function digBucket(field: Field, east: number, north: number, radius: number, bite: number): number {
  if (bite <= 0.0001) return 0;
  const area = field.spacing * field.spacing;
  let moved = 0;
  const minC = Math.max(0, Math.floor((east - radius) / field.spacing));
  const maxC = Math.min(field.cols - 1, Math.ceil((east + radius) / field.spacing));
  const minR = Math.max(0, Math.floor((north - radius) / field.spacing));
  const maxR = Math.min(field.rows - 1, Math.ceil((north + radius) / field.spacing));
  const dh = Math.min(bite, 0.4);
  for (let r = minR; r <= maxR; r++) {
    for (let c = minC; c <= maxC; c++) {
      const dx = (c + 0.5) * field.spacing - east;
      const dn = (r + 0.5) * field.spacing - north;
      if (dx * dx + dn * dn > radius * radius) continue;
      const i = field.index(c, r);
      field.heights[i] = (field.heights[i] ?? 0) - dh;
      field.channel[i] = 1;
      field.mark(i);
      moved += dh * area;
    }
  }
  if (moved <= 0) return 0;
  field.cutM3 += moved;
  field.dirty = true;
  return moved;
}

/** Put a held volume back on the ground, spread over the cells under the bed. */
export function dumpLoad(field: Field, east: number, north: number, volume: number): number {
  if (volume <= 0.05) return 0;
  const area = field.spacing * field.spacing;
  const radius = field.spacing * 1.4;
  const cells: number[] = [];
  const minC = Math.max(0, Math.floor((east - radius) / field.spacing));
  const maxC = Math.min(field.cols - 1, Math.ceil((east + radius) / field.spacing));
  const minR = Math.max(0, Math.floor((north - radius) / field.spacing));
  const maxR = Math.min(field.rows - 1, Math.ceil((north + radius) / field.spacing));
  for (let r = minR; r <= maxR; r++) {
    for (let c = minC; c <= maxC; c++) cells.push(field.index(c, r));
  }
  if (!cells.length) return 0;
  const lift = volume / (cells.length * area);
  for (const i of cells) {
    field.heights[i] = (field.heights[i] ?? 0) + lift;
    field.mark(i);
  }
  slump(field, cells);
  field.fillM3 += volume;
  field.dirty = true;
  return volume;
}

/**
 * A few raindrops on the heightfield. Sediment that is picked up is laid down
 * again, so the volume stays in the ground. This is our own droplet step.
 * It is the published hydraulic-erosion idea, not a copy of any tool's source.
 */
export function raindrops(field: Field, count: number): void {
  const area = field.spacing * field.spacing;
  for (let n = 0; n < count; n++) {
    let c = 1 + Math.floor(Math.random() * (field.cols - 2));
    let r = 1 + Math.floor(Math.random() * (field.rows - 2));
    let sediment = 0;
    let water = 1;
    for (let life = 0; life < 24; life++) {
      let lowC = c;
      let lowR = r;
      let lowH = field.heights[field.index(c, r)] ?? 0;
      for (const [dc, dr] of [
        [1, 0],
        [-1, 0],
        [0, 1],
        [0, -1],
      ] as const) {
        const h = field.heights[field.index(c + dc, r + dr)] ?? lowH;
        if (h < lowH) {
          lowH = h;
          lowC = c + dc;
          lowR = r + dr;
        }
      }
      if (lowC === c && lowR === r) break;
      const here = field.index(c, r);
      const height = field.heights[here] ?? 0;
      const next = field.heights[field.index(lowC, lowR)] ?? height;
      const slope = height - next;
      const capacity = Math.max(slope, 0) * water * 0.4;
      if (sediment > capacity) {
        const drop = Math.min(sediment - capacity, sediment) * 0.35;
        field.heights[here] = height + drop;
        field.mark(here);
        sediment -= drop;
        field.fillM3 += drop * area;
      } else if (slope > 0) {
        const take = Math.min((capacity - sediment) * 0.35, slope * 0.25, height * 0.02);
        field.heights[here] = height - take;
        field.mark(here);
        sediment += take;
        field.cutM3 += take * area;
        field.channel[here] = 1;
      }
      water *= 0.92;
      c = lowC;
      r = lowR;
      if (c < 1 || r < 1 || c >= field.cols - 1 || r >= field.rows - 1) break;
    }
    if (sediment > 0) {
      const here = field.index(c, r);
      field.heights[here] = (field.heights[here] ?? 0) + sediment;
      field.mark(here);
      field.fillM3 += sediment * area;
      sediment = 0;
    }
  }
  field.dirty = true;
}

/** Move soil from too-steep neighbours until the face is near the angle of repose, keeping the volume. */
function slump(field: Field, seeds: number[], reposeDeg = 35): void {
  const slope = Math.tan((reposeDeg * Math.PI) / 180);
  const area = field.spacing * field.spacing;
  let open = seeds.slice(0, 48);
  for (let pass = 0; pass < 3; pass++) {
    const next: number[] = [];
    for (const i of open) {
      const c = i % field.cols;
      const r = (i / field.cols) | 0;
      const h = field.heights[i] ?? 0;
      for (const [dc, dr] of [[1, 0], [-1, 0], [0, 1], [0, -1]] as const) {
        if (!field.contains(c + dc, r + dr)) continue;
        const j = field.index(c + dc, r + dr);
        const other = field.heights[j] ?? 0;
        const excess = h - other - slope * field.spacing;
        if (excess <= 0.05) continue;
        const shift = excess * 0.35;
        field.heights[i] = (field.heights[i] ?? 0) - shift;
        field.heights[j] = other + shift;
        field.mark(i);
        field.mark(j);
        field.cutM3 += shift * area;
        field.fillM3 += shift * area;
        next.push(j);
      }
    }
    open = next;
  }
}

/** Plane every cell under the blade down toward an absolute elevation and push that soil ahead. */
export function planeBlade(field: Field, east: number, north: number, heading: number, width: number, edgeY: number, reposeDeg = 35): number {
  const fx = Math.sin(heading);
  const fn = Math.cos(heading);
  const area = field.spacing * field.spacing;
  const under = cellsIn(field, east, north, field.spacing * 0.85, Math.max(width / 2, field.spacing * 0.7), fx, fn);
  let moved = 0;
  for (const i of under) {
    const h = field.heights[i] ?? 0;
    if (h <= edgeY + 0.02) continue;
    const dh = Math.min(h - edgeY, 0.28);
    field.heights[i] = h - dh;
    field.channel[i] = 1;
    field.mark(i);
    moved += dh * area;
  }
  if (moved <= 0) return 0;
  const ahead = cellsIn(field, east + fx * field.spacing * 1.05, north + fn * field.spacing * 1.05, field.spacing * 0.45, Math.max(width / 2, field.spacing * 0.55), fx, fn);
  const pile = ahead.length ? ahead : under;
  const lift = moved / (pile.length * area);
  for (const i of pile) {
    field.heights[i] = (field.heights[i] ?? 0) + lift;
    field.channel[i] = 1;
    field.mark(i);
  }
  slump(field, pile, reposeDeg);
  field.cutM3 += moved;
  field.fillM3 += moved;
  field.dirty = true;
  return moved;
}
