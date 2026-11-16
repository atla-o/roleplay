import geneArk from '../../data/gene-ark.json';
import machines from '../../data/machines.json';
import phases from '../../data/phases.json';
import physics from '../../data/physics.json';
import type { Heightfield } from './grid';
import { solveWater, type Pond, type WaterField } from './water';
import { cutChannel, digPit, gradePad } from './works';

export interface Species {
  id: string;
  module: string;
  scientific: string;
  common: string;
  actions: string[];
  placement: string;
  moisture: string;
  requires_shelter: boolean;
  requires_bed: boolean;
  establish_days: number;
  form: string;
  color: string;
  requires_nearby?: { module: string; radius_m: number; min_growth: number }[];
}

export interface MachineSpec {
  id: string;
  stage: number;
  class: string;
  name: string;
  summary: string;
  length_m: number;
  width_m: number;
  height_m: number;
  mass_t: number;
  blade_width_m: number;
  cut_rate_m3_per_h: number;
  power_kW: number;
}

export interface MachineBody {
  uid: number;
  specId: string;
  x: number;
  z: number;
  heading: number;
  pose: 'idle' | 'work';
}

export interface Dome {
  id: number;
  x: number;
  z: number;
  radius: number;
}
export interface Bed {
  id: number;
  x: number;
  z: number;
  heading: number;
}
export interface Planting {
  id: number;
  speciesId: string;
  x: number;
  z: number;
  growth: number;
  day: number;
  action: string;
}
export interface StreetSample {
  x: number;
  z: number;
  y: number;
  bridge: boolean;
}
export interface Street {
  id: number;
  width: number;
  samples: StreetSample[];
  length: number;
  stone: number;
}
export interface Structure {
  id: number;
  kind: 'greenhouse' | 'waterworks' | 'township';
  x: number;
  z: number;
  heading: number;
  stone: number;
  length: number;
  width: number;
}

export interface Result {
  ok: boolean;
  reason?: string;
}

export interface Reading {
  elevation: number;
  measured: number;
  slope: number;
  water: number;
  moisture: string;
  thaw: string;
  stable: boolean;
  buildable: boolean;
  edited: boolean;
}

interface Snap {
  z: Float32Array;
  edited: Uint8Array;
  graded: Uint8Array;
  channel: Uint8Array;
  stone: number;
  fill: number;
  energyMJ: number;
  cutVolume: number;
  surveys: number;
  walkedM: number;
  seq: number;
  domes: Dome[];
  beds: Bed[];
  plantings: Planting[];
  streets: Street[];
  structures: Structure[];
  machines: MachineBody[];
  milestones: string[];
}

const MILESTONE_KEY = 'roleplay.creation.milestones.v1';

export class Sim {
  readonly physics = physics;
  readonly machines = machines.machines as MachineSpec[];
  readonly species = geneArk.species as Species[];
  readonly phases = phases;
  water: WaterField;
  day = 188;
  watermark = 188;
  stone = 0;
  fill = 0;
  energyMJ = 0;
  cutVolume = 0;
  surveys = 0;
  walkedM = 0;
  status = 'Measured surface. Melt is liquid inside the thaw window.';
  reading: Reading | null = null;
  initialPonded = 0;
  readonly machineBodies: MachineBody[] = [];
  readonly domes: Dome[] = [];
  readonly beds: Bed[] = [];
  readonly plantings: Planting[] = [];
  readonly streets: Street[] = [];
  readonly structures: Structure[] = [];
  readonly milestones = new Set<string>();
  private seq = 1;
  private readonly history: Snap[] = [];

  constructor(readonly field: Heightfield) {
    this.water = this.computeWater();
    this.initialPonded = this.water.ponded_m3;
    this.loadMilestones();
  }

  private computeWater(): WaterField {
    const p = this.physics;
    return solveWater(
      this.field.z,
      this.field.cols,
      this.field.rows,
      this.field.spacing,
      {
        microrelief_m: p.microrelief_m,
        meltwater_mm: p.meltwater_mm,
        melt_duration_days: p.melt_duration_days,
        detention_slope_deg: p.detention_slope_deg,
        detention_max_m: p.detention_max_m,
        capture_m: p.capture_m,
        flow_draw_min_cells: p.flow_draw_min_cells,
        stream_coeff: p.stream_coeff,
        stream_cap_m: p.stream_cap_m,
        pond_block_m: p.pond_block_m,
      },
      this.field.channel,
      this.field.graded,
    );
  }

  refreshWater(): void {
    this.water = this.computeWater();
    this.evaluate();
  }

  inMelt(day = this.day): boolean {
    return day >= this.physics.melt_window.start_doy && day <= this.physics.melt_window.end_doy;
  }

