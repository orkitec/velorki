// SPDX-License-Identifier: AGPL-3.0-only
import { describe, expect, it } from 'vitest';
import { docSlugs, loadDoc, loadLegal } from '@/site/content';
import { renderMarkdown } from '@/site/markdown';

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
