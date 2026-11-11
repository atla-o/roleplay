import { readFileSync } from 'fs';
import { decodeGrayPng } from '../src/load/png';
import { Field, resampleNorthUp } from '../src/drive/field';
import { Detail } from '../src/drive/detail';
import { BERM, DRAIN, PAD, Play, RING_POINTS } from '../src/drive/play';

async function main(): Promise<void> {
  const meta = JSON.parse(readFileSync('public/data/terrain.json', 'utf8')) as { elevation_m: { min: number; max: number } };
  const buf = readFileSync('public/data/height.png');
  const png = await decodeGrayPng(buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength));
  const { min, max } = meta.elevation_m;
  const heights = resampleNorthUp(png.samples, png.width, png.height, 121, 121, (sample) => min + (sample / 65535) * (max - min));
  const field = new Field(121, 121, 4000 / 120, heights);
  const play = new Play(field);
  play.guide = 3;
  const detail = new Detail(field);
  detail.follow(PAD.e + 20, PAD.n + 20);
  const live = (e: number, n: number) => detail.cell(e, n) ?? field.sample(e, n);
  const south = live(PAD.e + 20, PAD.n + 2);
  const north = live(PAD.e + 20, PAD.n + PAD.size - 2);
  const heading = north > south ? Math.PI : 0;
  for (let pass = 0; pass < 3; pass++) {
    for (const x of [0.6, 3.5, 6.5, 9.5, 12.5, 15.5, 18.5, 21.5, 24.5, 27.5, 30.5, 33.5, 36.5, 39.2]) {
      for (let s = -1; s <= PAD.size + 4; s += 0.4) {
        const along = heading === 0 ? s : PAD.size - s;
        detail.grade(PAD.e + x, PAD.n + along, heading, 4.2, play.padTarget);
      }
    }
    for (let x = -1; x <= PAD.size + 1; x += 0.4) detail.grade(PAD.e + x, PAD.n + 1.2, Math.PI / 2, 4.2, play.padTarget);
    for (let x = PAD.size + 1; x >= -1; x -= 0.4) detail.grade(PAD.e + x, PAD.n + PAD.size - 1.2, -Math.PI / 2, 4.2, play.padTarget);
  }
  let guard = 0;
  while (play.jobs['polar-desert-basin']!.pad.progress < 1 && guard < 80) {
    play.tick('polar-desert-basin', 0.05, live, (e, n) => field.sampleBase(e, n), null, field.cutM3, 100);
    guard += 1;
  }
  const pad = play.jobs['polar-desert-basin']!.pad;
  if (!pad.done) {
    const misses: string[] = [];
    for (let y = 0; y < PAD.size; y++) {
      for (let x = 0; x < PAD.size; x++) {
        const h = live(PAD.e + x + 0.5, PAD.n + y + 0.5);
        const d = h - play.padTarget;
        if (Math.abs(d) > 0.3) misses.push(`${x},${y}:${d.toFixed(2)}`);
      }
    }
    throw new Error(`pad not finished, progress ${pad.progress} misses ${misses.slice(0, 12).join(' ')}`);
  }
  if (Math.abs(field.cutM3 - field.fillM3 - detail.carry) > 0.05) throw new Error(`pad did not conserve soil (cut ${field.cutM3} fill ${field.fillM3} carry ${detail.carry})`);

  const drop = Math.hypot(DRAIN.b.e - DRAIN.a.e, DRAIN.b.n - DRAIN.a.n);
  const steps = Math.ceil(drop);
  const mouth = live(DRAIN.a.e, DRAIN.a.n);
  for (let pass = 0; pass < 14; pass++) {
    for (let i = 0; i <= steps; i++) {
      const t = i / steps;
      const edge = mouth - drop * 0.015 * t - 0.08;
      const e = DRAIN.a.e + (DRAIN.b.e - DRAIN.a.e) * t;
      const n = DRAIN.a.n + (DRAIN.b.n - DRAIN.a.n) * t;
      detail.grade(e, n, Math.PI, 2.4, edge);
    }
  }
  guard = 0;
  while (!play.jobs['polar-desert-basin']!.drain.done && guard < 40) {
    play.tick('polar-desert-basin', 0.05, live, (e, n) => field.sampleBase(e, n), null, field.cutM3, 80);
    guard += 1;
  }
  if (!play.jobs['polar-desert-basin']!.drain.done) {
    const bad: string[] = [];
    for (let i = 0; i < steps; i++) {
      const h0 = live(DRAIN.a.e, DRAIN.a.n + (DRAIN.b.n - DRAIN.a.n) * (i / steps));
      const h1 = live(DRAIN.a.e, DRAIN.a.n + (DRAIN.b.n - DRAIN.a.n) * ((i + 1) / steps));
      const delta = h0 - h1;
      if (delta < 0.008) bad.push(`${i}:${delta.toFixed(3)}`);
    }
    throw new Error(`drain not finished, progress ${play.jobs['polar-desert-basin']!.drain.progress} ${bad.slice(0, 8).join(' ')}`);
  }

  for (let pass = 0; pass < 10; pass++) {
    for (let i = 0; i <= 32; i++) {
      const t = i / 32;
      const e = BERM.a.e + (BERM.b.e - BERM.a.e) * t;
      const n = BERM.a.n + (BERM.b.n - BERM.a.n) * t;
      detail.grade(e - 3.4, n, 0, 2.4, field.sampleBase(e - 3.4, n) - 3);
      if (detail.carry > 5) detail.release(e, n, 5);
    }
  }
  guard = 0;
  while (!play.jobs['polar-desert-basin']!.berm.done && guard < 40) {
    play.tick('polar-desert-basin', 0.05, live, (e, n) => field.sampleBase(e, n), null, field.cutM3, 40);
    guard += 1;
  }
  if (!play.jobs['polar-desert-basin']!.berm.done) throw new Error(`berm not finished, progress ${play.jobs['polar-desert-basin']!.berm.progress}`);

  const ring = new Field(20, 20, 10, new Float32Array(400).fill(100));
  const survey = new Play(field);
  survey.guide = 3;
  for (const point of RING_POINTS) {
    survey.tick('rene-levasseur', 0.1, () => 100, () => 100, { e: point.e, n: point.n }, 0, 10);
  }
  if (!survey.jobs['rene-levasseur']!.survey.done) throw new Error('survey did not complete');
  void ring;
  console.log('play-check ok', { pad: pad.moved.toFixed(1), target: play.padTarget.toFixed(2) });
}

main();
