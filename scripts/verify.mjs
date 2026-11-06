import { spawn } from 'node:child_process';
import { mkdirSync } from 'node:fs';
import { chromium } from 'playwright';

const outDir = '/opt/cursor/artifacts';
mkdirSync(outDir, { recursive: true });

const preview = spawn('npx', ['vite', 'preview', '--host', '127.0.0.1', '--port', '4173', '--strictPort'], {
  cwd: new URL('..', import.meta.url).pathname,
  stdio: ['ignore', 'pipe', 'pipe'],
});
preview.stdout.on('data', (b) => process.stdout.write(b));
preview.stderr.on('data', (b) => process.stderr.write(b));

const deadline = Date.now() + 20000;
let up = false;
while (Date.now() < deadline) {
  try {
    const res = await fetch('http://127.0.0.1:4173/');
    if (res.ok) {
      up = true;
      break;
    }
  } catch {
    await new Promise((r) => setTimeout(r, 300));
  }
}
if (!up) {
  preview.kill();
  throw new Error('preview did not start');
}

const errors = [];
const browser = await chromium.launch({
  headless: true,
  args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--disable-gpu-sandbox'],
});
try {
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 1 });
  page.setDefaultTimeout(120000);
  page.on('console', (msg) => {
    if (msg.type() === 'error') errors.push(msg.text());
  });
  page.on('pageerror', (err) => errors.push(String(err)));
  await page.goto('http://127.0.0.1:4173/', { waitUntil: 'networkidle', timeout: 30000 });
  await page.waitForFunction(() => window.__roleplay && window.__roleplay.ready, null, { timeout: 30000 });

  await page.evaluate(() => {
    window.__roleplay.setOverlay({ slope: true, water: true, hydro: true });
    window.__roleplay.home();
  });
  await page.evaluate(() => window.__roleplay.settle());
  await page.screenshot({ path: `${outDir}/01-orbit-water-slope.png` });

  const report = await page.evaluate(() => window.__roleplay.performSuccession());
  console.log('succession', JSON.stringify({ ok: report.ok, reasons: report.reasons, look: report.look, walk: report.walk }, null, 2));
  await page.evaluate(() => window.__roleplay.settle());
  await page.screenshot({ path: `${outDir}/02-channel-drainage-gene-ark.png` });

  await page.evaluate((walk) => {
    window.__roleplay.enterWalk(walk.x, walk.z, walk.yaw, walk.pitch);
  }, report.walk);
  await page.evaluate(() => window.__roleplay.settle());
  await page.screenshot({ path: `${outDir}/03-walk-streets.png` });
  const pose = await page.evaluate(() => window.__roleplay.pose());
  await page.evaluate(() => window.__roleplay.walkBy(6, 0));

  const stats = await page.evaluate(() => window.__roleplay.stats());
  console.log('stats', JSON.stringify(stats, null, 2));
  console.log('pose', JSON.stringify(pose));
  const eyeDelta = Math.abs(pose.eye - (pose.surface + 1.7));
  if (eyeDelta > 0.05) throw new Error(`eye height off by ${eyeDelta}`);
  if (stats.plantings < 1) throw new Error('Gene Ark did not deploy');
  if (stats.streets_m < 20) throw new Error('no street to walk');
  if (stats.ponded_m3 >= stats.input_m3) throw new Error('ponding exceeded the melt budget');
  if (!(stats.cut_m3 > 0)) throw new Error('no earth was cut');
  if (errors.length) {
    console.error(errors.join('\n'));
    throw new Error(`${errors.length} console errors`);
  }
  console.log('verify ok');
} catch (err) {
  console.error(err);
  process.exitCode = 1;
} finally {
  preview.kill();
  await Promise.race([browser.close(), new Promise((resolve) => setTimeout(resolve, 3000))]);
}
