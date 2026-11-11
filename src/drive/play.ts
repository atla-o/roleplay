import * as Cesium from 'cesium';
import type { Field } from './field';
import { offsetDegrees } from './field';

/** Where the basin work is, in metres on that site's heightfield. The pad is the flattest ground that still needs a pass. */
export const BASIN_DEPOT = { e: 1660, n: 2010 };
export const PAD = { e: 1660, n: 2060, size: 40 };
export const DRAIN = { a: { e: 1560, n: 2080 }, b: { e: 1560, n: 2030 } };
export const BERM = { a: { e: 1748, n: 2064 }, b: { e: 1748, n: 2096 } };
export const RING_POINTS = [
  { e: 1400, n: 2500, name: 'North stake' },
  { e: 2700, n: 2100, name: 'East stake' },
  { e: 1900, n: 1300, name: 'South stake' },
];
export const FUEL_MAX = 160;

export type JobId = 'pad' | 'drain' | 'berm' | 'survey';

export interface JobStat {
  done: boolean;
  progress: number;
  seconds: number;
  moved: number;
  fuel: number;
}

export interface FineSave {
  originE: number;
  originN: number;
  cells: { i: number; h: number }[];
}

export interface SaveData {
  v: 1;
  guide: number;
  fuel: { basin: number; ring: number };
  jobs: Record<string, Partial<Record<JobId, JobStat>>>;
  edits: Record<string, { i: number; h: number }[]>;
  fine?: Record<string, FineSave>;
}

const KEY = 'roleplay-play-v1';

export function loadSave(): SaveData | null {
  try {
    const raw = localStorage.getItem(KEY);
    if (!raw) return null;
    const data = JSON.parse(raw) as SaveData;
    if (data.v !== 1) return null;
    return data;
  } catch {
    return null;
  }
}

export function writeSave(data: SaveData): void {
  try {
    localStorage.setItem(KEY, JSON.stringify(data));
  } catch {
    /* private mode or a full disk */
  }
}

export function editsOf(field: Field): { i: number; h: number }[] {
  const out: { i: number; h: number }[] = [];
  for (let i = 0; i < field.heights.length; i++) {
    const h = field.heights[i] ?? 0;
    if (Math.abs(h - (field.base[i] ?? 0)) > 0.02) out.push({ i, h });
  }
  return out;
}

export function applyEdits(field: Field, edits: { i: number; h: number }[] | undefined): void {
  if (!edits) return;
  for (const edit of edits) {
    if (edit.i >= 0 && edit.i < field.heights.length) field.heights[edit.i] = edit.h;
  }
  field.touchAll();
}

/** Cells the blade has changed, compared with the measured ground, so a reload can put them back. */
export function fineOf(detail: { size: number; originE: number; originN: number; heights: Float32Array; field: Field }): FineSave | null {
  const cells: { i: number; h: number }[] = [];
  for (let i = 0; i < detail.heights.length; i++) {
    const h = detail.heights[i] ?? 0;
    const c = i % detail.size;
    const r = (i / detail.size) | 0;
    const original = detail.field.sampleBase(detail.originE + c + 0.5, detail.originN + r + 0.5);
    if (Math.abs(h - original) > 0.03) cells.push({ i, h });
  }
  if (!cells.length) return null;
  return { originE: detail.originE, originN: detail.originN, cells };
}

function meanPad(field: Field): number {
  let sum = 0;
  let n = 0;
  for (let y = 0; y < PAD.size; y++) {
    for (let x = 0; x < PAD.size; x++) {
      sum += field.sampleBase(PAD.e + x + 0.5, PAD.n + y + 0.5);
      n += 1;
    }
  }
  return sum / n;
}

