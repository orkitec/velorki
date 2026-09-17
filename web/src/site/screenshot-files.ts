// SPDX-License-Identifier: AGPL-3.0-only
// The build-time half of the screenshot manifest: which files the pipeline has
// actually produced. Server components only — it touches the filesystem.
import { existsSync } from 'node:fs';
import path from 'node:path';
import { ACCENTS, MODES, type Screen, type VariantKey, variantKey } from './screenshots';

/**
 * Which variants of `screen` are on disk. The result is a plain object of
 * booleans so it can cross to the client component that swaps the image when
 * the appearance switcher changes.
 */
export function availableVariants(screen: Screen): Record<string, boolean> {
  const available: Record<string, boolean> = {};
  for (const mode of MODES) {
    for (const accent of ACCENTS) {
      const key: VariantKey = variantKey(mode, accent);
      available[key] = existsSync(path.join(process.cwd(), 'public', 'screenshots', key, `${screen}.png`));
    }
  }
  return available;
}
