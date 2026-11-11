import * as Cesium from 'cesium';
import { Relief } from './dem';
import { Field } from './field';
import { Drape, projector, type GeoBounds } from './ground';
import { decodeGrayPng } from '../load/png';
import { Yard, type Rig } from './ride';
import { Director, TITAN, type ViewId } from './views';

interface SiteMeta {
  id: string;
  name: string;
  crs: string;
  origin_xy: [number, number];
  spacing_m: number;
  cols: number;
  rows: number;
  elevation_m: { min: number; max: number };
  image: string;
  image_bounds: GeoBounds;
  repose_deg: number;
  density_kg_m3: number;
  noon: string;
}

interface Site {
  id: string;
  name: string;
  field: Field;
  yard: Yard;
  rig: Rig;
  drape: Drape;
  originX: number;
  originY: number;
  project: (east: number, north: number) => { lon: number; lat: number };
  inverse: (lon: number, lat: number) => { east: number; north: number };
  noon: string;
  model: Cesium.Model;
  bounds: GeoBounds;
}

const SAVE_KEY = 'roleplay-ground-v2';

export async function startWorld(root: HTMLElement): Promise<void> {
  root.replaceChildren();
  root.insertAdjacentHTML('beforeend', markup());
  const host = document.createElement('div');
  host.id = 'cesium';
  root.prepend(host);
  const credit = document.createElement('div');
  credit.id = 'cesium-credit';
  root.append(credit);
  const base = import.meta.env.BASE_URL || './';
  (window as unknown as { CESIUM_BASE_URL?: string }).CESIUM_BASE_URL = new URL('cesium/', new URL(base, window.location.href)).href;
  if (new URLSearchParams(location.search).get('capture') === '1') document.documentElement.classList.add('capture');

  const viewer = new Cesium.Viewer(host, {
    animation: false,
    timeline: false,
    geocoder: false,
    homeButton: false,
    sceneModePicker: false,
    baseLayerPicker: false,
    navigationHelpButton: false,
    fullscreenButton: false,
    infoBox: false,
    selectionIndicator: false,
    baseLayer: Cesium.ImageryLayer.fromProviderAsync(
      Cesium.TileMapServiceImageryProvider.fromUrl(Cesium.buildModuleUrl('Assets/Textures/NaturalEarthII')),
    ),
    terrainProvider: new Cesium.EllipsoidTerrainProvider(),
    creditContainer: credit,
  });
  viewer.clock.shouldAnimate = false;
  viewer.scene.globe.enableLighting = true;
  viewer.scene.fog.enabled = true;
  viewer.scene.fog.density = 0.00008;
  viewer.scene.fog.minimumBrightness = 0.03;
  viewer.scene.globe.showGroundAtmosphere = true;
  viewer.scene.globe.depthTestAgainstTerrain = true;
  viewer.shadows = true;
  viewer.shadowMap.darkness = 0.28;
  viewer.scene.light.intensity = 2.4;
  viewer.terrainShadows = Cesium.ShadowMode.RECEIVE_ONLY;
  viewer.resolutionScale = 1;
  viewer.cesiumWidget.screenSpaceEventHandler.removeInputAction(Cesium.ScreenSpaceEventType.LEFT_DOUBLE_CLICK);
  const imagery = viewer.imageryLayers.addImageryProvider(new Cesium.UrlTemplateImageryProvider({
    url: 'https://tiles.maps.eox.at/wmts/1.0.0/s2cloudless-2021_3857/default/g/{z}/{y}/{x}.jpg',
    tilingScheme: new Cesium.WebMercatorTilingScheme(),
    maximumLevel: 12,
    credit: 'Sentinel-2 cloudless by EOX (CC BY 4.0), modified Copernicus Sentinel data 2021',
  }));
  imagery.brightness = 1.05;
  imagery.contrast = 1.08;

  const relief = new Relief(base, viewer);
  const groundAt = (lon: number, lat: number): number => {
    for (const site of sites) {
      const local = site.inverse(lon, lat);
      const width = (site.field.cols - 1) * site.field.spacing;
      const height = (site.field.rows - 1) * site.field.spacing;
      if (local.east >= 0 && local.north >= 0 && local.east <= width && local.north <= height) return site.field.sample(local.east, local.north);
    }
    return relief.sample(lon, lat) ?? 0;
  };

  const basin = await loadSite(viewer, base, 'data/terrain.json', relief);
  const ring = await loadSite(viewer, base, 'data/ile/terrain.json', relief);
  const sites = [basin, ring];
  let focus = basin;
  relief.prefetch(basin.project(2000, 2000).lon, basin.project(2000, 2000).lat);
  relief.prefetch(ring.project(2000, 2000).lon, ring.project(2000, 2000).lat);

  const home = focus.project(focus.rig ? focus.yard.pose(focus.rig).east : 2000, focus.rig ? focus.yard.pose(focus.rig).north : 2000);
  const director = new Director(viewer, { lon: home.lon, lat: home.lat, heading: 0, pitch: -0.18 });
  director.jump('robot');
  focusNoon(viewer, focus);
  focus.drape.follow(focus.yard.pose(focus.rig).east, focus.yard.pose(focus.rig).north);
  focus.drape.flush();

  const feet = { east: focus.yard.pose(focus.rig).east, north: focus.yard.pose(focus.rig).north, vy: 0 };
  const keys = new Set<string>();
  let throttle = 0;
  let steer = 0;
  const drive = { throttle: 0, steer: 0, brake: false, raise: false, lower: false, dig: false, dump: false };
  const panel = root.querySelector<HTMLElement>('#panel')!;
  const menu = root.querySelector<HTMLButtonElement>('#menu')!;
  let qualityDropped = false;
  const frameMs: number[] = [];
  let last = performance.now();
  let saveAt = 0;

  const placeBody = (site: Site, east: number, north: number) => {
    feet.east = east;
    feet.north = north;
    feet.vy = 0;
    const ll = site.project(east, north);
    director.anchor.lon = ll.lon;
    director.anchor.lat = ll.lat;
  };

  const showRobot = () => {
    const pose = focus.yard.pose(focus.rig);
    const ll = focus.project(pose.east, pose.north);
    director.anchor.lon = ll.lon;
    director.anchor.lat = ll.lat;
    director.anchor.heading = pose.heading;
  };

  menu.addEventListener('click', () => {
    panel.hidden = !panel.hidden;
    paintPanel();
  });
  panel.addEventListener('click', (ev) => {
    const button = (ev.target as HTMLElement).closest('button');
    if (!button) return;
    const view = button.dataset.view as ViewId | undefined;
    const siteId = button.dataset.site;
    if (view) {
      if (view === 'robot') showRobot();
      else if (director.view === 'robot') {
        const pose = focus.yard.pose(focus.rig);
        placeBody(focus, pose.east + 7, pose.north + 14);
        director.anchor.heading = pose.heading;
        director.anchor.pitch = view === 'titan' ? -0.42 : -0.2;
      }
      director.setView(view, 0.4);
      director.eyeLift = 0;
    }
    if (siteId && siteId !== focus.id) {
      const next = sites.find((site) => site.id === siteId);
      if (next) {
        focus = next;
        const midE = ((next.field.cols - 1) * next.field.spacing) / 2;
        const midN = ((next.field.rows - 1) * next.field.spacing) / 2;
        next.yard.recover(next.rig, midE, midN);
        placeBody(next, midE, midN);
        showRobot();
        director.setView(director.view, 1);
        focusNoon(viewer, next);
        next.drape.follow(midE, midN);
      }
    }
    paintPanel();
  });

  window.addEventListener('keydown', (ev) => {
    if (ev.key === 'Escape') {
      panel.hidden = true;
      return;
    }
    keys.add(ev.key.toLowerCase());
  });
  window.addEventListener('keyup', (ev) => keys.delete(ev.key.toLowerCase()));
  const canvas = viewer.scene.canvas;
  canvas.addEventListener('pointerdown', (ev) => {
    if (ev.button !== 0) return;
    if (director.view !== 'robot') canvas.requestPointerLock?.();
  });
  window.addEventListener('pointermove', (ev) => {
    if (director.view === 'robot') {
      if (ev.buttons !== 1) return;
    } else if (document.pointerLockElement !== canvas) return;
    director.mouse(ev.movementX || 0, ev.movementY || 0, director.view);
  });

  const loop = () => {
    const now = performance.now();
    const dt = Math.min(0.05, (now - last) / 1000);
    last = now;
    const pad = navigator.getGamepads?.()[0];
    const stickX = pad && Math.abs(pad.axes[0] || 0) > 0.14 ? pad.axes[0] || 0 : 0;
    const stickY = pad && Math.abs(pad.axes[1] || 0) > 0.14 ? pad.axes[1] || 0 : 0;
    const lookX = pad && Math.abs(pad.axes[2] || 0) > 0.14 ? pad.axes[2] || 0 : 0;
    const lookY = pad && Math.abs(pad.axes[3] || 0) > 0.14 ? pad.axes[3] || 0 : 0;
    const trigger = (index: number) => (pad?.buttons[index]?.value ?? 0) > 0.15 || Boolean(pad?.buttons[index]?.pressed);
    if (lookX || lookY) director.mouse(lookX * 18, lookY * 14, director.view);

    if (director.view === 'robot') {
      const forward = (keys.has('w') || keys.has('arrowup') ? 1 : 0) + (trigger(7) ? pad?.buttons[7]?.value || 1 : 0);
      const back = (keys.has('s') || keys.has('arrowdown') ? 1 : 0) + (trigger(6) ? pad?.buttons[6]?.value || 1 : 0);
      const targetThrottle = Math.max(-1, Math.min(1, forward - back));
      const targetSteer = Math.max(-1, Math.min(1, (keys.has('d') || keys.has('arrowright') ? 1 : 0) - (keys.has('a') || keys.has('arrowleft') ? 1 : 0) + stickX));
      throttle += (targetThrottle - throttle) * (1 - Math.exp(-dt / 0.28));
      steer += (targetSteer - steer) * (1 - Math.exp(-dt / 0.18));
      drive.throttle = Math.abs(throttle) < 0.04 ? 0 : throttle;
      drive.steer = Math.abs(steer) < 0.04 ? 0 : steer;
      drive.raise = keys.has('q') || trigger(4);
      drive.lower = keys.has('e') || trigger(5);
      drive.brake = false;
      focus.yard.step(dt, focus.rig, drive);
      showRobot();
      const pose = focus.yard.pose(focus.rig);
      focus.drape.follow(pose.east, pose.north);
      if (focus.field.dirty) paintCuts(focus);
    } else {
      const run = keys.has('shift') || trigger(7);
      const giant = director.view === 'titan';
      const pace = giant ? (run ? 1.05 : 0.5) * TITAN : run ? 4.4 : 1.45;
      let ahead = (keys.has('w') || keys.has('arrowup') ? 1 : 0) - (keys.has('s') || keys.has('arrowdown') ? 1 : 0) - stickY;
      let side = (keys.has('d') || keys.has('arrowright') ? 1 : 0) - (keys.has('a') || keys.has('arrowleft') ? 1 : 0) + stickX;
      const mag = Math.hypot(ahead, side);
      if (mag > 1) {
        ahead /= mag;
        side /= mag;
      }
      const heading = director.anchor.heading;
      feet.east += (Math.sin(heading) * ahead + Math.cos(heading) * side) * pace * dt;
      feet.north += (Math.cos(heading) * ahead - Math.sin(heading) * side) * pace * dt;
      const width = (focus.field.cols - 1) * focus.field.spacing;
      const height = (focus.field.rows - 1) * focus.field.spacing;
      feet.east = Math.max(4, Math.min(width - 4, feet.east));
      feet.north = Math.max(4, Math.min(height - 4, feet.north));
      const ground = focus.field.sample(feet.east, feet.north);
      const jumping = keys.has(' ') || Boolean(pad?.buttons[0]?.pressed);
      if (jumping && director.eyeLift <= 0.05 && feet.vy <= 0) feet.vy = giant ? 9 : 4.2;
      feet.vy -= (giant ? 14 : 12) * dt;
      director.eyeLift += feet.vy * dt;
      if (director.eyeLift <= 0) {
        director.eyeLift = 0;
        feet.vy = 0;
      }
      placeBody(focus, feet.east, feet.north);
      void ground;
      focus.drape.follow(feet.east, feet.north);
    }
    focus.drape.flush();
    // The global DEM is only a height sample for the tile edge. Its mesh is triangles
    // many kilometres wide and would paint over the measured ground.
    const vehicle = director.view === 'robot' ? robotPose(focus) : null;
    director.step(dt, groundAt, vehicle);
    poseModel(focus);
    frameMs.push(dt * 1000);
    if (frameMs.length > 40) frameMs.shift();
    if (!qualityDropped && frameMs.length > 30) {
      const avg = frameMs.reduce((sum, value) => sum + value, 0) / frameMs.length;
      if (avg > 34) {
        viewer.resolutionScale = 0.7;
        qualityDropped = true;
      }
    }
    if (focus.field.dirty === false && now - saveAt > 4000) {
      saveAt = now;
      writeSave(sites);
    }
    requestAnimationFrame(loop);
  };
  requestAnimationFrame(loop);

  (window as unknown as { __roleplay?: unknown }).__roleplay = {
    ready: true,
    view: () => director.view,
    site: () => focus.id,
    volumes: () => ({ cut: focus.field.cutM3, fill: focus.field.fillM3 }),
    pose: () => {
      const pose = focus.yard.pose(focus.rig);
      const ll = focus.project(pose.east, pose.north);
      return { ...pose, ...ll, blade: focus.rig.bladeAngle };
    },
    camera: () => {
      const carto = viewer.camera.positionCartographic;
      return {
        height: carto.height,
        pitch: viewer.camera.pitch,
        lon: Cesium.Math.toDegrees(carto.longitude),
        lat: Cesium.Math.toDegrees(carto.latitude),
        ground: groundAt(Cesium.Math.toDegrees(carto.longitude), Cesium.Math.toDegrees(carto.latitude)),
      };
    },
    ground: groundAt,
    snap: () => director.jump(director.view),
  };

  function paintPanel() {
    panel.querySelectorAll<HTMLButtonElement>('[data-view]').forEach((button) => {
      button.classList.toggle('on', button.dataset.view === director.view);
    });
    panel.querySelectorAll<HTMLButtonElement>('[data-site]').forEach((button) => {
      button.classList.toggle('on', button.dataset.site === focus.id);
    });
  }
  paintPanel();
}