  inGrow(day = this.day): boolean {
    const start = this.physics.growing_window.start_doy;
    return day >= start && day < start + this.physics.growing_window.days;
  }

  resistance(): number {
    return this.inMelt() ? this.physics.thawed_ground_resistance : this.physics.frozen_ground_resistance;
  }

  stableSlope(): number {
    return this.inMelt() ? this.physics.thawed_stable_slope_deg : this.physics.frozen_stable_slope_deg;
  }

  spec(id: string): MachineSpec {
    const found = this.machines.find((m) => m.id === id);
    if (!found) throw new Error(`Unknown machine ${id}`);
    return found;
  }

  speciesById(id: string): Species | undefined {
    return this.species.find((s) => s.id === id);
  }

  setDay(doy: number): void {
    const next = Math.max(1, Math.min(365, Math.round(doy)));
    if (next > this.watermark) this.accrue(this.watermark, next);
    this.day = next;
    if (next > this.watermark) this.watermark = next;
    const phase = this.inMelt() ? 'Melt is liquid.' : 'The surface is frozen. Meltwater is ice.';
    const grow = this.inGrow() ? 'Growing window is open.' : 'Growing window is closed.';
    this.status = `Day ${next}. ${phase} ${grow}`;
    this.evaluate();
  }

  private accrue(from: number, to: number): void {
    for (const planting of this.plantings) {
      const spec = this.speciesById(planting.speciesId);
      if (!spec) continue;
      if (spec.requires_shelter && !this.inShelter(planting.x, planting.z)) continue;
      let days = 0;
      const start = Math.max(from, planting.day);
      for (let d = start; d < to; d++) if (this.inGrow(d)) days++;
      planting.growth = Math.min(1, planting.growth + days / spec.establish_days);
    }
  }

  canUndo(): boolean {
    return this.history.length > 0;
  }

  /** Copy the working surface before a change, so Undo can put it back. */
  remember(): void {
    this.history.push({
      z: this.field.z.slice(),
      edited: this.field.edited.slice(),
      graded: this.field.graded.slice(),
      channel: this.field.channel.slice(),
      stone: this.stone,
      fill: this.fill,
      energyMJ: this.energyMJ,
      cutVolume: this.cutVolume,
      surveys: this.surveys,
      walkedM: this.walkedM,
      seq: this.seq,
      domes: structuredClone(this.domes),
      beds: structuredClone(this.beds),
      plantings: structuredClone(this.plantings),
      streets: structuredClone(this.streets),
      structures: structuredClone(this.structures),
      machines: structuredClone(this.machineBodies),
      milestones: [...this.milestones],
    });
    if (this.history.length > 8) this.history.shift();
  }

  undo(): boolean {
    const snap = this.history.pop();
    if (!snap) {
      this.status = 'Nothing to undo.';
      return false;
    }
    this.field.z.set(snap.z);
    this.field.edited.set(snap.edited);
    this.field.graded.set(snap.graded);
    this.field.channel.set(snap.channel);
    this.stone = snap.stone;
    this.fill = snap.fill;
    this.energyMJ = snap.energyMJ;
    this.cutVolume = snap.cutVolume;
    this.surveys = snap.surveys;
    this.walkedM = snap.walkedM;
    this.seq = snap.seq;
    this.domes.splice(0, this.domes.length, ...snap.domes);
    this.beds.splice(0, this.beds.length, ...snap.beds);
    this.plantings.splice(0, this.plantings.length, ...snap.plantings);
    this.streets.splice(0, this.streets.length, ...snap.streets);
    this.structures.splice(0, this.structures.length, ...snap.structures);
    this.machineBodies.splice(0, this.machineBodies.length, ...snap.machines);
    this.milestones.clear();
    for (const id of snap.milestones) this.milestones.add(id);
    this.refreshWater();
    this.saveMilestones();
    this.status = 'Last action undone.';
    return true;
  }

  private forget(): void {
    this.history.pop();
  }

  restoreMeasured(): void {
    this.remember();
    this.field.restore();
    this.stone = 0;
    this.fill = 0;
    this.domes.splice(0);
    this.beds.splice(0);
    this.plantings.splice(0);
    this.streets.splice(0);
    this.structures.splice(0);
    this.refreshWater();
    this.status = 'Measured surface restored. Banked material is back in the ground.';
  }

