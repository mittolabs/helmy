// Draws each screen of a React export and the design it came from at phone,
// tablet and desktop widths, and compares them pixel by pixel: 1:1, measured.
//   node check.mjs <design folder> <export folder> <out folder>
// TOLERANCE (0 by default) is how far a pixel's color may be off and still match.
import fs from 'node:fs'; import path from 'node:path'; import http from 'node:http';
import { build } from 'esbuild'; import { PNG } from 'pngjs';
import { chromium } from 'playwright';
const [design, exp, out] = process.argv.slice(2).map((p) => path.resolve(p));
fs.mkdirSync(out, { recursive: true });
const canvas = JSON.parse(fs.readFileSync(`${design}/canvas.json`, 'utf8'));
const order = canvas.order ?? Object.keys(canvas.boards);
const main = fs.readFileSync(`${exp}/src/main.tsx`, 'utf8');
const theme = fs.readFileSync(`${exp}/src/theme.css`, 'utf8');
const index = fs.readFileSync(`${exp}/index.html`, 'utf8');
const links = [...index.matchAll(/<link [^>]*>/g)].map((m) => m[0]).join('\n');
const routes = [...main.matchAll(/<Route path="([^"]*)" element=\{<(\w+) \/>\}/g)].map((m) => ({ route: m[1], name: m[2] }));
// Server-rendered: each screen's markup with the theme, as the app draws it.
const ssr = `${out}/ssr`; fs.mkdirSync(ssr, { recursive: true });
for (const [i, r] of routes.entries()) {
  const entry = `${out}/entry-${r.name}.tsx`;
  fs.writeFileSync(entry, `import { renderToStaticMarkup } from 'react-dom/server';
import { StaticRouter } from 'react-router-dom';
import S from '${exp}/src/screens/${r.name}/${r.name}';
console.log(renderToStaticMarkup(<StaticRouter location="${r.route}"><S /></StaticRouter>));`);
  await build({ entryPoints: [entry], bundle: true, platform: 'node', format: 'cjs', outfile: `${out}/entry-${r.name}.cjs`, jsx: 'automatic', nodePaths: [path.join(path.dirname(new URL(import.meta.url).pathname), 'node_modules')], logLevel: 'error' });
  const { execFileSync } = await import('node:child_process');
  const markup = execFileSync('node', [`${out}/entry-${r.name}.cjs`]).toString();
  fs.writeFileSync(`${ssr}/${order[i]}`, `<!doctype html><html><head><meta charset="utf-8">${links}<style>${theme}</style></head><body>${markup}</body></html>`);
}
const serve = (root) => http.createServer((q, s) => { let p = path.join(root, decodeURIComponent(q.url.split('?')[0].split('#')[0])); if (fs.existsSync(p) && fs.statSync(p).isDirectory()) p += '/index.html'; fs.readFile(p, (e, d) => { if (e) { s.writeHead(404); return s.end(); } s.writeHead(200, { 'content-type': p.endsWith('.html') ? 'text/html; charset=utf-8' : p.endsWith('.png') ? 'image/png' : p.endsWith('.svg') ? 'image/svg+xml' : 'application/octet-stream' }); s.end(d); }); }).listen(0);
const a = serve(design), b = serve(ssr);
// The export's files from public/ at the root, as Vite serves them.
fs.cpSync(`${exp}/public`, ssr, { recursive: true });
const browser = await chromium.launch(process.env.CHROME ? { executablePath: process.env.CHROME } : {});
const shot = async (port, file, width) => {
  const pg = await browser.newPage({ viewport: { width, height: 900 } });
  await pg.goto(`http://127.0.0.1:${port}/${file}`, { waitUntil: 'networkidle' });
  await pg.evaluate(() => document.fonts.ready);
  await pg.waitForTimeout(300);
  const buf = await pg.screenshot({ fullPage: true }); await pg.close(); return PNG.sync.read(buf);
};
let worst = 0;
for (const file of order) for (const width of [390, 834, 1440]) {
  const x = await shot(a.address().port, file, width), y = await shot(b.address().port, file, width);
  let diff = 0; const h = Math.min(x.height, y.height);
  for (let i = 0; i < width * h * 4; i += 4) if (Math.abs(x.data[i] - y.data[i]) + Math.abs(x.data[i + 1] - y.data[i + 1]) + Math.abs(x.data[i + 2] - y.data[i + 2]) > (Number(process.env.TOLERANCE ?? 0))) diff++;
  const pct = (100 * diff) / (width * h);
  worst = Math.max(worst, pct);
  console.log(`${file} @${width}: design ${x.height}px, export ${y.height}px tall, ${diff} pixels differ (${pct.toFixed(3)}%)`);
  if (diff || x.height !== y.height) { fs.writeFileSync(`${out}/${file}-${width}-design.png`, PNG.sync.write(x)); fs.writeFileSync(`${out}/${file}-${width}-export.png`, PNG.sync.write(y)); }
}
await browser.close(); a.close(); b.close();
console.log(worst === 0 ? 'IDENTICAL' : `worst ${worst.toFixed(3)}%`);