function robotPose(site: Site): { lon: number; lat: number; up: number; heading: number; speed: number } {
  const pose = site.yard.pose(site.rig);
  const ll = site.project(pose.east, pose.north);
  return { lon: ll.lon, lat: ll.lat, up: pose.up, heading: pose.heading, speed: pose.speed };
}

function poseModel(site: Site): void {
  const pose = site.yard.pose(site.rig);
  const ground = site.field.sample(pose.east, pose.north);
  const ll = site.project(pose.east, pose.north);
  const position = Cesium.Cartesian3.fromDegrees(ll.lon, ll.lat, Math.max(ground + 0.05, Math.min(ground + 2.4, pose.up - 0.85)));
  const rotation = Cesium.Transforms.headingPitchRollQuaternion(position, new Cesium.HeadingPitchRoll(pose.heading - Math.PI / 2, 0, 0));
  site.model.modelMatrix = Cesium.Matrix4.fromTranslationQuaternionRotationScale(position, rotation, new Cesium.Cartesian3(2.6, 2.6, 2.6));
  if (site.model.ready) {
    const shovel = site.model.getNode('shovel');
    if (shovel) {
      const tilt = Cesium.Matrix4.fromRotationTranslation(Cesium.Matrix3.fromRotationX(-site.rig.bladeAngle * 1.35));
      shovel.matrix = Cesium.Matrix4.multiply(shovel.originalMatrix, tilt, new Cesium.Matrix4());
    }
  }
}