  cutPolyline(points: { x: number; z: number }[], invertStart?: number, profile: 'graded' | 'ditch' = 'graded'): Result {
    if (points.length < 2) return this.fail('A line needs two points. Click the ground, then commit.');
    this.remember();
    const side = (this.physics.design_side_slope_deg * Math.PI) / 180;
    const before = this.water.ponded_m3;
    const cut = cutChannel(this.field, points, {
      depth: this.physics.channel_depth_m,
      grade: this.physics.channel_grade,
      invertWidth: this.physics.channel_invert_width_m,
      sideSlopeRad: side,
      invertStart,
      profile,
      maxCut: 1.8,
    });
    if (cut.cut_m3 < 1) {
      this.forget();
      this.status = 'That line does not lower the ground. The grade is already below the invert.';
      return { ok: false, reason: this.status };
    }
    this.bankCut(cut.cut_m3, this.physics.stone_fraction_of_cut);
    this.refreshWater();
    const spec = this.spec('mass-mover');
    const hours = (cut.cut_m3 / spec.cut_rate_m3_per_h) * this.resistance();
    const dropped = before - this.water.ponded_m3;
    this.status = `Mass Ton Mover cut ${fmt(cut.cut_m3)} m³ in ${hours.toFixed(1)} h. Standing water ${dropped > 0 ? 'down' : 'held'} ${fmt(Math.abs(dropped))} m³.`;
    this.placeMachine('mass-mover', points[Math.floor(points.length / 2)], headingOf(points), 'work');
    return { ok: true };
  }

  grade(x: number, z: number, radius = this.physics.pad_radius_m): Result {
    this.remember();
    const heading = this.downslopeHeading(x, z);
    const side = (this.physics.design_side_slope_deg * Math.PI) / 180;
    const result = gradePad(
      this.field,
      x,
      z,
      radius,
      this.physics.pad_fall,
      heading,
      side,
      this.fill,
      this.physics.fill_fraction_of_cut,
    );
    if (!result.ok) {
      this.forget();
      this.status = result.reason ?? 'The pad was not graded.';
      return { ok: false, reason: this.status };
    }
    this.stone += result.cut_m3 * this.physics.stone_fraction_of_cut;
    this.fill += result.cut_m3 * this.physics.fill_fraction_of_cut - result.fill_m3;
    if (this.fill < 0) this.fill = 0;
    this.cutVolume += result.cut_m3;
    this.energyMJ +=
      result.cut_m3 * this.physics.excavation_MJ_per_m3 * this.resistance() +
      result.fill_m3 * this.physics.place_MJ_per_m3 * this.resistance();
    this.refreshWater();
    this.placeMachine('mass-mover', { x, z }, heading, 'work');
    this.status = `Pad graded at a ${(this.physics.pad_fall * 100).toFixed(1)}% fall. Cut ${fmt(result.cut_m3)} m³, placed ${fmt(result.fill_m3)} m³.`;
    return { ok: true };
  }

  mine(x: number, z: number): Result {
    const info = this.readingAt(x, z);
    if (!info) return { ok: false, reason: 'Off the measured surface.' };
    this.remember();
    const side = (this.physics.design_side_slope_deg * Math.PI) / 180;
    const cut = digPit(this.field, x, z, this.physics.mine_radius_m, this.physics.mine_depth_m, side);
    if (cut.cut_m3 < 1) {
      this.forget();
      this.status = 'The miner finds nothing to take here.';
      return { ok: false, reason: this.status };
    }
    this.bankCut(cut.cut_m3, this.physics.mine_stone_fraction);
    this.refreshWater();
    const spec = this.spec('raw-miner');
    const hours = (cut.cut_m3 / spec.cut_rate_m3_per_h) * this.resistance();
    this.placeMachine('raw-miner', { x, z: z + 18 }, 0, 'work');
    this.status = `Raw Earth Miner banked ${fmt(cut.cut_m3)} m³ in ${hours.toFixed(1)} h. The pit can hold meltwater.`;
    return { ok: true };
  }

  survey(x: number, z: number): Result {
    const info = this.readingAt(x, z);
    if (!info) return { ok: false, reason: 'Off the measured surface.' };
    this.remember();
    this.reading = info;
    this.surveys++;
    this.placeMachine('bio-builder', { x, z }, 0.4, 'work');
    this.status = `${info.moisture} ground, slope ${info.slope.toFixed(1)}°, ${info.thaw}.`;
    this.evaluate();
    return { ok: true };
  }

