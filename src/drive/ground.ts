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

/**
 * One opaque surface. Posts are shared across LOD rings, so the mesh does not
 * overlap itself. The normal map is the slope of these same posts.
 */
const CLOTH = `
czm_material czm_getMaterial(czm_materialInput materialInput) {
  czm_material m = czm_getDefaultMaterial(materialInput);
  vec2 st = materialInput.st;
  float lon = mix(mix(sw.x, se.x, st.x), mix(nw.x, ne.x, st.x), st.y);
  float lat = mix(mix(sw.y, se.y, st.x), mix(nw.y, ne.y, st.x), st.y);
  vec2 img = vec2((lon - west) / (east - west), (lat - south) / (north - south));
  vec4 sat = texture(image, img);
  float cut = texture(mask, img).r;
  vec3 nTex = texture(relief, st).rgb * 2.0 - 1.0;
  float curve = texture(relief, st).a;
  vec3 lin = pow(max(sat.rgb, vec3(0.0)), vec3(2.2));
  float luma = dot(lin, vec3(0.2126, 0.7152, 0.0722));
  lin = mix(vec3(luma), lin, 1.35);
  vec3 slope = normalize(nTex);
  float hill = clamp(dot(slope, normalize(vec3(0.82, 0.28, 0.5))), 0.0, 1.0);
  lin *= clamp(0.86 + 0.26 * hill, 0.74, 1.06);
  float shade = clamp((curve - 0.5) * 2.0, -1.0, 1.0);
  lin *= 1.0 - shade * 0.22;
  vec3 moist = vec3(0.065, 0.032, 0.014);
  lin = mix(lin, moist, smoothstep(0.2, 0.9, cut) * 0.88);
  m.diffuse = max(lin, vec3(0.0));
  m.normal = materialInput.normalEC;
  m.specular = 0.015 + cut * 0.16;
  m.shininess = mix(6.0, 24.0, cut);
  m.alpha = 1.0;
  return m;
}
`;

const WATER = `
czm_material czm_getMaterial(czm_materialInput materialInput) {
  czm_material m = czm_getDefaultMaterial(materialInput);
  vec2 st = materialInput.st;
  float rip = sin(st.x * 180.0) * sin(st.y * 140.0);
  m.diffuse = vec3(0.03, 0.16, 0.20) + vec3(0.02, 0.04, 0.05) * rip;
  m.specular = 0.72;
  m.shininess = 28.0;
  m.alpha = 0.92;
  return m;
}
`;

export class Drape {
  private surface: Cesium.Primitive | null = null;
  private far: Cesium.Primitive | null = null;
  private waterPrim: Cesium.Primitive | null = null;
  private trees: Cesium.Primitive | null = null;
  private readonly material: Cesium.Material;
  private readonly mask: HTMLCanvasElement;
  private readonly pen: CanvasRenderingContext2D;
  private anchorC = -9999;
  private anchorR = -9999;
  private built = 0;
  readonly waterLevel: number | null;
  private readonly sw: { lon: number; lat: number };
  private readonly se: { lon: number; lat: number };
  private readonly nw: { lon: number; lat: number };
  private readonly ne: { lon: number; lat: number };

  constructor(
    private readonly viewer: Cesium.Viewer,
    readonly field: Field,
    private readonly toLonLat: (east: number, north: number) => { lon: number; lat: number },
    image: string,
    private readonly bounds: GeoBounds,
    waterLevel: number | null,
    private readonly forest: boolean,
  ) {
    this.waterLevel = waterLevel;
    this.mask = document.createElement('canvas');
    this.mask.width = 1024;
    this.mask.height = 1024;
    const pen = this.mask.getContext('2d');
    if (!pen) throw new Error('The ground mask could not be opened.');
    this.pen = pen;
    this.sw = this.toLonLat(0, 0);
    this.se = this.toLonLat((field.cols - 1) * field.spacing, 0);
    this.nw = this.toLonLat(0, (field.rows - 1) * field.spacing);
    this.ne = this.toLonLat((field.cols - 1) * field.spacing, (field.rows - 1) * field.spacing);
    const sw = this.sw;
    const se = this.se;
    const nw = this.nw;
    const ne = this.ne;
    const relief = this.reliefCanvas();
    this.material = new Cesium.Material({
      fabric: {
        uniforms: {
          image,
          mask: this.mask,
          relief,
          sw: new Cesium.Cartesian2(sw.lon, sw.lat),
          se: new Cesium.Cartesian2(se.lon, se.lat),
          nw: new Cesium.Cartesian2(nw.lon, nw.lat),
          ne: new Cesium.Cartesian2(ne.lon, ne.lat),
          west: bounds.west,
          south: bounds.south,
          east: bounds.east,
          north: bounds.north,
        },
        source: CLOTH,
      },
    });
    if (forest) this.trees = this.buildTrees();
    if (this.trees) this.viewer.scene.primitives.add(this.trees);
  }