function paintCuts(site: Site): void {
  const { field } = site;
  for (const key of field.dirtyChunks) {
    const [cs, rs] = key.split(':');
    const c0 = Number(cs) * field.chunk;
    const r0 = Number(rs) * field.chunk;
    for (let r = r0; r < r0 + field.chunk && r < field.rows; r++) {
      for (let c = c0; c < c0 + field.chunk && c < field.cols; c++) {
        if (field.channel[field.index(c, r)]) site.drape.paintCell(c, r);
      }
    }
  }
}

function focusNoon(viewer: Cesium.Viewer, site: Site): void {
  viewer.clock.currentTime = Cesium.JulianDate.fromIso8601(site.noon);
}

async function loadSite(viewer: Cesium.Viewer, base: string, path: string, relief: Relief): Promise<Site> {
  const meta = await fetch(`${base}${path}`).then((res) => res.json()) as SiteMeta;
  const heightBuf = await fetch(`${base}${path.replace('terrain.json', 'height.png')}`).then((res) => res.arrayBuffer());
  const png = await decodeGrayPng(heightBuf);
  const { min, max } = meta.elevation_m;
  const cols = png.width;
  const rows = png.height;
  const heights = new Float32Array(cols * rows);
  for (let r = 0; r < rows; r++) {
    const src = rows - 1 - r;
    for (let c = 0; c < cols; c++) {
      const sample = png.samples[src * cols + c] ?? 0;
      heights[r * cols + c] = min + (sample / 65535) * (max - min);
    }
  }
  const field = new Field(cols, rows, meta.spacing_m, heights);
  const saved = loadSave();
  const edits = saved?.[meta.id];
  if (edits) {
    for (const edit of edits) {
      if (edit.i >= 0 && edit.i < field.heights.length) {
        field.heights[edit.i] = edit.h;
        field.channel[edit.i] = 1;
      }
    }
  }
  const yard = new Yard(field);
  yard.repose = meta.repose_deg;
  yard.density = meta.density_kg_m3;
  const midE = ((cols - 1) * meta.spacing_m) / 2;
  const midN = ((rows - 1) * meta.spacing_m) / 2;
  const rig = yard.spawn('dozer', midE, midN);
  rig.bladeAngle = 0.42;
  yard.rest();
  const crs = projector(meta.crs);
  const originX = meta.origin_xy[0];
  const originY = meta.origin_xy[1];
  const project = (east: number, north: number) => crs.forward(originX + east, originY + north);
  const inverse = (lon: number, lat: number) => {
    const xy = crs.inverse(lon, lat);
    return { east: xy.x - originX, north: xy.y - originY };
  };
  const drape = new Drape(
    viewer,
    field,
    project,
    new URL(meta.image, new URL(path, new URL(base, window.location.href))).href,
    meta.image_bounds,
    (lon, lat) => relief.sample(lon, lat),
  );
  if (edits) {
    for (const edit of edits) {
      const c = edit.i % cols;
      const r = (edit.i / cols) | 0;
      drape.paintCell(c, r);
    }
  }
  const pose = yard.pose(rig);
  drape.follow(pose.east, pose.north);
  drape.flush();
  const at = project(pose.east, pose.north);
  const model = await Cesium.Model.fromGltfAsync({
    url: new URL('models/tractor-shovel.glb', new URL(base, window.location.href)).href,
    modelMatrix: Cesium.Matrix4.fromTranslation(Cesium.Cartesian3.fromDegrees(at.lon, at.lat, field.sample(pose.east, pose.north))),
  });
  viewer.scene.primitives.add(model);
  return { id: meta.id, name: meta.name, field, yard, rig, drape, originX, originY, project, inverse, noon: meta.noon, model, bounds: meta.image_bounds };
}

