// SPDX-License-Identifier: AGPL-3.0-only
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['test/**/*.test.ts'],
    environment: 'node',
    // Each test file gets its own process so module-level state (rate-limit
    // buckets, LRU caches, sqlite handles) cannot leak between files.
    isolate: true,
    pool: 'forks',
  },
});
