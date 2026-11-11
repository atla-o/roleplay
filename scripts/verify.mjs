import { spawn } from 'node:child_process';
import { mkdirSync } from 'node:fs';
import { chromium } from 'playwright';

const outDir = '/opt/cursor/artifacts';
mkdirSync(outDir, { recursive: true });

const preview = spawn('npx', ['vite', 'preview', '--host', '127.0.0.1', '--port', '4173', '--strictPort'], {
  cwd: new URL('..', import.meta.url).pathname,
  stdio: ['ignore', 'pipe', 'pipe'],
});
let log = '';
preview.stdout.on('data', (chunk) => {
  log += chunk;
  process.stdout.write(chunk);
});
preview.stderr.on('data', (chunk) => {
  log += chunk;
  process.stderr.write(chunk);
});

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
if (!up || log.includes('already in use')) {
  preview.kill();
  throw new Error(log.includes('already in use') ? 'preview port was already taken' : 'preview did not start');
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
  await page.goto('http://127.0.0.1:4173/', { waitUntil: 'domcontentloaded', timeout: 60000 });
  await page.waitForFunction(() => window.__roleplay && window.__roleplay.ready, null, { timeout: 60000 });
  await page.waitForTimeout(1500);
  await page.screenshot({ path: `${outDir}/10-orbit.png` });
  const places = await page.evaluate(() => window.__roleplay.places());
  if (!places.includes('polar-desert-basin') || !places.includes('rene-levasseur')) {
    throw new Error(`sites missing: ${JSON.stringify(places)}`);
  }
  await page.evaluate(() => window.__roleplay.fly('polar-desert-basin'));
  await page.waitForTimeout(2600);
  await page.screenshot({ path: `${outDir}/11-basin-from-orbit.png` });
  await page.evaluate(() => window.__roleplay.setView('vehicle'));
  await page.waitForTimeout(900);
  await page.keyboard.down('w');
  await page.keyboard.down('f');
  await page.waitForTimeout(3200);
  await page.keyboard.up('w');
  await page.keyboard.up('f');
  await page.waitForTimeout(400);
  const volumes = await page.evaluate(() => window.__roleplay.volumes());
  const read = await page.locator('#drive-read').innerText();
  await page.screenshot({ path: `${outDir}/12-driving.png` });
  if (!(volumes.cut > 1)) throw new Error(`the blade did not cut: ${read} ${JSON.stringify(volumes)}`);
  if (Math.abs(volumes.cut - volumes.fill - volumes.held) > 1) {
    throw new Error(`soil was not conserved: ${JSON.stringify(volumes)}`);
  }
  await page.evaluate(() => window.__roleplay.fly('rene-levasseur'));
  await page.waitForTimeout(2600);
  await page.screenshot({ path: `${outDir}/13-ring.png` });

  const serious = errors.filter((line) => !/Failed to obtain image tile|net::ERR_|404|glTF|texture/i.test(line));
  if (serious.length) {
    console.error(serious.slice(0, 12).join('\n'));
    throw new Error(`${serious.length} console errors`);
  }
  console.log('verify ok', JSON.stringify({ places, volumes }));
} catch (err) {
  console.error(err);
  process.exitCode = 1;
} finally {
  preview.kill('SIGKILL');
  setTimeout(() => process.exit(process.exitCode ?? 0), 200);
}
