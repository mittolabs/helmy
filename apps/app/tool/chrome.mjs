// Helmy in Chrome: the remote built for the web, as an unpacked extension in
// build/chrome, and zipped beside it for a release. Run from apps/app.
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const out = path.resolve('build/chrome');
const version = fs.readFileSync('pubspec.yaml', 'utf8').match(/^version:\s*([0-9.]+)/m)[1];
fs.rmSync(out, { recursive: true, force: true });
// fvm here; Flutter itself in CI (FLUTTER=flutter).
const [flutter, ...pre] = (process.env.FLUTTER ?? 'fvm flutter').split(' ');
execFileSync(flutter, [
  ...pre, 'build', 'web', '-t', 'lib/main_chrome.dart', '-o', out,
  // An extension may run no code from elsewhere, nor make any at runtime.
  '--no-web-resources-cdn', '--csp', '--no-wasm-dry-run',
  '--no-source-maps',
], { stdio: 'inherit' });

// What Chrome never loads. Chromium browsers (Chrome, Edge, Brave) take
// CanvasKit's chromium build; the others are for other browsers, or for
// the WebAssembly build this is not.
const drop = (p) => fs.rmSync(path.join(out, p), { recursive: true, force: true });
for (const f of fs.readdirSync(path.join(out, 'canvaskit'))) {
  if (f !== 'chromium') drop(path.join('canvaskit', f));
}
drop('canvaskit/chromium/canvaskit.js.symbols');
drop('flutter.js.map');

// Icon fonts the panel uses no glyph of: tree-shaking leaves them whole.
// Each one used is shaken down to a few kilobytes, so a whole one is unused.
const fonts = path.join(out, 'assets/FontManifest.json');
const families = JSON.parse(fs.readFileSync(fonts, 'utf8'));
const kept = families.filter(({ fonts: [{ asset }] }) => {
  const file = path.join(out, 'assets', asset);
  const unused = asset.startsWith('packages/ashlar_icons/') && fs.statSync(file).size > 200_000;
  if (unused) fs.rmSync(file);
  return !unused;
});
fs.writeFileSync(fonts, JSON.stringify(kept));
for (const f of ['flutter_service_worker.js', 'version.json', '.last_build_id']) drop(f);

const manifest = path.join(out, 'manifest.json');
const m = JSON.parse(fs.readFileSync(manifest, 'utf8'));
m.version = version;
fs.writeFileSync(manifest, JSON.stringify(m, null, 2) + '\n');

const zip = path.resolve(`build/helmy-chrome-${version}.zip`);
fs.rmSync(zip, { force: true });
execFileSync('zip', ['-qr', zip, '.'], { cwd: out });
const mb = (n) => (n / 1e6).toFixed(1);
console.log(`build/chrome (load it unpacked), ${path.relative('.', zip)} ${mb(fs.statSync(zip).size)} MB`);
