// SPDX-License-Identifier: AGPL-3.0-only
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { readdirSync, readFileSync } from 'node:fs';
import path from 'node:path';
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

  // Every catalogue the site ships, so a new language is held to it too.
  const messagesDir = path.join(__dirname, '..', 'messages');
  const catalogues = readdirSync(messagesDir)
    .filter((name) => name.endsWith('.json'))
    .map((name) => [name.slice(0, -'.json'.length), path.join(messagesDir, name)] as const);

  it('checks every locale', () => {
    expect(catalogues.map(([locale]) => locale)).toEqual(expect.arrayContaining(['en', 'de']));
  });

  for (const [locale, file] of catalogues) {
    it(`points at a heading that exists in the ${locale} privacy policy`, () => {
      const messages = JSON.parse(readFileSync(file, 'utf8')) as { cookies: { anchor: string } };
      const anchor = messages.cookies.anchor;
      const page = loadLegal(locale, 'privacy');
      expect(page).not.toBeNull();
      // The locale's own policy, not the English fallback.
      expect(page?.translated).toBe(true);
      // rehype-slug mints the ids, so this catches a renamed or translated
      // heading before the link silently goes nowhere.
      expect(page?.html).toContain(`id="${anchor}"`);
    });
  }
});
