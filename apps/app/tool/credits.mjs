// Writes lib/config/open_source.dart: every package Helmy ships, with its
// version and license, read from pubspec.lock and each package's LICENSE.
// Run after changing dependencies: node tool/credits.mjs
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const lock = fs.readFileSync('pubspec.lock', 'utf8');
const pub = path.join(process.env.PUB_CACHE || path.join(os.homedir(), '.pub-cache'), 'hosted', 'pub.dev');
const out = [];
// pubspec.lock, read entry by entry: a two-space name, then its fields.
const entries = [];
let cur = null;
for (const line of lock.split('\n')) {
  const head = line.match(/^  ([a-z0-9_]+):$/);
  if (head) { cur = { name: head[1] }; entries.push(cur); continue; }
  const field = line.match(/^    (dependency|source|version): "?([^"]+)"?$/);
  if (cur && field) cur[field[1]] = field[2];
}
for (const { name, dependency: dep = '', source, version } of entries) {
  if (source !== 'hosted' || dep.includes('dev')) continue;
  const dir = path.join(pub, `${name}-${version}`);
  let text = '';
  for (const f of ['LICENSE', 'LICENSE.md', 'LICENSE.txt', 'license']) {
    const p = path.join(dir, f);
    if (fs.existsSync(p)) { text = fs.readFileSync(p, 'utf8'); break; }
  }
  const license =
    /Apache License/i.test(text) ? 'Apache 2.0'
    : /MIT License|Permission is hereby granted, free of charge/i.test(text) ? 'MIT'
    : /BSD 3-Clause|Redistributions of source code[\s\S]*Neither the name/i.test(text) ? 'BSD 3-Clause'
    : /BSD 2-Clause|Redistributions of source code/i.test(text) ? 'BSD 2-Clause'
    : /Mozilla Public License/i.test(text) ? 'MPL 2.0'
    : /ISC License/i.test(text) ? 'ISC'
    : text ? 'See its license' : 'License not found';
  out.push({ name, version, license });
}
out.sort((a, b) => a.name.localeCompare(b.name));
const esc = (s) => s.replace(/\\/g, '\\\\').replace(/'/g, "\\'");
const dart = `// Written by tool/credits.mjs from pubspec.lock; do not edit by hand.

/// Open-source software Helmy ships, as the About window credits it.
const openSource = <({String name, String version, String license})>[
  (name: 'Flutter', version: '', license: 'BSD 3-Clause'),
${out.map((p) => `  (name: '${esc(p.name)}', version: '${esc(p.version)}', license: '${esc(p.license)}'),`).join('\n')}
];

/// Tools Helmy installs or uses on request, outside its own build.
const openSourceTools = <({String name, String license, String use})>[
  (name: 'AXe', license: 'MIT', use: 'Taps and typing on iOS simulators'),
];
`;
fs.writeFileSync('lib/config/open_source.dart', dart);
console.log(`${out.length} packages`, Object.entries(out.reduce((a, p) => ((a[p.license] = (a[p.license] || 0) + 1), a), {})));
