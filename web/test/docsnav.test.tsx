// SPDX-License-Identifier: AGPL-3.0-only
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { DocsList } from '@/components/DocsNav';
import type { DocEntry } from '@/site/content';
import type { Heading } from '@/site/markdown';
import { activeHeadingId, docToc } from '@/site/toc';

function doc(slug: string, title: string): DocEntry {
  return { slug, title, description: '', order: 1, draft: false };
}

const DOCS = [doc('navigation', 'Navigation'), doc('search', 'Search')];

const HEADINGS: Heading[] = [
  { depth: 2, id: 'turn-it-on', text: 'Turn it on' },
  { depth: 2, id: 'when-you-leave-the-route', text: 'When you leave the route' },
  { depth: 3, id: 'guide-you-back', text: 'Guide you back' },
  { depth: 3, id: 'compute-a-detour', text: 'Compute a detour' },
  { depth: 2, id: 'the-map', text: 'The map' },
];

function render(current: string, headings: Heading[]) {
  return renderToStaticMarkup(
    <DocsList locale="en" docs={DOCS} current={current} sections={docToc(headings)} />,
  );
}

/**
 * The menu is static markup: the section list has to be in the HTML the server
 * sends, because TocSpy only marks what is already there and a reader without
 * JavaScript gets the same links.
 */
describe('docs menu markup', () => {
  it('unfolds the open page into h2 entries with the h3s nested under them', () => {
    const html = render('navigation', HEADINGS);
    for (const heading of HEADINGS) expect(html, heading.id).toContain(`href="#${heading.id}"`);
    // Every anchor is one the spy can find.
    expect(html.match(/data-toc-id=/g)).toHaveLength(HEADINGS.length);
    // The h3s live in a list of their own, inside their h2's item.
    expect(html).toMatch(
      /href="#when-you-leave-the-route"[\s\S]*?<ul[^>]*>[\s\S]*?href="#guide-you-back"[\s\S]*?href="#compute-a-detour"[\s\S]*?<\/ul>/,
    );
    // A tree: the sections indented past the page titles, the h3s past those.
    expect(html).toContain('toc-link pl-7"');
    expect(html).toContain('toc-link pl-11"');
    // Only under the page that is open.
    expect(html).toMatch(/aria-current="page"[^>]*href="\/docs\/navigation"/);
    expect(html.split('href="/docs/search"')[1]).not.toContain('data-toc-id');
  });

  it('renders no section list for a page with a single heading, or none at all', () => {
    for (const headings of [[], [HEADINGS[0]!]]) {
      const html = render('navigation', headings);
      expect(html).not.toContain('data-toc-id');
      expect(html).not.toContain('toc-link');
      // The page list itself is untouched.
      expect(html).toContain('href="/docs/navigation"');
      expect(html).toContain('href="/docs/search"');
    }
  });

  it('unfolds whichever page is open, and only that one', () => {
    // The same headings under the second entry: the list follows `current`.
    const html = render('search', HEADINGS);
    expect(html.split('href="/docs/search"')[0]).not.toContain('data-toc-id');
    expect(html.split('href="/docs/search"')[1]).toContain('data-toc-id="turn-it-on"');
  });
});

/**
 * The whole of the scroll spy's decision, without a DOM: given where the
 * headings are and where the reader is, which one are they in.
 */
describe('active heading', () => {
  const tops = [
    { id: 'one', top: 400 },
    { id: 'two', top: 1200 },
    { id: 'three', top: 2000 },
  ];
  const view = (scrollY: number, documentHeight = 100000) => ({ scrollY, viewportHeight: 900, documentHeight });

  it('marks the last heading above the viewport top third', () => {
    // Line at 300: still above the first heading.
    expect(activeHeadingId(tops, view(0))).toBeNull();
    // Line at 400: the first heading has just reached it.
    expect(activeHeadingId(tops, view(100))).toBe('one');
    expect(activeHeadingId(tops, view(800))).toBe('one');
    // Line at 1200.
    expect(activeHeadingId(tops, view(900))).toBe('two');
    expect(activeHeadingId(tops, view(1699))).toBe('two');
    expect(activeHeadingId(tops, view(1700))).toBe('three');
    expect(activeHeadingId(tops, view(9000))).toBe('three');
  });

  it('marks the last heading once the page is scrolled to the bottom', () => {
    // A short final section never reaches the line on its own.
    const short = [
      { id: 'one', top: 400 },
      { id: 'last', top: 1500 },
    ];
    expect(activeHeadingId(short, { scrollY: 700, viewportHeight: 900, documentHeight: 1600 })).toBe('last');
    // Without a document height the bottom rule is off.
    expect(activeHeadingId(short, { scrollY: 700, viewportHeight: 900 })).toBe('one');
  });

  it('has no answer without headings', () => {
    expect(activeHeadingId([], view(500))).toBeNull();
  });
});

describe('section tree', () => {
  it('keeps document order and hangs each h3 on the h2 above it', () => {
    expect(docToc(HEADINGS)).toEqual([
      { id: 'turn-it-on', text: 'Turn it on', children: [] },
      {
        id: 'when-you-leave-the-route',
        text: 'When you leave the route',
        children: [
          { id: 'guide-you-back', text: 'Guide you back' },
          { id: 'compute-a-detour', text: 'Compute a detour' },
        ],
      },
      { id: 'the-map', text: 'The map', children: [] },
    ]);
  });

  it('gives an h3 before the first h2 an entry of its own rather than dropping it', () => {
    const headings: Heading[] = [
      { depth: 3, id: 'stray', text: 'Stray' },
      { depth: 2, id: 'proper', text: 'Proper' },
    ];
    expect(docToc(headings).map((section) => section.id)).toEqual(['stray', 'proper']);
  });

  it('is empty below the threshold', () => {
    expect(docToc([])).toEqual([]);
    expect(docToc([HEADINGS[0]!])).toEqual([]);
  });
});
