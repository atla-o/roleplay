import * as CANNON from 'cannon-es';
import type { Field } from './field';
import { digBucket, dumpLoad, planeBlade } from './sculpt';

export type RigKind = 'dozer' | 'excavator' | 'hauler';

export interface DriveInput {
  throttle: number;
  steer: number;
  brake: boolean;
  raise: boolean;
  lower: boolean;
  dig: boolean;
  dump: boolean;
}

export interface Rig {
  kind: RigKind;
  label: string;
  mesh: string;
  vehicle: CANNON.RaycastVehicle;
  loadM3: number;
  /** Radians. Positive lifts the blade. Negative puts the edge into the grade. */
  bladeAngle: number;
  applied: number;
  /** 1 is free, lower means the blade is in the ground. */
  loadDrag: number;
}

const SPECS: Record<RigKind, { mass: number; force: number; length: number; width: number; tracked: boolean; maxKmh: number; mesh: string; label: string }> = {
  dozer: { mass: 28_000, force: 95_000, length: 6.6, width: 3.6, tracked: true, maxKmh: 12, mesh: 'models/tractor-shovel.glb', label: 'Mass mover' },
  excavator: { mass: 22_000, force: 60_000, length: 5.6, width: 3.0, tracked: true, maxKmh: 8, mesh: 'models/tractor.glb', label: 'Excavator' },
  hauler: { mass: 32_000, force: 78_000, length: 8.2, width: 3.2, tracked: false, maxKmh: 36, mesh: 'models/garbage-truck.glb', label: 'Hauler' },
};

export class Yard {
  readonly world: CANNON.World;
  readonly rigs: Rig[] = [];
  private readonly shape: CANNON.Heightfield;
  private readonly data: number[][];
  private accumulator = 0;
  /** Ground the wheels stand on. The fine edit layer replaces the coarse posts while it is open. */
  surface: (east: number, north: number) => number = (east, north) => this.field.sample(east, north);
  /** Elevation the dozer's blade holds, set from the spawn datum and the blade angle. */
  datum = 0;
  /** Machine-scale cut. The last argument is the blade's elevation in metres. */
  sculpt: ((east: number, north: number, heading: number, width: number, edge: number) => number) | null = null;
  /** Soil the blade is holding, in m³. Used to drag the machine when the blade is full. */
  bladeLoad: (() => number) | null = null;
  /** Called when the blade is up so a pushed load can be left as a pile. */
  unload: ((east: number, north: number) => void) | null = null;

  constructor(readonly field: Field) {
    this.world = new CANNON.World({ gravity: new CANNON.Vec3(0, -9.82, 0) });
    this.world.broadphase = new CANNON.SAPBroadphase(this.world);
    this.world.allowSleep = false;
    this.data = [];
    for (let c = 0; c < field.cols; c++) {
      const column: number[] = [];
      // Cannon's local Y becomes world −Z after the ground rotation, then we shift it.
      // Store rows so world Z increases north, matching the mesh.
      for (let y = 0; y < field.rows; y++) column.push(field.heights[field.index(c, field.rows - 1 - y)] ?? 0);
      this.data.push(column);
    }
    this.shape = new CANNON.Heightfield(this.data, { elementSize: field.spacing });
    const ground = new CANNON.Body({ mass: 0 });
    ground.addShape(this.shape);
    const rotation = new CANNON.Quaternion();
    rotation.setFromEuler(-Math.PI / 2, 0, 0);
    ground.quaternion.copy(rotation);
    // The rotated field covers z from -(rows-1)*spacing to 0. Shift it so z is north.
    ground.position.set(0, 0, (field.rows - 1) * field.spacing);
    this.world.addBody(ground);
  }

