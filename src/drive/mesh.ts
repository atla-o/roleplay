import * as Cesium from 'cesium';
import { offsetDegrees, type Field } from './field';

/** How far the measured tile eases down onto the globe, so the edge is a slope rather than a cliff. */
export const FEATHER_M = 12_000;

export interface CoverHole {
  east: number;
  north: number;
  width: number;
  height: number;
}

/**
 * Height of the feather outside a patch, in the patch's local metres.
 * Null when the point is inside the measured grid or beyond the feather.
 */
export function feathered(field: Field, east: number, north: number, outside = 0): number | null {
  const width = (field.cols - 1) * field.spacing;
  const height = (field.rows - 1) * field.spacing;
  const dx = east < 0 ? -east : east > width ? east - width : 0;
  const dy = north < 0 ? -north : north > height ? north - height : 0;
  const dist = Math.hypot(dx, dy);
  if (dist <= 0 || dist > FEATHER_M) return null;
  const edge = field.sample(Math.max(0, Math.min(width, east)), Math.max(0, Math.min(height, north)));
  const t = dist / FEATHER_M;
  const s = t * t * (3 - 2 * t);
  return edge * (1 - s) + outside * s;
}

function appearance(color: Cesium.Color, translucent: boolean): Cesium.PerInstanceColorAppearance {
  return new Cesium.PerInstanceColorAppearance({
    flat: false,
    translucent,
    closed: false,
    renderState: {
      cull: { enabled: false },
      depthTest: { enabled: true },
      depthMask: !translucent,
    },
  });
}

function primitive(positions: Float64Array, index: number[], color: Cesium.Color, translucent: boolean): Cesium.Primitive {
  const geometry = new Cesium.Geometry({
    attributes: {
      position: new Cesium.GeometryAttribute({
        componentDatatype: Cesium.ComponentDatatype.DOUBLE,
        componentsPerAttribute: 3,
        values: positions,
      }),
    } as Cesium.GeometryAttributes,
    indices: index.length > 65535 ? new Uint32Array(index) : new Uint16Array(index),
    primitiveType: Cesium.PrimitiveType.TRIANGLES,
    boundingSphere: Cesium.BoundingSphere.fromVertices(positions as unknown as number[]),
  });
  Cesium.GeometryPipeline.computeNormal(geometry);
  return new Cesium.Primitive({
    geometryInstances: new Cesium.GeometryInstance({
      geometry,
      modelMatrix: Cesium.Matrix4.IDENTITY,
      attributes: { color: Cesium.ColorGeometryInstanceAttribute.fromColor(color) },
    }),
    appearance: appearance(color, translucent),
    asynchronous: false,
  });
}

/** Ease full relief into the edge height so the measured grid does not end in a hard line. */
function displayHeight(field: Field, c: number, r: number): number {
  c = Math.max(0, Math.min(field.cols - 1, c));
  r = Math.max(0, Math.min(field.rows - 1, r));
  const h = field.heights[field.index(c, r)] ?? 0;
  const band = Math.max(8, Math.round((Math.min(field.cols, field.rows) - 1) * 0.2));
  const inset = Math.min(c, r, field.cols - 1 - c, field.rows - 1 - r);
  if (inset >= band) return h;
  const s = inset / band;
  const fade = s * s * (3 - 2 * s);
  const cc = Math.max(band, Math.min(field.cols - 1 - band, c));
  const rr = Math.max(band, Math.min(field.rows - 1 - band, r));
  const inner = field.heights[field.index(cc, rr)] ?? h;
  return inner * fade + h * (1 - fade);
}

function writeVertex(west: number, south: number, east: number, north: number, up: number, positions: number[]): void {
  const ll = offsetDegrees(south, west, east, north);
  const c = Cesium.Cartesian3.fromDegrees(ll.lon, ll.lat, Math.max(0, up));
  positions.push(c.x, c.y, c.z);
}

/** A site mesh split into chunks. Edits rebuild a chunk, never the whole tile, and not on a camera change. */
export class ChunkLayer {
  private readonly chunks = new Map<string, Cesium.Primitive>();
  private water: Cesium.Primitive | null = null;
  private apron: Cesium.Primitive | null = null;
  private outside: (east: number, north: number) => number = () => 0;
  private waterDirty = false;
  private builtAt = 0;
  private waterAt = 0;

  constructor(
    private readonly viewer: Cesium.Viewer,
    readonly field: Field,
    readonly west: number,
    readonly south: number,
    private depth: Float32Array,
    private readonly hole: CoverHole | null = null,
  ) {
    this.field.touchAll();
    this.apron = apronPrimitive(field, west, south, this.outside);
    this.viewer.scene.primitives.add(this.apron);
    this.flush(400, true);
    this.waterDirty = true;
    this.flushWater(true);
  }

