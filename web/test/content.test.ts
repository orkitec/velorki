// SPDX-License-Identifier: AGPL-3.0-only
import { describe, expect, it } from 'vitest';
import { contentFile, docSlugs, loadDoc, loadLegal, translatedLocales } from '@/site/content';
import { renderMarkdown } from '@/site/markdown';

describe('content loader', () => {
  it('serves a known docs slug and falls back to English', () => {
    expect(docSlugs()).toContain('getting-started');
    expect(loadDoc('en', 'getting-started')?.translated).toBe(true);
    // A locale without content (no site language is "xx") falls back to the
    // English file.
    expect(loadDoc('xx', 'getting-started')?.translated).toBe(false);
  });

  it('names the locales a page is written in and the file each one reads', () => {
    // The imprint is in English and German; every other locale shows the
    // English text, which the sitemap and hreflang leave out.
    expect(translatedLocales('legal', 'imprint')).toEqual(['en', 'de']);
    expect(translatedLocales('docs', 'getting-started')).toContain('en');
    expect(contentFile('de', 'docs', 'getting-started')).toBe('content/de/docs/getting-started.md');
    expect(contentFile('xx', 'docs', 'getting-started')).toBe('content/en/docs/getting-started.md');
    expect(contentFile('en', 'docs', 'no-such-page')).toBeNull();
  });

  it('refuses anything that is not a plain slug', () => {
    for (const slug of ['../en/legal/privacy', 'legal/privacy', '..', 'Getting-Started', 'a b', '']) {
      expect(loadDoc('en', slug)).toBeNull();
    }
    expect(loadLegal('../../en/docs', 'privacy')).toBeNull();
    expect(loadDoc('en/../de', 'getting-started')).toBeNull();
  });
});

describe('markdown pipeline', () => {
  it('neutralises a javascript: link and a script tag', () => {
    const { html } = renderMarkdown(
      [
        '## Heading',
        '',
        '[click me](javascript:alert(1))',
        '',
        '<script>alert(2)</script>',
        '',
        '<a href="https://example.com" onclick="alert(3)">ok</a>',
      ].join('\n'),
      'Fallback',
    );
    expect(html).not.toContain('javascript:');
    expect(html).not.toContain('<script');
    expect(html).not.toContain('onclick');
    expect(html).toContain('click me');
  });

  it('keeps the heading id and the anchor the pipeline adds', () => {
    const { html, headings } = renderMarkdown('## A heading\n', 'Fallback');
    expect(html).toContain('id="a-heading"');
    expect(html).not.toContain('user-content-');
    expect(html).toContain('class="anchor"');
    expect(html).toContain('href="#a-heading"');
    // Reachable by keyboard: no aria-hidden, no tabindex=-1.
    expect(html).not.toContain('aria-hidden="true"');
    expect(html).not.toContain('tabindex="-1"');
    expect(html).toContain('aria-label="Link to this section"');
    // The anchor is not part of the heading text.
    expect(headings).toEqual([{ depth: 2, id: 'a-heading', text: 'A heading' }]);
  });

  it('reads draft out of the front matter', () => {
    expect(renderMarkdown('---\ntitle: T\ndraft: true\n---\n\nBody\n', 'F').frontMatter.draft).toBe(true);
    expect(renderMarkdown('---\ntitle: T\n---\n\nBody\n', 'F').frontMatter.draft).toBe(false);
  });
});
