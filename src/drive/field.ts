/** One heightfield, shared by the globe mesh, the driver, and the water. Row 0 is south. */

export class Field {
  readonly heights: Float32Array;
  readonly base: Float32Array;
  readonly channel: Uint8Array;
  cutM3 = 0;
  fillM3 = 0;
  dirty = true;
  /** Chunk keys that need a new mesh. Edits never rebuild the whole field. */
  readonly dirtyChunks = new Set<string>();
  readonly chunk = 24;

  constructor(
    readonly cols: number,
    readonly rows: number,
    readonly spacing: number,
    heights: Float32Array,
  ) {
    this.heights = heights;
    this.base = heights.slice();
    this.channel = new Uint8Array(heights.length);
    this.touchAll();
  }

  touchAll(): void {
    const nc = Math.ceil(this.cols / this.chunk);
    const nr = Math.ceil(this.rows / this.chunk);
    for (let r = 0; r < nr; r++) for (let c = 0; c < nc; c++) this.dirtyChunks.add(`${c}:${r}`);
    this.dirty = true;
  }

  mark(i: number): void {
    const c = i % this.cols;
    const r = (i / this.cols) | 0;
    this.dirtyChunks.add(`${(c / this.chunk) | 0}:${(r / this.chunk) | 0}`);
    this.dirty = true;
  }

  reset(): void {
    this.heights.set(this.base);
    this.channel.fill(0);
    this.cutM3 = 0;
    this.fillM3 = 0;
    this.touchAll();
  }

  index(c: number, r: number): number {
    return r * this.cols + c;
  }

  contains(c: number, r: number): boolean {
    return c >= 0 && r >= 0 && c < this.cols && r < this.rows;
  }

  sample(east: number, north: number): number {
    return this.bilinear(this.heights, east, north);
  }

  private bilinear(grid: Float32Array, east: number, north: number): number {
    const x = east / this.spacing;
    const y = north / this.spacing;
    const x0 = Math.floor(x);
    const y0 = Math.floor(y);
    if (x0 < 0 || y0 < 0 || x0 >= this.cols - 1 || y0 >= this.rows - 1) {
      const c = Math.max(0, Math.min(this.cols - 1, Math.round(x)));
      const r = Math.max(0, Math.min(this.rows - 1, Math.round(y)));
      return grid[this.index(c, r)] ?? 0;
    }
    const tx = x - x0;
    const ty = y - y0;
    const i00 = this.index(x0, y0);
    const h00 = grid[i00] ?? 0;
    const h10 = grid[i00 + 1] ?? h00;
    const h01 = grid[i00 + this.cols] ?? h00;
    const h11 = grid[i00 + this.cols + 1] ?? h00;
    return (h00 * (1 - tx) + h10 * tx) * (1 - ty) + (h01 * (1 - tx) + h11 * tx) * ty;
  }

  /** The measured surface, before any cut or fill. */
  sampleBase(east: number, north: number): number {
    return this.bilinear(this.base, east, north);
  }

  range(): { min: number; max: number } {
    let min = Infinity;
    let max = -Infinity;
    for (const h of this.heights) {
      if (h < min) min = h;
      if (h > max) max = h;
    }
    return { min, max };
  }
}

export function resampleNorthUp(
  samples: ArrayLike<number>,
  cols: number,
  rows: number,
  destCols: number,
  destRows: number,
  decode: (sample: number) => number,
): Float32Array {
  const out = new Float32Array(destCols * destRows);
  for (let r = 0; r < destRows; r++) {
    const north = destRows === 1 ? 1 : r / (destRows - 1);
    const sy = (1 - north) * (rows - 1);
    const y0 = Math.max(0, Math.min(rows - 1, Math.floor(sy)));
    const y1 = Math.min(rows - 1, y0 + 1);
    const ty = sy - y0;
    for (let c = 0; c < destCols; c++) {
      const east = destCols === 1 ? 0 : c / (destCols - 1);
      const sx = east * (cols - 1);
      const x0 = Math.max(0, Math.min(cols - 1, Math.floor(sx)));
      const x1 = Math.min(cols - 1, x0 + 1);
      const tx = sx - x0;
      const h00 = decode(samples[y0 * cols + x0] ?? 0);
      const h10 = decode(samples[y0 * cols + x1] ?? 0);
      const h01 = decode(samples[y1 * cols + x0] ?? 0);
      const h11 = decode(samples[y1 * cols + x1] ?? 0);
      out[r * destCols + c] = (h00 * (1 - tx) + h10 * tx) * (1 - ty) + (h01 * (1 - tx) + h11 * tx) * ty;
    }
  }
  return out;
}

/** Metres between two latitudes, and between two longitudes at a latitude. */
export function metersPerDegree(lat: number): { lat: number; lon: number } {
  return { lat: 111_320, lon: 111_320 * Math.cos((lat * Math.PI) / 180) };
}

export function offsetDegrees(lat: number, lon: number, east: number, north: number): { lat: number; lon: number } {
  const scale = metersPerDegree(lat);
  return { lat: lat + north / scale.lat, lon: lon + east / scale.lon };
}
