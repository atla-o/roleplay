import * as Cesium from 'cesium';
import { metersPerDegree, offsetDegrees } from './field';

export type ViewId = 'orbit' | 'titan' | 'vehicle' | 'sky';

/** 750× a person. Eye height makes a few hundred metres of relief read as hills. */
export const GIANT = 750;
export const EYE_M = 1.7 * GIANT;

export interface Anchor {
  lon: number;
  lat: number;
  heading: number;
  pitch: number;
}

interface Shot {
  lon: number;
  lat: number;
  height: number;
  heading: number;
  pitch: number;
  fov: number;
}

interface VehiclePose {
  lon: number;
  lat: number;
  up: number;
  heading: number;
  speed: number;
}

export class Director {
  view: ViewId = 'titan';
  orbitYaw = 0;
  orbitPitch = -0.55;
  orbitRange = 9000;
  mouseIdle = 10;
  private blend = 1;
  private blendDur = 0.8;
  private arc = 0;
  private from: Shot = { lon: -89.5, lat: 75.4, height: 2000, heading: 0, pitch: -0.4, fov: 55 };
  private applied: Shot = { ...this.from };
  private camE = -10;
  private camN = 0;
  private camU = 4.2;
  private velE = 0;
  private velN = 0;
  private velU = 0;
  private snap = true;

  constructor(private readonly viewer: Cesium.Viewer, public anchor: Anchor) {
    this.viewer.scene.screenSpaceCameraController.enableInputs = false;
  }

  mouse(dx: number, dy: number, view: ViewId): void {
    this.mouseIdle = 0;
    const yaw = dx * 0.003;
    const pitch = dy * 0.0022;
    if (view === 'orbit') {
      this.orbitYaw += yaw;
      this.orbitPitch = Math.max(-1.35, Math.min(-0.12, this.orbitPitch - pitch));
      return;
    }
    if (view === 'vehicle') {
      this.orbitYaw += yaw;
      this.orbitPitch = Math.max(-0.8, Math.min(0.45, this.orbitPitch - pitch));
      return;
    }
    this.anchor.heading += yaw;
    this.anchor.pitch = Math.max(-1.2, Math.min(0.4, this.anchor.pitch - pitch));
  }

  wheel(delta: number): void {
    if (this.view === 'orbit') this.orbitRange = Math.max(400, Math.min(2_000_000, this.orbitRange * (delta > 0 ? 1.08 : 0.92)));
  }

  report(): { blend: number; shot: number; from: number } {
    return { blend: this.blend, shot: this.applied.height, from: this.from.height };
  }

  setView(next: ViewId, arc = 0): void {
    if (next === this.view && this.blend >= 1 && arc === 0) return;
    this.from = { ...this.applied };
    this.view = next;
    this.blend = 0;
    this.blendDur = arc > 0 ? 1.15 : 0.8;
    this.arc = arc;
    if (next !== 'vehicle') this.orbitYaw = 0;
    if (next === 'vehicle') this.snap = true;
  }

  /** Move the giant or the sky camera across the same ground. Returns false if the slope is too steep. */
  walk(dt: number, throttle: number, strafe: number, ground: (lon: number, lat: number) => number, giant: boolean): void {
    const speed = (giant ? 1.55 * GIANT : 70) * (Math.abs(throttle) > 1 ? 1 : 1);
    const sprint = Math.abs(throttle) > 1.2 ? 1.65 : 1;
    const dist = speed * sprint * dt;
    const heading = this.anchor.heading;
    const east = Math.sin(heading) * throttle + Math.cos(heading) * strafe;
    const north = Math.cos(heading) * throttle - Math.sin(heading) * strafe;
    const mag = Math.hypot(east, north) || 1;
    const scale = metersPerDegree(this.anchor.lat);
    const lon2 = this.anchor.lon + (east / mag) * dist / scale.lon;
    const lat2 = this.anchor.lat + (north / mag) * dist / scale.lat;
    const rise = ground(lon2, lat2) - ground(this.anchor.lon, this.anchor.lat);
    const grade = Math.atan2(rise, Math.max(8, dist));
    if (grade > (35 * Math.PI) / 180) return;
    this.anchor.lon = lon2;
    this.anchor.lat = lat2;
  }

