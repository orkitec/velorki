// SPDX-License-Identifier: AGPL-3.0-only
//
// Guard rail for the "stock Node, no native code" deployment constraint.
//
// What ships is the traced tree under .next/standalone/node_modules, not the
// full install: next-intl, for one, depends on @swc/core and @parcel/watcher
// for its build-time message extractor, and neither is traced into the
// standalone output. So this walks the standalone tree after `next build` and
// fails if any package there
//   * ships a binding.gyp (a native addon built with node-gyp), or
//   * declares a preinstall / install / postinstall lifecycle script.
//
// Run by `npm run check:deps` (after `npm run build`). Exits 1 on findings.

import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';

const root = new URL('..', import.meta.url).pathname.replace(/\/$/, '');
const tree = join(root, '.next', 'standalone', 'node_modules');
const BAD_SCRIPTS = ['preinstall', 'install', 'postinstall'];

if (!existsSync(tree)) {
  console.error(`check:deps: ${relative(root, tree)} does not exist; run \`npm run build\` first`);
  process.exit(1);
}

/** Every directory holding a package.json under a node_modules tree. */
function* packages(dir) {
  for (const entry of readdirSync(dir)) {
    if (entry === '.bin' || entry === '.cache') continue;
    const path = join(dir, entry);
    if (!statSync(path).isDirectory()) continue;
    if (entry.startsWith('@')) {
      yield* packages(path);
      continue;
    }
    if (existsSync(join(path, 'package.json'))) yield path;
    const nested = join(path, 'node_modules');
    if (existsSync(nested)) yield* packages(nested);
  }
}

const problems = [];
let count = 0;
for (const dir of packages(tree)) {
  count += 1;
  const name = relative(tree, dir);
  let pkg;
  try {
    pkg = JSON.parse(readFileSync(join(dir, 'package.json'), 'utf8'));
  } catch {
    continue;
  }
  if (existsSync(join(dir, 'binding.gyp'))) problems.push(`${name}: ships binding.gyp`);
  for (const script of BAD_SCRIPTS) {
    if (pkg.scripts?.[script]) problems.push(`${name}: has a ${script} script (${pkg.scripts[script]})`);
  }
}

if (problems.length > 0) {
  console.error(`check:deps: ${problems.length} problem(s) in the standalone tree:`);
  for (const problem of problems) console.error(`  - ${problem}`);
  process.exit(1);
}
console.log(`check:deps: ${count} packages in the standalone tree, none native, no install scripts`);
