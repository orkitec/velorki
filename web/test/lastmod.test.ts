// SPDX-License-Identifier: AGPL-3.0-only
import { describe, expect, it } from 'vitest';
import { lastModified, parseGitLog } from '@/site/lastmod';

describe('parseGitLog', () => {
  it('keeps the newest date a file is seen with', () => {
    const output = [
      '\u00002026-10-20T10:00:00-04:00',
      '',
      'content/en/docs/library.md',
      'messages/en.json',
      '\u00002026-10-01T09:00:00-04:00',
      '',
      'content/en/docs/library.md',
      'content/de/docs/library.md',
      '',
    ].join('\n');
    expect(parseGitLog(output)).toEqual({
      'content/en/docs/library.md': '2026-10-20T10:00:00-04:00',
      'messages/en.json': '2026-10-20T10:00:00-04:00',
      'content/de/docs/library.md': '2026-10-01T09:00:00-04:00',
    });
  });

  it('is empty for no history', () => {
    expect(parseGitLog('')).toEqual({});
  });
});

describe('lastModified', () => {
  const dates = { a: '2026-10-01T00:00:00Z', b: '2026-10-05T00:00:00Z' };

  it('is the latest of the files that have a date', () => {
    expect(lastModified(['a', 'b', 'c'], dates)).toEqual(new Date('2026-10-05T00:00:00Z'));
  });

  it('is undefined when none has one', () => {
    expect(lastModified(['c'], dates)).toBeUndefined();
  });
});