  follow(east: number, north: number): void {
    const c = Math.round(east / this.field.spacing / 8) * 8;
    const r = Math.round(north / this.field.spacing / 8) * 8;
    if (Math.abs(c - this.anchorC) > 16 || Math.abs(r - this.anchorR) > 16) {
      this.anchorC = c;
      this.anchorR = r;
    }
  }

  paintCell(c: number, r: number): void {
    const ll = this.toLonLat((c + 0.5) * this.field.spacing, (r + 0.5) * this.field.spacing);
    const u = (ll.lon - this.bounds.west) / (this.bounds.east - this.bounds.west);
    const v = (ll.lat - this.bounds.south) / (this.bounds.north - this.bounds.south);
    if (u < 0 || v < 0 || u > 1 || v > 1) return;
    const x = u * this.mask.width;
    const y = (1 - v) * this.mask.height;
    this.pen.fillStyle = 'rgba(255,255,255,1)';
    this.pen.beginPath();
    this.pen.arc(x, y, 0.9, 0, Math.PI * 2);
    this.maskDirty = true;
    this.pen.fill();
  }

  flush(): void {
    const now = performance.now();
    const due = this.surface == null || this.field.dirty && now - this.built > 160;
    if (!due && this.anchorC === this.builtAnchorC && this.anchorR === this.builtAnchorR) {
      this.pushMask();
      return;
    }
    if (this.anchorC < -100) return;
    const moved = this.anchorC !== this.builtAnchorC || this.anchorR !== this.builtAnchorR;
    if (moved || this.far == null) this.far = this.swap(this.far, this.buildFar());
    this.surface = this.swap(this.surface, this.buildSurface());
    if (!this.waterBuilt) {
      this.waterPrim = this.swap(this.waterPrim, this.buildWater());
      this.waterBuilt = true;
    }
    this.built = now;
    this.builtAnchorC = this.anchorC;
    this.builtAnchorR = this.anchorR;
    this.field.dirty = false;
    this.field.dirtyChunks.clear();
    this.pushMask();
  }

  private maskDirty = true;

  /** A new canvas each time, so Cesium uploads the cut instead of reusing the first texture. */
  private pushMask(): void {
    if (!this.maskDirty) return;
    const copy = document.createElement('canvas');
    copy.width = this.mask.width;
    copy.height = this.mask.height;
    copy.getContext('2d')?.drawImage(this.mask, 0, 0);
    this.material.uniforms.mask = copy;
    this.maskDirty = false;
  }

  private builtAnchorC = -9999;
  private builtAnchorR = -9999;
  private waterBuilt = false;

  /** Bilinear of the four corner posts. The error against the projection stays under one post. */
  private cart(c: number, r: number, h: number): Cesium.Cartesian3 {
    const u = c / (this.field.cols - 1);
    const v = r / (this.field.rows - 1);
    const lon = (1 - v) * ((1 - u) * this.sw.lon + u * this.se.lon) + v * ((1 - u) * this.nw.lon + u * this.ne.lon);
    const lat = (1 - v) * ((1 - u) * this.sw.lat + u * this.se.lat) + v * ((1 - u) * this.nw.lat + u * this.ne.lat);
    return Cesium.Cartesian3.fromDegrees(lon, lat, h);
  }

  private swap(previous: Cesium.Primitive | null, next: Cesium.Primitive | null): Cesium.Primitive | null {
    if (previous) this.viewer.scene.primitives.remove(previous);
    if (next) this.viewer.scene.primitives.add(next);
    return next;
  }