  setDepth(depth: Float32Array): void {
    this.depth = depth;
    this.waterDirty = true;
  }

  /** Feather the skirt toward the global elevation instead of the ellipsoid. */
  retarget(outside: (east: number, north: number) => number): void {
    this.outside = outside;
    if (this.apron) this.viewer.scene.primitives.remove(this.apron);
    this.apron = apronPrimitive(this.field, this.west, this.south, outside);
    this.viewer.scene.primitives.add(this.apron);
  }

  /** Rebuild a few dirty chunks. Pass `now` so a blade scrape cannot upload a mesh every frame. */
  flush(max = 2, force = false): void {
    const now = performance.now();
    if (!force && (this.field.dirtyChunks.size === 0 || now - this.builtAt < 140)) {
      this.flushWater(false);
      return;
    }
    const built: string[] = [];
    for (const key of this.field.dirtyChunks) {
      if (built.length >= max) break;
      built.push(key);
    }
    for (const key of built) this.field.dirtyChunks.delete(key);
    for (const key of built) {
      const [cs, rs] = key.split(':');
      const c0 = Number(cs) * this.field.chunk;
      const r0 = Number(rs) * this.field.chunk;
      const previous = this.chunks.get(key);
      if (previous) this.viewer.scene.primitives.remove(previous);
      const fade = chunkFade(this.field, c0, r0);
      const next = fade < 1
        ? fringeChunk(this.field, this.west, this.south, c0, r0, this.hole)
        : chunkPrimitive(this.field, this.west, this.south, c0, r0, this.hole, 1);
      if (next) {
        this.viewer.scene.primitives.add(next);
        this.chunks.set(key, next);
      } else this.chunks.delete(key);
    }
    if (built.length) this.builtAt = now;
    this.field.dirty = this.field.dirtyChunks.size > 0;
    this.flushWater(false);
  }

  private flushWater(force: boolean): void {
    if (!this.waterDirty) return;
    const now = performance.now();
    if (!force && (this.field.dirtyChunks.size > 0 || now - this.waterAt < 3000)) return;
    if (this.water) this.viewer.scene.primitives.remove(this.water);
    this.water = waterPrimitive(this.field, this.west, this.south, this.depth);
    if (this.water) this.viewer.scene.primitives.add(this.water);
    this.waterDirty = false;
    this.waterAt = now;
  }
}

function valueNoise(east: number, north: number): number {
  const s = 220;
  const x = east / s;
  const y = north / s;
  const x0 = Math.floor(x);
  const y0 = Math.floor(y);
  const tx = x - x0;
  const ty = y - y0;
  const h = (ix: number, iy: number) => {
    const n = Math.sin(ix * 127.1 + iy * 311.7) * 43758.5453;
    return n - Math.floor(n);
  };
  const sx = tx * tx * (3 - 2 * tx);
  const sy = ty * ty * (3 - 2 * ty);
  const a = h(x0, y0) * (1 - sx) + h(x0 + 1, y0) * sx;
  const b = h(x0, y0 + 1) * (1 - sx) + h(x0 + 1, y0 + 1) * sx;
  return a * (1 - sy) + b * sy;
}

/** Alpha that dies out along valleys and ridges, not along the rectangle. */
function fringeAlpha(field: Field, east: number, north: number): number {
  const width = (field.cols - 1) * field.spacing;
  const height = (field.rows - 1) * field.spacing;
  const ox = Math.max(-east, 0, east - width);
  const oy = Math.max(-north, 0, north - height);
  const outside = Math.hypot(ox, oy);
  const inside = Math.min(east, north, width - east, height - north);
  const dist = east >= 0 && north >= 0 && east <= width && north <= height ? -inside : outside;
  const slope = Math.abs(field.sample(Math.max(0, east), Math.max(0, north)) - field.sample(Math.max(0, east + field.spacing), Math.max(0, north))) / field.spacing;
  const wobble = (valueNoise(east, north) - 0.5) * 1300 + Math.min(slope, 0.4) * 700;
  const t = Math.max(0, Math.min(1, (dist + 500 + wobble) / 1600));
  return 1 - t * t * (3 - 2 * t);
}

function chunkFade(field: Field, c0: number, r0: number): number {
  const nc = Math.max(1, Math.ceil((field.cols - 1) / field.chunk));
  const nr = Math.max(1, Math.ceil((field.rows - 1) / field.chunk));
  const cx = (c0 / field.chunk) | 0;
  const rx = (r0 / field.chunk) | 0;
  const inset = Math.min(cx, rx, nc - 1 - cx, nr - 1 - rx);
  if (inset <= 0) return 0.32;
  if (inset === 1) return 0.7;
  return 1;
}

