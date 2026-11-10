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
  await page.goto('http://127.0.0.1:4173/', { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForFunction(() => window.__roleplay && window.__roleplay.ready && window.__roleplay.mode() === 'world');
  await page.waitForTimeout(2500);
  await page.screenshot({ path: `${outDir}/01-world-map.png` });

  await page.evaluate(() => window.__roleplay.selectTile('rene-levasseur'));
  await page.waitForTimeout(4500);
  await page.screenshot({ path: `${outDir}/05-ring-globe.png` });
  await page.evaluate(() => window.__roleplay.enterBasin());
  await page.waitForFunction(() => window.__roleplay.mode() === 'tile' && window.__roleplay.home);
  await page.evaluate(() => window.__roleplay.home());
  await page.evaluate(() => window.__roleplay.settle());
  await page.screenshot({ path: `${outDir}/06-ring-tile.png` });
  await page.evaluate(() => window.__roleplay.showWorld());
  await page.waitForFunction(() => window.__roleplay.mode() === 'world');
  await page.evaluate(() => window.__roleplay.selectTile(window.__roleplay.playableId));
  await page.evaluate(() => window.__roleplay.command('mass'));
  await page.waitForTimeout(1600);
  await page.screenshot({ path: `${outDir}/02-giant-swarm.png` });
  const book = await page.evaluate(() => window.__roleplay.book());
  if (!(book.cut_m3 > 0) || book.cut_m3 !== book.fill_m3) throw new Error('swarm cut and fill diverged');

  await page.evaluate(() => window.__roleplay.enterBasin());
  await page.waitForFunction(() => window.__roleplay.mode() === 'tile' && window.__roleplay.tileReady);
  await page.evaluate(() => window.__roleplay.home());
  await page.evaluate(() => window.__roleplay.settle());
  await page.screenshot({ path: `${outDir}/03-tile-basin.png` });

  const pose = await page.evaluate(() => {
    window.__roleplay.enterWalk(2000, 2000, 0.2, -0.12);
    return window.__roleplay.pose();
  });
  await page.evaluate(() => window.__roleplay.settle());
  await page.screenshot({ path: `${outDir}/04-walk-mode.png` });
  if (Math.abs(pose.eye - (pose.surface + 1.7)) > 0.08) throw new Error(`eye height off: ${JSON.stringify(pose)}`);

  const serious = errors.filter((line) => !/Failed to obtain image tile|net::ERR_|404/.test(line));
  if (serious.length) {
    console.error(serious.slice(0, 12).join('\n'));
    throw new Error(`${serious.length} console errors`);
  }
  console.log('verify ok', JSON.stringify({ book, pose }));
} catch (err) {
  console.error(err);
  process.exitCode = 1;
} finally {
  preview.kill('SIGKILL');
  setTimeout(() => process.exit(process.exitCode ?? 0), 200);
}
