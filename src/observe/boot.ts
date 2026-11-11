import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { decodeGrayPng } from '../load/png';
import { RING_MARK } from '../world/tiles';

interface TerrainMeta {
  cols: number;
  rows: number;
  spacing_m: number;
  width_m: number;
  height_m: number;
  elevation_m: { min: number; max: number };
  georef: { cols: number; rows: number; lat: number[]; lon: number[] };
  cover_classes: Record<string, string>;
}

interface RecordPoint {
  species: string;
  scientificName: string;
  lat: number;
  lon: number;
}

const COVER_COLOR: Record<number, [number, number, number]> = {
  0: [0.45, 0.42, 0.38],
  1: [0.18, 0.28, 0.16],
  2: [0.24, 0.32, 0.2],
  5: [0.32, 0.38, 0.18],
  6: [0.22, 0.32, 0.18],
  8: [0.4, 0.38, 0.26],
  10: [0.46, 0.44, 0.28],
  14: [0.28, 0.34, 0.26],
  16: [0.55, 0.5, 0.42],
  17: [0.42, 0.4, 0.38],
  18: [0.22, 0.5, 0.66],
  19: [0.82, 0.85, 0.86],
};

export async function bootRing(root: HTMLElement, hooks?: { onWorld?: () => void }): Promise<Record<string, unknown>> {
  const bootEl = document.createElement('div');
  bootEl.className = 'boot';
  bootEl.textContent = 'Reading the ring';
  root.appendChild(bootEl);
  const base = import.meta.env.BASE_URL || './';
  const [meta, heightBuf, coverBuf, waterBuf, occurrences] = await Promise.all([
    fetch(`${base}data/ile/terrain.json`).then((r) => r.json()) as Promise<TerrainMeta>,
    fetch(`${base}data/ile/height.png`).then((r) => r.arrayBuffer()),
    fetch(`${base}data/ile/cover.png`).then((r) => r.arrayBuffer()),
    fetch(`${base}data/ile/water.png`).then((r) => r.arrayBuffer()),
    fetch(`${base}data/occurrences.json`).then((r) => r.json()).catch(() => ({ records: [] })),
  ]);
  const heightPng = await decodeGrayPng(heightBuf);
  const coverPng = await decodeGrayPng(coverBuf);
  const waterPng = await decodeGrayPng(waterBuf);
  const { cols, rows } = meta;
  const z = new Float32Array(cols * rows);
  const span = meta.elevation_m.max - meta.elevation_m.min;
  for (let i = 0; i < z.length; i++) z[i] = meta.elevation_m.min + (heightPng.samples[i] / 65535) * span;
  const cover = Uint8Array.from(coverPng.samples);
  const water = Uint8Array.from(waterPng.samples.map((v) => (v > 127 ? 1 : 0)));
  bootEl.remove();

  root.insertAdjacentHTML('beforeend', markup());
  const host = document.createElement('div');
  host.className = 'ring-view';
  root.prepend(host);
  const renderer = new THREE.WebGLRenderer({ antialias: true, stencil: false });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.5));
  renderer.setSize(root.clientWidth, root.clientHeight);
  renderer.setClearColor(0xd5dee3, 1);
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  host.appendChild(renderer.domElement);
  const camera = new THREE.PerspectiveCamera(42, root.clientWidth / Math.max(1, root.clientHeight), 2, 250_000);
  const controls = new OrbitControls(camera, renderer.domElement);
  controls.enableDamping = true;
  controls.maxPolarAngle = Math.PI * 0.48;
  controls.minDistance = 30;
  controls.maxDistance = 120_000;
  const scene = new THREE.Scene();
  scene.add(new THREE.HemisphereLight(0xd7e6ee, 0x6a6158, 0.95));
  scene.add(new THREE.AmbientLight(0xffffff, 0.38));
  const sun = new THREE.DirectionalLight(0xfff3e4, 1.45);
  sun.position.set(-0.4, 0.7, 0.35);
  scene.add(sun);

  const terrain = buildTerrain(meta, z, cover);
  scene.add(terrain);
  const waterMesh = buildWater(meta, z, water);
  scene.add(waterMesh);
  const species = buildSpecies(meta, z, (occurrences.records ?? []) as RecordPoint[]);
  scene.add(species);
  const crew = new THREE.Group();
  scene.add(crew);
  const crewPoints: { x: number; z: number }[] = [];

  const mark = localOf(meta, RING_MARK.lat, RING_MARK.lon);
  const peak = peakCell(z, cols, rows, meta.spacing_m);
  const look = () => frame(camera, controls, mark.x, sample(z, cols, rows, meta.spacing_m, mark.x, mark.z) + 40, mark.z, 128_000, 12, 74);
  look();

  const status = root.querySelector('#ring-status')!;
  const reading = root.querySelector('#ring-reading')!;
  let tool: 'orbit' | 'walk' | 'survey' | 'monitor' = 'orbit';
  let walking = false;
  let yaw = 0.4;
  let pitch = -0.12;
  let wx = peak.x;
  let wz = peak.z;
  const keys = new Set<string>();
  let alive = true;

  const paintTool = () => {
    root.querySelectorAll<HTMLButtonElement>('[data-tool]').forEach((button) => {
      button.classList.toggle('active', button.dataset.tool === tool);
    });
    root.querySelector('#crosshair')?.classList.toggle('on', tool === 'walk');
    root.querySelector('#walk-pad')?.toggleAttribute('hidden', tool !== 'walk');
    const ground = tool === 'survey' || tool === 'monitor';
    controls.mouseButtons.LEFT = (ground ? -1 : THREE.MOUSE.ROTATE) as THREE.MOUSE;
    controls.mouseButtons.RIGHT = ground ? THREE.MOUSE.ROTATE : THREE.MOUSE.PAN;
    controls.touches.ONE = (ground ? -1 : THREE.TOUCH.ROTATE) as THREE.TOUCH;
    controls.enabled = tool !== 'walk';
    renderer.domElement.style.cursor = ground ? 'crosshair' : '';
  };
  root.querySelectorAll<HTMLButtonElement>('[data-tool]').forEach((button) => {
    button.addEventListener('click', () => {
      tool = (button.dataset.tool as typeof tool) || 'orbit';
      if (tool === 'walk' && !stand(wx, wz, yaw)) tool = 'orbit';
      else if (tool !== 'walk') {
        walking = false;
        controls.enabled = true;
      }
      paintTool();
    });
  });
  root.querySelector('#open-world')?.addEventListener('click', () => hooks?.onWorld?.());
  root.querySelector('#ring-credits')?.addEventListener('click', () => root.querySelector<HTMLDialogElement>('#ring-about')?.showModal());
  root.querySelectorAll('[data-close]').forEach((button) => {
    button.addEventListener('click', () => button.closest('dialog')?.close());
  });
  root.querySelector('#show-water')?.addEventListener('change', (ev) => {
    waterMesh.visible = (ev.target as HTMLInputElement).checked;
  });
  root.querySelector('#show-forest')?.addEventListener('change', (ev) => {
    terrain.visible = true;
    const on = (ev.target as HTMLInputElement).checked;
    paintColors(terrain.geometry, meta, z, cover, on);
  });
  root.querySelector('#show-species')?.addEventListener('change', (ev) => {
    species.visible = (ev.target as HTMLInputElement).checked;
  });

  const canvas = renderer.domElement;
  canvas.addEventListener('pointerup', (ev) => {
    if (ev.button !== 0 || tool === 'orbit') return;
    const hit = rayHit(renderer, camera, terrain, ev.clientX, ev.clientY);
    if (!hit) return;
    const info = describe(meta, z, cover, water, hit.x, hit.z);
    reading.innerHTML = info.html;
    if (tool === 'walk') stand(hit.x, hit.z, yaw);
    if (tool === 'survey') status.textContent = `Survey. ${info.line} No ground is moved.`;
    if (tool === 'monitor') {
      if (info.wet) {
        status.textContent = 'The crew stays on land. The reservoir is open water.';
        return;
      }
      if (crewPoints.length < 8) {
        crewPoints.push(hit);
        const mark = new THREE.Mesh(
          new THREE.ConeGeometry(18, 46, 5),
          new THREE.MeshLambertMaterial({ color: 0xd7dbe0 }),
        );
        mark.position.set(hit.x, sample(z, cols, rows, meta.spacing_m, hit.x, hit.z) + 23, hit.z);
        crew.add(mark);
      }
      status.textContent = 'Monitoring crew. Simulated, and it does not cut or fill.';
    }
  });
  root.querySelectorAll<HTMLButtonElement>('[data-move]').forEach((button) => {
    const key = button.dataset.move || '';
    const down = (ev: Event) => {
      ev.preventDefault();
      keys.add(key);
    };
    const up = () => keys.delete(key);
    button.addEventListener('pointerdown', down);
    button.addEventListener('pointerup', up);
    button.addEventListener('pointerleave', up);
    button.addEventListener('pointercancel', up);
  });
  const onKeyDown = (ev: KeyboardEvent) => keys.add(ev.key);
  const onKeyUp = (ev: KeyboardEvent) => keys.delete(ev.key);
  window.addEventListener('keydown', onKeyDown);
  window.addEventListener('keyup', onKeyUp);
  const onResize = () => {
    camera.aspect = root.clientWidth / Math.max(1, root.clientHeight);
    camera.updateProjectionMatrix();
    renderer.setSize(root.clientWidth, root.clientHeight);
  };
  window.addEventListener('resize', onResize);

  let last = performance.now();
  const loop = (now: number) => {
    if (!alive) return;
    const dt = Math.min(0.05, (now - last) / 1000);
    last = now;
    if (walking) step(dt);
    else controls.update();
    renderer.render(scene, camera);
    requestAnimationFrame(loop);
  };
  requestAnimationFrame(loop);
  paintTool();
  status.textContent = 'Measured terrain. Forest, water, and species are observation layers.';

  function stand(x: number, zed: number, face: number): boolean {
    if (wetAt(water, cols, rows, meta.spacing_m, x, zed)) {
      status.textContent = 'Open water. Step onto the island or the shore.';
      return false;
    }
    wx = x;
    wz = zed;
    yaw = face;
    walking = true;
    controls.enabled = false;
    const eye = sample(z, cols, rows, meta.spacing_m, x, zed) + 1.7;
    camera.position.set(x, eye, zed);
    camera.rotation.order = 'YXZ';
    camera.rotation.y = face + Math.PI;
    camera.rotation.x = pitch;
    camera.near = 0.4;
    camera.far = 80_000;
    camera.updateProjectionMatrix();
    paintTool();
    return true;
  }

  function step(dt: number) {
    const speed = (keys.has('Shift') ? 80 : 28) * dt;
    let mx = 0;
    let mz = 0;
    const fx = Math.sin(yaw);
    const fz = Math.cos(yaw);
    if (keys.has('w') || keys.has('W') || keys.has('ArrowUp')) {
      mx += fx;
      mz += fz;
    }
    if (keys.has('s') || keys.has('S') || keys.has('ArrowDown')) {
      mx -= fx;
      mz -= fz;
    }
    if (keys.has('d') || keys.has('D') || keys.has('ArrowRight')) {
      mx += fz;
      mz -= fx;
    }
    if (keys.has('a') || keys.has('A') || keys.has('ArrowLeft')) {
      mx -= fz;
      mz += fx;
    }
    const mag = Math.hypot(mx, mz) || 1;
    const nx = wx + (mx / mag) * speed;
    const nz = wz + (mz / mag) * speed;
    if (!wetAt(water, cols, rows, meta.spacing_m, nx, nz)) {
      wx = nx;
      wz = nz;
    }
    const eye = sample(z, cols, rows, meta.spacing_m, wx, wz) + 1.7;
    camera.position.set(wx, eye, wz);
    camera.rotation.order = 'YXZ';
    camera.rotation.y = yaw + Math.PI;
    camera.rotation.x = pitch;
  }

  return {
    ready: true,
    stop: () => {
      alive = false;
      window.removeEventListener('resize', onResize);
      window.removeEventListener('keydown', onKeyDown);
      window.removeEventListener('keyup', onKeyUp);
      renderer.dispose();
    },
    settle: () => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(() => resolve(true)))),
    home: () => look(),
    enterWalk: (x: number, zed: number, face = 0.4, look = -0.12) => {
      pitch = look;
      stand(x, zed, face);
    },
    pose: () => ({
      x: wx,
      z: wz,
      yaw,
      pitch,
      eye: sample(z, cols, rows, meta.spacing_m, wx, wz) + 1.7,
      surface: sample(z, cols, rows, meta.spacing_m, wx, wz),
    }),
    peak: () => peak,
  };
}