function chunkPrimitive(field: Field, west: number, south: number, c0: number, r0: number, hole: CoverHole | null, alpha = 1): Cesium.Primitive | null {
  const c1 = Math.min(field.cols - 1, c0 + field.chunk);
  const r1 = Math.min(field.rows - 1, r0 + field.chunk);
  const positions: number[] = [];
  const index: number[] = [];
  const stride = c1 - c0 + 1;
  for (let r = r0; r <= r1; r++) {
    for (let c = c0; c <= c1; c++) {
      writeVertex(west, south, c * field.spacing, r * field.spacing, displayHeight(field, c, r), positions);
    }
  }
  for (let r = r0; r < r1; r++) {
    for (let c = c0; c < c1; c++) {
      const midE = (c + 0.5) * field.spacing;
      const midN = (r + 0.5) * field.spacing;
      if (hole && midE > hole.east && midN > hole.north && midE < hole.east + hole.width && midN < hole.north + hole.height) continue;
      const i = (r - r0) * stride + (c - c0);
      index.push(i, i + 1, i + stride, i + 1, i + stride + 1, i + stride);
    }
  }
  if (!index.length) return null;
  const color = Cesium.Color.fromCssColorString('#d2c0a4').withAlpha(alpha);
  return primitive(new Float64Array(positions), index, color, alpha < 0.98);
}

function waterPrimitive(field: Field, west: number, south: number, depth: Float32Array): Cesium.Primitive | null {
  const positions: number[] = [];
  const index: number[] = [];
  const { cols, rows, spacing } = field;
  for (let r = 0; r < rows - 1; r++) {
    for (let c = 0; c < cols - 1; c++) {
      const i = field.index(c, r);
      const d = Math.max(depth[i] ?? 0, depth[i + 1] ?? 0, depth[i + cols] ?? 0, depth[i + cols + 1] ?? 0);
      if (d < 0.08) continue;
      const base = positions.length / 3;
      for (const corner of [i, i + 1, i + cols, i + cols + 1]) {
        const cc = corner % cols;
        const rr = Math.floor(corner / cols);
        writeVertex(west, south, cc * spacing, rr * spacing, (field.heights[corner] ?? 0) + (depth[corner] ?? 0) + 0.4, positions);
      }
      index.push(base, base + 1, base + 2, base + 1, base + 3, base + 2);
    }
  }
  if (!index.length) return null;
  return primitive(new Float64Array(positions), index, Cesium.Color.fromCssColorString('#2f7ea3').withAlpha(0.72), true);
}

/** Ease the measured edge down to the ellipsoid over FEATHER_M so the tile has no square cliff and no underside. */
function apronPrimitive(field: Field, west: number, south: number, outside: (east: number, north: number) => number): Cesium.Primitive {
  const rings = 12;
  const reach = FEATHER_M;
  const { cols, rows, spacing } = field;
  const width = (cols - 1) * spacing;
  const height = (rows - 1) * spacing;
  const positions: number[] = [];
  const index: number[] = [];
  const add = (east: number, north: number, up: number) => {
    const id = positions.length / 3;
    writeVertex(west, south, east, north, up, positions);
    return id;
  };
  const drop = (edge: number, k: number, east: number, north: number) => {
    const t = k / rings;
    const s = t * t * (3 - 2 * t);
    return edge * (1 - s) + outside(east, north) * s;
  };
  const side = (count: number, at: (i: number, dist: number) => [number, number]) => {
    const ids: number[][] = [];
    for (let k = 0; k <= rings; k++) {
      const line: number[] = [];
      const dist = (k / rings) * reach;
      for (let i = 0; i < count; i++) {
        const edgeH = displayHeight(field, Math.round(at(i, 0)[0] / field.spacing), Math.round(at(i, 0)[1] / field.spacing));
        const [east, north] = at(i, dist);
        line.push(add(east, north, drop(edgeH, k, east, north)));
      }
      ids.push(line);
    }
    for (let k = 0; k < rings; k++) {
      for (let i = 0; i < count - 1; i++) {
        const a = ids[k][i] ?? 0;
        const b = ids[k][i + 1] ?? 0;
        const c = ids[k + 1]?.[i] ?? 0;
        const d = ids[k + 1]?.[i + 1] ?? 0;
        index.push(a, b, c, b, d, c);
      }
    }
  };
  side(cols, (i, dist) => [i * spacing, -dist]);
  side(cols, (i, dist) => [i * spacing, height + dist]);
  side(rows, (i, dist) => [-dist, i * spacing]);
  side(rows, (i, dist) => [width + dist, i * spacing]);
  const corner = (ox: number, oy: number, a0: number, a1: number, edgeH: number) => {
    const segs = 8;
    const ids: number[][] = [];
    for (let k = 0; k <= rings; k++) {
      const line: number[] = [];
      const dist = (k / rings) * reach;
      for (let s = 0; s <= segs; s++) {
        const ang = a0 + ((a1 - a0) * s) / segs;
        const east = ox + Math.cos(ang) * dist;
        const north = oy + Math.sin(ang) * dist;
        line.push(add(east, north, drop(edgeH, k, east, north)));
      }
      ids.push(line);
    }
    for (let k = 0; k < rings; k++) {
      for (let s = 0; s < segs; s++) {
        const a = ids[k][s] ?? 0;
        const b = ids[k][s + 1] ?? 0;
        const c = ids[k + 1]?.[s] ?? 0;
        const d = ids[k + 1]?.[s + 1] ?? 0;
        index.push(a, c, b, b, c, d);
      }
    }
  };
  corner(0, 0, Math.PI, Math.PI * 1.5, displayHeight(field, 0, 0));
  corner(width, 0, Math.PI * 1.5, Math.PI * 2, displayHeight(field, cols - 1, 0));
  corner(width, height, 0, Math.PI * 0.5, displayHeight(field, cols - 1, rows - 1));
  corner(0, height, Math.PI * 0.5, Math.PI, displayHeight(field, 0, rows - 1));
  return primitive(new Float64Array(positions), index, Cesium.Color.fromCssColorString('#c8c2b4').withAlpha(0.18), true);
}

