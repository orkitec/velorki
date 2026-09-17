// SPDX-License-Identifier: AGPL-3.0-only
import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vitest/config';

export default defineConfig({
  // tsconfig says `jsx: react-jsx`, which is what tsc and the editor use; the
  // test runner transforms the .tsx files itself and needs telling separately.
  oxc: { jsx: { runtime: 'automatic', importSource: 'react' } },
  resolve: { alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) } },
  test: {
    include: ['test/**/*.test.ts', 'test/**/*.test.tsx'],
    environment: 'node',
    // Module-level state (counters, sqlite handles, singletons) must not leak
    // between files.
    isolate: true,
    pool: 'forks',
  },
});