  spawn(kind: RigKind, east: number, north: number): Rig {
    const spec = SPECS[kind];
    const chassis = new CANNON.Body({ mass: spec.mass });
    chassis.addShape(new CANNON.Box(new CANNON.Vec3(spec.width / 2, 0.7, spec.length / 2)), new CANNON.Vec3(0, 0.55, 0));
    const ground = this.field.sample(east, north);
    chassis.position.set(east, ground + 1.7, north);
    this.world.addBody(chassis);
    const vehicle = new CANNON.RaycastVehicle({
      chassisBody: chassis,
      indexRightAxis: 0,
      indexUpAxis: 1,
      indexForwardAxis: 2,
    });
    const halfL = spec.length / 2 - 0.6;
    const halfW = spec.width / 2 - 0.15;
    for (const [x, z, front] of [
      [-halfW, halfL, true],
      [halfW, halfL, true],
      [-halfW, -halfL, false],
      [halfW, -halfL, false],
    ] as const) {
      vehicle.addWheel({
        chassisConnectionPointLocal: new CANNON.Vec3(x, -0.15, z),
        directionLocal: new CANNON.Vec3(0, -1, 0),
        axleLocal: new CANNON.Vec3(-1, 0, 0),
        radius: 0.72,
        suspensionStiffness: spec.mass > 25_000 ? 90 : 70,
        suspensionRestLength: 0.42,
        maxSuspensionForce: spec.mass * 40,
        maxSuspensionTravel: 0.28,
        frictionSlip: kind === 'dozer' ? 1.6 : 1.35,
        dampingRelaxation: 2.4,
        dampingCompression: 4.2,
        rollInfluence: 0.08,
        customSlidingRotationalSpeed: -30,
        useCustomSlidingRotationalSpeed: true,
        isFrontWheel: front,
      });
    }
    vehicle.addToWorld(this.world);
    const rig: Rig = { kind, label: spec.label, mesh: spec.mesh, vehicle, loadM3: 0, bladeAngle: 0.45, applied: 0, loadDrag: 1 };
    this.rigs.push(rig);
    return rig;
  }

  pose(rig: Rig): { east: number; north: number; up: number; heading: number; speed: number } {
    const body = rig.vehicle.chassisBody;
    const forward = new CANNON.Vec3(0, 0, 1);
    body.quaternion.vmult(forward, forward);
    return {
      east: body.position.x,
      north: body.position.z,
      up: body.position.y,
      heading: Math.atan2(forward.x, forward.z),
      speed: rig.vehicle.currentVehicleSpeedKmHour,
    };
  }

  grade(rig: Rig): number {
    const pose = this.pose(rig);
    const here = this.surface(pose.east, pose.north);
    const ahead = this.surface(pose.east + Math.sin(pose.heading) * 14, pose.north + Math.cos(pose.heading) * 14);
    return (Math.atan2(ahead - here, 14) * 180) / Math.PI;
  }

  /** Metres the cutting edge sits below the grade. Positive cuts. It does not follow a flying chassis. */
  bladeDepth(rig: Rig): number {
    return Math.max(-1.2, Math.min(1.6, -Math.sin(rig.bladeAngle) * 1.6));
  }

  /** Run the suspension onto the heightfield before anyone drives. */
  rest(): void {
    const parked: DriveInput = { throttle: 0, steer: 0, brake: true, raise: false, lower: false, dig: false, dump: false };
    for (let i = 0; i < 40; i++) this.step(1 / 60, null, parked);
  }

  step(dt: number, active: Rig | null, input: DriveInput): void {
    this.accumulator += Math.min(dt, 0.05);
    const h = 1 / 60;
    while (this.accumulator >= h) {
      this.substep(h, active, input);
      this.accumulator -= h;
    }
    this.plant();
    if (this.field.dirty) this.syncHeights();
  }

