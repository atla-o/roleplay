import * as Cesium from 'cesium';

/**
 * Mapzen/Tilezen terrarium tiles, copied into this repo because the public bucket
 * does not send CORS headers. Zoom 3 covers the globe. Zoom 5 covers the corridor
 * between the two measured sites. Oceans are held at sea level.
 */

export interface LonBox {
  west: number;
  south: number;
  east: number;
  north: number;
}

interface Tile {
  z: number;
  x: number;
  y: number;
  heights: Float32Array;
}

export class Relief {
  private readonly data = new Map<string, Float32Array>();
  private readonly pending = new Set<string>();
  private readonly missing = new Set<string>();
  private readonly meshes = new Map<string, Cesium.Primitive>();

  constructor(
    private readonly base: string,
    private readonly viewer: Cesium.Viewer,
  ) {}

  prefetch(lon: number, lat: number): void {
    for (const tile of around(lon, lat, 5, 1)) this.load(tile.z, tile.x, tile.y);
    for (const tile of around(lon, lat, 3, 1)) this.load(tile.z, tile.x, tile.y);
  }

  /** Metres above sea level, or null while the tile is still on its way. */
  sample(lon: number, lat: number): number | null {
    const fine = this.sampleZoom(lon, lat, 5);
    if (fine != null) return fine;
    return this.sampleZoom(lon, lat, 3);
  }

  /** Keep a few tiles of mesh around the viewer. Measured sites are left as holes. */
  update(lon: number, lat: number, holes: LonBox[]): void {
    const wanted = new Set<string>();
    const fine = around(lon, lat, 5, 1).filter((tile) => this.data.has(keyOf(tile)));
    const use = fine.length ? fine : around(lon, lat, 3, 1);
    for (const tile of around(lon, lat, 5, 1)) this.load(tile.z, tile.x, tile.y);
    for (const tile of around(lon, lat, 3, 1)) this.load(tile.z, tile.x, tile.y);
    for (const tile of use) {
      const id = keyOf(tile);
      const heights = this.data.get(id);
      if (!heights) continue;
      wanted.add(id);
      if (!this.meshes.has(id)) {
        const mesh = tileMesh(tile.z, tile.x, tile.y, heights, holes);
        if (mesh) {
          this.viewer.scene.primitives.add(mesh);
          this.meshes.set(id, mesh);
        }
      }
    }
    for (const [id, mesh] of this.meshes) {
      if (wanted.has(id)) continue;
      this.viewer.scene.primitives.remove(mesh);
      this.meshes.delete(id);
    }
  }

  private sampleZoom(lon: number, lat: number, z: number): number | null {
    const tile = tileAt(lon, lat, z);
    const id = keyOf(tile);
    if (!this.data.has(id)) {
      this.load(tile.z, tile.x, tile.y);
      return null;
    }
    const heights = this.data.get(id);
    if (!heights) return null;
    const { fx, fy } = pixelOf(lon, lat, z, tile.x, tile.y);
    return Math.max(0, bilinear(heights, 256, fx, fy));
  }

  private load(z: number, x: number, y: number): void {
    const id = `${z}/${x}/${y}`;
    if (this.data.has(id) || this.pending.has(id) || this.missing.has(id)) return;
    this.pending.add(id);
    fetch(`${this.base}dem/terrarium/${id}.png`)
      .then(async (response) => {
        if (!response.ok) {
          this.missing.add(id);
          return;
        }
        const bitmap = await createImageBitmap(await response.blob());
        const canvas = document.createElement('canvas');
        canvas.width = bitmap.width;
        canvas.height = bitmap.height;
        const ctx = canvas.getContext('2d');
        if (!ctx) return;
        ctx.drawImage(bitmap, 0, 0);
        const pixels = ctx.getImageData(0, 0, bitmap.width, bitmap.height).data;
        const heights = new Float32Array(bitmap.width * bitmap.height);
        for (let i = 0; i < heights.length; i++) {
          const o = i * 4;
          heights[i] = (pixels[o] ?? 0) * 256 + (pixels[o + 1] ?? 0) + (pixels[o + 2] ?? 0) / 256 - 32768;
        }
        this.data.set(id, heights);
      })
      .catch(() => {
        this.missing.add(id);
      })
      .finally(() => {
        this.pending.delete(id);
      });
  }
}

function around(lon: number, lat: number, z: number, radius: number): { z: number; x: number; y: number }[] {
  const here = tileAt(lon, lat, z);
  const n = 2 ** z;
  const tiles: { z: number; x: number; y: number }[] = [];
  for (let dy = -radius; dy <= radius; dy++) {
    for (let dx = -radius; dx <= radius; dx++) {
      tiles.push({ z, x: (here.x + dx + n) % n, y: Math.max(0, Math.min(n - 1, here.y + dy)) });
    }
  }
  return tiles;
}

