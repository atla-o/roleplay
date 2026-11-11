import * as Cesium from 'cesium';
import proj4 from 'proj4';
import type { Field } from './field';

proj4.defs('EPSG:3413', '+proj=stere +lat_0=90 +lat_ts=70 +lon_0=-45 +x_0=0 +y_0=0 +datum=WGS84 +units=m +no_defs');
proj4.defs('EPSG:32619', '+proj=utm +zone=19 +datum=WGS84 +units=m +no_defs');

export interface GeoBounds {
  west: number;
  south: number;
  east: number;
  north: number;
}

export function projector(crs: string): {
  forward: (x: number, y: number) => { lon: number; lat: number };
  inverse: (lon: number, lat: number) => { x: number; y: number };
} {
  return {
    forward(x, y) {
      const [lon, lat] = proj4(crs, 'WGS84', [x, y]) as number[];
      return { lon: lon ?? 0, lat: lat ?? 0 };
    },
    inverse(lon, lat) {
      const [x, y] = proj4('WGS84', crs, [lon, lat]) as number[];
      return { x: x ?? 0, y: y ?? 0 };
    },
  };
}

const CLOTH = `
float grain(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
czm_material czm_getMaterial(czm_materialInput materialInput) {
  czm_material m = czm_getDefaultMaterial(materialInput);
  vec2 st = materialInput.st;
  vec4 sat = texture(image, st);
  float cut = texture(mask, st).r;
  vec2 metres = st * vec2(span, span);
  float g = grain(metres * 1.15);
  float rock = smoothstep(0.86, 0.98, grain(floor(metres / 4.0) + vec2(3.0, 9.0)));
  vec3 color = pow(max(sat.rgb, vec3(0.02)), vec3(0.82)) * (1.15 + 0.05 * (g - 0.5));
  color = mix(color, color * vec3(0.48, 0.36, 0.27), clamp(cut, 0.0, 1.0));
  m.diffuse = color;
  m.alpha = 1.0;
  float bump = (g - 0.5) * 0.22 + rock * 0.18;
  m.normal = normalize(materialInput.normalEC + vec3(bump, 0.0, bump * 0.55));
  return m;
}
`;

/** The measured grid, drawn at full post spacing underfoot and coarser farther out. Both levels are the same posts. */
export class Drape {
  private coarse: Cesium.Primitive | null = null;
  private nearPrim: Cesium.Primitive | null = null;
  private readonly material: Cesium.Material;
  private readonly mask: HTMLCanvasElement;
  private readonly pen: CanvasRenderingContext2D;
  private nearC = 0;
  private nearR = 0;
  private readonly nearN = 120;
  private dirtyNear = true;
  private dirtyCoarse = true;

  constructor(
    private readonly viewer: Cesium.Viewer,
    readonly field: Field,
    private readonly toLonLat: (east: number, north: number) => { lon: number; lat: number },
    image: string,
    private readonly bounds: GeoBounds,
    private readonly relief: (lon: number, lat: number) => number | null,
  ) {
    this.mask = document.createElement('canvas');
    this.mask.width = 768;
    this.mask.height = 768;
    const pen = this.mask.getContext('2d');
    if (!pen) throw new Error('The ground mask could not be opened.');
    this.pen = pen;
    this.material = new Cesium.Material({
      fabric: {
        uniforms: {
          image,
          mask: this.mask,
          span: (field.cols - 1) * field.spacing,
        },
        source: CLOTH,
      },
    });
  }

  follow(east: number, north: number): void {
    const half = this.nearN / 2 | 0;
    const c = Math.floor(east / this.field.spacing) - half;
    const r = Math.floor(north / this.field.spacing) - half;
    const nc = Math.max(0, Math.min(this.field.cols - this.nearN, c));
    const nr = Math.max(0, Math.min(this.field.rows - this.nearN, r));
    if (Math.abs(nc - this.nearC) > 24 || Math.abs(nr - this.nearR) > 24 || (this.nearC === 0 && this.nearR === 0 && (nc !== 0 || nr !== 0))) {
      this.nearC = nc;
      this.nearR = nr;
      this.dirtyNear = true;
      this.dirtyCoarse = true;
    }
  }

  /** Darken the satellite texel over a post the blade has touched. */
  paintCell(c: number, r: number): void {
    const ll = this.toLonLat((c + 0.5) * this.field.spacing, (r + 0.5) * this.field.spacing);
    const u = (ll.lon - this.bounds.west) / (this.bounds.east - this.bounds.west);
    const v = (ll.lat - this.bounds.south) / (this.bounds.north - this.bounds.south);
    if (u < 0 || v < 0 || u > 1 || v > 1) return;
    const x = u * this.mask.width;
    const y = (1 - v) * this.mask.height;
    this.pen.fillStyle = 'rgba(255,255,255,0.9)';
    this.pen.beginPath();
    this.pen.arc(x, y, 2.1, 0, Math.PI * 2);
    this.pen.fill();
  }

