// Compares where every element lands in a Flutter export (its measure test's
// build/measure/*.json) with where the page puts it in Chromium.
//   node flutter.mjs <design folder> <flutter export folder>
// TOLERANCE (px, 1 by default) is how far a box may be off and still match;
// it exits 1 when any is further off. WORST=n lists the n furthest.
import fs from 'node:fs'; import path from 'node:path'; import http from 'node:http';
import { chromium } from 'playwright';
const [design, exp] = process.argv.slice(2).map((p) => path.resolve(p));
const tol = Number(process.env.TOLERANCE ?? 1);
const files = fs.readdirSync(`${exp}/build/measure`).filter((f) => f.endsWith('.json'));
const type = (p) => p.endsWith('.html') ? 'text/html; charset=utf-8' : p.endsWith('.svg') ? 'image/svg+xml' : 'application/octet-stream';
const srv = http.createServer((q, r) => { const p = path.join(design, decodeURIComponent(q.url.split('?')[0])); fs.readFile(p, (e, d) => { if (e) { r.writeHead(404); return r.end(); } r.writeHead(200, { 'content-type': type(p) }); r.end(d); }); }).listen(0);
const browser = await chromium.launch(process.env.CHROME ? { executablePath: process.env.CHROME } : {});
let all = 0, good = 0;
const worst = [];
for (const f of files.sort()) {
  const m = f.match(/^(.*)-(\d+)(?:\.0)?\.json$/);
  const [file, width] = [m[1], Number(m[2])];
  const flutter = JSON.parse(fs.readFileSync(`${exp}/build/measure/${f}`, 'utf8'));
  const pg = await browser.newPage({ viewport: { width, height: 900 } });
  await pg.goto(`http://127.0.0.1:${srv.address().port}/${file}`, { waitUntil: 'networkidle' });
  await pg.evaluate(() => document.fonts.ready);
  const page = await pg.evaluate((sels) => Object.fromEntries(sels.map((s) => {
    const el = document.querySelector(s); if (!el) return [s, null];
    const r = el.getBoundingClientRect(); return [s, [r.left + scrollX, r.top + scrollY, r.width, r.height]];
  })), Object.keys(flutter));
  await pg.close();
  let n = 0, ok = 0;
  for (const [sel, a] of Object.entries(flutter)) {
    const b = page[sel]; if (!b || b[2] === 0 && b[3] === 0) continue;
    n++;
    const off = Math.max(...a.map((v, i) => Math.abs(v - b[i])));
    if (off <= tol) ok++; else worst.push({ at: `${file} @${width}`, sel, off: Math.round(off), flutter: a.map(Math.round), page: b.map(Math.round) });
  }
  all += n; good += ok;
  console.log(`${file} @${width}: ${ok}/${n} elements within ${tol}px (${(100 * ok / n).toFixed(1)}%)`);
}
await browser.close(); srv.close();
console.log(`ALL: ${good}/${all} within ${tol}px (${(100 * good / all).toFixed(1)}%)`);
if (process.env.WORST) for (const w of worst.sort((a, b) => b.off - a.off).slice(0, Number(process.env.WORST))) console.log(JSON.stringify(w));
// Every element where the page puts it, or the check fails.
if (good < all) process.exitCode = 1;
