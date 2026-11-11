import { Field } from '../src/drive/field';
import { Detail } from '../src/drive/detail';

const cols = 40;
const heights = new Float32Array(cols * cols);
heights.fill(80);
const field = new Field(cols, cols, 20, heights);
const detail = new Detail(field);
detail.follow(220, 220);

const first = detail.cut(220, 220, 0, 3.6, 0.5);
if (!(first > 0)) throw new Error(`expected a moving blade to cut, got ${first}`);
if (Math.abs(field.cutM3 - field.fillM3) > 1e-6) throw new Error(`cut ${field.cutM3} != fill ${field.fillM3}`);

const parked = field.cutM3;
for (let i = 0; i < 40; i++) detail.cut(220.04, 220.02, 0, 3.6, 0.5);
if (field.cutM3 !== parked) throw new Error(`parked blade moved soil: ${parked} -> ${field.cutM3}`);
if (Math.abs(field.cutM3 - field.fillM3) > 1e-6) throw new Error('parked volumes diverged');

const swept = detail.cut(220, 223, 0, 3.6, 0.5);
if (!(swept > 0)) throw new Error('a blade that moved onto new ground should cut');
if (Math.abs(field.cutM3 - field.fillM3) > 1e-6) throw new Error(`after sweep cut ${field.cutM3} != fill ${field.fillM3}`);

detail.bakeAll();
if (Math.abs(detail.deltaM3()) > 1e-4) throw new Error(`bake left ${detail.deltaM3()} m³ unaccounted`);

console.log('detail-check ok', { first: first.toFixed(2), swept: swept.toFixed(2), cut: field.cutM3.toFixed(2) });