function markup(): string {
  return `
    <header class="top">
      <div class="brand">
        <svg class="mark" viewBox="0 0 32 32" aria-hidden="true"><circle cx="16" cy="16" r="10.5" fill="none" stroke="#d7dbe0" stroke-width="1.25"/></svg>
        <div><div class="word">ROLEPLAY</div><div class="sub">Creation division</div></div>
      </div>
      <div class="place"><strong>Île René-Levasseur</strong><div class="muted">Manicouagan ring · measured research terrain</div></div>
      <button id="open-world" class="text-btn" type="button" style="width:auto">World map</button>
      <button id="ring-credits" class="text-btn" type="button" style="width:auto">Credits</button>
    </header>
    <div class="coach">
      <p>This square is measured research terrain. Survey reads a point. The monitoring crew does not cut or fill.</p>
      <p id="coach-how">Drag to orbit. On a phone, two fingers look around and a tap surveys.</p>
    </div>
    <div id="walk-pad" class="walk-pad" hidden>
      <button type="button" data-move="w" aria-label="Walk forward">▲</button>
      <button type="button" data-move="a" aria-label="Walk left">◀</button>
      <button type="button" data-move="s" aria-label="Walk back">▼</button>
      <button type="button" data-move="d" aria-label="Walk right">▶</button>
    </div>
    <aside class="rail">
      <div class="group">View</div>
      <button class="tool active" data-tool="orbit" type="button">Orbit</button>
      <button class="tool" data-tool="walk" type="button">Walk the land</button>
      <div class="group">Observe</div>
      <button class="tool" data-tool="survey" type="button">Survey</button>
      <button class="tool" data-tool="monitor" type="button">Monitoring crew</button>
      <div class="group">Layers</div>
      <label class="row"><span>Forest</span><input id="show-forest" type="checkbox" checked /></label>
      <label class="row"><span>Water</span><input id="show-water" type="checkbox" checked /></label>
      <label class="row"><span>Species</span><input id="show-species" type="checkbox" checked /></label>
    </aside>
    <aside class="inspector">
      <div class="kicker">This square</div>
      <p class="status" id="ring-status"></p>
      <p class="peers">The ring is an emblem of the O. It is not land to reshape. Mass movers stay off this tile.</p>
      <div class="kicker">Reading</div>
      <div id="ring-reading"></div>
    </aside>
    <div class="crosshair" id="crosshair"></div>
    <dialog id="ring-about">
      <button class="close" data-close type="button">Close</button>
      <h2>Île René-Levasseur</h2>
      <p>Measured research terrain inside the Manicouagan ring reservoir, Quebec. The ring reads as an O. Nothing here is offered as land to cut or fill.</p>
      <h3>Place</h3>
      <p>This island is in the Nitassinan of the Innu of Pessamit. Louis-Babel Ecological Reserve. Réserve de biodiversité de la Météorite. Manicouagan-Uapishka UNESCO Biosphere Reserve.</p>
      <p>The reservoir is the water held by Hydro-Québec's Daniel-Johnson Dam. Mont de Babel, the central peak, is about 952 m. On this grid the high ground near the island centre reaches about 951 m.</p>
      <h3>Elevation</h3>
      <p>Playable surface: NRCan HRDEM mosaic, 1 m DTM, resampled to 120 m posts. Open Government Licence – Canada. ArcticDEM does not cover 51°N. NRCan MRDEM-30 (Open Government Licence – Canada; Copernicus GLO-30 is an input) was sampled on the same window and agrees, about 347–1,009 m. Quebec's 1 m LiDAR MNT (CC BY 4.0, Ministère des Ressources naturelles et des Forêts) is published as separate 1:20 000 sheets of about 750 MB each and was not downloaded; the HRDEM mosaic is the lidar-derived national surface over this island.</p>
      <h3>Water, forest, species</h3>
      <p>Water and forest are NRCan 2020 Land Cover of Canada, Open Government Licence – Canada. The reservoir is the water class, and that same mask is drawn on the globe. The white circle sits on that water, about 30 km from the reservoir centre, so the O reads. It is not a surveyed shoreline. GRHQ (CC BY 4.0) and NHN (Open Government Licence – Canada) vectors were not clipped into this build. Species are GBIF occurrences in the ring box. <a href="https://www.gbif.org">GBIF.org</a>. Each record keeps its source dataset licence.</p>
    </dialog>
  `;
}

