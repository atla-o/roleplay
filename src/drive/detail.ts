import type { Field } from './field';

/**
 * A 1 m edit layer in a 256 m window that follows one machine.
 * Cuts and berms live here. Cells that slide out of the window, and the whole
 * window when the machine leaves, are baked into the coarse field by volume.
 */

const SIZE = 256;

export class Detail {
  readonly size = SIZE;
  readonly spacing = 1;
  readonly heights = new Float32Array(SIZE * SIZE);
  readonly base = new Float32Array(SIZE * SIZE);
  readonly dirty = new Set<string>();
  readonly chunk = 32;
  originE = 0;
  originN = 0;
  ready = false;
  private sweptE = Number.NaN;
  private sweptN = Number.NaN;

  constructor(readonly field: Field) {}

  /** Metres of unbaked soil still only in this window. Zero after a full bake. */
  deltaM3(): number {
    let sum = 0;
    for (let i = 0; i < this.heights.length; i++) sum += (this.heights[i] ?? 0) - (this.base[i] ?? 0);
    return sum;
  }

  sample(east: number, north: number): number | null {
    if (!this.ready) return null;
    const x = east - this.originE;
    const y = north - this.originN;
    if (x < 0 || y < 0 || x >= SIZE - 1 || y >= SIZE - 1) return null;
    const x0 = Math.floor(x);
    const y0 = Math.floor(y);
    const tx = x - x0;
    const ty = y - y0;
    const i = y0 * SIZE + x0;
    const h00 = this.heights[i] ?? 0;
    const h10 = this.heights[i + 1] ?? h00;
    const h01 = this.heights[i + SIZE] ?? h00;
    const h11 = this.heights[i + SIZE + 1] ?? h00;
    return (h00 * (1 - tx) + h10 * tx) * (1 - ty) + (h01 * (1 - tx) + h11 * tx) * ty;
  }

  grade(east: number, north: number): number | null {
    if (!this.ready) return null;
    const c = Math.floor(east - this.originE);
    const r = Math.floor(north - this.originN);
    if (c < 0 || r < 0 || c >= SIZE || r >= SIZE) return null;
    return this.base[r * SIZE + c] ?? null;
  }

  follow(east: number, north: number): void {
    const nextE = Math.round(east - SIZE / 2);
    const nextN = Math.round(north - SIZE / 2);
    if (!this.ready) {
      this.originE = nextE;
      this.originN = nextN;
      this.resampleAll();
      this.ready = true;
      return;
    }
    const margin = 48;
    if (
      east > this.originE + margin &&
      east < this.originE + SIZE - margin &&
      north > this.originN + margin &&
      north < this.originN + SIZE - margin
    ) {
      return;
    }
    this.slide(nextE, nextN);
  }

  /**
   * Plane cells under the blade down to a fixed depth below the grade they were
   * sampled from, and lay that soil one metre ahead. Returns cubic metres moved.
   */
  cut(east: number, north: number, heading: number, width: number, depth: number): number {
    if (!this.ready || depth <= 0.01) return 0;
    if (Number.isFinite(this.sweptE)) {
      const travel = Math.hypot(east - this.sweptE, north - this.sweptN);
      if (travel < 0.25) return 0;
    }
    const fx = Math.sin(heading);
    const fn = Math.cos(heading);
    const half = Math.max(width / 2, 0.6);
    let moved = 0;
    const under = this.cells(east, north, 0.6, half, fx, fn);
    for (const i of under) {
      const grade = this.base[i] ?? 0;
      const edge = grade - depth;
      const h = this.heights[i] ?? grade;
      if (h <= edge + 0.01) continue;
      const dh = Math.min(h - edge, 0.12);
      this.heights[i] = h - dh;
      this.mark(i);
      moved += dh;
    }
    if (moved <= 0) return 0;
    const ahead = this.cells(east + fx * 2.2, north + fn * 2.2, 0.7, half, fx, fn);
    const pile = ahead.length ? ahead : under;
    const lift = moved / pile.length;
    for (const i of pile) {
      this.heights[i] = (this.heights[i] ?? 0) + lift;
      this.mark(i);
    }
    this.slump(pile);
    this.field.cutM3 += moved;
    this.field.fillM3 += moved;
    this.sweptE = east;
    this.sweptN = north;
    return moved;
  }

  bakeAll(): void {
    if (!this.ready) return;
    this.bakeRegion(0, SIZE, 0, SIZE);
    this.base.set(this.heights);
  }

