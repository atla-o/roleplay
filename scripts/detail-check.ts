import { Field } from '../src/drive/field';
import { planeBlade } from '../src/drive/sculpt';

const cols = 48;
const heights = new Float32Array(cols * cols);
heights.fill(80);
const field = new Field(cols, cols, 2, heights);

const first = planeBlade(field, 40, 40, 0, 3.6, 79.4, 35);
if (!(first > 0)) throw new Error(`expected a moving blade to cut, got ${first}`);
if (Math.abs(field.cutM3 - field.fillM3) > 1e-4) throw new Error(`cut ${field.cutM3} != fill ${field.fillM3}`);

const parked = field.cutM3;
planeBlade(field, 40, 40, 0, 3.6, 80.2, 35);
if (field.cutM3 !== parked) throw new Error('a blade above the ground moved soil');

const swept = planeBlade(field, 40, 48, 0, 3.6, 79.2, 35);
if (!(swept > 0)) throw new Error('a blade that moved onto new ground should cut');
if (Math.abs(field.cutM3 - field.fillM3) > 1e-3) throw new Error(`after sweep cut ${field.cutM3} != fill ${field.fillM3}`);

let steep = 0;
for (let r = 1; r < cols - 1; r++) {
  for (let c = 1; c < cols - 1; c++) {
    const h = field.heights[r * cols + c] ?? 0;
    const other = field.heights[r * cols + c + 1] ?? 0;
    steep = Math.max(steep, Math.abs(h - other) / field.spacing);
  }
}
if (steep > Math.tan((35 * Math.PI) / 180) + 0.35) throw new Error(`spoil stood steeper than the angle of repose: ${steep}`);

console.log('detail-check ok', { first: first.toFixed(2), swept: swept.toFixed(2), cut: field.cutM3.toFixed(2) });
