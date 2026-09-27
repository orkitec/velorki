// SPDX-License-Identifier: AGPL-3.0-only
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import de from '@/../messages/de.json';
import en from '@/../messages/en.json';
import { CookieNoticeCard } from '@/components/CookieNotice';
import { loadLegal } from '@/site/content';

/**
 * The notice is informational, not a consent gate: velorki.com stores nothing
 * until a visitor asks for it, and none of it is tracking. What the tests hold
 * is that it stays that way - one button, no third-party anything - and that the
 * link it offers actually lands on the section it promises.
 */
const STRINGS = { label: 'l', body: 'b', link: 'k', dismiss: 'd' };

describe('cookie notice', () => {
  it('is a notice with a single dismiss button and a link to the policy', () => {
    const html = renderToStaticMarkup(
      <CookieNoticeCard strings={STRINGS} href="/privacy#this-website" />,
    );
    expect(html).toContain('href="/privacy#this-website"');
    // One button, so there is no accept/reject pair to mistake for a choice.
    expect(html.match(/<button/g)).toHaveLength(1);
    expect(html).toContain('aria-label="l"');
  });

  for (const [locale, messages] of [
    ['en', en],
    ['de', de],
  ] as const) {
    it(`points at a heading that exists in the ${locale} privacy policy`, () => {
      const anchor = messages.cookies.anchor;
      const page = loadLegal(locale, 'privacy');
      expect(page).not.toBeNull();
      // rehype-slug mints the ids, so this catches a renamed or translated
      // heading before the link silently goes nowhere.
      expect(page?.html).toContain(`id="${anchor}"`);
    });
  }
});