  step(dt: number, groundAt: (lon: number, lat: number) => number, vehicle: VehiclePose | null): void {
    this.mouseIdle += dt;
    if (this.view === 'vehicle' && this.mouseIdle > 1.5) {
      this.orbitYaw += (0 - this.orbitYaw) * (1 - Math.exp(-dt / 0.35));
    }
    const ground = groundAt(this.anchor.lon, this.anchor.lat);
    const target = this.targetShot(ground, vehicle, groundAt);
    if (this.blend < 1) {
      this.blend = Math.min(1, this.blend + dt / this.blendDur);
      const t = this.blend * this.blend * (3 - 2 * this.blend);
      const arcLift = this.arc * Math.sin(t * Math.PI);
      this.applied = {
        lon: lerp(this.from.lon, target.lon, t),
        lat: lerp(this.from.lat, target.lat, t),
        height: lerp(this.from.height, target.height, t) + arcLift,
        heading: lerpAngle(this.from.heading, target.heading, t),
        pitch: lerp(this.from.pitch, target.pitch, t),
        fov: lerp(this.from.fov, target.fov, t),
      };
    } else {
      this.applied = target;
    }
    if (this.view === 'vehicle') {
      const floor = groundAt(this.applied.lon, this.applied.lat) + 2.4;
      if (this.applied.height < floor) this.applied.height = floor;
    }
    this.apply(this.applied);
  }

  private targetShot(ground: number, vehicle: VehiclePose | null, groundAt: (lon: number, lat: number) => number): Shot {
    if (this.view === 'titan') {
      return { lon: this.anchor.lon, lat: this.anchor.lat, height: ground + EYE_M, heading: this.anchor.heading, pitch: this.anchor.pitch, fov: 52 };
    }
    if (this.view === 'sky') {
      return { lon: this.anchor.lon, lat: this.anchor.lat, height: ground + 520, heading: this.anchor.heading, pitch: this.anchor.pitch, fov: 60 };
    }
    if (this.view === 'orbit') {
      const pitch = this.orbitPitch;
      const heading = this.anchor.heading + this.orbitYaw;
      const pe = Math.sin(heading) * Math.cos(pitch);
      const pn = Math.cos(heading) * Math.cos(pitch);
      const pu = Math.sin(pitch);
      const at = offsetDegrees(this.anchor.lat, this.anchor.lon, -pe * this.orbitRange, -pn * this.orbitRange);
      return { lon: at.lon, lat: at.lat, height: Math.max(ground + 40, ground - pu * this.orbitRange), heading, pitch, fov: 55 };
    }
    return this.chase(ground, vehicle, groundAt);
  }

