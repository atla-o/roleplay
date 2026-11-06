/** Eight neighbors, E, NE, N, NW, W, SW, S, SE. Row 0 is north. */
export const N8: ReadonlyArray<readonly [number, number]> = [
  [1, 0],
  [1, -1],
  [0, -1],
  [-1, -1],
  [-1, 0],
  [-1, 1],
  [0, 1],
  [1, 1],
];

export const DIST8 = [1, Math.SQRT2, 1, Math.SQRT2, 1, Math.SQRT2, 1, Math.SQRT2];

export function neighborIndex(i: number, k: number, cols: number, rows: number): number {
  const c = i % cols;
  const r = (i / cols) | 0;
  const cc = c + N8[k][0];
  const rr = r + N8[k][1];
  if (cc < 0 || rr < 0 || cc >= cols || rr >= rows) return -1;
  return rr * cols + cc;
}

export class Heightfield {
  readonly width: number;
  readonly height: number;
  readonly z: Float32Array;
  readonly edited: Uint8Array;
  readonly graded: Uint8Array;
  readonly channel: Uint8Array;

  constructor(
    readonly cols: number,
    readonly rows: number,
    readonly spacing: number,
    readonly z0: Float32Array,
  ) {
    this.width = (cols - 1) * spacing;
    this.height = (rows - 1) * spacing;
    this.z = z0.slice();
    this.edited = new Uint8Array(z0.length);
    this.graded = new Uint8Array(z0.length);
    this.channel = new Uint8Array(z0.length);
  }

  idx(c: number, r: number): number {
    return r * this.cols + c;
  }

  worldOf(c: number, r: number): { x: number; z: number } {
    return { x: c * this.spacing, z: (this.rows - 1 - r) * this.spacing };
  }

  /** Fractional column and north-origin row. */
  rcOf(x: number, z: number): { c: number; r: number } {
    return {
      c: x / this.spacing,
      r: this.rows - 1 - z / this.spacing,
    };
  }

  contains(x: number, z: number): boolean {
    return x >= 0 && z >= 0 && x <= this.width && z <= this.height;
  }

  sample(x: number, z: number): number {
    const { c, r } = this.rcOf(x, z);
    if (c < 0 || r < 0 || c > this.cols - 1 || r > this.rows - 1) return NaN;
    const c0 = Math.floor(c);
    const r0 = Math.floor(r);
    const c1 = Math.min(this.cols - 1, c0 + 1);
    const r1 = Math.min(this.rows - 1, r0 + 1);
    const tx = c - c0;
    const ty = r - r0;
    const z00 = this.z[this.idx(c0, r0)];
    const z10 = this.z[this.idx(c1, r0)];
    const z01 = this.z[this.idx(c0, r1)];
    const z11 = this.z[this.idx(c1, r1)];
    return (z00 * (1 - tx) + z10 * tx) * (1 - ty) + (z01 * (1 - tx) + z11 * tx) * ty;
  }

  slopeDeg(c: number, r: number): number {
    const cL = Math.max(0, c - 1);
    const cR = Math.min(this.cols - 1, c + 1);
    const rN = Math.max(0, r - 1);
    const rS = Math.min(this.rows - 1, r + 1);
    const dzdx = (this.z[this.idx(cR, r)] - this.z[this.idx(cL, r)]) / ((cR - cL) * this.spacing || this.spacing);
    const dzdn =
      (this.z[this.idx(c, rN)] - this.z[this.idx(c, rS)]) / ((rS - rN) * this.spacing || this.spacing);
    return (Math.atan(Math.hypot(dzdx, dzdn)) * 180) / Math.PI;
  }

  restore(): void {
    this.z.set(this.z0);
    this.edited.fill(0);
    this.graded.fill(0);
    this.channel.fill(0);
  }
}
