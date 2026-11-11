import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import type { Heightfield } from '../sim/grid';
import type { Sim } from '../sim/sim';
import type { WaterField } from '../sim/water';
import { buildMachine, syncWorks } from './meshes';

export interface OverlayState {
  slope: boolean;
  water: boolean;
  hydro: boolean;
}

interface TerrainMeta {
  elevation_m: { min: number; max: number };
}

export class Viewport {
  readonly renderer: THREE.WebGLRenderer;
  readonly scene = new THREE.Scene();
  readonly camera: THREE.PerspectiveCamera;
  readonly controls: OrbitControls;
  private terrain: THREE.Mesh;
  private water: THREE.Mesh;
  private readonly hydro = new THREE.Group();
  private readonly works = new THREE.Group();
  private readonly machines = new THREE.Group();
  private readonly preview = new THREE.Line(
    new THREE.BufferGeometry(),
    new THREE.LineBasicMaterial({ color: 0xf2f4f6 }),
  );
  private machineMeshes = new Map<string, THREE.Group>();
  private field: Heightfield | null = null;
  private overlay: OverlayState = { slope: true, water: true, hydro: true };
  private frozen = false;
  private meta: TerrainMeta = { elevation_m: { min: 0, max: 1 } };

  constructor(host: HTMLElement) {
    this.renderer = new THREE.WebGLRenderer({ antialias: true, alpha: false, powerPreference: 'high-performance', stencil: false });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.5));
    this.renderer.setSize(host.clientWidth, host.clientHeight);
    this.renderer.setClearColor(0xd5dee3, 1);
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    host.appendChild(this.renderer.domElement);

    this.camera = new THREE.PerspectiveCamera(42, host.clientWidth / Math.max(1, host.clientHeight), 1, 30000);
    this.controls = new OrbitControls(this.camera, this.renderer.domElement);
    this.controls.enableDamping = true;
    this.controls.dampingFactor = 0.08;
    this.controls.maxPolarAngle = Math.PI * 0.48;
    this.controls.minDistance = 12;
    this.controls.maxDistance = 9000;
    this.controls.mouseButtons = { LEFT: THREE.MOUSE.ROTATE, MIDDLE: THREE.MOUSE.DOLLY, RIGHT: THREE.MOUSE.PAN };

    this.scene.add(new THREE.HemisphereLight(0xd7e6ee, 0x6a6158, 0.95));
    this.scene.add(new THREE.AmbientLight(0xffffff, 0.38));
    const sun = new THREE.DirectionalLight(0xfff3e4, 1.45);
    const az = (315 * Math.PI) / 180;
    const alt = (28 * Math.PI) / 180;
    sun.position.set(Math.sin(az) * Math.cos(alt), Math.sin(alt), Math.cos(az) * Math.cos(alt));
    this.scene.add(sun);

    const geo = new THREE.BufferGeometry();
    this.terrain = new THREE.Mesh(geo, new THREE.MeshLambertMaterial({ vertexColors: true }));
    this.terrain.name = 'terrain';
    this.scene.add(this.terrain);

    this.water = new THREE.Mesh(new THREE.BufferGeometry(), waterMaterial());
    this.water.frustumCulled = false;
    this.scene.add(this.water);
    this.scene.add(this.hydro);
    this.scene.add(this.works);
    this.scene.add(this.machines);
    this.scene.add(this.preview);
  }

  /** Work tools take the left button and the first finger. Right-drag and two fingers still look around. */
  setGroundTool(active: boolean): void {
    this.controls.mouseButtons.LEFT = (active ? -1 : THREE.MOUSE.ROTATE) as THREE.MOUSE;
    this.controls.mouseButtons.RIGHT = active ? THREE.MOUSE.ROTATE : THREE.MOUSE.PAN;
    this.controls.touches.ONE = (active ? -1 : THREE.TOUCH.ROTATE) as THREE.TOUCH;
    this.controls.enabled = !this.walk;
    this.renderer.domElement.style.cursor = active ? 'crosshair' : '';
  }

  setDrawMode(drawing: boolean): void {
    this.setGroundTool(drawing);
  }

  private walk = false;

  resize(width: number, height: number): void {
    this.camera.aspect = width / Math.max(1, height);
    this.camera.updateProjectionMatrix();
    this.renderer.setSize(width, height);
  }

  frame(target: { x: number; y: number; z: number }, distance: number, azimuthDeg: number, altitudeDeg: number): void {
    this.leaveWalk();
    const az = (azimuthDeg * Math.PI) / 180;
    const alt = (altitudeDeg * Math.PI) / 180;
    const horiz = distance * Math.cos(alt);
    this.camera.position.set(target.x + Math.sin(az) * horiz, target.y + distance * Math.sin(alt), target.z - Math.cos(az) * horiz);
    this.controls.target.set(target.x, target.y, target.z);
    this.camera.near = 1;
    this.camera.far = 30000;
    this.camera.updateProjectionMatrix();
    this.controls.update();
  }

  enterWalk(x: number, z: number, yaw: number, pitch: number, eyeY: number): void {
    this.walk = true;
    this.controls.enabled = false;
    this.camera.near = 0.08;
    this.camera.far = 8000;
    this.camera.updateProjectionMatrix();
    this.setWalk(x, z, yaw, pitch, eyeY);
  }

  leaveWalk(): void {
    this.walk = false;
    this.controls.enabled = true;
  }

  setWalk(x: number, z: number, yaw: number, pitch: number, eyeY: number): void {
    this.camera.position.set(x, eyeY, z);
    this.camera.rotation.order = 'YXZ';
    this.camera.rotation.y = yaw + Math.PI;
    this.camera.rotation.x = pitch;
    this.camera.rotation.z = 0;
  }

  hit(clientX: number, clientY: number): { x: number; z: number } | null {
    const rect = this.renderer.domElement.getBoundingClientRect();
    const ndc = new THREE.Vector2(
      ((clientX - rect.left) / rect.width) * 2 - 1,
      -((clientY - rect.top) / rect.height) * 2 + 1,
    );
    const ray = new THREE.Raycaster();
    ray.setFromCamera(ndc, this.camera);
    const hits = ray.intersectObject(this.terrain, false);
    if (!hits.length) return null;
    return { x: hits[0].point.x, z: hits[0].point.z };
  }

  sync(sim: Sim, meta: TerrainMeta, overlay: OverlayState, parts: { terrain?: boolean } = {}): void {
    this.field = sim.field;
    this.meta = meta;
    this.overlay = overlay;
    this.frozen = !sim.inMelt();
    if (parts.terrain !== false) this.rebuildTerrain(sim.field, sim.water);
    this.rebuildWater(sim.field, sim.water);
    syncWorks(this.works, sim, sim.field);
    this.syncMachines(sim);
    this.water.visible = overlay.water;
    this.hydro.visible = overlay.hydro;
  }

  setPreview(points: { x: number; z: number }[], field: Heightfield | null): void {
    if (!field || points.length < 2) {
      this.preview.geometry.setFromPoints([]);
      return;
    }
    const pts = points.map((p) => new THREE.Vector3(p.x, field.sample(p.x, p.z) + 1.4, p.z));
    this.preview.geometry.setFromPoints(pts);
  }

  setHydro(geojson: GeoJSON.FeatureCollection, field: Heightfield): void {
    this.hydro.clear();
    const positions: number[] = [];
    const indices: number[] = [];
    const half = 3.2;
    const pushLine = (line: number[][]) => {
      const pts: { x: number; z: number; y: number }[] = [];
      const flush = () => {
        if (pts.length < 2) {
          pts.length = 0;
          return;
        }
        const base = positions.length / 3;
        for (let i = 0; i < pts.length; i++) {
          const prev = pts[Math.max(0, i - 1)];
          const next = pts[Math.min(pts.length - 1, i + 1)];
          let dx = next.x - prev.x;
          let dz = next.z - prev.z;
          const len = Math.hypot(dx, dz) || 1;
          dx /= len;
          dz /= len;
          const p = pts[i];
          positions.push(p.x - dz * half, p.y + 0.35, p.z + dx * half, p.x + dz * half, p.y + 0.35, p.z - dx * half);
          if (i > 0) {
            const a = base + (i - 1) * 2;
            indices.push(a, a + 1, a + 2, a + 1, a + 3, a + 2);
          }
        }
        pts.length = 0;
      };
      for (const p of line) {
        const x = p[0];
        const z = p[1];
        if (x < -10 || z < -10 || x > field.width + 10 || z > field.height + 10) {
          flush();
          continue;
        }
        const y = field.sample(x, z);
        if (!Number.isFinite(y)) {
          flush();
          continue;
        }
        const prev = pts[pts.length - 1];
        if (prev) {
          const d = Math.hypot(x - prev.x, z - prev.z);
          if (d < 1) continue;
          if (d > 180) flush();
        }
        pts.push({ x, z, y });
      }
      flush();
    };
    for (const feature of geojson.features) {
      if (String(feature.properties?.source ?? '').startsWith('derived')) continue;
      for (const line of linesOf(feature.geometry)) pushLine(line);
    }
    if (!positions.length) return;
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
    geo.setIndex(indices);
    geo.computeVertexNormals();
    this.hydro.add(new THREE.Mesh(geo, new THREE.MeshLambertMaterial({ color: 0x1a4a5c, side: THREE.DoubleSide })));
  }

  compass(): number {
    const origin = this.controls.target.clone();
    const north = origin.clone().add(new THREE.Vector3(0, 0, 180));
    const o = origin.project(this.camera);
    const n = north.project(this.camera);
    return Math.atan2(n.x - o.x, n.y - o.y);
  }

  metersPerPixel(): number {
    const dist = this.walk ? 14 : this.camera.position.distanceTo(this.controls.target);
    const vFov = (this.camera.fov * Math.PI) / 180;
    return (2 * Math.tan(vFov / 2) * dist) / Math.max(1, this.renderer.domElement.clientHeight);
  }

  render(): void {
    if (!this.walk) this.controls.update();
    this.renderer.render(this.scene, this.camera);
  }

  private syncMachines(sim: Sim): void {
    const live = new Set<string>();
    for (const body of sim.machineBodies) {
      live.add(body.specId);
      let mesh = this.machineMeshes.get(body.specId);
      if (!mesh) {
        mesh = buildMachine(sim.spec(body.specId));
        this.machineMeshes.set(body.specId, mesh);
        this.machines.add(mesh);
      }
      const y = sim.field.sample(body.x, body.z);
      mesh.position.set(body.x, Number.isFinite(y) ? y : 0, body.z);
      mesh.rotation.y = body.heading;
      mesh.visible = true;
    }
    for (const [id, mesh] of this.machineMeshes) mesh.visible = live.has(id);
  }

  private rebuildTerrain(field: Heightfield, water: WaterField): void {
    const { cols, rows, spacing, z } = field;
    const n = cols * rows;
    const geo = this.terrain.geometry;
    let positionAttr = geo.getAttribute('position') as THREE.BufferAttribute | null;
    if (!positionAttr || positionAttr.count !== n) {
      positionAttr = new THREE.BufferAttribute(new Float32Array(n * 3), 3);
      geo.setAttribute('position', positionAttr);
      geo.setAttribute('color', new THREE.BufferAttribute(new Float32Array(n * 3), 3));
      const index = new Uint32Array((rows - 1) * (cols - 1) * 6);
      let k = 0;
      for (let r = 0; r < rows - 1; r++) {
        for (let c = 0; c < cols - 1; c++) {
          const i = r * cols + c;
          index[k++] = i;
          index[k++] = i + 1;
          index[k++] = i + cols;
          index[k++] = i + 1;
          index[k++] = i + cols + 1;
          index[k++] = i + cols;
        }
      }
      geo.setIndex(new THREE.BufferAttribute(index, 1));
    }
    const positions = positionAttr.array as Float32Array;
    const colors = (geo.getAttribute('color') as THREE.BufferAttribute).array as Float32Array;
    const min = this.meta.elevation_m.min;
    const span = Math.max(1e-6, this.meta.elevation_m.max - min);
    for (let r = 0; r < rows; r++) {
      for (let c = 0; c < cols; c++) {
        const i = r * cols + c;
        positions[i * 3] = c * spacing;
        positions[i * 3 + 1] = z[i];
        positions[i * 3 + 2] = (rows - 1 - r) * spacing;
        const t = (z[i] - min) / span;
        let cr = mix(0.56, 0.8, t);
        let cg = mix(0.53, 0.81, t);
        let cb = mix(0.47, 0.82, t);
        if (this.overlay.slope) {
          const u = clamp(water.slope[i] / 30, 0, 1);
          const k = u * 0.75;
          cr = mix(cr, mix(0.78, 0.62, u), k);
          cg = mix(cg, mix(0.58, 0.32, u), k);
          cb = mix(cb, mix(0.34, 0.22, u), k);
        }
        if (field.edited[i]) {
          cr = mix(cr, 0.78, 0.42);
          cg = mix(cg, 0.64, 0.34);
          cb = mix(cb, 0.42, 0.28);
        }
        colors[i * 3] = srgb(cr);
        colors[i * 3 + 1] = srgb(cg);
        colors[i * 3 + 2] = srgb(cb);
      }
    }
    positionAttr.needsUpdate = true;
    (geo.getAttribute('color') as THREE.BufferAttribute).needsUpdate = true;
    geo.computeVertexNormals();
    geo.computeBoundingSphere();
  }

  private rebuildWater(field: Heightfield, water: WaterField): void {
    const { cols, rows } = field;
    const quads: number[] = [];
    for (let r = 0; r < rows - 1; r++) {
      for (let c = 0; c < cols - 1; c++) {
        const i = r * cols + c;
        const d = Math.max(
          water.depth[i],
          water.stream[i],
          water.depth[i + 1],
          water.stream[i + 1],
          water.depth[i + cols],
          water.stream[i + cols],
          water.depth[i + cols + 1],
          water.stream[i + cols + 1],
        );
        if (d > 0.03) quads.push(i);
      }
    }
    const positions = new Float32Array(quads.length * 4 * 3);
    const rgba = new Float32Array(quads.length * 4 * 4);
    const index = new Uint32Array(quads.length * 6);
    quads.forEach((cell, q) => {
      const corners = [cell, cell + 1, cell + field.cols, cell + field.cols + 1];
      corners.forEach((i, corner) => {
        const c = i % cols;
        const r = (i / cols) | 0;
        const depth = Math.max(water.depth[i], water.stream[i]);
        const o = (q * 4 + corner) * 3;
        positions[o] = c * field.spacing;
        positions[o + 1] = field.z[i] + depth + 0.07;
        positions[o + 2] = (rows - 1 - r) * field.spacing;
        const color = this.frozen ? [0.86, 0.91, 0.93] : mix3([0.45, 0.7, 0.76], [0.1, 0.28, 0.38], clamp(depth / 0.45, 0, 1));
        const a = this.frozen ? 0.62 : clamp(0.3 + depth * 0.85, 0.32, 0.8);
        const p = (q * 4 + corner) * 4;
        rgba[p] = srgb(color[0]);
        rgba[p + 1] = srgb(color[1]);
        rgba[p + 2] = srgb(color[2]);
        rgba[p + 3] = a;
      });
      const b = q * 4;
      const t = q * 6;
      index[t] = b;
      index[t + 1] = b + 1;
      index[t + 2] = b + 2;
      index[t + 3] = b + 1;
      index[t + 4] = b + 3;
      index[t + 5] = b + 2;
    });
    const geo = this.water.geometry;
    geo.setAttribute('position', new THREE.BufferAttribute(positions, 3));
    geo.setAttribute('rgba', new THREE.BufferAttribute(rgba, 4));
    geo.setIndex(new THREE.BufferAttribute(index, 1));
    geo.computeBoundingSphere();
  }
}

