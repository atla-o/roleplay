import { decodeGrayPng } from './load/png';
import { Heightfield } from './sim/grid';
import { Sim } from './sim/sim';
import { performSuccession } from './sim/succession';
import { Viewport } from './render/view';
import { Hud, type ToolId } from './ui/hud';

interface TerrainMeta {
  cols: number;
  rows: number;
  spacing_m: number;
  width_m: number;
  height_m: number;
  elevation_m: { min: number; max: number };
  georef: { cols: number; rows: number; lat: number[]; lon: number[] };
}

export async function boot(root: HTMLElement, hooks?: { onWorld?: () => void }): Promise<Record<string, unknown>> {
  const bootEl = document.createElement('div');
  bootEl.className = 'boot';
  bootEl.textContent = 'Reading the measured surface';
  root.appendChild(bootEl);
  const base = import.meta.env.BASE_URL;
  const [meta, heightBuf, hydro] = await Promise.all([
    fetch(`${base}data/terrain.json`).then((r) => r.json()) as Promise<TerrainMeta>,
    fetch(`${base}data/height.png`).then((r) => r.arrayBuffer()),
    fetch(`${base}data/hydro.geojson`).then((r) => r.json()),
  ]);
  const png = await decodeGrayPng(heightBuf);
  if (png.width !== meta.cols || png.height !== meta.rows) throw new Error('Measured raster does not match its metadata.');
  const z0 = new Float32Array(meta.cols * meta.rows);
  const span = meta.elevation_m.max - meta.elevation_m.min;
  for (let i = 0; i < z0.length; i++) z0[i] = meta.elevation_m.min + (png.samples[i] / 65535) * span;
  const field = new Heightfield(meta.cols, meta.rows, meta.spacing_m, z0);
  const sim = new Sim(field);
  bootEl.remove();

  const view = new Viewport(root);
  const hud = new Hud(root, sim.species);
  view.setHydro(hydro, field);
  const occurrences = await fetch(`${base}data/occurrences.json`)
    .then((response) => response.json())
    .catch(() => ({ records: [] as { region: string; species: string; scientificName: string }[] }));
  hud.setOccurrences(
    (occurrences.records ?? []).filter((record: { region: string }) => record.region === 'polar-desert-basin'),
  );
  if (hooks?.onWorld) hud.onWorld = hooks.onWorld;
  let place = '';
  let drawing: { x: number; z: number }[] = [];
  let walking = false;
  let yaw = 0;
  let pitch = -0.14;
  let wx = field.width / 2;
  let wz = field.height / 2;
  const keys = new Set<string>();

  const overlay = () => ({ slope: hud.slopeBox.checked, water: hud.waterBox.checked, hydro: hud.hydroBox.checked });
  const refresh = () => {
    view.sync(sim, meta, overlay());
    view.setPreview(drawing, field);
    paintHud();
  };
  const paintHud = () => {
    const stats = sim.stats();
    const phase = Math.max(1, ...sim.phases.milestones.filter((m) => sim.milestones.has(m.id)).map((m) => m.phase));
    hud.setPhase(`Phase ${phase}`);
    hud.setStatus(sim.status);
    hud.setBank(`Stone ${fmt(stats.stone_m3)} m³\nFill ${fmt(stats.fill_m3)} m³\nEnergy ${stats.energy_MJ >= 1000 ? (stats.energy_MJ / 1000).toFixed(1) + ' GJ' : fmt(stats.energy_MJ) + ' MJ'}`);
    const growDay = sim.day - sim.physics.growing_window.start_doy + 1;
    const season = sim.inGrow()
      ? `Day ${sim.day} · growing window, day ${growDay} of ${sim.physics.growing_window.days}`
      : sim.inMelt()
        ? `Day ${sim.day} · thaw, before the growing window`
        : `Day ${sim.day} · frozen ground`;
    hud.setSeason(sim.day, season);
    hud.renderMilestones(sim.milestones);
    if (sim.reading) {
      const r = sim.reading;
      hud.setReading(`
        <div class="row"><span>Elevation</span><span>${r.elevation.toFixed(1)} m <i class="tag">${r.edited ? 'WORKING' : 'MEASURED'}</i></span></div>
        <div class="row"><span>Measured</span><span>${r.measured.toFixed(1)} m <i class="tag">DEM</i></span></div>
        <div class="row"><span>Slope</span><span>${r.slope.toFixed(1)}° <i class="tag">${r.edited ? 'WORKING' : 'DERIVED'}</i></span></div>
        <div class="row"><span>Water</span><span>${r.water.toFixed(2)} m <i class="tag">SIM</i></span></div>
        <div class="row"><span>Ground</span><span>${r.moisture}, ${r.thaw}</span></div>
        <div class="row"><span>Resistance</span><span>${sim.resistance().toFixed(2)} <i class="tag">SIM</i></span></div>
        <div class="row"><span>Stable face</span><span>${r.stable ? 'inside limit' : 'past limit'}</span></div>
        ${place ? `<div class="row"><span>Place</span><span>${place}</span></div>` : ''}
      `);
    }
  };

  const stand = (x: number, z: number, face = yaw) => {
    wx = x;
    wz = z;
    yaw = face;
    walking = true;
    const eye = sim.surfaceAt(x, z).y + sim.physics.walk_eye_m;
    view.enterWalk(x, z, yaw, pitch, Number.isFinite(eye) ? eye : 80);
    hud.tool = 'walk';
    hud.paintTools();
  };

  hud.onTool = (id: ToolId) => {
    drawing = [];
    view.setDrawMode(id === 'channel' || id === 'street');
    if (id === 'walk') stand(wx, wz, yaw);
    else {
      walking = false;
      view.leaveWalk();
    }
    refresh();
  };
  hud.onDay = (day) => {
    sim.setDay(day);
    refresh();
  };
  hud.onOverlay = () => refresh();
  hud.onRestore = () => {
    sim.restoreMeasured();
    drawing = [];
    refresh();
  };
  hud.onCommit = () => {
    if (drawing.length < 2) return;
    if (hud.tool === 'channel') sim.cutPolyline(drawing);
    if (hud.tool === 'street') sim.buildStreet(drawing);
    drawing = [];
    refresh();
  };

  const canvas = view.renderer.domElement;
  let pointer: { x: number; y: number } | null = null;
  canvas.addEventListener('contextmenu', (ev) => ev.preventDefault());
  canvas.addEventListener('pointerdown', (ev) => {
    pointer = { x: ev.clientX, y: ev.clientY };
    if (walking) canvas.requestPointerLock?.();
  });
  canvas.addEventListener('pointermove', (ev) => {
    const hit = view.hit(ev.clientX, ev.clientY);
    if (hit && !walking) {
      sim.reading = sim.readingAt(hit.x, hit.z);
      place = locate(meta, hit.x, hit.z);
      paintHud();
    }
    if (!walking || !pointer) return;
    const dx = ev.movementX || ev.clientX - pointer.x;
    const dy = ev.movementY || ev.clientY - pointer.y;
    if (ev.buttons || document.pointerLockElement === canvas) {
      yaw -= dx * 0.003;
      pitch = Math.max(-1.05, Math.min(0.55, pitch - dy * 0.003));
      pointer = { x: ev.clientX, y: ev.clientY };
    }
  });
  canvas.addEventListener('pointerup', (ev) => {
    if (!pointer) return;
    const moved = Math.hypot(ev.clientX - pointer.x, ev.clientY - pointer.y);
    pointer = null;
    if (ev.button !== 0 || moved > 6 || hud.tool === 'orbit') return;
    const hit = view.hit(ev.clientX, ev.clientY);
    if (!hit) return;
    if (hud.tool === 'walk') {
      stand(hit.x, hit.z, yaw);
      return;
    }
    act(hit.x, hit.z);
  });
  canvas.addEventListener('dblclick', () => hud.requestCommit());

  window.addEventListener('keydown', (ev) => {
    keys.add(ev.key);
    if (['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'Space'].includes(ev.key)) ev.preventDefault();
    if (ev.key === 'Enter') hud.requestCommit();
    if (ev.key === 'Backspace') {
      drawing.pop();
      view.setPreview(drawing, field);
    }
    if (ev.key === 'Escape') {
      drawing = [];
      document.exitPointerLock?.();
      view.setPreview([], field);
    }
  });
  window.addEventListener('keyup', (ev) => keys.delete(ev.key));
  const resize = () => view.resize(root.clientWidth, root.clientHeight);
  resize();
  window.addEventListener('resize', resize);

  const home = () => {
    const x = field.width / 2;
    const z = field.height / 2;
    view.frame({ x, y: field.sample(x, z), z }, 5200, 18, 30);
  };
  home();
  refresh();

  let last = performance.now();
  let alive = true;
  const loop = (now: number) => {
    if (!alive) return;
    const dt = Math.min(0.05, (now - last) / 1000);
    last = now;
    if (walking) step(dt);
    view.render();
    hud.setCompass(view.compass());
    const mpp = view.metersPerPixel();
    const choices = [10, 20, 50, 100, 200, 500, 1000, 2000];
    let meters = 100;
    for (const c of choices) if (c / mpp < 140) meters = c;
    hud.setScale(meters, meters / mpp);
    requestAnimationFrame(loop);
  };
  requestAnimationFrame(loop);

  function step(dt: number) {
    let mx = 0;
    let mz = 0;
    const fx = Math.sin(yaw);
    const fz = Math.cos(yaw);
    const rx = Math.cos(yaw);
    const rz = -Math.sin(yaw);
    if (keys.has('w') || keys.has('W') || keys.has('ArrowUp')) {
      mx += fx;
      mz += fz;
    }
    if (keys.has('s') || keys.has('S') || keys.has('ArrowDown')) {
      mx -= fx;
      mz -= fz;
    }
    if (keys.has('d') || keys.has('D') || keys.has('ArrowRight')) {
      mx += rx;
      mz += rz;
    }
    if (keys.has('a') || keys.has('A') || keys.has('ArrowLeft')) {
      mx -= rx;
      mz -= rz;
    }
    const mag = Math.hypot(mx, mz);
    if (mag > 0) {
      const speed = (keys.has('Shift') ? sim.physics.walk_stride_m_s : sim.physics.walk_m_s) * dt;
      mx = (mx / mag) * speed;
      mz = (mz / mag) * speed;
      const fromY = sim.surfaceAt(wx, wz).y;
      if (!sim.blocked(wx + mx, wz + mz, fromY)) {
        wx += mx;
        wz += mz;
      } else if (!sim.blocked(wx + mx, wz, fromY)) wx += mx;
      else if (!sim.blocked(wx, wz + mz, fromY)) wz += mz;
      sim.noteWalk(Math.hypot(mx, mz));
    }
    const eye = sim.surfaceAt(wx, wz).y + sim.physics.walk_eye_m;
    view.setWalk(wx, wz, yaw, pitch, eye);
  }

  function act(x: number, z: number) {
    sim.reading = sim.readingAt(x, z);
    if (hud.tool === 'channel' || hud.tool === 'street') {
      drawing.push({ x, z });
      view.setPreview(drawing, field);
      sim.status = `${drawing.length} points. Enter commits the ${hud.tool === 'channel' ? 'channel' : 'street'}.`;
      paintHud();
      return;
    }
    if (hud.tool === 'drain') {
      const { c, r } = field.rcOf(x, z);
      const i = field.idx(clamp(Math.round(c), 0, field.cols - 1), clamp(Math.round(r), 0, field.rows - 1));
      const plan = sim.planDiversion(sim.water.pondId[i] >= 0 ? sim.water.pondId[i] : undefined);
      if (!plan) sim.status = 'No pond under the cursor.';
      else sim.cutPolyline(plan.points, plan.invertStart);
    } else if (hud.tool === 'grade') sim.grade(x, z);
    else if (hud.tool === 'mine') sim.mine(x, z);
    else if (hud.tool === 'survey') sim.survey(x, z);
    else if (hud.tool === 'dome') sim.placeDome(x, z);
    else if (hud.tool === 'bed') sim.placeBed(x, z);
    else if (hud.tool === 'ark') sim.deploy(hud.speciesId, x, z, hud.action);
    else if (hud.tool === 'greenhouse' || hud.tool === 'waterworks' || hud.tool === 'township') sim.buildStructure(hud.tool, x, z, yaw);
    wx = x;
    wz = z;
    refresh();
  }

  const api = {
    ready: true,
    stats: () => sim.stats(),
    status: () => sim.status,
    setDay: (day: number) => {
      sim.setDay(day);
      refresh();
    },
    setOverlay: (next: { slope?: boolean; water?: boolean; hydro?: boolean }) => {
      if (next.slope !== undefined) hud.slopeBox.checked = next.slope;
      if (next.water !== undefined) hud.waterBox.checked = next.water;
      if (next.hydro !== undefined) hud.hydroBox.checked = next.hydro;
      refresh();
    },
    cutChannel: (points: { x: number; z: number }[], invertStart?: number) => {
      const result = sim.cutPolyline(points, invertStart);
      refresh();
      return result;
    },
    grade: (x: number, z: number, radius?: number) => {
      const result = sim.grade(x, z, radius);
      refresh();
      return result;
    },
    mine: (x: number, z: number) => {
      const result = sim.mine(x, z);
      refresh();
      return result;
    },
    placeDome: (x: number, z: number) => {
      const result = sim.placeDome(x, z);
      refresh();
      return result;
    },
    placeBed: (x: number, z: number) => {
      const result = sim.placeBed(x, z);
      refresh();
      return result;
    },
    deploy: (id: string, x: number, z: number, action: string) => {
      const result = sim.deploy(id, x, z, action);
      refresh();
      return result;
    },
    buildStreet: (points: { x: number; z: number }[]) => {
      const result = sim.buildStreet(points);
      refresh();
      return result;
    },
    buildStructure: (kind: 'greenhouse' | 'waterworks' | 'township', x: number, z: number, heading: number) => {
      const result = sim.buildStructure(kind, x, z, heading);
      refresh();
      return result;
    },
    planDiversion: () => sim.planDiversion(),
    performSuccession: () => {
      const report = performSuccession(sim);
      view.frame(report.look, report.look.distance, report.look.azimuth, report.look.altitude);
      refresh();
      return report;
    },
    frame: (target: { x: number; y: number; z: number }, distance: number, azimuth: number, altitude: number) => {
      walking = false;
      view.frame(target, distance, azimuth, altitude);
    },
    home,
    enterWalk: (x: number, z: number, face: number, look = -0.16) => {
      pitch = look;
      stand(x, z, face);
    },
    walkBy: (dx: number, dz: number) => {
      const fromY = sim.surfaceAt(wx, wz).y;
      if (!sim.blocked(wx + dx, wz + dz, fromY)) {
        wx += dx;
        wz += dz;
        sim.noteWalk(Math.hypot(dx, dz));
      }
      yaw = Math.atan2(dx, dz);
      const eye = sim.surfaceAt(wx, wz).y + sim.physics.walk_eye_m;
      view.setWalk(wx, wz, yaw, pitch, eye);
      paintHud();
      return { x: wx, z: wz, eye, surface: eye - sim.physics.walk_eye_m };
    },
    pose: () => ({ x: wx, z: wz, yaw, pitch, eye: sim.surfaceAt(wx, wz).y + sim.physics.walk_eye_m }),
    settle: () => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(() => resolve(true)))),
    stop: () => {
      alive = false;
    },
  };
  window.__roleplay = api;
  return api;
}

