import * as Cesium from 'cesium';
import { metersPerDegree, offsetDegrees } from './field';

export type ViewId = 'titan' | 'robot' | 'human';

/** Tall enough that a 4 km site is a few minutes on foot, and heavy enough to feel planted. */
export const TITAN = 48;
export const TITAN_EYE = 1.7 * TITAN;
export const HUMAN_EYE = 1.8;

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
  /** Chase-only orbit. It does not keep the Orbit view's angle. */
  private chaseYaw = 0;
  private chasePitch = 0;
  orbitRange = 9000;
  mouseIdle = 10;
  /** Extra metres on the eye, used for a jump. */
  eyeLift = 0;
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
    if (view === 'robot') {
      this.chaseYaw += yaw;
      this.chasePitch = Math.max(-0.35, Math.min(0.55, this.chasePitch - pitch));
      return;
    }
    this.anchor.heading += yaw;
    this.anchor.pitch = Math.max(-1.2, Math.min(0.4, this.anchor.pitch - pitch));
  }

  wheel(_delta: number): void {}

  get blending(): boolean {
    return this.blend < 1;
  }

  report(): { blend: number; shot: number; from: number } {
    return { blend: this.blend, shot: this.applied.height, from: this.from.height };
  }

  /** Place a view immediately. Used so the opening shot is the machine, not a long blend. */
  jump(next: ViewId): void {
    this.view = next;
    this.blend = 1;
    this.chaseYaw = 0;
    this.chasePitch = 0;
    this.snap = true;
    this.arc = 0;
  }

  setView(next: ViewId, arc = 0): void {
    if (next === this.view && this.blend >= 1 && arc === 0) return;
    this.from = { ...this.applied };
    this.view = next;
    this.blend = 0;
    this.blendDur = arc > 0 ? 1.15 : 0.8;
    this.arc = arc;
    if (next === 'robot') {
      this.chaseYaw = 0;
      this.chasePitch = 0;
      this.snap = true;
    }
  }

  /** Move the giant or the sky camera across the same ground. Returns false if the slope is too steep. */
  walk(dt: number, throttle: number, strafe: number, ground: (lon: number, lat: number) => number, giant: boolean): void {
    const speed = (giant ? 0.55 * TITAN : 1.5) * (Math.abs(throttle) > 1 ? 1.8 : 1);
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
    if (this.view === 'robot' && this.mouseIdle > 1.5) {
      this.chaseYaw += (0 - this.chaseYaw) * (1 - Math.exp(-dt / 0.35));
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
    if (this.view === 'robot' || this.view === 'human') {
      const floor = groundAt(this.applied.lon, this.applied.lat) + (this.view === 'human' ? 1.2 : 2.2);
      if (this.applied.height < floor) this.applied.height = floor;
    }
    this.apply(this.applied);
  }

  private targetShot(ground: number, vehicle: VehiclePose | null, groundAt: (lon: number, lat: number) => number): Shot {
    if (this.view === 'titan') {
      return { lon: this.anchor.lon, lat: this.anchor.lat, height: ground + TITAN_EYE + this.eyeLift, heading: this.anchor.heading, pitch: this.anchor.pitch, fov: 55 };
    }
    if (this.view === 'human') {
      return { lon: this.anchor.lon, lat: this.anchor.lat, height: ground + HUMAN_EYE + this.eyeLift, heading: this.anchor.heading, pitch: this.anchor.pitch, fov: 68 };
    }
    return this.chase(ground, vehicle, groundAt);
  }

  private chase(ground: number, vehicle: VehiclePose | null, groundAt: (lon: number, lat: number) => number): Shot {
    const pose = vehicle ?? { lon: this.anchor.lon, lat: this.anchor.lat, up: ground + 1.6, heading: this.anchor.heading, speed: 0 };
    const floor = groundAt(pose.lon, pose.lat);
    const base = Math.max(floor + 1.15, Math.min(floor + 3.2, pose.up));
    const yaw = pose.heading + this.chaseYaw;
    const back = 16;
    const above = 3.3 + this.chasePitch * 1.4;
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
    const lookE = Math.sin(pose.heading) * 11;
    const lookN = Math.cos(pose.heading) * 11;
    const lookU = base + 0.05;
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
    const mid = offsetDegrees(pose.lat, pose.lon, camE * 0.5, camN * 0.5);
    const camGround = groundAt(at.lon, at.lat);
    const midGround = groundAt(mid.lon, mid.lat);
    const height = Math.max(camGround + 2.4, midGround + 1.6, camU);
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
      if (line < ground + 0.35) limit = Math.min(limit, Math.max(0.82, (s - 1) / 8));
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