  private slide(nextE: number, nextN: number): void {
    const de = nextE - this.originE;
    const dn = nextN - this.originN;
    if (Math.abs(de) >= SIZE || Math.abs(dn) >= SIZE) {
      this.bakeAll();
      this.originE = nextE;
      this.originN = nextN;
      this.resampleAll();
      return;
    }
    if (de > 0) this.bakeRegion(0, de, 0, SIZE);
    if (de < 0) this.bakeRegion(SIZE + de, SIZE, 0, SIZE);
    const c0 = Math.max(0, de);
    const c1 = Math.min(SIZE, SIZE + de);
    if (dn > 0) this.bakeRegion(c0, c1, 0, dn);
    if (dn < 0) this.bakeRegion(c0, c1, SIZE + dn, SIZE);
    const nextH = new Float32Array(SIZE * SIZE);
    const nextB = new Float32Array(SIZE * SIZE);
    for (let r = 0; r < SIZE; r++) {
      const or = r + dn;
      for (let c = 0; c < SIZE; c++) {
        const oc = c + de;
        const i = r * SIZE + c;
        if (or >= 0 && oc >= 0 && or < SIZE && oc < SIZE) {
          const o = or * SIZE + oc;
          nextH[i] = this.heights[o] ?? 0;
          nextB[i] = this.base[o] ?? 0;
        } else {
          const h = this.field.sample(nextE + c + 0.5, nextN + r + 0.5);
          nextH[i] = h;
          nextB[i] = h;
          this.mark(i);
        }
      }
    }
    this.heights.set(nextH);
    this.base.set(nextB);
    this.originE = nextE;
    this.originN = nextN;
    this.touchAll();
  }

  private resampleAll(): void {
    for (let r = 0; r < SIZE; r++) {
      for (let c = 0; c < SIZE; c++) {
        const h = this.field.sample(this.originE + c + 0.5, this.originN + r + 0.5);
        const i = r * SIZE + c;
        this.heights[i] = h;
        this.base[i] = h;
      }
    }
    this.touchAll();
  }

  /** Add the height delta, times 1 m², onto the coarse cell under each fine cell. */
  private bakeRegion(c0: number, c1: number, r0: number, r1: number): void {
    const area = this.field.spacing * this.field.spacing;
    const pending = new Map<number, number>();
    for (let r = r0; r < r1; r++) {
      for (let c = c0; c < c1; c++) {
        const i = r * SIZE + c;
        const delta = (this.heights[i] ?? 0) - (this.base[i] ?? 0);
        if (Math.abs(delta) < 1e-8) continue;
        const east = this.originE + c + 0.5;
        const north = this.originN + r + 0.5;
        const cc = Math.floor(east / this.field.spacing);
        const rr = Math.floor(north / this.field.spacing);
        if (!this.field.contains(cc, rr)) continue;
        const ci = this.field.index(cc, rr);
        pending.set(ci, (pending.get(ci) ?? 0) + delta);
        this.base[i] = this.heights[i] ?? 0;
      }
    }
    for (const [ci, volume] of pending) {
      this.field.heights[ci] = (this.field.heights[ci] ?? 0) + volume / area;
      this.field.mark(ci);
    }
  }

  private cells(east: number, north: number, along: number, side: number, fx: number, fn: number): number[] {
    const found: number[] = [];
    const minC = Math.max(0, Math.floor(east - this.originE - side - 1));
    const maxC = Math.min(SIZE - 1, Math.ceil(east - this.originE + side + 1));
    const minR = Math.max(0, Math.floor(north - this.originN - side - 1));
    const maxR = Math.min(SIZE - 1, Math.ceil(north - this.originN + side + 1));
    for (let r = minR; r <= maxR; r++) {
      for (let c = minC; c <= maxC; c++) {
        const px = this.originE + c + 0.5;
        const pn = this.originN + r + 0.5;
        const dx = px - east;
        const dn = pn - north;
        const a = dx * fx + dn * fn;
        const s = dx * fn - dn * fx;
        if (a >= -along && a <= along && Math.abs(s) <= side) found.push(r * SIZE + c);
      }
    }
    return found;
  }

  private slump(seeds: number[]): void {
    const slope = Math.tan((34 * Math.PI) / 180);
    let open = seeds.slice(0, 64);
    for (let pass = 0; pass < 2; pass++) {
      const next: number[] = [];
      for (const i of open) {
        const c = i % SIZE;
        const r = (i / SIZE) | 0;
        const h = this.heights[i] ?? 0;
        for (const [dc, dr] of [[1, 0], [-1, 0], [0, 1], [0, -1]] as const) {
          if (c + dc < 0 || r + dr < 0 || c + dc >= SIZE || r + dr >= SIZE) continue;
          const j = i + dr * SIZE + dc;
          const other = this.heights[j] ?? 0;
          const excess = h - other - slope;
          if (excess <= 0.04) continue;
          const shift = excess * 0.35;
          this.heights[i] = (this.heights[i] ?? 0) - shift;
          this.heights[j] = other + shift;
          this.mark(i);
          this.mark(j);
          next.push(j);
        }
      }
      open = next;
    }
  }

  private mark(i: number): void {
    const c = i % SIZE;
    const r = (i / SIZE) | 0;
    this.dirty.add(`${(c / this.chunk) | 0}:${(r / this.chunk) | 0}`);
  }

  private touchAll(): void {
    const n = SIZE / this.chunk;
    for (let r = 0; r < n; r++) for (let c = 0; c < n; c++) this.dirty.add(`${c}:${r}`);
  }
}