function locate(meta: TerrainMeta, x: number, z: number): string {
  const u = x / meta.width_m;
  const v = 1 - z / meta.height_m;
  const gx = u * (meta.georef.cols - 1);
  const gy = v * (meta.georef.rows - 1);
  const lat = bilinear(meta.georef.lat, meta.georef.cols, gx, gy);
  const lon = bilinear(meta.georef.lon, meta.georef.cols, gx, gy);
  return `${lat.toFixed(3)}°N ${Math.abs(lon).toFixed(3)}°W`;
}

function bilinear(values: number[], cols: number, gx: number, gy: number): number {
  const x0 = Math.max(0, Math.min(cols - 2, Math.floor(gx)));
  const y0 = Math.max(0, Math.min(cols - 2, Math.floor(gy)));
  const tx = gx - x0;
  const ty = gy - y0;
  const i = (row: number, col: number) => values[row * cols + col];
  return i(y0, x0) * (1 - tx) * (1 - ty) + i(y0, x0 + 1) * tx * (1 - ty) + i(y0 + 1, x0) * (1 - tx) * ty + i(y0 + 1, x0 + 1) * tx * ty;
}

function fmt(n: number): string {
  return n.toLocaleString('en-US', { maximumFractionDigits: 0 });
}
function clamp(v: number, lo: number, hi: number): number {
  return Math.max(lo, Math.min(hi, v));
}

declare global {
  interface Window {
    __roleplay?: Record<string, unknown>;
  }
}