function loadSave(): Record<string, { i: number; h: number }[]> | null {
  try {
    const raw = localStorage.getItem(SAVE_KEY);
    if (!raw) return null;
    return JSON.parse(raw) as Record<string, { i: number; h: number }[]>;
  } catch {
    return null;
  }
}

function writeSave(sites: Site[]): void {
  const data: Record<string, { i: number; h: number }[]> = {};
  for (const site of sites) {
    const edits: { i: number; h: number }[] = [];
    const { field } = site;
    for (let i = 0; i < field.heights.length; i++) {
      const h = field.heights[i] ?? 0;
      if (Math.abs(h - (field.base[i] ?? 0)) > 0.03) edits.push({ i, h });
    }
    data[site.id] = edits;
  }
  try {
    localStorage.setItem(SAVE_KEY, JSON.stringify(data));
  } catch {
    /* a private window or a full disk */
  }
}

function markup(): string {
  return `
    <button id="menu" type="button" aria-label="Viewpoint and place"></button>
    <div id="panel" hidden>
      <div class="choices">
        <button type="button" data-view="titan">Titan</button>
        <button type="button" data-view="robot">Robot</button>
        <button type="button" data-view="human">Human</button>
      </div>
      <div class="choices">
        <button type="button" data-site="polar-desert-basin">Polar Desert Basin</button>
        <button type="button" data-site="rene-levasseur">Île René-Levasseur</button>
      </div>
    </div>
  `;
}