function tileAt(lon: number, lat: number, z: number): { z: number; x: number; y: number } {
  const n = 2 ** z;
  const x = Math.floor(((lon + 180) / 360) * n);
  const latR = (lat * Math.PI) / 180;
  const y = Math.floor(((1 - Math.log(Math.tan(latR) + 1 / Math.cos(latR)) / Math.PI) / 2) * n);
  return { z, x: Math.max(0, Math.min(n - 1, x)), y: Math.max(0, Math.min(n - 1, y)) };
}

function keyOf(tile: { z: number; x: number; y: number }): string {
  return `${tile.z}/${tile.x}/${tile.y}`;
}

function pixelOf(lon: number, lat: number, z: number, x: number, y: number): { fx: number; fy: number } {
  const n = 2 ** z;
  const latR = (lat * Math.PI) / 180;
  const gx = ((lon + 180) / 360) * n;
  const gy = ((1 - Math.log(Math.tan(latR) + 1 / Math.cos(latR)) / Math.PI) / 2) * n;
  return { fx: (gx - x) * 256, fy: (gy - y) * 256 };
}

function bilinear(heights: Float32Array, size: number, fx: number, fy: number): number {
  const x0 = Math.max(0, Math.min(size - 2, Math.floor(fx)));
  const y0 = Math.max(0, Math.min(size - 2, Math.floor(fy)));
  const tx = Math.max(0, Math.min(1, fx - x0));
  const ty = Math.max(0, Math.min(1, fy - y0));
  const i = y0 * size + x0;
  const h00 = heights[i] ?? 0;
  const h10 = heights[i + 1] ?? h00;
  const h01 = heights[i + size] ?? h00;
  const h11 = heights[i + size + 1] ?? h00;
  return (h00 * (1 - tx) + h10 * tx) * (1 - ty) + (h01 * (1 - tx) + h11 * tx) * ty;
}

function lonLatOf(z: number, x: number, y: number, px: number, py: number): { lon: number; lat: number } {
  const n = 2 ** z * 256;
  const gx = x * 256 + px;
  const gy = y * 256 + py;
  const lon = (gx / n) * 360 - 180;
  const merc = Math.PI * (1 - (2 * gy) / n);
  const lat = (Math.atan(Math.sinh(merc)) * 180) / Math.PI;
  return { lon, lat };
}

function inside(lon: number, lat: number, box: LonBox): boolean {
  return lon >= box.west && lon <= box.east && lat >= box.south && lat <= box.north;
}

function tileMesh(z: number, x: number, y: number, heights: Float32Array, holes: LonBox[]): Cesium.Primitive | null {
  const step = z >= 5 ? 4 : 8;
  const positions: number[] = [];
  const index: number[] = [];
  const stride = Math.floor(256 / step) + 1;
  for (let py = 0; py <= 256; py += step) {
    for (let px = 0; px <= 256; px += step) {
      const clampedX = Math.min(255, px);
      const clampedY = Math.min(255, py);
      const { lon, lat } = lonLatOf(z, x, y, clampedX, clampedY);
      const h = Math.max(0, heights[clampedY * 256 + clampedX] ?? 0);
      const cart = Cesium.Cartesian3.fromDegrees(lon, lat, h);
      positions.push(cart.x, cart.y, cart.z);
    }
  }
  for (let row = 0; row < stride - 1; row++) {
    for (let col = 0; col < stride - 1; col++) {
      const px = col * step + step / 2;
      const py = row * step + step / 2;
      const { lon, lat } = lonLatOf(z, x, y, px, py);
      if (holes.some((box) => inside(lon, lat, box))) continue;
      const i = row * stride + col;
      index.push(i, i + 1, i + stride, i + 1, i + stride + 1, i + stride);
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
    } as Cesium.GeometryAttributes,
    indices: index.length > 65535 ? new Uint32Array(index) : new Uint16Array(index),
    primitiveType: Cesium.PrimitiveType.TRIANGLES,
    boundingSphere: Cesium.BoundingSphere.fromVertices(positions),
  });
  Cesium.GeometryPipeline.computeNormal(geometry);
  return new Cesium.Primitive({
    geometryInstances: new Cesium.GeometryInstance({
      geometry,
      attributes: { color: Cesium.ColorGeometryInstanceAttribute.fromColor(Cesium.Color.fromCssColorString('#b7a88f').withAlpha(0.92)) },
    }),
    appearance: new Cesium.PerInstanceColorAppearance({ flat: false, translucent: false, closed: false }),
    asynchronous: true,
  });
}
