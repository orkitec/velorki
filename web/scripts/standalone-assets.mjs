// SPDX-License-Identifier: AGPL-3.0-only
// `next build` with output: 'standalone' does not copy public/ or .next/static
// into the standalone tree; this does, so `node .next/standalone/server.js`
// (and orkify) serve the assets. Runs as npm's postbuild.
import { cpSync, existsSync } from 'node:fs';

const root = new URL('..', import.meta.url).pathname;
const standalone = `${root}.next/standalone/`;
if (!existsSync(standalone)) {
  console.error('no .next/standalone: run `next build` first');
  process.exit(1);
}
cpSync(`${root}.next/static`, `${standalone}.next/static`, { recursive: true });
if (existsSync(`${root}public`)) cpSync(`${root}public`, `${standalone}public`, { recursive: true });
console.log('standalone: copied .next/static and public/');
