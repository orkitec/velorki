// SPDX-License-Identifier: AGPL-3.0-only
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { HeaderMenu, type HeaderLink } from '@/components/HeaderMenu';

/**
 * Below `md` the header is the wordmark plus three 44 px controls, and the nav
 * links live in this menu. SiteHeader itself is a server component holding
 * translations; the menu is the pure half, and its markup is the contract: a
 * `<details>` a reader without JavaScript can open, real links inside it, and
 * the Download call to action at the bottom.
 */
const LINKS: HeaderLink[] = [
  { href: '/de#features', label: 'Funktionen' },
  { href: '/de/docs', label: 'Doku' },
  { href: '/de/plus', label: 'Plus' },
  { href: 'https://github.com/orkitec/velorki', label: 'GitHub', external: true },
];

const DOWNLOAD: HeaderLink = { href: '/de/download', label: 'Download' };

function render() {
  return renderToStaticMarkup(<HeaderMenu label="Menü" navLabel="Haupt" links={LINKS} download={DOWNLOAD} />);
}

describe('small-screen header menu', () => {
  it('opens without JavaScript and says what it is', () => {
    const html = render();
    expect(html).toContain('<details');
    expect(html).toContain('<summary');
    expect(html).toContain('aria-label="Menü"');
    // The links keep a landmark of their own: the wide row's nav is not in the
    // tree at this width.
    expect(html).toMatch(/<nav[^>]*aria-label="Haupt"/);
    // The disclosure is the browser's own: nothing here is a handler.
    expect(html).not.toContain('onclick');
  });

  it('carries every nav link and the download button', () => {
    const html = render();
    for (const link of LINKS) expect(html, link.label).toContain(`href="${link.href}"`);
    expect(html).toContain(`href="${DOWNLOAD.href}"`);
    expect(html).toContain('btn btn-primary');
  });

  it('leaves the site for GitHub with a plain anchor, and stays on it for the rest', () => {
    const html = render();
    expect(html).toMatch(/<a[^>]*href="https:\/\/github.com\/orkitec\/velorki"[^>]*rel="noreferrer"/);
    // next/link renders an anchor too; what matters is that the external one
    // is not routed and the internal ones are not absolute.
    expect(html).not.toContain('href="https://github.com/orkitec/velorki" data-prefetch');
  });

  it('is the small-screen half only, and its rows are thumb-sized', () => {
    const html = render();
    expect(html).toContain('md:hidden');
    // Every row at least 44 px: min-h-11 on the links, a taller pill below.
    expect(html.match(/min-h-11/g)).toHaveLength(LINKS.length);
    expect(html).toContain('h-11 w-11');
    expect(html).toContain('!min-h-12');
  });
});
