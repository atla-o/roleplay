import * as Cesium from 'cesium';

/**
 * A dozer built from boxes, at real size. The local frame is east-north-up:
 * +X right, +Y forward, +Z up, which is the frame Cesium's heading uses.
 * Tracks are 3.5 m across the outside. The blade is 3.7 m and sits in front.
 */
export class Dozer {
  private readonly body: Cesium.Primitive;
  private readonly tracks: Cesium.Primitive;
  private readonly blade: Cesium.Primitive;
  private readonly bladeMatrix = new Cesium.Matrix4();
  private readonly scratch = new Cesium.Matrix4();

  constructor(private readonly viewer: Cesium.Viewer) {
    this.tracks = solid(merge([
      box(-1.42, 0.05, 0.42, 0.62, 4.7, 0.86),
      box(1.42, 0.05, 0.42, 0.62, 4.7, 0.86),
    ]), '#1f2937');
    this.body = solid(merge([
      box(0, -0.1, 0.5, 1.9, 3.2, 0.55),
      box(0, -0.15, 0.95, 1.7, 2.0, 0.4),
      box(0, -1.25, 1.45, 1.35, 1.15, 0.85),
      box(0, -1.25, 1.7, 1.05, 0.06, 0.55),
    ]), '#b45309');
    this.blade = solid(merge([
      box(0, 0.85, 0.05, 4.4, 0.22, 1.6),
      box(-1.7, 0.25, 0.35, 0.12, 1.15, 0.12),
      box(1.7, 0.25, 0.35, 0.12, 1.15, 0.12),
    ]), '#4b5563');
    viewer.scene.primitives.add(this.tracks);
    viewer.scene.primitives.add(this.body);
    viewer.scene.primitives.add(this.blade);
  }

  place(lon: number, lat: number, ground: number, heading: number, bladeAngle: number): void {
    const position = Cesium.Cartesian3.fromDegrees(lon, lat, ground + 0.02);
    const rotation = Cesium.Transforms.headingPitchRollQuaternion(
      position,
      new Cesium.HeadingPitchRoll(heading, 0, 0),
    );
    const bodyMatrix = Cesium.Matrix4.fromTranslationQuaternionRotationScale(
      position,
      rotation,
      new Cesium.Cartesian3(1, 1, 1),
      this.scratch,
    );
    const placed = Cesium.Matrix4.clone(bodyMatrix, this.body.modelMatrix);
    this.tracks.modelMatrix = Cesium.Matrix4.clone(placed, this.tracks.modelMatrix);
    // Pivot at the front of the tracks. A negative angle drops the edge into the grade.
    const pivot = Cesium.Matrix4.fromTranslation(new Cesium.Cartesian3(0, 2.15, 1.15));
    const spin = Cesium.Matrix4.fromRotationTranslation(Cesium.Matrix3.fromRotationX(bladeAngle));
    Cesium.Matrix4.multiply(bodyMatrix, pivot, this.bladeMatrix);
    Cesium.Matrix4.multiply(this.bladeMatrix, spin, this.bladeMatrix);
    this.blade.modelMatrix = Cesium.Matrix4.clone(this.bladeMatrix, this.blade.modelMatrix);
  }
}

function box(x: number, y: number, z: number, sx: number, sy: number, sz: number): number[] {
  const hx = sx / 2;
  const hy = sy / 2;
  const hz = sz / 2;
  const p = [
    [-hx, -hy, -hz], [hx, -hy, -hz], [hx, hy, -hz], [-hx, hy, -hz],
    [-hx, -hy, hz], [hx, -hy, hz], [hx, hy, hz], [-hx, hy, hz],
  ].map(([a, b, c]) => [a + x, b + y, c + z]);
  const faces = [
    [0, 1, 2, 3], [4, 7, 6, 5], [0, 4, 5, 1], [2, 6, 7, 3], [0, 3, 7, 4], [1, 5, 6, 2],
  ];
  const out: number[] = [];
  for (const f of faces) {
    const tri = [0, 1, 2, 0, 2, 3];
    for (const k of tri) {
      const v = p[f[k] ?? 0];
      if (!v) continue;
      out.push(v[0] ?? 0, v[1] ?? 0, v[2] ?? 0);
    }
  }
  return out;
}

function merge(parts: number[][]): number[] {
  return parts.flat();
}

function solid(positions: number[], css: string): Cesium.Primitive {
  const coords = new Float64Array(positions);
  const indices = new Uint16Array(positions.length / 3);
  for (let i = 0; i < indices.length; i++) indices[i] = i;
  const geo = new Cesium.Geometry({
    attributes: {
      position: new Cesium.GeometryAttribute({
        componentDatatype: Cesium.ComponentDatatype.DOUBLE,
        componentsPerAttribute: 3,
        values: coords,
      }),
    } as Cesium.GeometryAttributes,
    indices,
    primitiveType: Cesium.PrimitiveType.TRIANGLES,
    boundingSphere: Cesium.BoundingSphere.fromVertices(Array.from(coords)),
  });
  Cesium.GeometryPipeline.computeNormal(geo);
  return new Cesium.Primitive({
    geometryInstances: new Cesium.GeometryInstance({
      geometry: geo,
      attributes: { color: Cesium.ColorGeometryInstanceAttribute.fromColor(Cesium.Color.fromCssColorString(css)) },
    }),
    appearance: new Cesium.PerInstanceColorAppearance({
      flat: false,
      closed: true,
      translucent: false,
    }),
    asynchronous: false,
    shadows: Cesium.ShadowMode.ENABLED,
  });
}
