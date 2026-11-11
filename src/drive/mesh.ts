import * as Cesium from 'cesium';
import type { Field } from './field';

function surface(positions: Float64Array, index: number[], modelMatrix: Cesium.Matrix4, color: Cesium.Color, translucent: boolean): Cesium.Primitive {
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
    boundingSphere: Cesium.BoundingSphere.fromVertices(Array.from(positions)),
  });
  Cesium.GeometryPipeline.computeNormal(geometry);
  return new Cesium.Primitive({
    geometryInstances: new Cesium.GeometryInstance({
      geometry,
      modelMatrix,
      attributes: {
        color: Cesium.ColorGeometryInstanceAttribute.fromColor(color),
      },
    }),
    appearance: new Cesium.PerInstanceColorAppearance({
      flat: false,
      translucent,
      closed: false,
    }),
    asynchronous: false,
  });
}

export function terrainPrimitive(
  field: Field,
  west: number,
  south: number,
  depth?: Float32Array,
): { primitive: Cesium.Primitive; water: Cesium.Primitive | null } {
  const { cols, rows, spacing } = field;
  const positions = new Float64Array(cols * rows * 3);
  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < cols; c++) {
      const i = field.index(c, r);
      const o = i * 3;
      positions[o] = c * spacing;
      positions[o + 1] = r * spacing;
      positions[o + 2] = field.heights[i] ?? 0;
    }
  }
  const index: number[] = [];
  for (let r = 0; r < rows - 1; r++) {
    for (let c = 0; c < cols - 1; c++) {
      const i = field.index(c, r);
      index.push(i, i + 1, i + cols, i + 1, i + cols + 1, i + cols);
    }
  }
  const modelMatrix = Cesium.Transforms.eastNorthUpToFixedFrame(Cesium.Cartesian3.fromDegrees(west, south, 0));
  const primitive = surface(positions, index, modelMatrix, Cesium.Color.fromCssColorString('#d7c4a8'), false);
  return { primitive, water: depth ? waterPrimitive(field, depth, modelMatrix) : null };
}

function waterPrimitive(field: Field, depth: Float32Array, modelMatrix: Cesium.Matrix4): Cesium.Primitive | null {
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
        positions.push(cc * spacing, rr * spacing, (field.heights[corner] ?? 0) + (depth[corner] ?? 0) + 0.25);
      }
      index.push(base, base + 1, base + 2, base + 1, base + 3, base + 2);
    }
  }
  if (!index.length) return null;
  return surface(new Float64Array(positions), index, modelMatrix, Cesium.Color.fromCssColorString('#2f7ea3').withAlpha(0.72), true);
}

/** A site mesh split into chunks so a blade edit does not rebuild the whole field. */
export class ChunkLayer {
  private readonly chunks = new Map<string, Cesium.Primitive>();
  private water: Cesium.Primitive | null = null;
  private skirt: Cesium.Primitive | null = null;
  private waterDirty = false;

  constructor(
    private readonly viewer: Cesium.Viewer,
    readonly field: Field,
    readonly west: number,
    readonly south: number,
    private depth: Float32Array,
  ) {
    this.field.touchAll();
    this.waterDirty = true;
    this.skirt = skirtPrimitive(field, west, south);
    this.viewer.scene.primitives.add(this.skirt);
    this.flush(64);
  }

  setDepth(depth: Float32Array): void {
    this.depth = depth;
    this.waterDirty = true;
  }

  flush(max = 4): void {
    const modelMatrix = Cesium.Transforms.eastNorthUpToFixedFrame(Cesium.Cartesian3.fromDegrees(this.west, this.south, 0));
    let built = 0;
    for (const key of this.field.dirtyChunks) {
      if (built >= max) break;
      this.field.dirtyChunks.delete(key);
      const [cs, rs] = key.split(':');
      const c0 = Number(cs) * this.field.chunk;
      const r0 = Number(rs) * this.field.chunk;
      const previous = this.chunks.get(key);
      if (previous) this.viewer.scene.primitives.remove(previous);
      const primitive = chunkPrimitive(this.field, c0, r0, modelMatrix);
      this.viewer.scene.primitives.add(primitive);
      this.chunks.set(key, primitive);
      built += 1;
    }
    if (this.waterDirty && this.field.dirtyChunks.size === 0) {
      if (this.water) this.viewer.scene.primitives.remove(this.water);
      const mesh = terrainPrimitive(this.field, this.west, this.south, this.depth);
      this.water = mesh.water;
      if (this.water) this.viewer.scene.primitives.add(this.water);
      this.viewer.scene.primitives.remove(mesh.primitive);
      this.waterDirty = false;
    }
    this.field.dirty = this.field.dirtyChunks.size > 0;
  }
}

function chunkPrimitive(field: Field, c0: number, r0: number, modelMatrix: Cesium.Matrix4): Cesium.Primitive {
  const c1 = Math.min(field.cols - 1, c0 + field.chunk);
  const r1 = Math.min(field.rows - 1, r0 + field.chunk);
  const positions: number[] = [];
  const index: number[] = [];
  const id: number[] = [];
  for (let r = r0; r <= r1; r++) {
    for (let c = c0; c <= c1; c++) {
      id.push(field.index(c, r));
      positions.push(c * field.spacing, r * field.spacing, field.heights[field.index(c, r)] ?? 0);
    }
  }
  const stride = c1 - c0 + 1;
  for (let r = r0; r < r1; r++) {
    for (let c = c0; c < c1; c++) {
      const i = (r - r0) * stride + (c - c0);
      index.push(i, i + 1, i + stride, i + 1, i + stride + 1, i + stride);
    }
  }
  void id;
  return surface(new Float64Array(positions), index, modelMatrix, Cesium.Color.fromCssColorString('#d2c0a4'), false);
}

export function skirtPrimitive(field: Field, west: number, south: number): Cesium.Primitive {
  const { cols, rows, spacing } = field;
  const reach = Math.max(1200, spacing * 8);
  const positions: number[] = [];
  const index: number[] = [];
  const edge = (c: number, r: number, outwardEast: number, outwardNorth: number) => {
    const h = field.heights[field.index(c, r)] ?? 0;
    const base = positions.length / 3;
    positions.push(c * spacing, r * spacing, h, c * spacing + outwardEast, r * spacing + outwardNorth, Math.max(0, h - 140));
    return base;
  };
  for (let c = 0; c < cols - 1; c++) {
    const south0 = edge(c, 0, 0, -reach);
    const south1 = edge(c + 1, 0, 0, -reach);
    index.push(south0, south1, south0 + 1, south1, south1 + 1, south0 + 1);
    const north0 = edge(c, rows - 1, 0, reach);
    const north1 = edge(c + 1, rows - 1, 0, reach);
    index.push(north0, north0 + 1, north1, north1, north0 + 1, north1 + 1);
  }
  for (let r = 0; r < rows - 1; r++) {
    const west0 = edge(0, r, -reach, 0);
    const west1 = edge(0, r + 1, -reach, 0);
    index.push(west0, west0 + 1, west1, west1, west0 + 1, west1 + 1);
    const east0 = edge(cols - 1, r, reach, 0);
    const east1 = edge(cols - 1, r + 1, reach, 0);
    index.push(east0, east1, east0 + 1, east1, east1 + 1, east0 + 1);
  }
  const modelMatrix = Cesium.Transforms.eastNorthUpToFixedFrame(Cesium.Cartesian3.fromDegrees(west, south, 0));
  return surface(new Float64Array(positions), index, modelMatrix, Cesium.Color.fromCssColorString('#b7c3c8'), false);
}