  placeDome(x: number, z: number): Result {
    const radius = this.physics.dome_radius_m;
    if (!this.field.contains(x, z)) return this.fail('Off the measured surface.');
    for (let k = 0; k < 12; k++) {
      const px = x + Math.cos((k / 12) * Math.PI * 2) * radius * 0.7;
      const pz = z + Math.sin((k / 12) * Math.PI * 2) * radius * 0.7;
      const wet = this.wetReason(px, pz);
      if (wet) return this.fail(wet);
      const slope = this.slopeAt(px, pz);
      if (slope > this.physics.dome_max_slope_deg) {
        return this.fail(`Slope ${slope.toFixed(1)}° is past the shelter limit of ${this.physics.dome_max_slope_deg}°.`);
      }
    }
    if (this.stone + 1e-6 < this.physics.dome_stone_m3) {
      return this.fail(`Stone bank is short by ${fmt(this.physics.dome_stone_m3 - this.stone)} m³. Cut or mine first.`);
    }
    this.remember();
    this.stone -= this.physics.dome_stone_m3;
    this.domes.push({ id: this.seq++, x, z, radius });
    this.placeMachine('weather-manipulator', { x: x + radius + 6, z }, Math.PI, 'work');
    this.status = 'Micro-climate shelter set for the ninety-day window.';
    this.evaluate();
    return { ok: true };
  }

  placeBed(x: number, z: number): Result {
    const wet = this.wetReason(x, z);
    if (wet) return this.fail(wet);
    const slope = this.slopeAt(x, z);
    if (slope > 14) return this.fail(`Slope ${slope.toFixed(1)}° is too steep for a soil bed.`);
    this.remember();
    this.beds.push({ id: this.seq++, x, z, heading: this.downslopeHeading(x, z) });
    this.placeMachine('bio-builder', { x: x + 8, z: z + 6 }, 0.6, 'work');
    this.status = 'Living soil bed placed.';
    this.evaluate();
    return { ok: true };
  }

  deploy(speciesId: string, x: number, z: number, action: string): Result {
    const spec = this.speciesById(speciesId);
    if (!spec) return this.fail('That line is not in the catalog.');
    if (!spec.actions.includes(action)) return this.fail(`${spec.common} is not deployed that way.`);
    if (!this.inGrow()) return this.fail('The growing window is closed. This line holds until thaw.');
    const wet = this.wetReason(x, z);
    if (wet) return this.fail(wet);
    if (spec.requires_shelter && !this.inShelter(x, z)) {
      return this.fail(`${spec.common} is placed inside a shelter.`);
    }
    if (spec.requires_bed && !this.onBed(x, z)) {
      return this.fail(`${spec.common} is placed on a soil bed.`);
    }
    const moisture = this.moistureAt(x, z);
    if (spec.moisture === 'damp' && moisture !== 'damp') {
      return this.fail(`${spec.common} wants damp, drained ground.`);
    }
    for (const req of spec.requires_nearby ?? []) {
      const near = this.plantings.some((p) => {
        const other = this.speciesById(p.speciesId);
        if (!other || other.module !== req.module) return false;
        if (p.growth < req.min_growth) return false;
        return Math.hypot(p.x - x, p.z - z) <= req.radius_m;
      });
      if (!near) return this.fail(`${spec.common} waits for nearby ${req.module.replace('-', ' ')} to establish.`);
    }
    this.remember();
    this.plantings.push({
      id: this.seq++,
      speciesId,
      x,
      z,
      growth: 0.02,
      day: this.day,
      action,
    });
    this.placeMachine('ark-rig', { x: x + 9, z: z - 7 }, 0.8, 'work');
    const verb = action === 'clone' ? 'Cloned' : action === 'spawn' ? 'Spawned' : 'Cultivated';
    this.status = `${verb} ${spec.common}. Growth runs only inside the window.`;
    this.evaluate();
    return { ok: true };
  }

  buildStreet(points: { x: number; z: number }[]): Result {
    if (points.length < 2) return this.fail('A street needs two ends.');
    const samples = streetSamples(this, points, this.physics.street_width_m);
    if (!samples) return this.fail('The alignment leaves the measured surface.');
    for (const s of samples) {
      if (!s.bridge) {
        const wet = this.wetReason(s.x, s.z);
        if (wet) return this.fail(wet);
        const slope = this.slopeAt(s.x, s.z);
        const limit = (Math.atan(this.physics.road_grade_limit) * 180) / Math.PI + 1.2;
        if (slope > limit) return this.fail(`Street grade ${slope.toFixed(1)}° is past the ${Math.round(this.physics.road_grade_limit * 100)}% limit.`);
      }
    }
    let length = 0;
    let bridge = 0;
    for (let i = 1; i < samples.length; i++) {
      const step = Math.hypot(samples[i].x - samples[i - 1].x, samples[i].z - samples[i - 1].z);
      length += step;
      if (samples[i].bridge) bridge += step;
    }
    const stone = length * this.physics.street_stone_m3_per_m + bridge * this.physics.bridge_extra_stone_m3_per_m;
    if (this.stone + 1e-6 < stone) return this.fail(`Stone bank is short by ${fmt(stone - this.stone)} m³. Cut or mine first.`);
    this.remember();
    this.stone -= stone;
    this.streets.push({ id: this.seq++, width: this.physics.street_width_m, samples, length, stone });
    const mid = samples[Math.floor(samples.length / 2)];
    this.placeMachine('structure-builder', { x: mid.x + 14, z: mid.z + 10 }, headingOf(points), 'work');
    this.status = `Street laid, ${fmt(length)} m, ${bridge > 4 ? `${fmt(bridge)} m of it a bridge, ` : ''}${fmt(stone)} m³ of stone.`;
    this.evaluate();
    return { ok: true };
  }

