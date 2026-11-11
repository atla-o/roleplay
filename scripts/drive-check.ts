import { Field } from '../src/drive/field';
import { digBucket, dumpLoad, pushBlade } from '../src/drive/sculpt';

function assert(cond: unknown, message: string): void {
  if (!cond) throw new Error(message);
}

const cols = 24;
const rows = 24;
const spacing = 8;
const heights = new Float32Array(cols * rows);
for (let i = 0; i < heights.length; i++) heights[i] = 40;
const field = new Field(cols, rows, spacing, heights);
const before = field.heights.reduce((sum, h) => sum + h, 0);
const moved = pushBlade(field, 80, 80, 0.4, 14, 0.3);
const after = field.heights.reduce((sum, h) => sum + h, 0);
assert(moved > 1, 'the blade should move soil');
assert(Math.abs(after - before) < 0.01, `push did not conserve height sum ${before} -> ${after}`);
assert(Math.abs(field.cutM3 - field.fillM3) < 0.01, 'cut and fill diverged on a push');

const dug = digBucket(field, 40, 40, 10, 0.25);
assert(dug > 1, 'the bucket should dig');
const held = dug;
const dumped = dumpLoad(field, 120, 120, held);
assert(Math.abs(dumped - held) < 0.01, 'dump should place the whole bucket');
assert(Math.abs(field.cutM3 - field.fillM3) < 0.05, `volumes diverged cut ${field.cutM3} fill ${field.fillM3}`);
const end = field.heights.reduce((sum, h) => sum + h, 0);
assert(Math.abs(end - before) < 0.05, `the field lost soil ${before} -> ${end}`);
console.log(`drive-check ok  pushed ${moved.toFixed(1)} m3  dug ${dug.toFixed(1)} m3`);
