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

  const work = await page.evaluate(() => {
    const before = window.__roleplay.stats().cut_m3;
    const graded = window.__roleplay.grade(2000, 2000, 48);
    const cut = window.__roleplay.stats().cut_m3;
    const undone = window.__roleplay.undo();
    const back = window.__roleplay.stats().cut_m3;
    return {
      ok: graded.ok,
      reason: graded.reason || window.__roleplay.status(),
      before,
      cut,
      undone,
      back,
      coach: document.querySelector('#coach-next')?.textContent || '',
    };
  });
  if (!work.ok) throw new Error(`grade failed: ${work.reason}`);
  if (!(work.cut > work.before)) throw new Error(`grade did not move ground: ${JSON.stringify(work)}`);
  if (!work.undone || Math.abs(work.back - work.before) > 1) throw new Error(`undo missed: ${JSON.stringify(work)}`);
  if (!work.coach) throw new Error('the basin has no onboarding line');
  await page.click('[data-tool="grade"]');
  const box = await page.locator('#tile canvas').boundingBox();
  if (!box) throw new Error('basin canvas missing');
  await page.mouse.click(box.x + box.width * 0.55, box.y + box.height * 0.48);
  await page.waitForTimeout(1200);
  const clicked = await page.locator('#status').innerText();
  if (!/Pad graded|fill bank|off the measured/i.test(clicked)) throw new Error(`grade click had no result: ${clicked}`);
  await page.screenshot({ path: `${outDir}/07-graded-pad.png` });

  const pose = await page.evaluate(() => {
    window.__roleplay.enterWalk(2000, 2000, 0.2, -0.12);
    return window.__roleplay.pose();
  });
  await page.evaluate(() => window.__roleplay.settle());
  await page.screenshot({ path: `${outDir}/04-walk-mode.png` });
  if (Math.abs(pose.eye - (pose.surface + 1.7)) > 0.08) throw new Error(`eye height off: ${JSON.stringify(pose)}`);

  const phone = await browser.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 1 });
  await phone.goto('http://127.0.0.1:4173/', { waitUntil: 'domcontentloaded', timeout: 60000 });
  await phone.waitForFunction(() => window.__roleplay && window.__roleplay.ready && window.__roleplay.mode() === 'world');
  await phone.waitForTimeout(800);
  await phone.screenshot({ path: `${outDir}/08-phone-world.png` });
  await phone.evaluate(() => window.__roleplay.enterBasin());
  await phone.waitForFunction(() => window.__roleplay.mode() === 'tile' && window.__roleplay.tileReady);
  await phone.waitForTimeout(600);
  await phone.screenshot({ path: `${outDir}/09-phone-basin.png` });
  await phone.close();

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
