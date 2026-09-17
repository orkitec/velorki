// SPDX-License-Identifier: AGPL-3.0-only
import { describe, expect, it } from 'vitest';
import { docSlugs, loadDoc, loadLegal } from '@/site/content';

describe('content loader', () => {
  it('serves a known docs slug and falls back to English', () => {
    expect(docSlugs()).toContain('getting-started');
    expect(loadDoc('en', 'getting-started')?.translated).toBe(true);
    // A locale without content falls back to the English file.
    expect(loadDoc('fr', 'getting-started')?.translated).toBe(false);
  });

  it('refuses anything that is not a plain slug', () => {
    for (const slug of ['../en/legal/privacy', 'legal/privacy', '..', 'Getting-Started', 'a b', '']) {
      expect(loadDoc('en', slug)).toBeNull();
    }
    expect(loadLegal('../../en/docs', 'privacy')).toBeNull();
    expect(loadDoc('en/../de', 'getting-started')).toBeNull();
  });
});