  /** Slope of the measured posts, one texel per post, in the same geographic frame as the photograph. */
  private reliefCanvas(): HTMLCanvasElement {
    const { field } = this;
    const canvas = document.createElement('canvas');
    const n = 1024;
    canvas.width = n;
    canvas.height = n;
    const ctx = canvas.getContext('2d');
    if (!ctx) return canvas;
    const img = ctx.createImageData(n, n);
    const acc = new Float32Array(n * n * 3);
    const count = new Uint16Array(n * n);
    const step = Math.max(1, Math.floor(field.cols / n));
    for (let r = 1; r < field.rows - 1; r += step) {
      for (let c = 1; c < field.cols - 1; c += step) {
        const hL = field.heights[field.index(c - 1, r)] ?? 0;
        const hR = field.heights[field.index(c + 1, r)] ?? 0;
        const hD = field.heights[field.index(c, r - 1)] ?? 0;
        const hU = field.heights[field.index(c, r + 1)] ?? 0;
        const h = field.heights[field.index(c, r)] ?? 0;
        const dx = (hR - hL) / (2 * field.spacing);
        const dy = (hU - hD) / (2 * field.spacing);
        const len = Math.hypot(dx, dy, 1);
        const nx = -dx / len;
        const ny = -dy / len;
        const nz = 1 / len;
        const lap = (hL + hR + hD + hU) * 0.25 - h;
        const x = Math.max(0, Math.min(n - 1, Math.floor((c / (field.cols - 1)) * n)));
        const y = Math.max(0, Math.min(n - 1, Math.floor((1 - r / (field.rows - 1)) * n)));
        const i = y * n + x;
        acc[i * 3] = (acc[i * 3] ?? 0) + nx;
        acc[i * 3 + 1] = (acc[i * 3 + 1] ?? 0) + ny;
        acc[i * 3 + 2] = (acc[i * 3 + 2] ?? 0) + nz;
        count[i] = (count[i] ?? 0) + 1;
        img.data[i * 4 + 3] = Math.max(0, Math.min(255, Math.round(128 + lap * 40)));
      }
    }
    for (let i = 0; i < n * n; i++) {
      const k = count[i] ?? 0;
      const nx = k ? (acc[i * 3] ?? 0) / k : 0;
      const ny = k ? (acc[i * 3 + 1] ?? 0) / k : 0;
      const nz = k ? (acc[i * 3 + 2] ?? 0) / k : 1;
      img.data[i * 4] = Math.round((nx * 0.5 + 0.5) * 255);
      img.data[i * 4 + 1] = Math.round((ny * 0.5 + 0.5) * 255);
      img.data[i * 4 + 2] = Math.round((nz * 0.5 + 0.5) * 255);
      if (!k) img.data[i * 4 + 3] = 128;
    }
    ctx.putImageData(img, 0, 0);
    return canvas;
  }

  private buildSurface(): Cesium.Primitive | null {
    const { field } = this;
    const cols = field.cols;
    const rows = field.rows;
    const ac = Math.max(64, Math.min(cols - 65, this.anchorC));
    const ar = Math.max(64, Math.min(rows - 65, this.anchorR));
    const indexOf = new Map<number, number>();
    const positions: number[] = [];
    const sts: number[] = [];
    const indices: number[] = [];
    const add = (c: number, r: number, drop = 0): number => {
      c = Math.max(0, Math.min(cols - 1, c));
      r = Math.max(0, Math.min(rows - 1, r));
      const key = (r * cols + c) * 2 + (drop < 0 ? 1 : 0);
      const have = indexOf.get(key);
      if (have != null) return have;
      const id = positions.length / 3;
      indexOf.set(key, id);
      const h = (field.heights[field.index(c, r)] ?? 0) + drop;
      const cart = this.cart(c, r, h);
      positions.push(cart.x, cart.y, cart.z);
      sts.push(c / (cols - 1), r / (rows - 1));
      return id;
    };
    const quad = (c: number, r: number, s: number) => {
      const a = add(c, r);
      const b = add(c + s, r);
      const d = add(c, r + s);
      const e = add(c + s, r + s);
      indices.push(a, b, d, b, e, d);
    };
    const emit = (half: number, stride: number, hole: number) => {
      const c0 = Math.max(0, Math.floor((ac - half) / stride) * stride);
      const r0 = Math.max(0, Math.floor((ar - half) / stride) * stride);
      const c1 = Math.min(cols - 1 - stride, ac + half);
      const r1 = Math.min(rows - 1 - stride, ar + half);
      for (let r = r0; r <= r1; r += stride) {
        for (let c = c0; c <= c1; c += stride) {
          if (hole > 0 && c >= ac - hole && c + stride <= ac + hole && r >= ar - hole && r + stride <= ar + hole) continue;
          quad(c, r, stride);
        }
      }
    };
    emit(80, 1, 0);
    emit(272, 2, 80);
    const edge = 272;
    for (let c = ac - edge; c < ac + edge; c += 2) {
      skirt(add, indices, c, ar - edge, c + 2, ar - edge, -4);
      skirt(add, indices, c, ar + edge, c + 2, ar + edge, -4);
    }
    for (let r = ar - edge; r < ar + edge; r += 2) {
      skirt(add, indices, ac - edge, r, ac - edge, r + 2, -4);
      skirt(add, indices, ac + edge, r, ac + edge, r + 2, -4);
    }
    return primitive(positions, sts, indices, this.material, false, Cesium.ShadowMode.ENABLED);
  }

