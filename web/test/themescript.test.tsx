// SPDX-License-Identifier: AGPL-3.0-only
// The theme script in the server's HTML: there, and doing what it says.
import { runInNewContext } from 'node:vm';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { ThemeScript } from '@/components/ThemeScript';
import { THEME_STORAGE_KEY } from '@/site/theme';

/** Runs the inline script against a stored value; returns the data-theme it set. */
function run(stored: string | null, storageThrows = false): string | null {
  const html = renderToStaticMarkup(<ThemeScript />);
  const source = html.match(/^<script>([\s\S]*)<\/script>$/)?.[1];
  expect(source).toBeDefined();
  let theme: string | null = null;
  const localStorage = {
    getItem: (key: string) => {
      if (storageThrows) throw new Error('blocked');
      return key === THEME_STORAGE_KEY ? stored : null;
    },
  };
  const document = { documentElement: { setAttribute: (_: string, value: string) => (theme = value) } };
  runInNewContext(source!, { localStorage, document });
  return theme;
}

describe('ThemeScript', () => {
  it('puts a stored light or dark back on <html> in the server render', () => {
    expect(run('dark')).toBe('dark');
    expect(run('light')).toBe('light');
  });

  it('leaves the system theme alone, and survives blocked storage', () => {
    expect(run(null)).toBeNull();
    expect(run('purple')).toBeNull();
    expect(run('dark', true)).toBeNull();
  });
});