  buildStructure(kind: Structure['kind'], x: number, z: number, heading: number): Result {
    const size = {
      greenhouse: { length: 18, width: 11, stone: this.physics.greenhouse_stone_m3, name: 'Greenhouse' },
      waterworks: { length: 16, width: 12, stone: this.physics.waterworks_stone_m3, name: 'Water works' },
      township: { length: 18, width: 16, stone: this.physics.township_stone_m3, name: 'Township module' },
    }[kind];
    const check = this.footprintOk(x, z, size.length, size.width, heading);
    if (!check.ok) return this.fail(check.reason ?? 'The module does not sit.');
    if (this.stone + 1e-6 < size.stone) return this.fail(`Stone bank is short by ${fmt(size.stone - this.stone)} m³. Cut or mine first.`);
    this.remember();
    this.stone -= size.stone;
    this.structures.push({
      id: this.seq++,
      kind,
      x,
      z,
      heading,
      stone: size.stone,
      length: size.length,
      width: size.width,
    });
    this.placeMachine('structure-builder', { x: x + 16, z: z - 12 }, heading, 'work');
    this.status = `${size.name} set with ${fmt(size.stone)} m³ of local stone.`;
    this.evaluate();
    return { ok: true };
  }

  park(specId: string, x: number, z: number, heading: number): void {
    this.placeMachine(specId, { x, z }, heading, 'work');
  }

  /** A diversion from a pond (the largest, unless an id is given), running downslope. */
  planDiversion(pondId?: number): { points: { x: number; z: number }[]; invertStart: number } | null {
    const pond = (pondId === undefined ? this.water.ponds[0] : this.water.ponds.find((p) => p.id === pondId)) ?? null;
    if (!pond) return null;
    const low = this.indexWorld(pond.low);
    const points: { x: number; z: number }[] = [{ ...low }];
    let guard = this.nearestIndex(low.x, low.z);
    const seen = new Set<number>();
    for (let step = 0; step < 900; step++) {
      seen.add(guard);
      const c = guard % this.field.cols;
      const r = (guard / this.field.cols) | 0;
      if (c <= 1 || r <= 1 || c >= this.field.cols - 2 || r >= this.field.rows - 2) break;
      let best = -1;
      let bestZ = this.field.z[guard] - 0.02;
      for (let dc = -1; dc <= 1; dc++) {
        for (let dr = -1; dr <= 1; dr++) {
          if (!dc && !dr) continue;
          const cc = c + dc;
          const rr = r + dr;
          if (cc < 0 || rr < 0 || cc >= this.field.cols || rr >= this.field.rows) continue;
          const j = this.field.idx(cc, rr);
          if (seen.has(j)) continue;
          if (this.field.z[j] < bestZ) {
            bestZ = this.field.z[j];
            best = j;
          }
        }
      }
      if (best < 0) break;
      guard = best;
      points.push(this.indexWorld(best));
    }
    const end = points[points.length - 1];
    const edge = this.nearestEdge(end.x, end.z);
    if (Math.hypot(edge.x - end.x, edge.z - end.z) > this.field.spacing * 2) points.push(edge);
    return { points, invertStart: this.field.z[pond.low] - 0.35 };
  }

  surfaceAt(x: number, z: number): { y: number; kind: 'ground' | 'street' } {
    let y = this.field.sample(x, z);
    let kind: 'ground' | 'street' = 'ground';
    for (const street of this.streets) {
      const hit = projectStreet(street, x, z);
      if (hit && hit.y >= y - 0.05) {
        y = hit.y;
        kind = 'street';
      }
    }
    return { y, kind };
  }

  blocked(x: number, z: number, fromY: number): boolean {
    if (!this.field.contains(x, z)) return true;
    const surface = this.surfaceAt(x, z);
    if (!Number.isFinite(surface.y)) return true;
    if (surface.kind === 'ground') {
      const i = this.nearestIndex(x, z);
      if (this.water.depth[i] > 0.35 || this.water.stream[i] > 0.22) return true;
      if (this.water.slope[i] > 46) return true;
      if (surface.y > fromY + 0.65) return true;
    }
    for (const structure of this.structures) {
      if (inRect(x, z, structure.x, structure.z, structure.length, structure.width, structure.heading, 0.4)) return true;
    }
    for (const body of this.machineBodies) {
      const spec = this.spec(body.specId);
      if (Math.hypot(body.x - x, body.z - z) < Math.max(2.4, spec.width_m * 0.42)) return true;
    }
    return false;
  }

