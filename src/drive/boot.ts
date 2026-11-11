import * as Cesium from 'cesium';
import { decodeGrayPng } from '../load/png';
import { solveWater, type WaterConfig } from '../sim/water';
import { Field, metersPerDegree, offsetDegrees, resampleNorthUp } from './field';
import { ChunkLayer } from './mesh';
import { raindrops } from './sculpt';
import { Yard, type DriveInput, type Rig, type RigKind } from './ride';
import { Director, drawMinimap, type ViewId } from './views';

interface Patch {
  field: Field;
  west: number;
  south: number;
  widthM: number;
  heightM: number;
  depth: Float32Array;
  layer: ChunkLayer | null;
}

interface Place {
  id: string;
  name: string;
  note: string;
  anchorLat: number;
  anchorLon: number;
  ground: Patch;
  context: Patch | null;
  yard: Yard;
}

const WATER: WaterConfig = {
  microrelief_m: 0.04,
  meltwater_mm: 18,
  melt_duration_days: 18,
  detention_slope_deg: 0.85,
  detention_max_m: 0.35,
  capture_m: 60,
  flow_draw_min_cells: 30,
  stream_coeff: 0.55,
  stream_cap_m: 0.45,
  pond_block_m: 0.1,
};

const POSTS = 121;

export async function startWorld(root: HTMLElement): Promise<void> {
  root.insertAdjacentHTML('beforeend', markup());
  const host = document.createElement('div');
  host.id = 'cesium';
  root.prepend(host);
  const credit = document.createElement('div');
  credit.id = 'cesium-credit';
  root.append(credit);
  const base = import.meta.env.BASE_URL || './';
  (window as unknown as { CESIUM_BASE_URL?: string }).CESIUM_BASE_URL = new URL('cesium/', new URL(base, window.location.href)).href;

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
  viewer.clock.currentTime = Cesium.JulianDate.fromIso8601('2026-06-21T16:30:00Z');
  viewer.clock.shouldAnimate = false;
  viewer.scene.globe.enableLighting = true;
  viewer.scene.fog.enabled = true;
  viewer.scene.fog.density = 0.00004;
  viewer.scene.fog.minimumBrightness = 0.08;
  viewer.scene.globe.showGroundAtmosphere = true;
  viewer.cesiumWidget.screenSpaceEventHandler.removeInputAction(Cesium.ScreenSpaceEventType.LEFT_DOUBLE_CLICK);
  viewer.imageryLayers.addImageryProvider(
    new Cesium.UrlTemplateImageryProvider({
      url: 'https://tiles.maps.eox.at/wmts/1.0.0/s2cloudless-2021_3857/default/g/{z}/{y}/{x}.jpg',
      tilingScheme: new Cesium.WebMercatorTilingScheme(),
      maximumLevel: 13,
      credit: 'Sentinel-2 cloudless by EOX (CC BY 4.0), modified Copernicus Sentinel data 2021',
    }),
  );

  const status = root.querySelector('#drive-status')!;
  status.textContent = 'Reading the measured ground';
  const basin = await loadBasin(base);
  const ring = await loadRing(base);
  const places = [basin, ring];
  for (const place of places) {
    mount(viewer, place.ground);
    if (place.context) mount(viewer, place.context);
    viewer.entities.add({
      id: place.id,
      position: Cesium.Cartesian3.fromDegrees(place.anchorLon, place.anchorLat, 2500),
      label: {
        text: place.name,
        font: '600 14px Instrument Sans, sans-serif',
        fillColor: Cesium.Color.WHITE,
        outlineColor: Cesium.Color.fromCssColorString('#121416'),
        outlineWidth: 3,
        style: Cesium.LabelStyle.FILL_AND_OUTLINE,
        disableDepthTestDistance: Number.POSITIVE_INFINITY,
      },
    });
  }

  const drawn: { place: Place; rig: Rig; model: Cesium.Model }[] = [];
  for (const place of places) {
    for (const rig of place.yard.rigs) {
      const model = await Cesium.Model.fromGltfAsync({
        url: new URL(rig.mesh, new URL(base, window.location.href)).href,
      });
      viewer.scene.primitives.add(model);
      drawn.push({ place, rig, model });
    }
  }

  let focus = basin;
  let active: Rig | null = null;
  let chosen: RigKind = 'dozer';
  let previousView: ViewId = 'titan';
  const keys = new Set<string>();
  const input: DriveInput = { throttle: 0, steer: 0, brake: false, raise: false, lower: false, dig: false, dump: false };
  let waterAt = 0;
  let eHeld = 0;
  let eFired = false;
  const director = new Director(viewer, {
    lon: basin.anchorLon,
    lat: basin.anchorLat,
    heading: 0.4,
    pitch: -0.28,
  });
  const map = root.querySelector<HTMLCanvasElement>('#minimap')!;

  const list = root.querySelector('#site-list')!;
  const paintList = () => {
    list.innerHTML = places
      .map((place) => `<button type="button" class="tool${place === focus ? ' active' : ''}" data-site="${place.id}">${place.name}</button>`)
      .join('');
    list.querySelectorAll<HTMLButtonElement>('[data-site]').forEach((button) => {
      button.addEventListener('click', () => {
        const place = places.find((item) => item.id === button.dataset.site);
        if (place) fly(place);
      });
    });
  };
  const groundAt = (lon: number, lat: number): number => {
    for (const place of places) {
      const patch = place.ground;
      const scale = metersPerDegree(patch.south);
      const east = (lon - patch.west) * scale.lon;
      const north = (lat - patch.south) * scale.lat;
      if (east >= 0 && north >= 0 && east <= patch.widthM && north <= patch.heightM) return patch.field.sample(east, north);
    }
    for (const place of places) {
      const patch = place.context;
      if (!patch) continue;
      const scale = metersPerDegree(patch.south);
      const east = (lon - patch.west) * scale.lon;
      const north = (lat - patch.south) * scale.lat;
      if (east >= 0 && north >= 0 && east <= patch.widthM && north <= patch.heightM) return patch.field.sample(east, north);
    }
    return 0;
  };
  const rigGeo = (place: Place, rig: Rig) => {
    const pose = place.yard.pose(rig);
    const at = offsetDegrees(place.ground.south, place.ground.west, pose.east, pose.north);
    return { ...pose, lon: at.lon, lat: at.lat };
  };
  const siteAt = (lon: number, lat: number) => places.find((place) => {
    const scale = metersPerDegree(place.ground.south);
    const east = (lon - place.ground.west) * scale.lon;
    const north = (lat - place.ground.south) * scale.lat;
    return east >= 0 && north >= 0 && east <= place.ground.widthM && north <= place.ground.heightM;
  }) ?? null;
  const showView = () => {
    root.querySelectorAll<HTMLButtonElement>('[data-view]').forEach((button) => {
      button.classList.toggle('active', button.dataset.view === director.view);
    });
  };
  const enter = (rig: Rig) => {
    active = rig;
    chosen = rig.kind;
    focus = places.find((place) => place.yard.rigs.includes(rig)) ?? focus;
    const geo = rigGeo(focus, rig);
    director.anchor.lon = geo.lon;
    director.anchor.lat = geo.lat;
    if (director.view !== 'vehicle') {
      previousView = director.view;
      director.setView('vehicle');
    }
    paintList();
    showView();
  };
  const leave = () => {
    active = null;
    director.setView(previousView === 'vehicle' ? 'titan' : previousView);
    showView();
  };
  const fly = (place: Place) => {
    focus = place;
    const scale = metersPerDegree(director.anchor.lat);
    const east = (place.anchorLon - director.anchor.lon) * scale.lon;
    const north = (place.anchorLat - director.anchor.lat) * scale.lat;
    const distance = Math.hypot(east, north);
    active = null;
    director.anchor.lon = place.anchorLon;
    director.anchor.lat = place.anchorLat;
    director.anchor.pitch = -0.35;
    previousView = 'titan';
    director.setView('titan', distance > 6000 ? Math.min(distance * 0.22, 380_000) : 0);
    paintList();
    showView();
  };

  paintList();
  showView();
  director.step(0, groundAt, null);

  const handler = new Cesium.ScreenSpaceEventHandler(viewer.scene.canvas);
  handler.setInputAction((event: { position: Cesium.Cartesian2 }) => {
    const picked = viewer.scene.pick(event.position);
    const id = picked && typeof picked.id === 'object' && picked.id && 'id' in picked.id ? String(picked.id.id) : '';
    const place = places.find((item) => item.id === id);
    if (place) fly(place);
  }, Cesium.ScreenSpaceEventType.LEFT_CLICK);

  root.querySelector('#drive-enter')?.addEventListener('click', () => {
    if (director.view === 'vehicle') leave();
    else {
      const rig = focus.yard.rigs.find((item) => item.kind === chosen) ?? focus.yard.rigs[0];
      if (rig) enter(rig);
    }
  });
  root.querySelectorAll<HTMLButtonElement>('[data-view]').forEach((button) => {
    button.addEventListener('click', () => chooseView((button.dataset.view || 'titan') as ViewId));
  });
  root.querySelector('#drive-rain')?.addEventListener('click', () => {
    raindrops(focus.ground.field, 70);
    status.textContent = 'Rain moved sediment downhill. The soil stayed in the field.';
  });
  root.querySelector('#drive-reset')?.addEventListener('click', () => {
    focus.ground.field.reset();
    for (const rig of focus.yard.rigs) rig.loadM3 = 0;
    settleWater(focus);
    status.textContent = 'Measured surface restored. Banked soil is back in the ground.';
  });
  root.querySelector('#open-credits')?.addEventListener('click', () => root.querySelector<HTMLDialogElement>('#credits')?.showModal());
  root.querySelectorAll('[data-close]').forEach((button) => {
    button.addEventListener('click', () => button.closest('dialog')?.close());
  });
  root.querySelectorAll<HTMLButtonElement>('[data-hold]').forEach((button) => {
    const key = button.dataset.hold || '';
    const down = (ev: Event) => {
      ev.preventDefault();
      keys.add(key);
    };
    const up = () => keys.delete(key);
    button.addEventListener('pointerdown', down);
    button.addEventListener('pointerup', up);
    button.addEventListener('pointerleave', up);
  });
  const canvas = viewer.scene.canvas;
  let dragging = false;
  canvas.addEventListener('pointerdown', (ev) => {
    if (director.view === 'titan' || director.view === 'sky') canvas.requestPointerLock?.();
    dragging = true;
    void ev;
  });
  canvas.addEventListener('pointerup', () => {
    dragging = false;
  });
  canvas.addEventListener('pointermove', (ev) => {
    if (!dragging && document.pointerLockElement !== canvas) return;
    director.mouse(ev.movementX || 0, ev.movementY || 0, director.view);
  });
  canvas.addEventListener('wheel', (ev) => {
    if (director.view === 'vehicle' && active) {
      ev.preventDefault();
      active.bladeAngle = Math.max(-0.7, Math.min(0.55, active.bladeAngle + (ev.deltaY > 0 ? -0.05 : 0.05)));
    } else director.wheel(ev.deltaY);
  }, { passive: false });
  window.addEventListener('keydown', (ev) => {
    keys.add(ev.key.toLowerCase());
    if (ev.key === '1') chooseView('orbit');
    if (ev.key === '2') chooseView('titan');
    if (ev.key === '3') chooseView('vehicle');
    if (ev.key === '4') chooseView('sky');
    if (ev.key === 'Escape') {
      document.exitPointerLock?.();
      if (director.view === 'vehicle') leave();
    }
  });
  window.addEventListener('keyup', (ev) => keys.delete(ev.key.toLowerCase()));

  function chooseView(next: ViewId) {
    if (next === 'vehicle') {
      const rig = focus.yard.rigs.find((item) => item.kind === chosen) ?? focus.yard.rigs[0];
      if (rig) enter(rig);
      return;
    }
    if (director.view === 'vehicle') previousView = next;
    active = null;
    director.setView(next);
    showView();
  }

  let last = performance.now();
  const loop = () => {
    const now = performance.now();
    const dt = Math.min(0.05, (now - last) / 1000);
    last = now;
    readInput();
    if (keys.has('e')) {
      eHeld += dt;
      if (!eFired && eHeld > 0.4) {
        eFired = true;
        if (director.view === 'vehicle') leave();
        else {
          const rig = focus.yard.rigs.find((item) => item.kind === chosen) ?? focus.yard.rigs[0];
          if (rig) enter(rig);
        }
      }
    } else {
      eHeld = 0;
      eFired = false;
    }
    if (director.view === 'titan' || director.view === 'sky') {
      let throttle = (keys.has('w') || keys.has('arrowup') ? 1 : 0) - (keys.has('s') || keys.has('arrowdown') ? 1 : 0);
      const strafe = (keys.has('d') || keys.has('arrowright') ? 1 : 0) - (keys.has('a') || keys.has('arrowleft') ? 1 : 0);
      if (director.view === 'titan' && keys.has('shift')) throttle *= 1.7;
      if (throttle || strafe) director.walk(dt, throttle, strafe, groundAt, director.view === 'titan');
      const under = siteAt(director.anchor.lon, director.anchor.lat);
      if (under) focus = under;
    }
    const driving = director.view === 'vehicle' && active && focus.yard.rigs.includes(active) ? active : null;
    if (driving) focus.yard.step(dt, driving, input);
    input.raise = false;
    input.lower = false;
    if (driving) {
      const geo = rigGeo(focus, driving);
      director.anchor.lon = geo.lon;
      director.anchor.lat = geo.lat;
      director.anchor.heading = geo.heading;
    }
    director.step(dt, groundAt, driving ? rigGeo(focus, driving) : null);
    if (focus.ground.field.dirtyChunks.size) {
      if (now - waterAt > 1800) {
        settleWater(focus);
        waterAt = now;
      }
      refresh(focus);
    }
    poseModels(drawn);
    paint(focus);
    drawMinimap(
      map,
      director.anchor,
      places.map((place) => ({
        name: place.name,
        west: place.ground.west,
        south: place.ground.south,
        east: offsetDegrees(place.ground.south, place.ground.west, place.ground.widthM, 0).lon,
        north: offsetDegrees(place.ground.south, place.ground.west, 0, place.ground.heightM).lat,
      })),
      focus.yard.rigs.map((rig) => {
        const geo = rigGeo(focus, rig);
        return { lon: geo.lon, lat: geo.lat };
      }),
    );
    requestAnimationFrame(loop);
  };
  requestAnimationFrame(loop);
  status.textContent = 'One ground. Fly in from orbit, then drive. The blade pushes soil. The bucket holds it until you dump.';

  window.__roleplay = {
    ready: true,
    places: () => places.map((place) => place.id),
    fly: (id: string) => {
      const place = places.find((item) => item.id === id);
      if (place) fly(place);
    },
    sculpt: () => {
      const field = focus.ground.field;
      const before = field.cutM3;
      const rig = focus.yard.rigs[0];
      if (rig) rig.bladeAngle = -0.45;
      focus.yard.step(1 / 20, rig ?? null, { throttle: 1, steer: 0, brake: false, raise: false, lower: true, dig: false, dump: false });
      return { cut: field.cutM3 - before, fill: field.fillM3, held: focus.yard.held() };
    },
    volumes: () => ({ cut: focus.ground.field.cutM3, fill: focus.ground.field.fillM3, held: focus.yard.held() }),
    setView: (id: ViewId) => chooseView(id),
    view: () => director.view,
    held: () => [...keys],
  };

  function readInput() {
    const pad = navigator.getGamepads?.()[0];
    const axis = pad ? pad.axes[0] || 0 : 0;
    const driving = director.view === 'vehicle';
    const accel = driving && (pad?.buttons[7]?.pressed || keys.has('w') || keys.has('arrowup'));
    const back = driving && (pad?.buttons[6]?.pressed || keys.has('s') || keys.has('arrowdown'));
    input.throttle = accel ? 1 : back ? -0.55 : 0;
    input.steer = driving ? axis : 0;
    if (driving && (keys.has('a') || keys.has('arrowleft'))) input.steer -= 0.85;
    if (driving && (keys.has('d') || keys.has('arrowright'))) input.steer += 0.85;
    input.brake = driving && keys.has(' ');
    input.raise = driving && (keys.has('r') || Boolean(pad?.buttons[5]?.pressed));
    input.lower = driving && (keys.has('f') || Boolean(pad?.buttons[4]?.pressed));
    input.dig = driving && keys.has('g');
    input.dump = driving && keys.has('t');
  }

  function paint(place: Place) {
    const rig = director.view === 'vehicle' ? active : null;
    const names = { orbit: 'Orbit', titan: 'Titan', vehicle: 'Vehicle', sky: 'Sky' };
    if (rig) {
      const pose = place.yard.pose(rig);
      const grade = place.yard.grade(rig);
      const depth = place.yard.bladeDepth(rig);
      root.querySelector('#drive-read')!.textContent = `${rig.label}  ${pose.speed.toFixed(0)} km/h  grade ${grade.toFixed(0)}°  blade ${((rig.bladeAngle * 180) / Math.PI).toFixed(0)}°  depth ${depth.toFixed(2)} m`;
    } else {
      root.querySelector('#drive-read')!.textContent = `${names[director.view]} · ${place.name}`;
    }
    root.querySelector('#drive-volumes')!.textContent = `Moved ${Math.round(place.ground.field.cutM3).toLocaleString('en-US')} m³   Fill ${Math.round(place.ground.field.fillM3).toLocaleString('en-US')} m³   In machines ${place.yard.held().toFixed(1)} m³`;
    root.querySelector('#drive-note')!.textContent = place.note;
  }
}