  private chase(ground: number, vehicle: VehiclePose | null, groundAt: (lon: number, lat: number) => number): Shot {
    const pose = vehicle ?? { lon: this.anchor.lon, lat: this.anchor.lat, up: ground + 1.6, heading: this.anchor.heading, speed: 0 };
    const floor = groundAt(pose.lon, pose.lat);
    const base = Math.max(floor + 1.15, Math.min(floor + 3.2, pose.up));
    const yaw = pose.heading + this.orbitYaw;
    const back = 12;
    const above = 4 + Math.max(-1.2, Math.min(1.5, this.orbitPitch));
    const wantE = -Math.sin(yaw) * back;
    const wantN = -Math.cos(yaw) * back;
    if (this.snap) {
      this.camE = wantE;
      this.camN = wantN;
      this.camU = above;
      this.velE = 0;
      this.velN = 0;
      this.velU = 0;
      this.snap = false;
    } else {
      this.camE = damp(this.camE, wantE, this.velE, 0.28, 1 / 60, (v) => { this.velE = v; });
      this.camN = damp(this.camN, wantN, this.velN, 0.28, 1 / 60, (v) => { this.velN = v; });
      this.camU = damp(this.camU, above, this.velU, 0.28, 1 / 60, (v) => { this.velU = v; });
    }
    const lookE = Math.sin(pose.heading) * 3;
    const lookN = Math.cos(pose.heading) * 3;
    const lookU = base + 1.1;
    const pulled = this.pullIn(pose, lookE, lookN, lookU, this.camE, this.camN, base + this.camU, groundAt);
    let camE = lookE + (this.camE - lookE) * pulled;
    let camN = lookN + (this.camN - lookN) * pulled;
    const span = Math.hypot(camE, camN);
    if (span < 8) {
      const lift = 8 / Math.max(0.2, span);
      camE *= lift;
      camN *= lift;
    }
    let camU = lookU + (base + this.camU - lookU) * pulled;
    const at = offsetDegrees(pose.lat, pose.lon, camE, camN);
    const camGround = groundAt(at.lon, at.lat);
    const height = Math.max(camGround + 2.4, camU);
    const dE = lookE - camE;
    const dN = lookN - camN;
    const dU = lookU - height;
    const heading = Math.atan2(dE, dN);
    const pitch = Math.atan2(dU, Math.hypot(dE, dN));
    const fov = 60 + 10 * Math.max(0, Math.min(1, Math.abs(pose.speed) / 36));
    return { lon: at.lon, lat: at.lat, height, heading, pitch, fov };
  }

  /** Fraction of the boom that stays above the heightfield. 1 means the full 11 m arm is clear. */
  private pullIn(
    pose: VehiclePose,
    lookE: number,
    lookN: number,
    lookU: number,
    camE: number,
    camN: number,
    camU: number,
    groundAt: (lon: number, lat: number) => number,
  ): number {
    let limit = 1;
    for (let s = 1; s <= 8; s++) {
      const t = s / 8;
      const e = lookE + (camE - lookE) * t;
      const n = lookN + (camN - lookN) * t;
      const at = offsetDegrees(pose.lat, pose.lon, e, n);
      const ground = groundAt(at.lon, at.lat);
      const line = lookU + (camU - lookU) * t;
      if (line < ground + 0.45) limit = Math.min(limit, Math.max(0.45, (s - 1) / 8));
    }
    return limit;
  }

  private apply(shot: Shot): void {
    this.viewer.camera.setView({
      destination: Cesium.Cartesian3.fromDegrees(shot.lon, shot.lat, shot.height),
      orientation: { heading: shot.heading, pitch: shot.pitch, roll: 0 },
    });
    const frustum = this.viewer.camera.frustum;
    if (frustum instanceof Cesium.PerspectiveFrustum) frustum.fov = Cesium.Math.toRadians(shot.fov);
  }
}

const mapCache = new WeakMap<HTMLCanvasElement, { key: string; canvas: HTMLCanvasElement }>();