  noteWalk(meters: number): void {
    if (meters <= 0) return;
    this.walkedM += meters;
    this.evaluate();
  }

  readingAt(x: number, z: number): Reading | null {
    if (!this.field.contains(x, z)) return null;
    const { c, r } = this.field.rcOf(x, z);
    const ci = clamp(Math.round(c), 0, this.field.cols - 1);
    const ri = clamp(Math.round(r), 0, this.field.rows - 1);
    const i = this.field.idx(ci, ri);
    const slope = this.water.slope[i];
    const water = this.water.depth[i];
    const moisture = this.moistureAt(x, z);
    const stable = slope <= this.stableSlope();
    const buildable = moisture !== 'ponded' && slope <= (Math.atan(this.physics.road_grade_limit) * 180) / Math.PI + 1.5;
    return {
      elevation: this.field.z[i],
      measured: this.field.z0[i],
      slope,
      water: Math.max(water, this.water.stream[i]),
      moisture,
      thaw: this.inMelt() ? 'active layer' : 'frozen',
      stable,
      buildable,
      edited: this.field.edited[i] === 1,
    };
  }

  inShelter(x: number, z: number): boolean {
    for (const dome of this.domes) {
      if (Math.hypot(dome.x - x, dome.z - z) <= dome.radius - 0.5) return true;
    }
    for (const structure of this.structures) {
      if (structure.kind !== 'greenhouse') continue;
      if (inRect(x, z, structure.x, structure.z, structure.length - 1, structure.width - 1, structure.heading, 0)) return true;
    }
    return false;
  }

  stats() {
    const street = this.streets.reduce((n, s) => n + s.length, 0);
    let grown = 0;
    let fauna = 0;
    let crop = 0;
    for (const p of this.plantings) {
      if (p.growth > 0.4) grown++;
      const spec = this.speciesById(p.speciesId);
      if (spec?.module === 'open-fauna' || spec?.module === 'soil-fauna') fauna++;
      if (spec?.module === 'shelter-crop' && p.growth >= 0.5) crop++;
    }
    return {
      day: this.day,
      ponded_m3: this.water.ponded_m3,
      ponds: this.water.ponds.length,
      input_m3: this.water.input_m3,
      runoff_m3: this.water.runoff_m3,
      pit_m3: this.water.pit_m3,
      stone_m3: this.stone,
      fill_m3: this.fill,
      energy_MJ: this.energyMJ,
      cut_m3: this.cutVolume,
      domes: this.domes.length,
      beds: this.beds.length,
      plantings: this.plantings.length,
      grown,
      fauna,
      crop,
      streets_m: street,
      structures: this.structures.map((s) => s.kind),
      walked_m: this.walkedM,
      milestones: [...this.milestones],
      resistance: this.resistance(),
      thaw: this.inMelt(),
      growing: this.inGrow(),
    };
  }

  private bankCut(volume: number, stoneFraction: number): void {
    this.stone += volume * stoneFraction;
    this.fill += volume * (1 - stoneFraction);
    this.cutVolume += volume;
    this.energyMJ += volume * this.physics.excavation_MJ_per_m3 * this.resistance();
  }

  private placeMachine(specId: string, at: { x: number; z: number }, heading: number, pose: MachineBody['pose']): void {
    let body = this.machineBodies.find((m) => m.specId === specId);
    if (!body) {
      body = { uid: this.seq++, specId, x: at.x, z: at.z, heading, pose };
      this.machineBodies.push(body);
    }
    body.x = at.x;
    body.z = at.z;
    body.heading = heading;
    body.pose = pose;
  }

  private wetReason(x: number, z: number): string | null {
    if (!this.field.contains(x, z)) return 'Off the measured surface.';
    const i = this.nearestIndex(x, z);
    if (this.water.depth[i] >= this.physics.pond_block_m) return 'Standing meltwater covers this ground.';
    if (this.water.stream[i] >= this.physics.stream_block_m) return 'A waterway runs through this ground.';
    return null;
  }

  private moistureAt(x: number, z: number): 'ponded' | 'damp' | 'dry' {
    const i = this.nearestIndex(x, z);
    if (this.water.depth[i] >= this.physics.pond_block_m || this.water.stream[i] >= this.physics.stream_block_m) return 'ponded';
    const c = i % this.field.cols;
    const r = (i / this.field.cols) | 0;
    for (let dc = -2; dc <= 2; dc++) {
      for (let dr = -2; dr <= 2; dr++) {
        const cc = c + dc;
        const rr = r + dr;
        if (cc < 0 || rr < 0 || cc >= this.field.cols || rr >= this.field.rows) continue;
        const j = this.field.idx(cc, rr);
        if (this.water.depth[j] > 0.08 || this.water.stream[j] > 0.05) return 'damp';
      }
    }
    return 'dry';
  }

