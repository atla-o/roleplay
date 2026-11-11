import * as CANNON from 'cannon-es';
import type { Field } from './field';
import { digBucket, dumpLoad, pushBlade } from './sculpt';

export type RigKind = 'dozer' | 'excavator' | 'hauler';

export interface DriveInput {
  throttle: number;
  steer: number;
  brake: boolean;
  blade: number;
  dig: boolean;
  dump: boolean;
}

export interface Rig {
  kind: RigKind;
  label: string;
  mesh: string;
  vehicle: CANNON.RaycastVehicle;
  loadM3: number;
  blade: number;
}

const SPECS: Record<RigKind, { mass: number; force: number; length: number; width: number; mesh: string; label: string }> = {
  dozer: { mass: 2200, force: 4200, length: 6.4, width: 3.2, mesh: 'models/tractor-shovel.glb', label: 'Mass mover' },
  excavator: { mass: 2600, force: 2600, length: 5.4, width: 2.8, mesh: 'models/tractor.glb', label: 'Excavator' },
  hauler: { mass: 3400, force: 3800, length: 7.2, width: 3.1, mesh: 'models/garbage-truck.glb', label: 'Hauler' },
};

export class Yard {
  readonly world: CANNON.World;
  readonly rigs: Rig[] = [];
  private readonly shape: CANNON.Heightfield;
  private readonly data: number[][];

  constructor(readonly field: Field) {
    this.world = new CANNON.World({ gravity: new CANNON.Vec3(0, -9.82, 0) });
    this.world.broadphase = new CANNON.SAPBroadphase(this.world);
    this.world.allowSleep = false;
    this.data = [];
    for (let c = 0; c < field.cols; c++) {
      const column: number[] = [];
      for (let r = 0; r < field.rows; r++) column.push(field.heights[field.index(c, r)] ?? 0);
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
    chassis.addShape(new CANNON.Box(new CANNON.Vec3(spec.width / 2, 0.45, spec.length / 2)));
    const ground = this.field.sample(east, north);
    chassis.position.set(east, ground + 2.2, north);
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
        radius: 0.62,
        suspensionStiffness: 32,
        suspensionRestLength: 0.38,
        maxSuspensionForce: 120_000,
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
    const rig: Rig = { kind, label: spec.label, mesh: spec.mesh, vehicle, loadM3: 0, blade: kind === 'dozer' ? 0.15 : 0 };
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

  step(dt: number, active: Rig | null, input: DriveInput): void {
    for (const rig of this.rigs) {
      const drive = rig === active;
      const spec = SPECS[rig.kind];
      const speed = Math.abs(rig.vehicle.currentVehicleSpeedKmHour);
      const throttle = drive && speed < 42 ? input.throttle : 0;
      const force = -throttle * spec.force;
      const steer = drive ? Math.max(-0.45, Math.min(0.45, input.steer)) : 0;
      const brake = drive && input.brake ? 18 : 0;
      rig.vehicle.applyEngineForce(force, 2);
      rig.vehicle.applyEngineForce(force, 3);
      rig.vehicle.setSteeringValue(steer, 0);
      rig.vehicle.setSteeringValue(steer, 1);
      for (let wheel = 0; wheel < 4; wheel++) rig.vehicle.setBrake(brake, wheel);
      if (drive) this.work(rig, input, dt);
    }
    this.world.step(Math.min(dt, 0.05), undefined, 3);
    if (this.field.dirty) this.syncHeights();
  }

  private work(rig: Rig, input: DriveInput, dt: number): void {
    const pose = this.pose(rig);
    const spec = SPECS[rig.kind];
    if (rig.kind === 'dozer') {
      rig.blade = Math.max(0, Math.min(1.1, input.blade));
      if (rig.blade > 0.04 && Math.abs(pose.speed) > 0.4) {
        const reach = spec.length / 2 + this.field.spacing * 0.6;
        pushBlade(
          this.field,
          pose.east + Math.sin(pose.heading) * reach,
          pose.north + Math.cos(pose.heading) * reach,
          pose.heading,
          Math.max(spec.width + 1.5, this.field.spacing),
          rig.blade * dt * 0.9,
        );
      }
    }
    if (rig.kind === 'excavator' && input.dig && rig.loadM3 < 18) {
      const dug = digBucket(
        this.field,
        pose.east + Math.sin(pose.heading) * this.field.spacing,
        pose.north + Math.cos(pose.heading) * this.field.spacing,
        Math.max(6, this.field.spacing * 0.9),
        0.12 * dt,
      );
      rig.loadM3 += dug;
    }
    if (input.dump && rig.loadM3 > 0.05 && (rig.kind === 'hauler' || rig.kind === 'excavator')) {
      const placed = dumpLoad(this.field, pose.east - Math.sin(pose.heading) * 3, pose.north - Math.cos(pose.heading) * 3, rig.loadM3);
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
      for (let r = 0; r < rows; r++) column[r] = this.field.heights[this.field.index(c, r)] ?? 0;
    }
    this.shape.update();
  }
}