/** Outer posts as small patches whose alpha follows the noisy terrain mask. */
function fringeChunk(field: Field, west: number, south: number, c0: number, r0: number, hole: CoverHole | null): Cesium.Primitive | null {
  const c1 = Math.min(field.cols - 1, c0 + field.chunk);
  const r1 = Math.min(field.rows - 1, r0 + field.chunk);
  const instances: Cesium.GeometryInstance[] = [];
  const step = 4;
  for (let r = r0; r < r1; r += step) {
    for (let c = c0; c < c1; c += step) {
      const midE = (c + step / 2) * field.spacing;
      const midN = (r + step / 2) * field.spacing;
      if (hole && midE > hole.east && midN > hole.north && midE < hole.east + hole.width && midN < hole.north + hole.height) continue;
      const alpha = fringeAlpha(field, midE, midN);
      if (alpha < 0.05) continue;
      const positions: number[] = [];
      const index: number[] = [];
      const cc1 = Math.min(c1, c + step);
      const rr1 = Math.min(r1, r + step);
      const stride = cc1 - c + 1;
      for (let rr = r; rr <= rr1; rr++) {
        for (let cc = c; cc <= cc1; cc++) {
          writeVertex(west, south, cc * field.spacing, rr * field.spacing, displayHeight(field, cc, rr), positions);
        }
      }
      for (let rr = r; rr < rr1; rr++) {
        for (let cc = c; cc < cc1; cc++) {
          const i = (rr - r) * stride + (cc - c);
          index.push(i, i + 1, i + stride, i + 1, i + stride + 1, i + stride);
        }
      }
      if (!index.length) continue;
      const geometry = new Cesium.Geometry({
        attributes: {
          position: new Cesium.GeometryAttribute({
            componentDatatype: Cesium.ComponentDatatype.DOUBLE,
            componentsPerAttribute: 3,
            values: new Float64Array(positions),
          }),
        } as Cesium.GeometryAttributes,
        indices: new Uint16Array(index),
        primitiveType: Cesium.PrimitiveType.TRIANGLES,
        boundingSphere: Cesium.BoundingSphere.fromVertices(positions),
      });
      Cesium.GeometryPipeline.computeNormal(geometry);
      instances.push(new Cesium.GeometryInstance({
        geometry,
        attributes: { color: Cesium.ColorGeometryInstanceAttribute.fromColor(Cesium.Color.fromCssColorString('#d2c0a4').withAlpha(alpha)) },
      }));
    }
  }
  if (!instances.length) return null;
  return new Cesium.Primitive({
    geometryInstances: instances,
    appearance: new Cesium.PerInstanceColorAppearance({
      flat: false,
      translucent: true,
      closed: false,
      renderState: { cull: { enabled: false }, depthTest: { enabled: true }, depthMask: false },
    }),
    asynchronous: true,
  });
}
