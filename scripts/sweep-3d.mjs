#!/usr/bin/env node
// Opens each of the 150 sweep setups (web/tests/fixtures/sweep-bundles.json) in the desktop 3D view
// and records, per setup: console errors, how long the room took to open, shaders built, meshes
// with broken positions, parts below the floor or far outside the room, and a screenshot.
//   cd web && npx vite --port 5173 &   then   node scripts/sweep-3d.mjs [out-dir] [first] [count]
// Needs the dev server (the 3D view exposes window.__scene3d only in development).
import { createRequire } from 'node:module';
const { chromium } = createRequire(import.meta.url)('playwright'); // the copy installed with the browser
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const URL = process.env.SWEEP_URL ?? 'http://localhost:5173/';
const out = process.argv[2] ?? 'sweep-3d-out';
const first = Number(process.argv[3] ?? 0), count = Number(process.argv[4] ?? 150);
mkdirSync(out, { recursive: true });
const cases = JSON.parse(readFileSync(new globalThis.URL('../web/tests/fixtures/sweep-bundles.json', import.meta.url), 'utf8')).slice(first, first + count);

const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
const page = await browser.newPage({ viewport: { width: 1000, height: 640 } });
let log = [];
page.on('console', m => { if (m.type() === 'error' || m.type() === 'warning') log.push(`${m.type()}: ${m.text()}`); });
page.on('pageerror', e => log.push(`pageerror: ${e.message}`));
await page.addInitScript(() => {
  try {
    localStorage.setItem('framescan.plan.view', '3d');
    localStorage.setItem('framescan.plan.layers', 'beams,readings');
    for (const k of ['3d-gestures', 'welcome']) localStorage.setItem('framescan.tip.' + k, '1');
  } catch { /* */ }
  // Count shader programs linked.
  const proto = WebGL2RenderingContext.prototype, link = proto.linkProgram;
  window.__links = 0;
  proto.linkProgram = function (p) { window.__links++; return link.call(this, p); };
});
await page.goto(URL);
await page.waitForTimeout(1500);
// Put the setups straight into the app's local store, one project each.
await page.evaluate(async items => {
  const db = await new Promise((res, rej) => { const r = indexedDB.open('framescan', 1); r.onupgradeneeded = () => r.result.createObjectStore('projects', { keyPath: 'id' }); r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error); });
  await new Promise((res, rej) => {
    const t = db.transaction('projects', 'readwrite');
    for (const c of items) t.objectStore('projects').put({ id: c.bundle.project.id, bundle: c.bundle, dirty: false });
    t.oncomplete = res; t.onerror = () => rej(t.error);
  });
}, cases);
await page.reload();
await page.waitForTimeout(1500);
log = [];