function settleWater(place: Place): void {
  const field = place.ground.field;
  const water = solveWater(field.heights, field.cols, field.rows, field.spacing, WATER, field.channel, new Uint8Array(field.heights.length));
  place.ground.depth = water.depth;
  mirror(place);
}

function mirror(place: Place): void {
  const context = place.context;
  if (!context) return;
  const core = place.ground;
  for (let r = 0; r < context.field.rows; r++) {
    const north = (r / (context.field.rows - 1)) * context.heightM;
    const latC = context.south + north / metersPerDegree(context.south).lat;
    for (let c = 0; c < context.field.cols; c++) {
      const east = (c / (context.field.cols - 1)) * context.widthM;
      const lon = context.west + east / metersPerDegree(context.south).lon;
      const coreEast = (lon - core.west) * metersPerDegree(core.south).lon;
      const coreNorth = (latC - core.south) * metersPerDegree(core.south).lat;
      if (coreEast < 0 || coreNorth < 0 || coreEast > core.widthM || coreNorth > core.heightM) continue;
      const sample = core.field.sample(coreEast, coreNorth);
      const i = context.field.index(c, r);
      if (Math.abs((context.field.heights[i] ?? 0) - sample) > 0.2) {
        context.field.heights[i] = sample;
        context.field.mark(i);
      }
    }
  }
  context.field.dirty = true;
}