function waterMaterial(): THREE.ShaderMaterial {
  return new THREE.ShaderMaterial({
    transparent: true,
    depthWrite: false,
    uniforms: {},
    vertexShader: `
      attribute vec4 rgba;
      varying vec4 vRgba;
      void main() {
        vRgba = rgba;
        gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
      }
    `,
    fragmentShader: `
      varying vec4 vRgba;
      void main() {
        if (vRgba.a < 0.04) discard;
        gl_FragColor = vRgba;
      }
    `,
  });
}

function linesOf(geometry: GeoJSON.Geometry | null): number[][][] {
  if (!geometry) return [];
  if (geometry.type === 'LineString') return [geometry.coordinates as number[][]];
  if (geometry.type === 'MultiLineString') return geometry.coordinates as number[][][];
  if (geometry.type === 'Polygon') return geometry.coordinates as number[][][];
  if (geometry.type === 'MultiPolygon') return (geometry.coordinates as number[][][][]).flat();
  return [];
}

function srgb(c: number): number {
  return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
}
function mix(a: number, b: number, t: number): number {
  return a + (b - a) * t;
}
function mix3(a: number[], b: number[], t: number): number[] {
  return [mix(a[0], b[0], t), mix(a[1], b[1], t), mix(a[2], b[2], t)];
}
function clamp(v: number, lo: number, hi: number): number {
  return Math.max(lo, Math.min(hi, v));
}

declare namespace GeoJSON {
  interface Geometry {
    type: string;
    coordinates: unknown;
  }
  interface Feature {
    properties?: Record<string, unknown> | null;
    geometry: Geometry | null;
  }
  interface FeatureCollection {
    features: Feature[];
  }
}
