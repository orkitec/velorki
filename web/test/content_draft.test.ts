// SPDX-License-Identifier: AGPL-3.0-only
// A translation marked `draft: true` renders with noindex, so the sitemap and
// the hreflang set must not list it. No live text is a draft right now, so the
// German privacy policy is read as one here.
import path from 'node:path';
import { describe, expect, it, vi } from 'vitest';

const DRAFTED = path.join(process.cwd(), 'content', 'de', 'legal', 'privacy.md');

vi.mock('node:fs', async (importOriginal) => {
  const fs = await importOriginal<typeof import('node:fs')>();
  const original = fs.readFileSync as (...args: unknown[]) => string | Buffer;
  const readFileSync = ((...args: unknown[]) => {
    const text = original(...args);
    if (args[0] === DRAFTED && typeof text === 'string') return text.replace(/^draft: false$/m, 'draft: true');
    return text;
  }) as unknown as typeof fs.readFileSync;
  return { ...fs, readFileSync };
});

describe('translatedLocales with a draft translation', () => {
  it('leaves a draft out of the locales a page is written in', async () => {
    const { translatedLocales } = await import('@/site/content');
    const privacy = translatedLocales('legal', 'privacy');
    expect(privacy).toContain('en');
    expect(privacy).toContain('fr');
    expect(privacy).not.toContain('de');
  });
});
