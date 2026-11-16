// Helmy in a phone's browser: the remote built for the web, packed into one
// file the desktop app serves to phones (assets/remote/helmy-remote.bin).
// Run from apps/app, before building the desktop app; without it, the
// desktop app says it has no page for phone browsers.
//
// The pack: 4 bytes (big-endian) of index length, the index as JSON
// ({ "path": [offset, length] }, offsets after the index), then each file
// gzipped, so it is sent as it is with Content-Encoding: gzip.
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';

// --page: the page alone, for Helmy Connect's relay to serve at
// connect.helmy.ke (infra/relay.Dockerfile), not packed.
const pageOnly = process.argv.includes('--page');
const out = path.resolve(pageOnly ? 'build/connect' : 'build/remote');
fs.rmSync(out, { recursive: true, force: true });
// fvm here; Flutter itself in CI (FLUTTER=flutter).
const [flutter, ...pre] = (process.env.FLUTTER ?? 'fvm flutter').split(' ');
const args = [
  ...pre, 'build', 'web', '-t', 'lib/main_chrome.dart', '-o', out,
  // A phone on the same Wi-Fi may have no internet: everything from here.
  '--no-web-resources-cdn', '--no-wasm-dry-run', '--no-source-maps',
];
// On Windows, flutter is flutter.bat, which only a shell finds.
execFileSync(flutter, args, { stdio: 'inherit', shell: process.platform === 'win32' });

const drop = (p) => fs.rmSync(path.join(out, p), { recursive: true, force: true });
// The extension's own files, which a browser tab never loads.
for (const f of ['manifest.json', 'background.js', 'page.js']) drop(f);
// What this build never loads: the WebAssembly renderer, the experimental text
// renderer (loaded only when asked for), and files only for debugging or for a
// service worker it does not register.
for (const f of fs.readdirSync(path.join(out, 'canvaskit'), { recursive: true })) {
  if (/skwasm|wimp|webparagraph|\.symbols$/.test(f)) drop(path.join('canvaskit', f));
}
for (const f of ['flutter.js.map', 'flutter_service_worker.js', 'version.json', '.last_build_id']) drop(f);

// Icon fonts the remote uses no glyph of: tree-shaking leaves them whole.
const fonts = path.join(out, 'assets/FontManifest.json');
const families = JSON.parse(fs.readFileSync(fonts, 'utf8'));
fs.writeFileSync(fonts, JSON.stringify(families.filter(({ fonts: [{ asset }] }) => {
  const file = path.join(out, 'assets', asset);
  const unused = asset.startsWith('packages/ashlar_icons/') && fs.statSync(file).size > 200_000;
  if (unused) fs.rmSync(file);
  return !unused;
})));

// A Mac program the desktop app runs, which a browser cannot.
drop('assets/assets/helmy/bin');

if (pageOnly) {
  console.log(`${path.relative('.', out)}: the page for Helmy Connect`);
  process.exit(0);
}

const files = fs.readdirSync(out, { recursive: true })
  .filter((f) => fs.statSync(path.join(out, f)).isFile())
  .map((f) => f.split(path.sep).join('/'))
  .sort();
const index = {};
const chunks = [];
let at = 0;
for (const f of files) {
  const gz = zlib.gzipSync(fs.readFileSync(path.join(out, f)), { level: 9 });
  index[f] = [at, gz.length];
  chunks.push(gz);
  at += gz.length;
}
const head = Buffer.from(JSON.stringify(index));
const len = Buffer.alloc(4);
len.writeUInt32BE(head.length);
const pack = path.resolve('assets/remote/helmy-remote.bin');
fs.mkdirSync(path.dirname(pack), { recursive: true });
fs.writeFileSync(pack, Buffer.concat([len, head, ...chunks]));
console.log(`${path.relative('.', pack)}: ${files.length} files, ${(fs.statSync(pack).size / 1e6).toFixed(1)} MB`);