function buildTerrain(meta: TerrainMeta, z: Float32Array, cover: Uint8Array): THREE.Mesh {
  const { cols, rows, spacing_m: spacing } = meta;
  const geo = new THREE.BufferGeometry();
  const positions = new Float32Array(cols * rows * 3);
  const colors = new Float32Array(cols * rows * 3);
  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < cols; c++) {
      const i = r * cols + c;
      positions[i * 3] = c * spacing;
      positions[i * 3 + 1] = z[i];
      positions[i * 3 + 2] = (rows - 1 - r) * spacing;
    }
  }
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
  geo.setAttribute('position', new THREE.BufferAttribute(positions, 3));
  geo.setAttribute('color', new THREE.BufferAttribute(colors, 3));
  geo.setIndex(new THREE.BufferAttribute(index, 1));
  paintColors(geo, meta, z, cover, true);
  geo.computeVertexNormals();
  return new THREE.Mesh(geo, new THREE.MeshLambertMaterial({ vertexColors: true }));
}

function paintColors(geo: THREE.BufferGeometry, meta: TerrainMeta, z: Float32Array, cover: Uint8Array, forest: boolean): void {
  const colors = geo.getAttribute('color') as THREE.BufferAttribute;
  const span = Math.max(1, meta.elevation_m.max - meta.elevation_m.min);
  for (let i = 0; i < z.length; i++) {
    const code = cover[i] ?? 0;
    const base = forest ? COVER_COLOR[code] ?? COVER_COLOR[0] : [0.55, 0.52, 0.46];
    const lift = (z[i] - meta.elevation_m.min) / span;
    colors.setXYZ(i, srgb(base[0] + lift * 0.12), srgb(base[1] + lift * 0.1), srgb(base[2] + lift * 0.08));
  }
  colors.needsUpdate = true;
}