export class Play {
  readonly padTarget: number;
  guide = 0;
  fuel = { basin: FUEL_MAX, ring: FUEL_MAX };
  readonly jobs: Record<string, Record<JobId, JobStat>> = {
    'polar-desert-basin': {
      pad: blank(),
      drain: blank(),
      berm: blank(),
      survey: blank(),
    },
    'rene-levasseur': {
      pad: blank(),
      drain: blank(),
      berm: blank(),
      survey: blank(),
    },
  };
  private padSeen = new Uint8Array(PAD.size * PAD.size);
  private padHits = 0;
  private padCursor = 0;
  private drainCursor = 0;
  private drainOk = 0;
  private drainCount = 0;
  private drainScore = 0;
  private bermCursor = 0;
  private bermOk = 0;
  private bermCount = 0;
  private bermScore = 0;
  private readonly visited = [false, false, false];
  private readonly memory = new Map<string, number>();
  private fuelSeen = { basin: FUEL_MAX, ring: FUEL_MAX };
  private readonly markEntities: Cesium.Entity[] = [];
  banner = '';
  private bannerUntil = 0;

  constructor(basin: Field) {
    this.padTarget = meanPad(basin);
    this.drainCount = Math.ceil(Math.hypot(DRAIN.b.e - DRAIN.a.e, DRAIN.b.n - DRAIN.a.n));
    this.bermCount = Math.ceil(Math.hypot(BERM.b.e - BERM.a.e, BERM.b.n - BERM.a.n));
  }

  restore(data: SaveData | null): void {
    if (!data) return;
    this.guide = data.guide ?? 0;
    if (data.fuel) {
      this.fuel = { basin: data.fuel.basin ?? FUEL_MAX, ring: data.fuel.ring ?? FUEL_MAX };
      this.fuelSeen = { ...this.fuel };
    }
    for (const site of Object.keys(this.jobs)) {
      const saved = data.jobs?.[site];
      if (!saved) continue;
      for (const id of Object.keys(this.jobs[site]!) as JobId[]) {
        const row = saved[id];
        if (row) this.jobs[site]![id] = { ...this.jobs[site]![id]!, ...row };
      }
    }
  }

  snapshot(basin: Field, ring: Field, fine?: Record<string, FineSave>): SaveData {
    return {
      v: 1,
      guide: this.guide,
      fuel: this.fuel,
      jobs: this.jobs,
      edits: {
        'polar-desert-basin': editsOf(basin),
        'rene-levasseur': editsOf(ring),
      },
      fine,
    };
  }

  guideText(): string {
    if (this.guide <= 0) return 'The mass mover is in front of you. Hold E to get in.';
    if (this.guide === 1) return 'W drives forward, S reverses, A and D steer. Roll a few metres.';
    if (this.guide === 2) return 'F lowers the blade, R raises it. The number is the edge elevation. Match the stake, then the first job starts.';
    return '';
  }

  /** A few cells per call. Returns a job that just finished, if one did. */
  tick(
    site: string,
    dt: number,
    live: (e: number, n: number) => number,
    original: (e: number, n: number) => number,
    pose: { e: number; n: number } | null,
    moved: number,
    fuelLeft: number,
  ): JobStat & { id: JobId; title: string } | null {
    if (this.guide < 3) return null;
    const table = this.jobs[site];
    if (!table) return null;
    const order: JobId[] = site === 'rene-levasseur' ? ['survey'] : ['pad', 'drain', 'berm'];
    const current = order.find((id) => !table[id].done);
    if (!current) return null;
    const job = table[current];
    if (job.seconds === 0 && job.progress === 0) job.moved = moved;
    const tank = site === 'rene-levasseur' ? 'ring' : 'basin';
    const burned = this.fuelSeen[tank] - fuelLeft;
    if (burned > 0) job.fuel += burned;
    this.fuelSeen[tank] = fuelLeft;
    job.seconds += dt;
    if (current === 'pad') this.scanPad(site, live);
    if (current === 'drain') this.scanDrain(site, live);
    if (current === 'berm') this.scanBerm(site, live, original);
    if (current === 'survey' && pose) this.scanSurvey(pose);
    job.progress = this.progress(current);
    if (job.progress < 1) return null;
    job.done = true;
    job.moved = Math.max(0, moved - job.moved);
    this.banner = `${titleOf(current)} complete. ${formatTime(job.seconds)} · ${job.moved.toFixed(0)} m³ moved · ${job.fuel.toFixed(0)} fuel used`;
    this.bannerUntil = performance.now() + 7000;
    return { ...job, id: current, title: titleOf(current) };
  }

