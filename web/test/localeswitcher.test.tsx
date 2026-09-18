// SPDX-License-Identifier: AGPL-3.0-only
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { LocaleSwitcherMenu } from '@/components/LocaleSwitcherMenu';
import { localeName, localeNames } from '@/site/locales';
import { LOCALES } from '@/site/paths';

/**
 * The switcher's contract is the markup, not a click handler: every entry has
 * to be a real `<a>` doing a full navigation.
 *
 * A `next/link` here made the switch a soft navigation, and next-intl only
 * sets NEXT_LOCALE on a document request - it will not let a prefetch or a
 * router revalidation change the reader's language. The 307 from `/en` came
 * back without its cookie, the follow-up request for `/` still said German,
 * and the page never switched. These tests are what keeps a `<Link>` from
 * creeping back in.
 */
describe('locale switcher markup', () => {
  function render(current: string, pathname = '/') {
    return renderToStaticMarkup(
      <LocaleSwitcherMenu current={current} pathname={pathname} label="Sprache" />,
    );
  }

  it('links every locale with a plain anchor, prefix included', () => {
    const html = render('de', '/docs/loops');
    for (const locale of LOCALES) {
      expect(html, locale).toContain(`href="/${locale}/docs/loops"`);
      expect(html, locale).toContain(`hrefLang="${locale}"`);
    }
    // A soft navigation cannot carry the locale cookie; nothing here may be a
    // router link.
    expect(html).not.toContain('data-prefetch');
    expect(html).not.toContain('<button');
  });

  it('keeps the prefix on the home page too, so /en resets a German cookie', () => {
    const html = render('de');
    expect(html).toContain('href="/en"');
    expect(html).toContain('href="/de"');
    expect(html).not.toContain('href="/"');
  });

  it('names every language in its own words and marks the current one', () => {
    const html = render('de');
    for (const { name } of localeNames()) expect(html).toContain(name);
    // The summary shows what the reader is reading now.
    expect(html).toContain(localeName('de'));
    expect(html).toMatch(/href="\/de"[^>]*aria-current="page"/);
    expect(html).not.toMatch(/href="\/en"[^>]*aria-current/);
  });

  it('opens without JavaScript and labels itself', () => {
    const html = render('en');
    expect(html).toContain('<details');
    expect(html).toContain('<summary');
    expect(html).toContain('aria-label="Sprache"');
  });
});

describe('native locale names', () => {
  it('falls back to the code for a locale nobody has named yet', () => {
    expect(localeName('en')).toBe('English');
    expect(localeName('de')).toBe('Deutsch');
    expect(localeName('fr')).toBe('FR');
  });
});
