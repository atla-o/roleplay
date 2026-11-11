import * as Cesium from 'cesium';
import { offsetDegrees } from './field';
import type { Detail } from './detail';

/** The 1 m edit window, drawn in chunks so a blade scrape does not rebuild all 256 m. */
export class FineLayer {
  private readonly chunks = new Map<string, Cesium.Primitive>();

  constructor(
    private readonly viewer: Cesium.Viewer,
    private readonly west: number,
    private readonly south: number,
    readonly detail: Detail,
  ) {}

  flush(max = 3): void {
    let built = 0;
    for (const key of this.detail.dirty) {
      if (built >= max) break;
      this.detail.dirty.delete(key);
      const [cs, rs] = key.split(':');
      const previous = this.chunks.get(key);
      if (previous) this.viewer.scene.primitives.remove(previous);
      const primitive = fineChunk(this.detail, this.west, this.south, Number(cs), Number(rs));
      this.viewer.scene.primitives.add(primitive);
      this.chunks.set(key, primitive);
      built += 1;
    }
  }

  destroy(): void {
    for (const primitive of this.chunks.values()) this.viewer.scene.primitives.remove(primitive);
    this.chunks.clear();
  }
}

function fineChunk(detail: Detail, west: number, south: number, cx: number, cy: number): Cesium.Primitive {
  const c0 = cx * detail.chunk;
  const r0 = cy * detail.chunk;
  const c1 = Math.min(detail.size - 1, c0 + detail.chunk);
  const r1 = Math.min(detail.size - 1, r0 + detail.chunk);
  const positions: number[] = [];
  const index: number[] = [];
  const stride = c1 - c0 + 1;
  for (let r = r0; r <= r1; r++) {
    for (let c = c0; c <= c1; c++) {
      const east = detail.originE + c;
      const north = detail.originN + r;
      const ll = offsetDegrees(south, west, east, north);
      const cart = Cesium.Cartesian3.fromDegrees(ll.lon, ll.lat, (detail.heights[r * detail.size + c] ?? 0) + 0.04);
      positions.push(cart.x, cart.y, cart.z);
    }
  }
  for (let r = r0; r < r1; r++) {
    for (let c = c0; c < c1; c++) {
      const i = (r - r0) * stride + (c - c0);
      index.push(i, i + 1, i + stride, i + 1, i + stride + 1, i + stride);
    }
  }
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
  return new Cesium.Primitive({
    geometryInstances: new Cesium.GeometryInstance({
      geometry,
      attributes: { color: Cesium.ColorGeometryInstanceAttribute.fromColor(Cesium.Color.fromCssColorString('#c9b496')) },
    }),
    appearance: new Cesium.PerInstanceColorAppearance({ flat: false, translucent: false, closed: false }),
    asynchronous: true,
  });
}