  private slopeAt(x: number, z: number): number {
    return this.water.slope[this.nearestIndex(x, z)] ?? 0;
  }

  private onBed(x: number, z: number): boolean {
    return this.beds.some((b) => Math.hypot(b.x - x, b.z - z) <= 6);
  }

  private downslopeHeading(x: number, z: number): number {
    const i = this.nearestIndex(x, z);
    const c = i % this.field.cols;
    const r = (i / this.field.cols) | 0;
    let best = this.field.z[i];
    let heading = 0;
    for (let dc = -2; dc <= 2; dc++) {
      for (let dr = -2; dr <= 2; dr++) {
        if (!dc && !dr) continue;
        const cc = c + dc;
        const rr = r + dr;
        if (cc < 0 || rr < 0 || cc >= this.field.cols || rr >= this.field.rows) continue;
        const h = this.field.z[this.field.idx(cc, rr)];
        if (h < best) {
          best = h;
          const p = this.field.worldOf(cc, rr);
          heading = Math.atan2(p.x - x, p.z - z);
        }
      }
    }
    return heading;
  }

  private footprintOk(x: number, z: number, length: number, width: number, heading: number): Result {
    const pts = [
      [0, 0],
      [length * 0.45, width * 0.4],
      [-length * 0.45, width * 0.4],
      [length * 0.45, -width * 0.4],
      [-length * 0.45, -width * 0.4],
    ];
    const cos = Math.cos(heading);
    const sin = Math.sin(heading);
    let minH = Infinity;
    let maxH = -Infinity;
    for (const [lx, lz] of pts) {
      const wx = x + lx * sin + lz * cos;
      const wz = z + lx * cos - lz * sin;
      const wet = this.wetReason(wx, wz);
      if (wet) return { ok: false, reason: wet };
      const h = this.field.sample(wx, wz);
      if (!Number.isFinite(h)) return { ok: false, reason: 'The module leaves the measured surface.' };
      minH = Math.min(minH, h);
      maxH = Math.max(maxH, h);
    }
    if (maxH - minH > 0.95) return { ok: false, reason: 'This ground is not flat enough. Grade a pad first.' };
    const slope = this.slopeAt(x, z);
    const limit = (Math.atan(this.physics.road_grade_limit) * 180) / Math.PI + 2;
    if (slope > limit) return { ok: false, reason: `Slope ${slope.toFixed(1)}° is past the grade limit.` };
    return { ok: true };
  }

  private nearestEdge(x: number, z: number): { x: number; z: number } {
    const dWest = x;
    const dEast = this.field.width - x;
    const dSouth = z;
    const dNorth = this.field.height - z;
    const m = Math.min(dWest, dEast, dSouth, dNorth);
    if (m === dWest) return { x: 0, z };
    if (m === dEast) return { x: this.field.width, z };
    if (m === dSouth) return { x, z: 0 };
    return { x, z: this.field.height };
  }

  private nearestIndex(x: number, z: number): number {
    const { c, r } = this.field.rcOf(x, z);
    const ci = clamp(Math.round(c), 0, this.field.cols - 1);
    const ri = clamp(Math.round(r), 0, this.field.rows - 1);
    return this.field.idx(ci, ri);
  }

  private indexWorld(i: number): { x: number; z: number } {
    return this.field.worldOf(i % this.field.cols, (i / this.field.cols) | 0);
  }

  private fail(reason: string): Result {
    this.status = reason;
    return { ok: false, reason };
  }

  private evaluate(): void {
    const before = this.milestones.size;
    const street = this.streets.reduce((n, s) => n + s.length, 0);
    const crop = this.plantings.some((p) => {
      const spec = this.speciesById(p.speciesId);
      return spec?.module === 'shelter-crop' && p.growth >= 0.5;
    });
    const checks: Record<string, boolean> = {
      'channel-cut': this.cutVolume > 80,
      'ponds-drained': this.cutVolume > 80 && this.initialPonded - this.water.ponded_m3 > 800,
      'stone-banked': this.stone > 80 || this.cutVolume > 200,
      'pad-graded': this.field.graded.some((v) => v === 1),
      survey: this.surveys > 0,
      dome: this.domes.length > 0,
      'soil-bed': this.beds.length > 0,
      cultivated: this.plantings.length > 0,
      grown: this.plantings.some((p) => p.growth > 0.4),
      fauna: this.plantings.some((p) => {
        const spec = this.speciesById(p.speciesId);
        return spec?.module === 'open-fauna' || spec?.module === 'soil-fauna';
      }),
      street: street > 40,
      greenhouse: this.structures.some((s) => s.kind === 'greenhouse'),
      waterworks: this.structures.some((s) => s.kind === 'waterworks'),
      township: this.structures.some((s) => s.kind === 'township'),
      walked: this.walkedM > 25,
      'settlement-ready':
        this.structures.some((s) => s.kind === 'waterworks') &&
        this.structures.some((s) => s.kind === 'township') &&
        crop &&
        street > 40 &&
        this.walkedM > 20,
    };
    for (const milestone of this.phases.milestones) {
      if (checks[milestone.id]) this.milestones.add(milestone.id);
    }
    if (this.milestones.size !== before) this.saveMilestones();
  }