function mount(viewer: Cesium.Viewer, patch: Patch): void {
  patch.layer = new ChunkLayer(viewer, patch.field, patch.west, patch.south, patch.depth);
}

function refresh(place: Place): void {
  place.ground.layer?.setDepth(place.ground.depth);
  place.ground.layer?.flush(4);
  place.context?.layer?.flush(2);
}

function poseModels(drawn: { place: Place; rig: Rig; model: Cesium.Model }[]): void {
  for (const { place, rig, model } of drawn) {
    const pose = place.yard.pose(rig);
    const origin = Cesium.Cartesian3.fromDegrees(place.ground.west, place.ground.south, 0);
    const enu = Cesium.Transforms.eastNorthUpToFixedFrame(origin);
    const rotation = Cesium.Quaternion.fromHeadingPitchRoll(new Cesium.HeadingPitchRoll(pose.heading, 0, 0));
    const local = Cesium.Matrix4.fromTranslationQuaternionRotationScale(
      new Cesium.Cartesian3(pose.east, pose.north, pose.up - 0.6),
      rotation,
      new Cesium.Cartesian3(8, 8, 8),
    );
    Cesium.Matrix4.multiply(enu, local, model.modelMatrix);
  }
}

function follow(viewer: Cesium.Viewer, place: Place, rig: Rig): void {
  const pose = place.yard.pose(rig);
  const back = 28;
  const eye = offsetDegrees(
    place.ground.south,
    place.ground.west,
    pose.east - Math.sin(pose.heading) * back,
    pose.north - Math.cos(pose.heading) * back,
  );
  const look = offsetDegrees(place.ground.south, place.ground.west, pose.east, pose.north);
  viewer.camera.setView({
    destination: Cesium.Cartesian3.fromDegrees(eye.lon, eye.lat, pose.up + 12),
    orientation: {
      heading: pose.heading,
      pitch: Cesium.Math.toRadians(-28),
      roll: 0,
    },
  });
  void look;
}