const results = [];
for (const c of cases) {
  const name = c.bundle.project.name;
  await page.evaluate(() => { if (window.__scene3d) window.__scene3d.__old = true; window.__links = 0; });
  log = [];
  const t0 = Date.now();
  await page.locator('button.room-row, nav.sidebar button.row', { hasText: name }).first().click();
  let opened = -1, warmedAt = -1;
  try {
    await page.waitForFunction(() => window.__scene3d && !window.__scene3d.__old, null, { timeout: 20000 });
    opened = Date.now() - t0;
    await page.waitForFunction(() => window.__scene3d.warmed && !window.__scene3d.warming, null, { timeout: 20000, polling: 50 });
    warmedAt = Date.now() - t0;
  } catch { /* recorded below */ }
  await page.evaluate(() => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(() => requestAnimationFrame(r)))));
  await page.waitForTimeout(250);
  const ready = Date.now() - t0;
  const plan = c.bundle.plans[c.bundle.project.locations[0].primaryScanID];
  const stats = await page.evaluate(bounds => {
    const a = window.__scene3d;
    if (!a) return { error: 'no 3D view' };
    const THREE_Box = a.scene.constructor; // unused; keep the bundle's three
    const issues = [];
    const path = o => { const n = []; for (let p = o; p && p !== a.scene; p = p.parent) n.push(p.name || p.type + (p.userData.sel ? `[${p.userData.sel.kind}]` : '')); return n.reverse().join('/'); };
    let meshes = 0, lights = 0;
    const box = { min: [Infinity, Infinity, Infinity], max: [-Infinity, -Infinity, -Infinity] };
    a.scene.updateMatrixWorld(true);
    a.scene.traverse(o => {
      if (o.isLight) lights++;
      if (!o.isMesh || !o.visible) return;
      let hidden = false; for (let p = o; p; p = p.parent) if (!p.visible) hidden = true;
      if (hidden || o === a.grid) return;
      meshes++;
      const g = o.geometry; if (!g.boundingBox) g.computeBoundingBox();
      const bb = g.boundingBox; if (!bb) return;
      const e = o.matrixWorld.elements;
      if (e.some(v => !Number.isFinite(v))) { issues.push(`NaN matrix: ${path(o)}`); return; }
      if ([bb.min.x, bb.min.y, bb.min.z, bb.max.x, bb.max.y, bb.max.z].some(v => !Number.isFinite(v))) { issues.push(`NaN geometry: ${path(o)}`); return; }
      // World box of the 8 corners.
      const lo = [Infinity, Infinity, Infinity], hi = [-Infinity, -Infinity, -Infinity];
      for (const x of [bb.min.x, bb.max.x]) for (const y of [bb.min.y, bb.max.y]) for (const z of [bb.min.z, bb.max.z]) {
        const w = [e[0] * x + e[4] * y + e[8] * z + e[12], e[1] * x + e[5] * y + e[9] * z + e[13], e[2] * x + e[6] * y + e[10] * z + e[14]];
        for (let k = 0; k < 3; k++) { lo[k] = Math.min(lo[k], w[k]); hi[k] = Math.max(hi[k], w[k]); }
      }
      if (o.userData.noAO && o.material?.type === 'ShaderMaterial') return; // beams: haze reaches where it reaches
      for (let k = 0; k < 3; k++) { box.min[k] = Math.min(box.min[k], lo[k]); box.max[k] = Math.max(box.max[k], hi[k]); }
      if (lo[1] < -0.12) issues.push(`below floor ${lo[1].toFixed(2)}: ${path(o)}`);
      const m = 1.5;
      if (lo[0] < bounds.minX - m || hi[0] > bounds.maxX + m || lo[2] < bounds.minZ - m || hi[2] > bounds.maxZ + m) issues.push(`outside room [${lo.map(v => v.toFixed(1))}…${hi.map(v => v.toFixed(1))}]: ${path(o)}`);
    });
    const info = a.renderer.info;
    return { meshes, lights, issues: [...new Set(issues)].slice(0, 25), programs: info.programs?.length ?? 0, calls: info.render.calls, triangles: info.render.triangles, links: window.__links, exposure: a.renderer.toneMappingExposure };
  }, plan.bounds);
  const shot = join(out, `${c.id}.png`);
  // Read the picture straight off the canvas, drawn in the same task (a page screenshot waits on the
  // software GPU and often times out).
  try {
    const url = await page.evaluate(() => { const a = window.__scene3d; a.composer.render(); return a.renderer.domElement.toDataURL('image/jpeg', 0.85); });
    writeFileSync(shot.replace(/png$/, 'jpg'), Buffer.from(url.split(',')[1], 'base64'));
  } catch (e) { log.push('screenshot failed: ' + e.message.split('\n')[0]); }
  const r = { id: c.id, family: c.family, title: c.title, opened, warmed: warmedAt, ready, ...stats, console: log };
  results.push(r);
  console.log(`${c.id} ${String(ready).padStart(5)} ms  warm ${String(warmedAt).padStart(5)}  links ${String(stats.links).padStart(3)}  issues ${stats.issues?.length ?? '?'}  console ${log.length}  ${c.title}`);
  writeFileSync(join(out, `results-${first}.json`), JSON.stringify(results, null, 1));
}
await browser.close();