  private buildFar(): Cesium.Primitive | null {
    const { field } = this;
    const cols = field.cols;
    const rows = field.rows;
    const ac = Math.max(64, Math.min(cols - 65, this.anchorC));
    const ar = Math.max(64, Math.min(rows - 65, this.anchorR));
    const indexOf = new Map<number, number>();
    const positions: number[] = [];
    const sts: number[] = [];
    const indices: number[] = [];
    const add = (c: number, r: number, drop = 0): number => {
      c = Math.max(0, Math.min(cols - 1, c));
      r = Math.max(0, Math.min(rows - 1, r));
      const key = (r * cols + c) * 2 + (drop < 0 ? 1 : 0);
      const have = indexOf.get(key);
      if (have != null) return have;
      const id = positions.length / 3;
      indexOf.set(key, id);
      const cart = this.cart(c, r, (field.heights[field.index(c, r)] ?? 0) + drop);
      positions.push(cart.x, cart.y, cart.z);
      sts.push(c / (cols - 1), r / (rows - 1));
      return id;
    };
    const hole = 272;
    const stride = 8;
    for (let r = 0; r <= rows - 1 - stride; r += stride) {
      for (let c = 0; c <= cols - 1 - stride; c += stride) {
        if (c >= ac - hole && c + stride <= ac + hole && r >= ar - hole && r + stride <= ar + hole) continue;
        const a = add(c, r);
        const b = add(c + stride, r);
        const d = add(c, r + stride);
        const e = add(c + stride, r + stride);
        indices.push(a, b, d, b, e, d);
      }
    }
    for (let c = 0; c < cols - 4; c += 4) {
      skirt(add, indices, c, 0, c + 4, 0);
      skirt(add, indices, c, rows - 1, c + 4, rows - 1);
    }
    for (let r = 0; r < rows - 4; r += 4) {
      skirt(add, indices, 0, r, 0, r + 4);
      skirt(add, indices, cols - 1, r, cols - 1, r + 4);
    }
    return primitive(positions, sts, indices, this.material, false, Cesium.ShadowMode.DISABLED);
  }

  private buildWater(): Cesium.Primitive | null {
    if (this.waterLevel == null) return null;
    const { field } = this;
    const level = this.waterLevel + 0.35;
    const positions: number[] = [];
    const sts: number[] = [];
    const indices: number[] = [];
    const stride = 2;
    for (let r = 0; r < field.rows - stride; r += stride) {
      for (let c = 0; c < field.cols - stride; c += stride) {
        let wet = 0;
        for (const [dc, dr] of [[0, 0], [stride, 0], [0, stride], [stride, stride]] as const) {
          if ((field.heights[field.index(c + dc, r + dr)] ?? 99) <= this.waterLevel + 0.4) wet += 1;
        }
        if (wet < 3) continue;
        const base = positions.length / 3;
        for (const [dc, dr] of [[0, 0], [stride, 0], [0, stride], [stride, stride]] as const) {
          const cart = this.cart(c + dc, r + dr, level);
          positions.push(cart.x, cart.y, cart.z);
          sts.push(dc / stride, dr / stride);
        }
        indices.push(base, base + 1, base + 2, base + 1, base + 3, base + 2);
      }
    }
    // Past the tile the reservoir would end as a cliff. Continue the same water plane.
    const apron = 1600;
    const wide = 100;
    for (let r = -apron; r < field.rows + apron; r += wide) {
      for (let c = -apron; c < field.cols + apron; c += wide) {
        const overTile = c >= -wide && r >= -wide && c < field.cols && r < field.rows;
        if (overTile) continue;
        const base = positions.length / 3;
        for (const [dc, dr] of [[0, 0], [wide, 0], [0, wide], [wide, wide]] as const) {
          const cart = this.cart(c + dc, r + dr, level);
          positions.push(cart.x, cart.y, cart.z);
          sts.push(0, 0);
        }
        indices.push(base, base + 1, base + 2, base + 1, base + 3, base + 2);
      }
    }
    if (!indices.length) return null;
    const material = new Cesium.Material({ fabric: { source: WATER } });
    return primitive(positions, sts, indices, material, true, Cesium.ShadowMode.DISABLED);
  }