async function loadBasin(base: string): Promise<Place> {
  const [meta, heightBuf] = await Promise.all([
    fetch(`${base}data/terrain.json`).then((r) => r.json()) as Promise<{ elevation_m: { min: number; max: number }; cols: number; rows: number; center_wgs84: { lat: number; lon: number } }>,
    fetch(`${base}data/height.png`).then((r) => r.arrayBuffer()),
  ]);
  const png = await decodeGrayPng(heightBuf);
  const { min, max } = meta.elevation_m;
  const heights = resampleNorthUp(png.samples, png.width, png.height, POSTS, POSTS, (sample) => min + (sample / 65535) * (max - min));
  const widthM = 4000;
  const sw = offsetDegrees(meta.center_wgs84.lat, meta.center_wgs84.lon, -widthM / 2, -widthM / 2);
  const field = new Field(POSTS, POSTS, widthM / (POSTS - 1), heights);
  const yard = new Yard(field);
  yard.spawn('dozer', widthM * 0.42, widthM * 0.48);
  yard.spawn('excavator', widthM * 0.42 + 45, widthM * 0.48 + 20);
  yard.spawn('hauler', widthM * 0.42 + 16, widthM * 0.48 - 40);
  return {
    id: 'polar-desert-basin',
    name: 'Polar Desert Basin',
    note: 'Northern Canada. The measured 4 km surface. Cut soil is pushed ahead, or held in a bucket until you dump it.',
    anchorLat: meta.center_wgs84.lat,
    anchorLon: meta.center_wgs84.lon,
    ground: { field, west: sw.lon, south: sw.lat, widthM, heightM: widthM, depth: new Float32Array(heights.length), layer: null },
    context: null,
    yard,
  };
}

