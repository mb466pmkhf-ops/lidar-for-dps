#!/usr/bin/env node
// Checks the code keeps to the look sheet (Docs/LOOK.md). Run from the repo root:
//   node scripts/check-look.mjs
// Fails on: corner radii other than the two tokens, frosted-glass blur, upper-case transforms,
// and new ALL-CAPS labels in SwiftUI text. Fix the code, or change Docs/LOOK.md first if the
// rule itself should change.
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

const problems = [];
const walk = (dir, ext, out = []) => {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (name === 'node_modules' || name === 'dist') continue;
    if (statSync(p).isDirectory()) walk(p, ext, out);
    else if (ext.some(e => p.endsWith(e))) out.push(p);
  }
  return out;
};
const report = (file, i, msg, line) => problems.push(`${file}:${i + 1}: ${msg}\n    ${line.trim()}`);

// Web: CSS and inline styles.
for (const file of [...walk('web/src', ['.css']), ...walk('web/src', ['.tsx'])]) {
  readFileSync(file, 'utf8').split('\n').forEach((line, i) => {
    for (const m of line.matchAll(/border-?[rR]adius:\s*([^;}'",]+)/g)) {
      const v = m[1].trim();
      if (!/^(var\(--radius(-lg)?\)|50%|0)$/.test(v)) report(file, i, `radius "${v}": use var(--radius) or var(--radius-lg)`, line);
    }
    if (/backdrop-filter/.test(line)) report(file, i, 'frosted-glass blur: use a solid surface', line);
    if (/text-transform:\s*uppercase|textTransform:\s*'uppercase'/.test(line)) report(file, i, 'upper-case labels: write labels in sentence case', line);
  });
}

// iPhone: SwiftUI.
const caps = /Text\("([A-Z][A-Z ]{3,})"\)/;
const allowedCaps = new Set(['ISO', 'LED', 'HMI', 'RGB', 'USDZ', 'LIDAR']);
for (const file of walk('FrameScout', ['.swift'])) {
  if (file.endsWith('Shared/Theme.swift')) continue;
  readFileSync(file, 'utf8').split('\n').forEach((line, i) => {
    if (/cornerRadius:\s*\d/.test(line)) report(file, i, 'literal corner radius: use Theme.corner or Theme.cornerSmall', line);
    if (/\.textCase\(\.uppercase\)/.test(line)) report(file, i, 'upper-case labels: write labels in sentence case', line);
    const m = line.match(caps);
    if (m && !allowedCaps.has(m[1].trim())) report(file, i, `ALL-CAPS label "${m[1]}": write it in sentence case`, line);
  });
}

if (problems.length) {
  console.error(`Look sheet check: ${problems.length} problem(s). See Docs/LOOK.md.\n`);
  console.error(problems.join('\n'));
  process.exit(1);
}
console.log('Look sheet check: OK');