  private substep(dt: number, active: Rig | null, input: DriveInput): void {
    for (const rig of this.rigs) {
      const drive = rig === active;
      const spec = SPECS[rig.kind];
      const pose = this.pose(rig);
      const climbing = this.grade(rig);
      let grip = 1;
      if (climbing > 30) grip = Math.max(0.08, 1 - (climbing - 30) / 8);
      if (climbing > 36) grip = 0.04;
      const target = drive ? input.throttle * spec.force * grip * rig.loadDrag : 0;
      const limited = Math.abs(pose.speed) > spec.maxKmh && input.throttle > 0 ? 0 : target;
      rig.applied += (limited - rig.applied) * (1 - Math.exp(-dt / 0.35));
      const steer = drive ? Math.max(-1, Math.min(1, input.steer)) : 0;
      const brake = !drive || input.brake ? spec.mass * 0.45 : Math.abs(input.throttle) < 0.05 ? spec.mass * 0.05 : 0;
      this.driveWheels(rig, spec, -rig.applied, steer, brake);
      if (climbing > 34 && drive) {
        const body = rig.vehicle.chassisBody;
        body.applyForce(new CANNON.Vec3(-Math.sin(pose.heading) * spec.mass * 1.4, 0, -Math.cos(pose.heading) * spec.mass * 1.4), body.position);
      }
      if (drive) this.work(rig, input, dt, pose, spec);
    }
    this.world.step(dt, undefined, 2);
  }

  private plant(): void {
    const spanE = (this.field.cols - 1) * this.field.spacing;
    const spanN = (this.field.rows - 1) * this.field.spacing;
    const margin = Math.max(8, this.field.spacing);
    for (const rig of this.rigs) {
      const body = rig.vehicle.chassisBody;
      const x = Math.max(margin, Math.min(spanE - margin, body.position.x));
      const z = Math.max(margin, Math.min(spanN - margin, body.position.z));
      const ground = this.surface(x, z);
      let y = body.position.y;
      if (y < ground + 0.8) {
        y = ground + 1.15;
        if (body.velocity.y < 0) body.velocity.y = 0;
      } else if (y > ground + 3.4) {
        y = ground + 1.8;
        body.velocity.y = 0;
        body.velocity.x *= 0.6;
        body.velocity.z *= 0.6;
      }
      const up = new CANNON.Vec3(0, 1, 0);
      body.quaternion.vmult(up, up);
      if (up.y < 0.4) {
        const forward = new CANNON.Vec3(0, 0, 1);
        body.quaternion.vmult(forward, forward);
        const heading = Math.atan2(forward.x, forward.z);
        body.quaternion.setFromEuler(0, heading, 0);
        body.angularVelocity.set(0, 0, 0);
        y = ground + 1.5;
      }
      body.position.set(x, y, z);
    }
  }

  private driveWheels(rig: Rig, spec: (typeof SPECS)[RigKind], force: number, steer: number, brake: number): void {
    const vehicle = rig.vehicle;
    if (spec.tracked) {
      const left = force * (1 + steer * 0.85);
      const right = force * (1 - steer * 0.85);
      vehicle.applyEngineForce(left, 0);
      vehicle.applyEngineForce(right, 1);
      vehicle.applyEngineForce(left, 2);
      vehicle.applyEngineForce(right, 3);
      for (let wheel = 0; wheel < 4; wheel++) vehicle.setSteeringValue(0, wheel);
    } else {
      const [inner, outer] = ackermann(steer * 0.42, spec.length * 0.72, spec.width * 0.85);
      vehicle.setSteeringValue(steer >= 0 ? outer : inner, 0);
      vehicle.setSteeringValue(steer >= 0 ? inner : outer, 1);
      vehicle.applyEngineForce(force, 2);
      vehicle.applyEngineForce(force, 3);
      vehicle.applyEngineForce(0, 0);
      vehicle.applyEngineForce(0, 1);
    }
    for (let wheel = 0; wheel < 4; wheel++) vehicle.setBrake(brake, wheel);
  }

