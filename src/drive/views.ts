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
  private camE = 0;
  private camN = 0;
  private camU = 8;
  private velE = 0;
  private velN = 0;
  private velU = 0;
  private yawLag = 0;

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

  setView(next: ViewId, arc = 0): void {
    if (next === this.view && this.blend >= 1 && arc === 0) return;
    this.from = { ...this.applied };
    this.view = next;
    this.blend = 0;
    this.blendDur = arc > 0 ? 1.15 : 0.8;
    this.arc = arc;
    if (next !== 'vehicle') this.orbitYaw = 0;
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
    const pose = vehicle ?? { lon: this.anchor.lon, lat: this.anchor.lat, up: ground + 2, heading: this.anchor.heading, speed: 0 };
    const yaw = pose.heading + this.orbitYaw;
    const back = 10;
    const above = 3.5 + this.orbitPitch * 2;
    const wantE = -Math.sin(yaw) * back;
    const wantN = -Math.cos(yaw) * back;
    const wantU = above;
    this.camE = damp(this.camE, wantE, this.velE, 0.28, 1 / 60, (v) => { this.velE = v; });
    this.camN = damp(this.camN, wantN, this.velN, 0.28, 1 / 60, (v) => { this.velN = v; });
    this.camU = damp(this.camU, wantU, this.velU, 0.28, 1 / 60, (v) => { this.velU = v; });
    this.yawLag = lerpAngle(this.yawLag, yaw, 1 - Math.exp(-(1 / 60) / 0.3));
    let camE = this.camE;
    let camN = this.camN;
    let camU = this.camU;
    const clearance = this.pullIn(pose, camE, camN, camU, groundAt);
    camE *= clearance;
    camN *= clearance;
    camU = pose.up + 1.2 + camU * clearance;
    const at = offsetDegrees(pose.lat, pose.lon, camE, camN);
    const fov = 60 + 10 * Math.max(0, Math.min(1, Math.abs(pose.speed) / 36));
    return { lon: at.lon, lat: at.lat, height: Math.max(groundAt(at.lon, at.lat) + 2, camU), heading: this.yawLag, pitch: -0.22 + this.orbitPitch * 0.15, fov };
  }

  private pullIn(pose: VehiclePose, camE: number, camN: number, camU: number, groundAt: (lon: number, lat: number) => number): number {
    let limit = 1;
    for (let s = 1; s <= 6; s++) {
      const t = s / 6;
      const at = offsetDegrees(pose.lat, pose.lon, camE * t, camN * t);
      const ground = groundAt(at.lon, at.lat);
      const line = pose.up + 1.3 + (camU - pose.up - 1.3) * t;
      if (line < ground + 1.8) limit = Math.min(limit, Math.max(0.18, t * 0.82));
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

export function drawMinimap(
  canvas: HTMLCanvasElement,
  anchor: Anchor,
  sites: { name: string; west: number; south: number; east: number; north: number }[],
  vehicles: { lon: number; lat: number }[],
): void {
  const ctx = canvas.getContext('2d');
  if (!ctx) return;
  const w = canvas.width;
  const h = canvas.height;
  ctx.clearRect(0, 0, w, h);
  ctx.fillStyle = 'rgba(16, 18, 20, 0.82)';
  ctx.fillRect(0, 0, w, h);
  const scale = metersPerDegree(anchor.lat);
  const range = 6000;
  const project = (lon: number, lat: number) => ({
    x: w / 2 + ((lon - anchor.lon) * scale.lon / range) * (w / 2),
    y: h / 2 - ((lat - anchor.lat) * scale.lat / range) * (h / 2),
  });
  ctx.strokeStyle = 'rgba(215, 219, 224, 0.7)';
  ctx.lineWidth = 1;
  for (const site of sites) {
    const a = project(site.west, site.south);
    const b = project(site.east, site.north);
    ctx.strokeRect(a.x, b.y, b.x - a.x, a.y - b.y);
  }
  ctx.fillStyle = '#d7dbe0';
  for (const vehicle of vehicles) {
    const p = project(vehicle.lon, vehicle.lat);
    if (p.x < 0 || p.y < 0 || p.x > w || p.y > h) continue;
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