  reset(site: string): void {
    const order: JobId[] = site === 'rene-levasseur' ? ['survey'] : ['pad', 'drain', 'berm'];
    for (const id of order) this.jobs[site]![id] = { done: false, progress: 0, seconds: 0, moved: 0, fuel: 0 };
    if (site === 'polar-desert-basin') {
      this.padSeen.fill(0);
      this.padHits = 0;
      this.padCursor = 0;
      this.drainScore = 0;
      this.drainCursor = 0;
      this.drainOk = 0;
      this.bermScore = 0;
      this.bermCursor = 0;
      this.bermOk = 0;
      this.fuel.basin = FUEL_MAX;
      this.fuelSeen.basin = FUEL_MAX;
      for (const key of this.memory.keys()) if (key.startsWith('polar-desert-basin:')) this.memory.delete(key);
    } else {
      this.visited[0] = false;
      this.visited[1] = false;
      this.visited[2] = false;
      this.fuel.ring = FUEL_MAX;
      this.fuelSeen.ring = FUEL_MAX;
    }
    this.banner = '';
    this.bannerUntil = 0;
  }

  bannerOn(): boolean {
    return performance.now() < this.bannerUntil;
  }

  mount(viewer: Cesium.Viewer, basin: { west: number; south: number }, ring: { west: number; south: number }, basinH: number, ringH: (e: number, n: number) => number): void {
    const stake = (west: number, south: number, e: number, n: number, h: number, text: string, color: string) => {
      const ll = offsetDegrees(south, west, e, n);
      this.markEntities.push(viewer.entities.add({
        position: Cesium.Cartesian3.fromDegrees(ll.lon, ll.lat, h + 2.2),
        point: { pixelSize: 10, color: Cesium.Color.fromCssColorString(color), disableDepthTestDistance: Number.POSITIVE_INFINITY },
        label: {
          text,
          font: '600 13px Instrument Sans, sans-serif',
          fillColor: Cesium.Color.WHITE,
          outlineColor: Cesium.Color.fromCssColorString('#121416'),
          outlineWidth: 3,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          pixelOffset: new Cesium.Cartesian2(0, -18),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
      }));
    };
    const line = (west: number, south: number, points: { e: number; n: number; h: number }[], color: string) => {
      this.markEntities.push(viewer.entities.add({
        polyline: {
          positions: points.map((p) => {
            const ll = offsetDegrees(south, west, p.e, p.n);
            return Cesium.Cartesian3.fromDegrees(ll.lon, ll.lat, p.h);
          }),
          width: 3,
          material: Cesium.Color.fromCssColorString(color),
          arcType: Cesium.ArcType.NONE,
        },
      }));
    };
    const padH = this.padTarget + 0.4;
    line(basin.west, basin.south, [
      { e: PAD.e, n: PAD.n, h: padH },
      { e: PAD.e + PAD.size, n: PAD.n, h: padH },
      { e: PAD.e + PAD.size, n: PAD.n + PAD.size, h: padH },
      { e: PAD.e, n: PAD.n + PAD.size, h: padH },
      { e: PAD.e, n: PAD.n, h: padH },
    ], '#f4f7f8');
    stake(basin.west, basin.south, PAD.e + 2, PAD.n + 2, this.padTarget, `Pad ${this.padTarget.toFixed(1)} m`, '#f4f7f8');
    stake(basin.west, basin.south, DRAIN.a.e, DRAIN.a.n, basinH, 'A', '#9fd4c4');
    stake(basin.west, basin.south, DRAIN.b.e, DRAIN.b.n, basinH, 'B', '#9fd4c4');
    line(basin.west, basin.south, [
      { e: DRAIN.a.e, n: DRAIN.a.n, h: basinH + 1 },
      { e: DRAIN.b.e, n: DRAIN.b.n, h: basinH + 1 },
    ], '#9fd4c4');
    line(basin.west, basin.south, [
      { e: BERM.a.e, n: BERM.a.n, h: basinH + 1 },
      { e: BERM.b.e, n: BERM.b.n, h: basinH + 1 },
    ], '#e2b15a');
    stake(basin.west, basin.south, BERM.a.e, BERM.a.n, basinH, 'Berm +2 m', '#e2b15a');
    stake(basin.west, basin.south, BASIN_DEPOT.e + 12, BASIN_DEPOT.n - 16, basinH, 'Fuel', '#d7dbe0');
    for (const point of RING_POINTS) {
      stake(ring.west, ring.south, point.e, point.n, ringH(point.e, point.n), point.name, '#f4f7f8');
    }
  }

  /** Last 1 m reading for each checked cell, so a sliding window does not forget finished ground. */
  remember(site: string, detail: { cell: (e: number, n: number) => number | null }): void {
    if (site !== 'polar-desert-basin') return;
    const keep = (e: number, n: number) => {
      const h = detail.cell(e, n);
      if (h != null) this.memory.set(`${site}:${e.toFixed(1)}:${n.toFixed(1)}`, h);
    };
    for (let y = 0; y < PAD.size; y++) for (let x = 0; x < PAD.size; x++) keep(PAD.e + x + 0.5, PAD.n + y + 0.5);
    const span = Math.hypot(DRAIN.b.e - DRAIN.a.e, DRAIN.b.n - DRAIN.a.n);
    for (let i = 0; i <= span; i++) {
      const t = i / span;
      keep(DRAIN.a.e + (DRAIN.b.e - DRAIN.a.e) * t, DRAIN.a.n + (DRAIN.b.n - DRAIN.a.n) * t);
    }
    const berm = Math.hypot(BERM.b.e - BERM.a.e, BERM.b.n - BERM.a.n);
    for (let i = 0; i <= berm; i++) {
      const t = berm <= 0 ? 0 : i / berm;
      keep(BERM.a.e + (BERM.b.e - BERM.a.e) * t, BERM.a.n + (BERM.b.n - BERM.a.n) * t);
    }
  }

  paintMemory(site: string, detail: { writeCell: (e: number, n: number, h: number) => void }): void {
    const prefix = `${site}:`;
    for (const [key, h] of this.memory) {
      if (!key.startsWith(prefix)) continue;
      const parts = key.slice(prefix.length).split(':');
      detail.writeCell(Number(parts[0]), Number(parts[1]), h);
    }
  }

  private recall(site: string, e: number, n: number, live: (e: number, n: number) => number): number | null {
    const key = `${site}:${e.toFixed(1)}:${n.toFixed(1)}`;
    const h = live(e, n);
    if (Number.isFinite(h)) {
      this.memory.set(key, h);
      return h;
    }
    return this.memory.get(key) ?? null;
  }

  private scanPad(site: string, live: (e: number, n: number) => number): void {
    const total = PAD.size * PAD.size;
    for (let n = 0; n < 40; n++) {
      const i = this.padCursor;
      const x = i % PAD.size;
      const y = (i / PAD.size) | 0;
      const h = this.recall(site, PAD.e + x + 0.5, PAD.n + y + 0.5, live);
      if (h == null) {
        this.padCursor = (i + 1) % total;
        continue;
      }
      const ok = Math.abs(h - this.padTarget) <= 0.3 ? 1 : 0;
      if (ok && !this.padSeen[i]) this.padHits += 1;
      if (!ok && this.padSeen[i]) this.padHits -= 1;
      this.padSeen[i] = ok;
      this.padCursor = (i + 1) % total;
    }
  }

  private scanDrain(site: string, live: (e: number, n: number) => number): void {
    const len = this.drainCount;
    const reach = 4;
    const windows = Math.max(1, Math.ceil(len / reach));
    if (this.drainCursor === 0) this.drainOk = 0;
    const steps = Math.min(2, windows - this.drainCursor);
    const span = Math.hypot(DRAIN.b.e - DRAIN.a.e, DRAIN.b.n - DRAIN.a.n);
    for (let s = 0; s < steps; s++) {
      const i1 = Math.min(len, (this.drainCursor + 1) * reach);
      const i0 = Math.max(0, i1 - reach);
      const h0 = this.recall(site, DRAIN.a.e + (DRAIN.b.e - DRAIN.a.e) * (i0 / len), DRAIN.a.n + (DRAIN.b.n - DRAIN.a.n) * (i0 / len), live);
      const h1 = this.recall(site, DRAIN.a.e + (DRAIN.b.e - DRAIN.a.e) * (i1 / len), DRAIN.a.n + (DRAIN.b.n - DRAIN.a.n) * (i1 / len), live);
      if (h0 == null || h1 == null) {
        this.drainCursor += 1;
        continue;
      }
      const dist = span * ((i1 - i0) / len);
      if (h0 - h1 >= dist * 0.01 - 0.002) this.drainOk += 1;
      this.drainCursor += 1;
    }
    if (this.drainCursor >= windows) {
      this.drainScore = this.drainOk / windows;
      this.drainCursor = 0;
      this.drainOk = 0;
    }
  }

  private scanBerm(site: string, live: (e: number, n: number) => number, original: (e: number, n: number) => number): void {
    const len = this.bermCount;
    if (this.bermCursor === 0) this.bermOk = 0;
    const steps = Math.min(6, len - this.bermCursor);
    for (let s = 0; s < steps; s++) {
      const t = len <= 1 ? 0 : this.bermCursor / (len - 1);
      const e = BERM.a.e + (BERM.b.e - BERM.a.e) * t;
      const n = BERM.a.n + (BERM.b.n - BERM.a.n) * t;
      const h = this.recall(site, e, n, live);
      if (h != null && h - original(e, n) >= 2) this.bermOk += 1;
      this.bermCursor += 1;
    }
    if (this.bermCursor >= len) {
      this.bermScore = this.bermOk / len;
      this.bermCursor = 0;
      this.bermOk = 0;
    }
  }

  checkSurvey(e: number, n: number): { progress: number; dist: number[] } {
    this.scanSurvey({ e, n });
    return {
      progress: this.progress('survey'),
      dist: RING_POINTS.map((point) => Math.hypot(e - point.e, n - point.n)),
    };
  }

  private scanSurvey(pose: { e: number; n: number }): void {
    RING_POINTS.forEach((point, i) => {
      if (Math.hypot(pose.e - point.e, pose.n - point.n) < 14) this.visited[i] = true;
    });
  }

  private progress(id: JobId): number {
    if (id === 'pad') return this.padHits / (PAD.size * PAD.size);
    if (id === 'drain') return this.drainScore;
    if (id === 'berm') return this.bermScore;
    return this.visited.filter(Boolean).length / this.visited.length;
  }
}

function blank(): JobStat {
  return { done: false, progress: 0, seconds: 0, moved: 0, fuel: 0 };
}

function titleOf(id: JobId): string {
  if (id === 'pad') return 'Grade the pad';
  if (id === 'drain') return 'Cut the drain';
  if (id === 'berm') return 'Push the berm';
  return 'Ring survey';
}

function formatTime(seconds: number): string {
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${m}:${s.toString().padStart(2, '0')}`;
}

export function jobRows(site: string, play: Play): { id: JobId; title: string; stat: JobStat }[] {
  const order: JobId[] = site === 'rene-levasseur' ? ['survey'] : ['pad', 'drain', 'berm'];
  return order.map((id) => ({ id, title: titleOf(id), stat: play.jobs[site]![id] }));
}
