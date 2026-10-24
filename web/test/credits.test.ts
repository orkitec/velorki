// SPDX-License-Identifier: AGPL-3.0-only
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { routing } from '@/i18n/routing';
import { CREDITS } from '@/site/credits';

/** The names `app/lib/app/licenses.dart` registers, in its order. */
function appLicenceNames(): string[] {
  const dart = readFileSync(join(process.cwd(), '../app/lib/app/licenses.dart'), 'utf8');
  const constants = new Map(
    [...dart.matchAll(/const String (_\w+) = '([^']+)';/g)].map((m) => [m[1], m[2]] as const),
  );
  return [...dart.matchAll(/_DataLicense\(\s*(?:'([^']+)'|(_\w+))/g)].map(
    (m) => m[1] ?? constants.get(m[2] ?? '') ?? `unknown constant ${m[2] ?? ''}`,
  );
}

describe('credits', () => {
  it('stand for every entry of the app’s licence page, in its order', () => {
    const names = appLicenceNames();
    expect(names.length).toBeGreaterThan(5);
    const fromSite = CREDITS.flatMap((c) => c.app);
    expect([...fromSite].sort()).toEqual([...names].sort());
    // The order is the app's, apart from the fonts, which the site keeps together.
    const fonts = (n: string) => n.endsWith('(font)');
    expect(fromSite.filter((n) => !fonts(n))).toEqual(names.filter((n) => !fonts(n)));
  });

  it('have a title, a body and a licence in every language', () => {
    for (const locale of routing.locales) {
      const messages = JSON.parse(
        readFileSync(join(process.cwd(), `messages/${locale}.json`), 'utf8'),
      ) as { credits: { items: Record<string, Record<string, string>> } };
      for (const credit of CREDITS) {
        const item = messages.credits.items[credit.id];
        for (const key of ['title', 'body', 'licence']) {
          expect(item?.[key]?.trim(), `${locale} ${credit.id}.${key}`).toBeTruthy();
        }
      }
      expect(Object.keys(messages.credits.items).sort()).toEqual(CREDITS.map((c) => c.id).sort());
    }
  });
});