/** Top-down height shading of the ground under the player, plus the site rectangle and the machines. */
export function drawMinimap(
  canvas: HTMLCanvasElement,
  anchor: Anchor,
  sites: { name: string; west: number; south: number; east: number; north: number }[],
  vehicles: { lon: number; lat: number }[],
  sample: (lon: number, lat: number) => number | null,
  revision: number,
): void {
  const ctx = canvas.getContext('2d');
  if (!ctx) return;
  const w = canvas.width;
  const h = canvas.height;
  const range = 3200;
  const scale = metersPerDegree(anchor.lat);
  const key = `${revision}:${Math.round(anchor.lon * 500)}:${Math.round(anchor.lat * 500)}`;
  let cached = mapCache.get(canvas);
  if (!cached || cached.key !== key) {
    const shade = document.createElement('canvas');
    shade.width = w;
    shade.height = h;
    const g = shade.getContext('2d');
    if (g) {
      const image = g.createImageData(w, h);
      const mid = sample(anchor.lon, anchor.lat) ?? 200;
      const step = 4;
      for (let y = 0; y < h; y += step) {
        const lat = anchor.lat + ((h / 2 - y) / (h / 2)) * (range / scale.lat);
        const latN = anchor.lat + ((h / 2 - (y + step)) / (h / 2)) * (range / scale.lat);
        for (let x = 0; x < w; x += step) {
          const lon = anchor.lon + ((x - w / 2) / (w / 2)) * (range / scale.lon);
          const lonE = anchor.lon + ((x + step - w / 2) / (w / 2)) * (range / scale.lon);
          const height = sample(lon, lat);
          let r = 42;
          let gv = 52;
          let b = 56;
          if (height != null) {
            const east = sample(lonE, lat);
            const north = sample(lon, latN);
            const slope = (east ?? height) - height + ((north ?? height) - height);
            const light = Math.max(-18, Math.min(22, -slope * 1.4));
            const t = Math.max(0, Math.min(1, (height - (mid - 40)) / 110));
            r = Math.max(0, Math.min(255, 92 + t * 120 + light));
            gv = Math.max(0, Math.min(255, 78 + t * 96 + light));
            b = Math.max(0, Math.min(255, 58 + t * 62 + light * 0.6));
          }
          for (let dy = 0; dy < step && y + dy < h; dy++) {
            for (let dx = 0; dx < step && x + dx < w; dx++) {
              const o = ((y + dy) * w + (x + dx)) * 4;
              image.data[o] = r;
              image.data[o + 1] = gv;
              image.data[o + 2] = b;
              image.data[o + 3] = 255;
            }
          }
        }
      }
      g.putImageData(image, 0, 0);
    }
    cached = { key, canvas: shade };
    mapCache.set(canvas, cached);
  }
  ctx.clearRect(0, 0, w, h);
  ctx.drawImage(cached.canvas, 0, 0);
  const project = (lon: number, lat: number) => ({
    x: w / 2 + ((lon - anchor.lon) * scale.lon / range) * (w / 2),
    y: h / 2 - ((lat - anchor.lat) * scale.lat / range) * (h / 2),
  });
  ctx.strokeStyle = 'rgba(244, 247, 248, 0.9)';
  ctx.lineWidth = 1;
  for (const site of sites) {
    const a = project(site.west, site.south);
    const b = project(site.east, site.north);
    ctx.strokeRect(Math.min(a.x, b.x), Math.min(a.y, b.y), Math.abs(b.x - a.x), Math.abs(b.y - a.y));
  }
  ctx.fillStyle = '#f0d78c';
  for (const vehicle of vehicles) {
    const p = project(vehicle.lon, vehicle.lat);
    if (p.x < 2 || p.y < 2 || p.x > w - 2 || p.y > h - 2) continue;
    ctx.fillRect(p.x - 2, p.y - 2, 4, 4);
  }
  ctx.save();
  ctx.translate(w / 2, h / 2);
  ctx.rotate(anchor.heading);
  ctx.fillStyle = '#f4f7f8';
  ctx.beginPath();
  ctx.moveTo(0, -8);
  ctx.lineTo(5, 6);
  ctx.lineTo(0, 3);
  ctx.lineTo(-5, 6);
  ctx.closePath();
  ctx.fill();
  ctx.restore();
}

function damp(current: number, target: number, vel: number, smooth: number, dt: number, setVel: (v: number) => void): number {
  const omega = 2 / smooth;
  const x = omega * dt;
  const exp = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x);
  const change = current - target;
  const temp = (vel + omega * change) * dt;
  setVel((vel - omega * temp) * exp);
  return target + (change + temp) * exp;
}

function lerp(a: number, b: number, t: number): number {
  return a + (b - a) * t;
}

function lerpAngle(a: number, b: number, t: number): number {
  let d = b - a;
  while (d > Math.PI) d -= Math.PI * 2;
  while (d < -Math.PI) d += Math.PI * 2;
  return a + d * t;
}
