#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-only
//
// Writes web/build-info.json: the commit the release artifact was packed from.
//
// `orkify deploy upload` packs the working tree and excludes `.git`
// (@orkify/cli, deploy/tarball.js ALWAYS_EXCLUDE), so the box that builds the
// artifact cannot ask git what it is building. This file is the only channel,
// and next.config.ts reads it while building to inline VELORKI_COMMIT.
//
// Run in CI immediately after `npm ci`, before the build and the upload
// (.github/workflows/web-deploy.yml). Running it by hand is harmless: the file
// is deliberately NOT committed and NOT gitignored - gitignoring it would drop
// it from the artifact, which is the one place it has to be.
import { execFileSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const webDir = dirname(dirname(fileURLToPath(import.meta.url)));

/** GitHub hands the checked-out sha to the job; locally, ask git. */
function resolve(envName, ...gitArgs) {
  const fromEnv = process.env[envName];
  if (fromEnv) return fromEnv.trim();
  try {
    return execFileSync('git', gitArgs, { cwd: webDir, encoding: 'utf-8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  } catch {
    return null;
  }
}

const commit = resolve('GITHUB_SHA', 'rev-parse', 'HEAD');
if (!commit) {
  console.error('build-info: no commit found (no GITHUB_SHA and no git repository)');
  process.exit(1);
}

const info = {
  commit,
  branch: resolve('GITHUB_REF_NAME', 'rev-parse', '--abbrev-ref', 'HEAD'),
  packedAt: new Date().toISOString(),
};

const target = join(webDir, 'build-info.json');
writeFileSync(target, `${JSON.stringify(info, null, 2)}\n`, 'utf-8');
console.log(`build-info: ${info.commit.slice(0, 7)} (${info.branch ?? 'detached'}) -> ${target}`);