  private work(rig: Rig, input: DriveInput, dt: number, pose: ReturnType<Yard['pose']>, spec: (typeof SPECS)[RigKind]): void {
    if (input.raise) rig.bladeAngle = Math.min(0.6, rig.bladeAngle + dt * 1.4);
    if (input.lower) rig.bladeAngle = Math.max(-0.75, rig.bladeAngle - dt * 1.4);
    const edge = this.datum + Math.sin(rig.bladeAngle) * 2.4;
    let moved = 0;
    if (rig.kind === 'dozer' && rig.bladeAngle < 0.05 && Math.abs(pose.speed) > 1) {
      const depth = Math.max(0, -Math.sin(rig.bladeAngle) * 1.15);
      if (this.sculpt) {
        moved = this.sculpt(pose.east + Math.sin(pose.heading) * (spec.length / 2 + 1.2), pose.north + Math.cos(pose.heading) * (spec.length / 2 + 1.2), pose.heading, spec.width, edge);
      } else {
        const reach = spec.length / 2 + this.field.spacing * 0.55;
        const ground = this.field.sample(pose.east + Math.sin(pose.heading) * reach, pose.north + Math.cos(pose.heading) * reach);
        const edge = ground - depth;
        if (ground > edge + 0.03) {
          planeBlade(this.field, pose.east + Math.sin(pose.heading) * reach, pose.north + Math.cos(pose.heading) * reach, pose.heading, Math.max(spec.width, this.field.spacing), edge);
        }
      }
    }
    if (rig.kind === 'dozer' && rig.bladeAngle > 0.2 && this.unload) {
      const reach = spec.length / 2 + 1.2;
      this.unload(pose.east + Math.sin(pose.heading) * reach, pose.north + Math.cos(pose.heading) * reach);
    }
    rig.loadDrag = 1;
    if (rig.bladeAngle < -0.05) rig.loadDrag *= 0.68;
    if (moved > 0.02 || (this.bladeLoad?.() ?? 0) > 6) rig.loadDrag *= 0.5;
    if (rig.kind === 'excavator' && input.dig && rig.loadM3 < 24) {
      const dug = digBucket(
        this.field,
        pose.east + Math.sin(pose.heading) * this.field.spacing,
        pose.north + Math.cos(pose.heading) * this.field.spacing,
        Math.max(6, this.field.spacing * 0.9),
        0.16 * dt,
      );
      rig.loadM3 += dug;
    }
    if (input.dump && rig.loadM3 > 0.05 && (rig.kind === 'hauler' || rig.kind === 'excavator')) {
      const placed = dumpLoad(this.field, pose.east - Math.sin(pose.heading) * 4, pose.north - Math.cos(pose.heading) * 4, rig.loadM3);
      rig.loadM3 = Math.max(0, rig.loadM3 - placed);
    }
  }

  held(): number {
    return this.rigs.reduce((sum, rig) => sum + rig.loadM3, 0);
  }

  private syncHeights(): void {
    const { cols, rows } = this.field;
    for (let c = 0; c < cols; c++) {
      const column = this.data[c];
      if (!column) continue;
      for (let y = 0; y < rows; y++) column[y] = this.field.heights[this.field.index(c, rows - 1 - y)] ?? 0;
    }
    this.shape.update();
  }

  /** Copy the field into the collision heightfield after a saved edit is restored. */
  pullHeights(): void {
    this.syncHeights();
  }

  recover(rig: Rig, east: number, north: number): void {
    const body = rig.vehicle.chassisBody;
    const ground = this.surface(east, north);
    body.position.set(east, ground + 1.6, north);
    body.velocity.set(0, 0, 0);
    body.angularVelocity.set(0, 0, 0);
    const forward = new CANNON.Vec3(0, 0, 1);
    body.quaternion.vmult(forward, forward);
    body.quaternion.setFromEuler(0, Math.atan2(forward.x, forward.z), 0);
  }
}

function ackermann(steer: number, wheelbase: number, track: number): [number, number] {
  if (Math.abs(steer) < 0.01) return [steer, steer];
  const radius = wheelbase / Math.tan(steer);
  const inner = Math.atan(wheelbase / (radius - Math.sign(steer) * track / 2));
  const outer = Math.atan(wheelbase / (radius + Math.sign(steer) * track / 2));
  return [inner, outer];
}