  private buildTrees(): Cesium.Primitive | null {
    const { field } = this;
    const positions: number[] = [];
    const indices: number[] = [];
    const step = 18;
    for (let r = 2; r < field.rows - 2; r += step) {
      for (let c = 2; c < field.cols - 2; c += step) {
        const h = field.heights[field.index(c, r)] ?? 0;
        if (this.waterLevel != null && h <= this.waterLevel + 2) continue;
        const slope = Math.abs(h - (field.heights[field.index(c + 2, r)] ?? h)) / (2 * field.spacing);
        if (slope > 0.45) continue;
        const n = ((c * 17 + r * 31) % 7) / 7;
        if (n > 0.72) continue;
        const height = 7 + n * 9;
        const base = this.cart(c, r, h);
        const top = this.cart(c, r, h + height);
        const east = this.cart(c + 1.2, r, h + height * 0.25);
        const north = this.cart(c, r + 1.2, h + height * 0.25);
        const start = positions.length / 3;
        pushVec(positions, base);
        pushVec(positions, east);
        pushVec(positions, north);
        pushVec(positions, top);
        indices.push(start, start + 1, start + 3, start, start + 2, start + 3, start + 1, start + 2, start + 3);
      }
    }
    if (!indices.length) return null;
    const geometry = new Cesium.Geometry({
      attributes: {
        position: new Cesium.GeometryAttribute({
          componentDatatype: Cesium.ComponentDatatype.DOUBLE,
          componentsPerAttribute: 3,
          values: new Float64Array(positions),
        }),
      } as Cesium.GeometryAttributes,
      indices: indices.length > 65535 ? new Uint32Array(indices) : new Uint16Array(indices),
      primitiveType: Cesium.PrimitiveType.TRIANGLES,
      boundingSphere: Cesium.BoundingSphere.fromVertices(positions),
    });
    Cesium.GeometryPipeline.computeNormal(geometry);
    return new Cesium.Primitive({
      geometryInstances: new Cesium.GeometryInstance({
        geometry,
        attributes: { color: Cesium.ColorGeometryInstanceAttribute.fromColor(Cesium.Color.fromCssColorString('#5a9a42')) },
      }),
      appearance: new Cesium.PerInstanceColorAppearance({ flat: false, closed: false, translucent: false }),
      asynchronous: false,
      shadows: Cesium.ShadowMode.DISABLED,
    });
  }
}

function skirt(
  add: (c: number, r: number, drop?: number) => number,
  indices: number[],
  c: number,
  r: number,
  c2: number,
  r2: number,
  drop = -22,
): void {
  const a = add(c, r, 0);
  const b = add(c2, r2, 0);
  const d = add(c, r, drop);
  const e = add(c2, r2, drop);
  indices.push(a, b, d, b, e, d);
}

function pushVec(positions: number[], v: Cesium.Cartesian3): void {
  positions.push(v.x, v.y, v.z);
}

function primitive(
  positions: number[],
  sts: number[],
  indices: number[],
  material: Cesium.Material,
  translucent: boolean,
  shadows: Cesium.ShadowMode,
): Cesium.Primitive {
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
    indices: indices.length > 65535 ? new Uint32Array(indices) : new Uint16Array(indices),
    primitiveType: Cesium.PrimitiveType.TRIANGLES,
    boundingSphere: Cesium.BoundingSphere.fromVertices(positions),
  });
  Cesium.GeometryPipeline.computeNormal(geometry);
  return new Cesium.Primitive({
    geometryInstances: new Cesium.GeometryInstance({ geometry }),
    appearance: new Cesium.MaterialAppearance({
      material,
      flat: false,
      faceForward: false,
      closed: false,
      translucent,
      renderState: {
        cull: { enabled: true, face: Cesium.CullFace.BACK },
        depthTest: { enabled: true },
        depthMask: !translucent,
      },
    }),
    asynchronous: false,
    shadows,
  });
}
