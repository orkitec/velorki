// SPDX-License-Identifier: AGPL-3.0-only
//
// Guard rail for the "stock Node, no native code" deployment constraint.
//
// Orkify deploys this service as `node dist/server.js`, so what matters is the
// *production* dependency tree: that is the code that has to run on a plain
// Node 22+ runtime with nothing compiled and nothing fetched at install time.
// This script walks that tree (`npm ls --omit=dev`) and fails if any package
//   * ships a binding.gyp (i.e. builds a native addon via node-gyp), or
//   * declares a preinstall / install / postinstall lifecycle script.
//
// Dev-only packages are reported for information but do not fail the check:
// the mandated toolchain (tsx, vitest) pulls in esbuild, whose postinstall
// unpacks a prebuilt binary. None of that is deployed.
//
// Run by `npm run check:deps`. Exits 1 when the production tree is dirty.
// Pass --strict to fail on dev-tree findings as well.

import { execFileSync } from 'node:child_process';
import { readFileSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';

const root = new URL('..', import.meta.url).pathname.replace(/\/$/, '');
const BAD_SCRIPTS = ['preinstall', 'install', 'postinstall'];
const strict = process.argv.includes('--strict');

/** Package directories in the dependency tree, per `npm ls --parseable`. */
function treePaths(omitDev) {
  const args = ['ls', '--all', '--parseable', '--long=false'];
  if (omitDev) args.push('--omit=dev');
  let out;
  try {
    out = execFileSync('npm', args, { cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  } catch (err) {
    // `npm ls` exits non-zero on peer-dependency complaints but still prints
    // the tree; only give up when there is genuinely no output.
    out = err.stdout ?? '';
    if (out.trim() === '') {
      console.error('check:deps could not read the dependency tree:', err.message);
      process.exit(1);
    }
  }
  return out
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line !== '' && line !== root);
}

/** Inspect one package directory; returns a list of problem descriptions. */
function inspect(dir) {
  const problems = [];
  const name = relative(join(root, 'node_modules'), dir) || dir;

  let pkg;
  try {
    pkg = JSON.parse(readFileSync(join(dir, 'package.json'), 'utf8'));
  } catch {
    return problems;
  }

  try {
    statSync(join(dir, 'binding.gyp'));
    problems.push(`${name}: ships binding.gyp (native addon)`);
  } catch {
    // No binding.gyp: good.
  }

  const scripts = pkg.scripts ?? {};
  for (const hook of BAD_SCRIPTS) {
    if (typeof scripts[hook] === 'string' && scripts[hook].trim() !== '') {
      problems.push(`${name}: has a "${hook}" script (${scripts[hook]})`);
    }
  }
  return problems;
}

const prodDirs = treePaths(true);
const allDirs = treePaths(false);
const prodSet = new Set(prodDirs);
const devOnlyDirs = allDirs.filter((d) => !prodSet.has(d));

const prodProblems = prodDirs.flatMap(inspect);
const devProblems = devOnlyDirs.flatMap(inspect);

if (devProblems.length > 0) {
  console.log(
    `check:deps note - ${devProblems.length} dev-only package(s) with install scripts (not deployed):`,
  );
  for (const line of devProblems) console.log(`  - ${line}`);
}

if (prodProblems.length > 0 || (strict && devProblems.length > 0)) {
  console.error(
    `check:deps FAILED - ${prodProblems.length} problem(s) in the ${prodDirs.length} runtime packages:`,
  );
  for (const line of prodProblems) console.error(`  - ${line}`);
  console.error('\nVelorki must deploy as a plain Node process: no native addons, no install scripts.');
  process.exit(1);
}

console.log(
  `check:deps OK - ${prodDirs.length} runtime packages, no binding.gyp and no install scripts.`,
);