  private loadMilestones(): void {
    try {
      const raw = localStorage.getItem(MILESTONE_KEY);
      if (!raw) return;
      const ids = JSON.parse(raw) as string[];
      for (const id of ids) this.milestones.add(id);
    } catch {
      /* private window or blocked storage */
    }
  }

  private saveMilestones(): void {
    try {
      localStorage.setItem(MILESTONE_KEY, JSON.stringify([...this.milestones]));
    } catch {
      /* ignore quota */
    }
  }
}

function streetSamples(sim: Sim, points: { x: number; z: number }[], _width: number): StreetSample[] | null {
  const raw: { x: number; z: number; ground: number }[] = [];
  for (let i = 1; i < points.length; i++) {
    const a = points[i - 1];
    const b = points[i];
    const len = Math.hypot(b.x - a.x, b.z - a.z);
    const n = Math.max(1, Math.ceil(len / 2));
    for (let s = i === 1 ? 0 : 1; s <= n; s++) {
      const t = s / n;
      const x = a.x + (b.x - a.x) * t;
      const z = a.z + (b.z - a.z) * t;
      const ground = sim.field.sample(x, z);
      if (!Number.isFinite(ground)) return null;
      raw.push({ x, z, ground });
    }
  }
  const deck = raw.map((s) => s.ground);
  const bridge = raw.map(() => false);
  const radius = 18;
  for (let i = 0; i < raw.length; i++) {
    const left = raw[Math.max(0, i - radius)].ground;
    const right = raw[Math.min(raw.length - 1, i + radius)].ground;
    if (raw[i].ground < left - 0.55 && raw[i].ground < right - 0.55) {
      const i0 = Math.max(0, i - radius);
      const i1 = Math.min(raw.length - 1, i + radius);
      const t = (i - i0) / Math.max(1, i1 - i0);
      deck[i] = left + (right - left) * t;
      bridge[i] = true;
    }
  }
  return raw.map((s, i) => ({
    x: s.x,
    z: s.z,
    y: Math.max(deck[i], s.ground) + (bridge[i] ? 0.35 : 0.1),
    bridge: bridge[i],
  }));
}

function projectStreet(street: Street, x: number, z: number): { y: number; across: number } | null {
  let best = Infinity;
  let y = 0;
  for (let i = 1; i < street.samples.length; i++) {
    const a = street.samples[i - 1];
    const b = street.samples[i];
    const dx = b.x - a.x;
    const dz = b.z - a.z;
    const len2 = dx * dx + dz * dz || 1;
    let t = ((x - a.x) * dx + (z - a.z) * dz) / len2;
    t = Math.max(0, Math.min(1, t));
    const px = a.x + dx * t;
    const pz = a.z + dz * t;
    const across = Math.hypot(x - px, z - pz);
    if (across < best) {
      best = across;
      y = a.y + (b.y - a.y) * t;
    }
  }
  if (best > street.width * 0.5) return null;
  return { y, across: best };
}

function inRect(
  x: number,
  z: number,
  cx: number,
  cz: number,
  length: number,
  width: number,
  heading: number,
  pad: number,
): boolean {
  const dx = x - cx;
  const dz = z - cz;
  const sin = Math.sin(heading);
  const cos = Math.cos(heading);
  const lx = dx * sin + dz * cos;
  const lz = dx * cos - dz * sin;
  return Math.abs(lx) <= length / 2 + pad && Math.abs(lz) <= width / 2 + pad;
}

function headingOf(points: { x: number; z: number }[]): number {
  if (points.length < 2) return 0;
  const a = points[0];
  const b = points[points.length - 1];
  return Math.atan2(b.x - a.x, b.z - a.z);
}

function fmt(n: number): string {
  return n.toLocaleString('en-US', { maximumFractionDigits: 0 });
}

function clamp(v: number, lo: number, hi: number): number {
  return Math.max(lo, Math.min(hi, v));
}

export type { Pond };