async function loadRing(base: string): Promise<Place> {
  const [meta, heightBuf, waterBuf] = await Promise.all([
    fetch(`${base}data/ile/terrain.json`).then((r) => r.json()) as Promise<{ elevation_m: { min: number; max: number }; bounds_wgs84: { west: number; south: number; east: number; north: number } }>,
    fetch(`${base}data/ile/height.png`).then((r) => r.arrayBuffer()),
    fetch(`${base}data/ile/water.png`).then((r) => r.arrayBuffer()),
  ]);
  const height = await decodeGrayPng(heightBuf);
  const water = await decodeGrayPng(waterBuf);
  const { min, max } = meta.elevation_m;
  const decode = (sample: number) => min + (sample / 65535) * (max - min);
  const contextHeights = resampleNorthUp(height.samples, height.width, height.height, 140, 154, decode);
  const bounds = meta.bounds_wgs84;
  const scale = metersPerDegree((bounds.south + bounds.north) / 2);
  const widthM = (bounds.east - bounds.west) * scale.lon;
  const heightM = (bounds.north - bounds.south) * scale.lat;
  const context = new Field(140, 154, widthM / 139, contextHeights);
  const contextDepth = new Float32Array(contextHeights.length);
  for (let r = 0; r < 154; r++) {
    for (let c = 0; c < 140; c++) {
      const sy = Math.min(water.height - 1, Math.floor((1 - r / 153) * (water.height - 1)));
      const sx = Math.min(water.width - 1, Math.floor((c / 139) * (water.width - 1)));
      if ((water.samples[sy * water.width + sx] ?? 0) > 127) {
        context.heights[r * 140 + c] = Math.min(context.heights[r * 140 + c] ?? 0, 360);
        contextDepth[r * 140 + c] = 2;
      }
    }
  }
  const anchor = { lat: 51.43995, lon: -68.73717 };
  const coreW = 4000;
  const sw = offsetDegrees(anchor.lat, anchor.lon, -coreW / 2, -coreW / 2);
  const coreHeights = new Float32Array(POSTS * POSTS);
  for (let r = 0; r < POSTS; r++) {
    const north = (r / (POSTS - 1)) * coreW;
    const lat = sw.lat + north / scale.lat;
    const sy = (1 - (lat - bounds.south) / (bounds.north - bounds.south)) * (height.height - 1);
    for (let c = 0; c < POSTS; c++) {
      const east = (c / (POSTS - 1)) * coreW;
      const lon = sw.lon + east / scale.lon;
      const sx = ((lon - bounds.west) / (bounds.east - bounds.west)) * (height.width - 1);
      coreHeights[r * POSTS + c] = bilerp(height.samples, height.width, height.height, sx, sy, decode);
    }
  }
  const field = new Field(POSTS, POSTS, coreW / (POSTS - 1), coreHeights);
  const yard = new Yard(field);
  yard.spawn('dozer', coreW * 0.5, coreW * 0.55);
  yard.spawn('excavator', coreW * 0.5 + 45, coreW * 0.55 + 16);
  yard.spawn('hauler', coreW * 0.5 + 12, coreW * 0.55 - 40);
  return {
    id: 'rene-levasseur',
    name: 'Île René-Levasseur',
    note: 'Measured research terrain in the Nitassinan of the Innu of Pessamit. The ring is an emblem of the O, not a claim on the land. Machines here are a simulation.',
    anchorLat: anchor.lat,
    anchorLon: anchor.lon,
    ground: { field, west: sw.lon, south: sw.lat, widthM: coreW, heightM: coreW, depth: new Float32Array(coreHeights.length), layer: null },
    context: {
      field: context,
      west: bounds.west,
      south: bounds.south,
      widthM,
      heightM,
      depth: contextDepth,
      layer: null,
    },
    yard,
  };
}