function buildWater(meta: TerrainMeta, z: Float32Array, water: Uint8Array): THREE.Mesh {
  const { cols, rows, spacing_m: spacing } = meta;
  const positions: number[] = [];
  const index: number[] = [];
  for (let r = 0; r < rows - 2; r += 2) {
    for (let c = 0; c < cols - 2; c += 2) {
      const i = r * cols + c;
      const corners = [i, i + 2, i + cols * 2, i + cols * 2 + 2];
      if (!corners.some((corner) => water[corner])) continue;
      const base = positions.length / 3;
      for (const corner of corners) {
        const cc = corner % cols;
        const rr = (corner / cols) | 0;
        positions.push(cc * spacing, z[corner] + 1.2, (rows - 1 - rr) * spacing);
      }
      index.push(base, base + 1, base + 2, base + 1, base + 3, base + 2);
    }
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
  geo.setIndex(index);
  return new THREE.Mesh(
    geo,
    new THREE.MeshLambertMaterial({ color: 0x3a96c4, transparent: true, opacity: 0.9, depthWrite: false }),
  );
}

function buildSpecies(meta: TerrainMeta, z: Float32Array, records: RecordPoint[]): THREE.Points {
  const { width_m: width, height_m: height, spacing_m: spacing, cols, rows } = meta;
  const west = meta.georef.lon[0];
  const east = meta.georef.lon[meta.georef.cols - 1];
  const north = meta.georef.lat[0];
  const south = meta.georef.lat[meta.georef.lat.length - 1];
  const positions: number[] = [];
  for (const record of records) {
    if (record.lon < west || record.lon > east || record.lat < south || record.lat > north) continue;
    const x = ((record.lon - west) / (east - west)) * width;
    const zz = ((record.lat - south) / (north - south)) * height;
    const y = sample(z, cols, rows, spacing, x, zz);
    positions.push(x, y + 180, zz);
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
  return new THREE.Points(
    geo,
    new THREE.PointsMaterial({ color: 0xe7d7b1, size: 1400, sizeAttenuation: true }),
  );
}

function describe(meta: TerrainMeta, z: Float32Array, cover: Uint8Array, water: Uint8Array, x: number, zz: number): { html: string; line: string; wet: boolean } {
  const { cols, rows, spacing_m: spacing } = meta;
  const c = clamp(Math.round(x / spacing), 0, cols - 1);
  const r = clamp(Math.round(rows - 1 - zz / spacing), 0, rows - 1);
  const i = r * cols + c;
  const code = cover[i] ?? 0;
  const name = meta.cover_classes[String(code)] ?? 'unclassified';
  const wet = water[i] === 1;
  const elev = z[i];
  const line = `${elev.toFixed(0)} m, ${name}`;
  return {
    wet,
    line,
    html: `<div class="row"><span>Elevation</span><span>${elev.toFixed(1)} m <i class="tag">MEASURED</i></span></div>
      <div class="row"><span>Cover</span><span>${name} <i class="tag">MEASURED</i></span></div>
      <div class="row"><span>Water</span><span>${wet ? 'open water' : 'land'}</span></div>`,
  };
}

function peakCell(z: Float32Array, cols: number, rows: number, spacing: number): { x: number; z: number; y: number } {
  let best = 0;
  for (let i = 1; i < z.length; i++) if (z[i] > z[best]) best = i;
  const c = best % cols;
  const r = (best / cols) | 0;
  return { x: c * spacing, z: (rows - 1 - r) * spacing, y: z[best] };
}

function sample(z: Float32Array, cols: number, rows: number, spacing: number, x: number, zz: number): number {
  const c = clamp(Math.round(x / spacing), 0, cols - 1);
  const r = clamp(Math.round(rows - 1 - zz / spacing), 0, rows - 1);
  return z[r * cols + c] ?? 0;
}

function wetAt(water: Uint8Array, cols: number, rows: number, spacing: number, x: number, zz: number): boolean {
  const c = clamp(Math.round(x / spacing), 0, cols - 1);
  const r = clamp(Math.round(rows - 1 - zz / spacing), 0, rows - 1);
  return water[r * cols + c] === 1;
}

function rayHit(renderer: THREE.WebGLRenderer, camera: THREE.Camera, terrain: THREE.Object3D, clientX: number, clientY: number): { x: number; z: number } | null {
  const rect = renderer.domElement.getBoundingClientRect();
  const ndc = new THREE.Vector2(((clientX - rect.left) / rect.width) * 2 - 1, -((clientY - rect.top) / rect.height) * 2 + 1);
  const ray = new THREE.Raycaster();
  ray.setFromCamera(ndc, camera);
  const hits = ray.intersectObject(terrain, false);
  if (!hits.length) return null;
  return { x: hits[0].point.x, z: hits[0].point.z };
}

function localOf(meta: TerrainMeta, lat: number, lon: number): { x: number; z: number } {
  const west = meta.georef.lon[0];
  const east = meta.georef.lon[meta.georef.cols - 1];
  const north = meta.georef.lat[0];
  const south = meta.georef.lat[meta.georef.lat.length - 1];
  return {
    x: ((lon - west) / (east - west)) * meta.width_m,
    z: ((lat - south) / (north - south)) * meta.height_m,
  };
}

function frame(camera: THREE.PerspectiveCamera, controls: OrbitControls, x: number, y: number, z: number, distance: number, azimuthDeg: number, altitudeDeg: number): void {
  const az = (azimuthDeg * Math.PI) / 180;
  const alt = (altitudeDeg * Math.PI) / 180;
  const horiz = distance * Math.cos(alt);
  camera.position.set(x + Math.sin(az) * horiz, y + distance * Math.sin(alt), z - Math.cos(az) * horiz);
  controls.target.set(x, y, z);
  camera.near = 20;
  camera.far = 250_000;
  camera.updateProjectionMatrix();
  controls.update();
}

function srgb(c: number): number {
  const v = Math.max(0, Math.min(1, c));
  return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
}

function clamp(v: number, lo: number, hi: number): number {
  return Math.max(lo, Math.min(hi, v));
}