  flush(): void {
    if (this.dirtyCoarse) {
      this.coarse = this.swap(this.coarse, this.build(0, 0, this.field.cols - 1, this.field.rows - 1, 8, true));
      this.dirtyCoarse = false;
    }
    if (this.dirtyNear || this.field.dirty) {
      this.nearPrim = this.swap(this.nearPrim, this.build(this.nearC, this.nearR, this.nearC + this.nearN - 1, this.nearR + this.nearN - 1, 1, false));
      this.dirtyNear = false;
      this.field.dirty = false;
      this.field.dirtyChunks.clear();
    }
    this.material.uniforms.mask = this.mask;
  }

  private swap(previous: Cesium.Primitive | null, next: Cesium.Primitive | null): Cesium.Primitive | null {
    if (previous) this.viewer.scene.primitives.remove(previous);
    if (next) this.viewer.scene.primitives.add(next);
    return next;
  }

  private build(c0: number, r0: number, c1: number, r1: number, stride: number, hole: boolean): Cesium.Primitive | null {
    const { field } = this;
    const postsC: number[] = [];
    const postsR: number[] = [];
    for (let c = c0; c <= c1; c += stride) postsC.push(c);
    if (postsC[postsC.length - 1] !== c1) postsC.push(c1);
    for (let r = r0; r <= r1; r += stride) postsR.push(r);
    if (postsR[postsR.length - 1] !== r1) postsR.push(r1);
    const positions: number[] = [];
    const sts: number[] = [];
    const index: number[] = [];
    const strideC = postsC.length;
    for (const r of postsR) {
      for (const c of postsC) {
        const east = c * field.spacing;
        const north = r * field.spacing;
        const ll = this.toLonLat(east, north);
        const h = this.display(c, r, ll);
        const cartesian = Cesium.Cartesian3.fromDegrees(ll.lon, ll.lat, h);
        positions.push(cartesian.x, cartesian.y, cartesian.z);
        const u = (ll.lon - this.bounds.west) / (this.bounds.east - this.bounds.west);
        const v = (ll.lat - this.bounds.south) / (this.bounds.north - this.bounds.south);
        sts.push(u, v);
      }
    }
    for (let j = 0; j < postsR.length - 1; j++) {
      for (let i = 0; i < postsC.length - 1; i++) {
        if (hole) {
          const midC = ((postsC[i] ?? 0) + (postsC[i + 1] ?? 0)) / 2;
          const midR = ((postsR[j] ?? 0) + (postsR[j + 1] ?? 0)) / 2;
          if (midC > this.nearC + 2 && midC < this.nearC + this.nearN - 2 && midR > this.nearR + 2 && midR < this.nearR + this.nearN - 2) continue;
        }
        const a = j * strideC + i;
        index.push(a, a + 1, a + strideC, a + 1, a + strideC + 1, a + strideC);
      }
    }
    if (!index.length) return null;
    const geometry = new Cesium.Geometry({
      attributes: {
        position: new Cesium.GeometryAttribute({
          componentDatatype: Cesium.ComponentDatatype.DOUBLE,
          componentsPerAttribute: 3,
          values: new Float64Array(positions),
        }),
        st: new Cesium.GeometryAttribute({
          componentDatatype: Cesium.ComponentDatatype.FLOAT,
          componentsPerAttribute: 2,
          values: new Float32Array(sts),
        }),
      } as Cesium.GeometryAttributes,
      indices: index.length > 65535 ? new Uint32Array(index) : new Uint16Array(index),
      primitiveType: Cesium.PrimitiveType.TRIANGLES,
      boundingSphere: Cesium.BoundingSphere.fromVertices(positions),
    });
    Cesium.GeometryPipeline.computeNormal(geometry);
    return new Cesium.Primitive({
      geometryInstances: new Cesium.GeometryInstance({ geometry }),
      appearance: new Cesium.MaterialAppearance({
        material: this.material,
        flat: false,
        faceForward: true,
        closed: false,
        renderState: { cull: { enabled: false }, depthTest: { enabled: true } },
      }),
      asynchronous: false,
      shadows: Cesium.ShadowMode.ENABLED,
    });
  }

  /** Real posts inland. The outer 80 m eases onto the global DEM so the tile does not end in a wall. */
  private display(c: number, r: number, ll: { lon: number; lat: number }): number {
    const { field } = this;
    const h = field.heights[field.index(c, r)] ?? 0;
    const inset = Math.min(c, r, field.cols - 1 - c, field.rows - 1 - r);
    const band = Math.round(80 / field.spacing);
    if (inset >= band) return h;
    const outside = this.relief(ll.lon, ll.lat);
    if (outside == null) return h;
    const t = inset / band;
    const s = t * t * (3 - 2 * t);
    return h * s + outside * (1 - s);
  }
}