function bilerp(
  samples: ArrayLike<number>,
  cols: number,
  rows: number,
  x: number,
  y: number,
  decode: (sample: number) => number,
): number {
  const x0 = Math.max(0, Math.min(cols - 1, Math.floor(x)));
  const y0 = Math.max(0, Math.min(rows - 1, Math.floor(y)));
  const x1 = Math.min(cols - 1, x0 + 1);
  const y1 = Math.min(rows - 1, y0 + 1);
  const tx = x - x0;
  const ty = y - y0;
  const h00 = decode(samples[y0 * cols + x0] ?? 0);
  const h10 = decode(samples[y0 * cols + x1] ?? 0);
  const h01 = decode(samples[y1 * cols + x0] ?? 0);
  const h11 = decode(samples[y1 * cols + x1] ?? 0);
  return (h00 * (1 - tx) + h10 * tx) * (1 - ty) + (h01 * (1 - tx) + h11 * tx) * ty;
}

function markup(): string {
  return `
    <header class="top">
      <div class="brand">
        <svg class="mark" viewBox="0 0 32 32" aria-hidden="true"><circle cx="16" cy="16" r="10.5" fill="none" stroke="#d7dbe0" stroke-width="1.25"/></svg>
        <div><div class="word">ROLEPLAY</div><div class="sub">Creation division</div></div>
      </div>
      <div class="place"><strong id="drive-read">World</strong><div class="muted" id="drive-volumes"></div></div>
      <button id="drive-enter" class="text-btn" type="button" style="width:auto">Drive</button>
      <button id="open-credits" class="text-btn" type="button" style="width:auto">Credits</button>
    </header>
    <aside class="rail">
      <div class="group">Sites</div>
      <div id="site-list"></div>
      <div class="group">Machines</div>
      <p class="peers">Hold E to enter or leave a machine. WASD or a gamepad drives. R raises the blade, F lowers it. G digs. T dumps. Shift is a longer Titan stride.</p>
      <button id="drive-rain" class="tool" type="button">Rain on this ground</button>
      <button id="drive-reset" class="tool" type="button">Reset to measured</button>
    </aside>
    <aside class="inspector">
      <div class="views" role="group" aria-label="View">
        <button type="button" data-view="orbit">Orbit <i>1</i></button>
        <button type="button" data-view="titan" class="active">Titan <i>2</i></button>
        <button type="button" data-view="vehicle">Vehicle <i>3</i></button>
        <button type="button" data-view="sky">Sky <i>4</i></button>
      </div>
      <div class="kicker">This ground</div>
      <p class="status" id="drive-status"></p>
      <p class="peers" id="drive-note"></p>
      <div class="kicker">Hands</div>
      <div class="pad">
        <button type="button" data-hold="w">Drive</button>
        <button type="button" data-hold="s">Back</button>
        <button type="button" data-hold="a">Left</button>
        <button type="button" data-hold="d">Right</button>
        <button type="button" data-hold="f">Blade down</button>
        <button type="button" data-hold="r">Blade up</button>
        <button type="button" data-hold=" ">Brake</button>
        <button type="button" data-hold="g">Dig</button>
        <button type="button" data-hold="t">Dump</button>
      </div>
    </aside>
    <canvas id="minimap" class="minimap" width="168" height="168"></canvas>
    <dialog id="credits">
      <button class="close" data-close type="button">Close</button>
      <h2>Credits</h2>
      <p>One measured world. Orbit, the overview, and the driver read the same heightfield. Soil that is cut is filled somewhere else, or held in a machine.</p>
      <p>Polar Desert Basin is Northern Canada, ArcticDEM v4.1, CC-BY-4.0, Porter et al. 2023, doi:10.7910/DVN/3VDC4W. Hydrography in the older tools is NRCan NHN, Open Government Licence – Canada.</p>
      <p>Île René-Levasseur is in the Nitassinan of the Innu of Pessamit. Louis-Babel Ecological Reserve. Réserve de biodiversité de la Météorite. Manicouagan-Uapishka UNESCO Biosphere Reserve. The reservoir is held by Hydro-Québec's Daniel-Johnson Dam. Elevation is the NRCan HRDEM mosaic, with MRDEM-30 on the same window. Open Government Licence – Canada. Land cover and the water class are NRCan 2020. Species records are GBIF.</p>
      <p>The globe is CesiumJS, Apache-2.0. Vehicles use cannon-es, MIT. The machine meshes are Kenney Car Kit, CC0. Imagery is Sentinel-2 cloudless by EOX, CC BY 4.0, over Natural Earth II.</p>
    </dialog>
  `;
}

declare global {
  interface Window {
    __roleplay?: Record<string, unknown>;
  }
}
