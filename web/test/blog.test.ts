// SPDX-License-Identifier: AGPL-3.0-only
// The blog against the posts in test/fixtures/blog, never the real ones in
// content/: an English post with a German version under another slug
// (hello-world / hallo-welt, key `hello`), an English ride in a folder with a
// cover, a picture and a GPX, and an English draft. Spanish, French, Italian
// and Dutch have no posts of their own.
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import {
  allPosts,
  blogIndexed,
  blogListing,
  blogRouteExists,
  blogSwitchPairs,
  configureBlog,
  coverImage,
  feedXml,
  findPost,
  mediaPath,
  postsIn,
  readMedia,
  renderPost,
} from '@/site/blog';
import { blogSitemap, postMetadata } from '@/site/blog-pages';
import { localeSwitchHref } from '@/site/blog-switch';
import { blogPostingJsonLd } from '@/site/jsonld';
import { renderBody } from '@/site/markdown';
import { pageMetadata } from '@/site/seo';

const FIXTURES = path.join(process.cwd(), 'test', 'fixtures', 'blog');
const SITE = 'https://velorki.com';
const STRINGS = { feedTitle: 'Velorki blog', section: 'Engineering' };
const FEED = {
  title: 'Velorki blog',
  description: 'Notes.',
  categories: { engineering: 'Engineering', rides: 'Rides' },
};

beforeEach(() => configureBlog({ root: FIXTURES, drafts: false }));
afterEach(() => {
  configureBlog(null);
  vi.unstubAllEnvs();
});

/** A content root holding one English post with `front` and `body`, and the path of the post. */
function tempPost(front: string, body = 'Text.\n', files: Record<string, string> = {}): { root: string; file: string } {
  const root = mkdtempSync(path.join(tmpdir(), 'velorki-blog-'));
  const dir = path.join(root, 'en', 'blog', 'post');
  mkdirSync(dir, { recursive: true });
  const file = path.join(dir, 'index.md');
  writeFileSync(file, `---\n${front}\n---\n\n${body}`);
  for (const [name, content] of Object.entries(files)) writeFileSync(path.join(dir, name), content);
  configureBlog({ root, drafts: false });
  return { root, file };
}

const VALID = [
  'title: A post',
  'description: One sentence.',
  'date: 2026-11-01',
  'author: steffen',
  'category: engineering',
];

describe('front matter', () => {
  const cases: Array<[string, string[], RegExp]> = [
    ['a missing title', VALID.filter((line) => !line.startsWith('title')), /`title` is required/],
    ['a missing description', VALID.filter((line) => !line.startsWith('description')), /`description` is required/],
    ['a missing date', VALID.filter((line) => !line.startsWith('date')), /`date` is required/],
    ['a missing author', VALID.filter((line) => !line.startsWith('author')), /`author` is required/],
    ['a missing category', VALID.filter((line) => !line.startsWith('category')), /`category` is required/],
    ['an unknown author', [...VALID.filter((line) => !line.startsWith('author')), 'author: nobody'], /`author` nobody/],
    ['an unknown category', [...VALID.filter((line) => !line.startsWith('category')), 'category: news'], /`category` must be/],
    ['a date that is not a day', [...VALID.filter((line) => !line.startsWith('date')), "date: '2026-02-30'"], /`date` must be/],
    ['an update before the date', [...VALID, 'updated: 2026-10-01'], /`updated` is before `date`/],
    ['a description over 160 characters', [...VALID.slice(0, 1), `description: ${'x'.repeat(161)}`, ...VALID.slice(2)], /161 characters/],
    ['a misspelt field', [...VALID, 'catgory: rides'], /unknown front-matter field `catgory`/],
    ['a draft that is not a boolean', [...VALID, 'draft: yes please'], /`draft` must be true or false/],
    ['a cover that is not there', [...VALID, 'image: cover.png'], /cover.png is not beside the post/],
    ['a description of a cover there is not', [...VALID, 'imageAlt: A loop'], /`imageAlt` without an `image`/],
  ];

  for (const [what, front, problem] of cases) {
    it(`fails the build on ${what}, naming the file`, () => {
      const { root, file } = tempPost(front.join('\n'));
      try {
        expect(() => allPosts()).toThrow(problem);
        expect(() => allPosts()).toThrow(path.relative(process.cwd(), file).split(path.sep).join('/'));
      } finally {
        rmSync(root, { recursive: true, force: true });
      }
    });
  }

  it('reads the fixtures, newest first, with key and folder', () => {
    expect(allPosts().map((post) => `${post.locale}/${post.slug}`)).toEqual([
      'en/ride-madeira',
      'de/hallo-welt',
      'en/hello-world',
    ]);
    const hello = findPost('en', 'hello-world')!;
    expect(hello).toMatchObject({ key: 'hello', date: '2026-10-01', updated: '2026-10-05', dir: null });
    // The leading `# Hello world` repeats the title; the page has its own h1.
    expect(hello.markdown.startsWith('A short post')).toBe(true);
    expect(findPost('en', 'ride-madeira')).toMatchObject({ key: 'ride-madeira', image: 'cover.png', gpx: 'ride.gpx' });
  });
});

describe('drafts', () => {
  it('are left out of a production build', () => {
    vi.stubEnv('NODE_ENV', 'production');
    configureBlog({ root: FIXTURES });
    expect(findPost('en', 'unfinished')).toBeNull();
    expect(blogRouteExists('en', ['unfinished'])).toBe(false);
    expect(feedXml('en', FEED)).not.toContain('unfinished');
    expect(blogSitemap().map((entry) => entry.url)).not.toContain(`${SITE}/blog/unfinished`);
  });

  it('show under next dev, but never in a feed or the sitemap', () => {
    vi.stubEnv('NODE_ENV', 'development');
    configureBlog({ root: FIXTURES });
    expect(findPost('en', 'unfinished')?.draft).toBe(true);
    expect(postsIn('en').map((post) => post.slug)).toContain('unfinished');
    expect(feedXml('en', FEED)).not.toContain('unfinished');
    expect(blogSitemap().map((entry) => entry.url)).not.toContain(`${SITE}/blog/unfinished`);
    expect(postMetadata(findPost('en', 'unfinished')!, STRINGS).robots).toMatchObject({ index: false });
  });
});

describe('a post in one language', () => {
  it('exists at its own address only', () => {
    expect(findPost('en', 'ride-madeira')).not.toBeNull();
    expect(findPost('de', 'ride-madeira')).toBeNull();
    expect(blogRouteExists('en', ['ride-madeira'])).toBe(true);
    expect(blogRouteExists('en', ['ride-madeira', 'og-card'])).toBe(true);
    expect(blogRouteExists('de', ['ride-madeira'])).toBe(false);
    expect(blogRouteExists('de', ['ride-madeira', 'og-card'])).toBe(false);
    expect(blogRouteExists('de', ['hallo-welt'])).toBe(true);
    expect(blogRouteExists('en', ['hallo-welt'])).toBe(false);
  });

  it('knows the listing pages and nothing else', () => {
    expect(blogRouteExists('es', [])).toBe(true);
    expect(blogRouteExists('es', ['feed.xml'])).toBe(true);
    expect(blogRouteExists('es', ['category', 'rides'])).toBe(true);
    expect(blogRouteExists('es', ['category', 'news'])).toBe(false);
    expect(blogRouteExists('es', ['authors', 'steffen'])).toBe(true);
    expect(blogRouteExists('es', ['authors', 'nobody'])).toBe(false);
    expect(blogRouteExists('en', ['hello-world', 'extra'])).toBe(false);
  });

  it('is listed on another language index under its own heading', () => {
    const de = blogListing('de');
    expect(de.own.map((post) => post.slug)).toEqual(['hallo-welt']);
    // hello-world has a German version, which is listed instead.
    expect(de.english.map((post) => post.slug)).toEqual(['ride-madeira']);
    expect(blogListing('es').english.map((post) => post.slug)).toEqual(['ride-madeira', 'hello-world']);
    expect(blogListing('en').english).toEqual([]);
  });

  it('is in the sitemap in its own language only', () => {
    const urls = blogSitemap().map((entry) => entry.url);
    expect(urls).toContain(`${SITE}/blog/ride-madeira`);
    expect(urls.filter((url) => url.endsWith('/blog/ride-madeira'))).toHaveLength(1);
    expect(urls).toContain(`${SITE}/de/blog/hallo-welt`);
    expect(urls).not.toContain(`${SITE}/de/blog/hello-world`);
  });
});

describe('hreflang', () => {
  it('pairs the versions sharing a key, each at its own slug, x-default English', () => {
    const expected = {
      en: `${SITE}/blog/hello-world`,
      de: `${SITE}/de/blog/hallo-welt`,
      'x-default': `${SITE}/blog/hello-world`,
    };
    const en = postMetadata(findPost('en', 'hello-world')!, STRINGS);
    const de = postMetadata(findPost('de', 'hallo-welt')!, STRINGS);
    expect(en.alternates?.languages).toEqual(expected);
    expect(de.alternates?.languages).toEqual(expected);
    expect(en.alternates?.canonical).toBe(expected.en);
    expect(de.alternates?.canonical).toBe(expected.de);
    const entry = blogSitemap().find((item) => item.url === expected.de);
    expect(entry?.alternates?.languages).toEqual(expected);
  });

  it('points x-default at the post itself when there is no English version', () => {
    const { root } = tempPost(VALID.join('\n'));
    try {
      // Move the temp post into German by pointing the root at a copy.
      const de = path.join(root, 'de', 'blog');
      mkdirSync(de, { recursive: true });
      writeFileSync(path.join(de, 'nur-deutsch.md'), `---\n${VALID.join('\n')}\n---\n\nText.\n`);
      configureBlog({ root, drafts: false });
      const meta = postMetadata(findPost('de', 'nur-deutsch')!, STRINGS);
      expect(meta.alternates?.languages).toEqual({
        de: `${SITE}/de/blog/nur-deutsch`,
        'x-default': `${SITE}/de/blog/nur-deutsch`,
      });
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });

  it('makes a post an article with its dates and author', () => {
    const meta = postMetadata(findPost('en', 'hello-world')!, STRINGS);
    expect(meta.openGraph).toMatchObject({
      type: 'article',
      publishedTime: '2026-10-01',
      modifiedTime: '2026-10-05',
      authors: [`${SITE}/blog/authors/steffen`],
    });
    expect(meta.alternates?.types).toEqual({
      'application/rss+xml': [{ url: `${SITE}/blog/feed.xml`, title: 'Velorki blog' }],
    });
  });

  it('shares the cover where there is one, and the card with the title otherwise', () => {
    const ride = findPost('en', 'ride-madeira')!;
    const withCover = postMetadata(ride, STRINGS).openGraph?.images;
    expect(withCover).toEqual([{ url: `${SITE}${mediaPath(ride, 'cover.png')}`, width: 12, height: 8, alt: ride.title }]);
    const card = postMetadata(findPost('de', 'hallo-welt')!, STRINGS).openGraph?.images;
    expect(card).toMatchObject([{ url: `${SITE}/de/blog/hallo-welt/og-card`, width: 1200, height: 630 }]);
  });
});

describe('a language without posts of its own', () => {
  it('has an index that is noindex but followed, and is out of the sitemap', () => {
    expect(blogIndexed('en')).toBe(true);
    expect(blogIndexed('de')).toBe(true);
    expect(blogIndexed('es')).toBe(false);
    const meta = pageMetadata({
      locale: 'es',
      path: '/blog',
      title: 'Blog',
      description: 'x',
      noIndex: !blogIndexed('es'),
      follow: true,
    });
    expect(meta.robots).toEqual({ index: false, follow: true });
    const urls = blogSitemap().map((entry) => entry.url);
    expect(urls).toContain(`${SITE}/blog`);
    expect(urls).toContain(`${SITE}/de/blog`);
    expect(urls).not.toContain(`${SITE}/es/blog`);
    const index = blogSitemap().find((entry) => entry.url === `${SITE}/blog`);
    expect(Object.keys(index?.alternates?.languages ?? {}).sort()).toEqual(['de', 'en', 'x-default']);
  });

  it('applies the same rule to category and author pages', () => {
    const urls = blogSitemap().map((entry) => entry.url);
    expect(urls).toContain(`${SITE}/blog/category/rides`);
    expect(urls).toContain(`${SITE}/de/blog/category/engineering`);
    // German has no ride of its own.
    expect(urls).not.toContain(`${SITE}/de/blog/category/rides`);
    expect(urls).toContain(`${SITE}/de/blog/authors/steffen`);
    expect(urls).not.toContain(`${SITE}/es/blog/authors/steffen`);
  });
});

describe('feeds', () => {
  it('carries English posts in English', () => {
    const xml = feedXml('en', FEED);
    expect(xml).toContain('<rss version="2.0"');
    expect(xml).toContain(`<atom:link href="${SITE}/blog/feed.xml" rel="self"`);
    expect(xml).toContain(`<link>${SITE}/blog/hello-world</link>`);
    expect(xml).toContain(`<link>${SITE}/blog/ride-madeira</link>`);
    expect(xml).not.toContain('hallo-welt');
    expect(xml).toContain('<pubDate>Thu, 01 Oct 2026 00:00:00 GMT</pubDate>');
    expect(xml).toContain('<dc:creator>Steffen Römer</dc:creator>');
  });

  it("carries a language's own posts and the English ones", () => {
    const xml = feedXml('de', { ...FEED, categories: { engineering: 'Technik', rides: 'Fahrten' } });
    expect(xml).toContain('<language>de</language>');
    expect(xml).toContain(`<link>${SITE}/de/blog/hallo-welt</link>`);
    expect(xml).toContain(`<link>${SITE}/blog/ride-madeira</link>`);
    expect(xml).toContain('<category>Fahrten</category>');
    // Newest first, across both languages.
    expect(xml.indexOf('ride-madeira')).toBeLessThan(xml.indexOf('hallo-welt'));
    // hello-world is carried as its German version.
    expect(xml).not.toContain('hello-world');
    expect(feedXml('es', FEED)).toContain(`<link>${SITE}/blog/hello-world</link>`);
  });

  it('escapes what a title may contain', () => {
    const { root } = tempPost([...VALID.filter((l) => !l.startsWith('title')), 'title: "Fish & <chips>"'].join('\n'));
    try {
      expect(feedXml('en', FEED)).toContain('<title>Fish &amp; &lt;chips&gt;</title>');
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });
});

describe('the language switcher on a post', () => {
  it("links the paired post in the other language, at that post's slug", () => {
    const pairs = blogSwitchPairs('en');
    expect(localeSwitchHref('de', 'en', '/blog/hello-world', pairs)).toBe('/de/blog/hallo-welt');
    expect(localeSwitchHref('en', 'de', '/blog/hallo-welt', blogSwitchPairs('de'))).toBe('/en/blog/hello-world');
  });

  it("falls back to the other language's blog index", () => {
    const pairs = blogSwitchPairs('en');
    expect(localeSwitchHref('de', 'en', '/blog/ride-madeira', pairs)).toBe('/de/blog');
    expect(localeSwitchHref('es', 'en', '/blog/hello-world', pairs)).toBe('/es/blog');
  });

  it('keeps the path everywhere else, and on the current language', () => {
    expect(localeSwitchHref('en', 'en', '/blog/ride-madeira')).toBe('/en/blog/ride-madeira');
    expect(localeSwitchHref('de', 'en', '/blog')).toBe('/de/blog');
    expect(localeSwitchHref('de', 'en', '/blog/category/rides')).toBe('/de/blog/category/rides');
    expect(localeSwitchHref('de', 'en', '/blog/authors/steffen')).toBe('/de/blog/authors/steffen');
    expect(localeSwitchHref('de', 'en', '/docs/loops')).toBe('/de/docs/loops');
  });

  it('only carries the posts that have a version elsewhere', () => {
    expect(blogSwitchPairs('en')).toEqual({ '/blog/hello-world': { en: '/blog/hello-world', de: '/blog/hallo-welt' } });
  });
});

describe('JSON-LD', () => {
  it('describes a post as a BlogPosting by a Person, published by the Organization', () => {
    const data = blogPostingJsonLd({
      locale: 'de',
      path: '/blog/hallo-welt',
      title: 'Hallo Welt',
      description: 'Der erste Beitrag.',
      datePublished: '2026-10-02',
      image: `${SITE}/blog-media/x.png`,
      author: { name: 'Steffen Römer', url: `${SITE}/de/blog/authors/steffen`, sameAs: ['https://github.com/steffen-roemer'] },
      section: 'Technik',
    });
    expect(data).toEqual({
      '@context': 'https://schema.org',
      '@type': 'BlogPosting',
      headline: 'Hallo Welt',
      description: 'Der erste Beitrag.',
      url: `${SITE}/de/blog/hallo-welt`,
      mainEntityOfPage: { '@type': 'WebPage', '@id': `${SITE}/de/blog/hallo-welt` },
      image: [`${SITE}/blog-media/x.png`],
      datePublished: '2026-10-02',
      dateModified: '2026-10-02',
      inLanguage: 'de',
      articleSection: 'Technik',
      author: {
        '@type': 'Person',
        name: 'Steffen Römer',
        url: `${SITE}/de/blog/authors/steffen`,
        sameAs: ['https://github.com/steffen-roemer'],
      },
      publisher: { '@id': `${SITE}/#organization` },
      isPartOf: { '@id': `${SITE}/#website` },
    });
  });
});

describe('pictures and files', () => {
  it('serves a picture beside the post, lazily, with its size', () => {
    const ride = findPost('en', 'ride-madeira')!;
    const { html, readingMinutes } = renderPost(ride);
    const src = mediaPath(ride, 'coast.png');
    expect(src).toMatch(/^\/blog-media\/en\/ride-madeira\/[0-9a-f]{12}\/coast\.png$/);
    expect(html).toContain(`src="${src}"`);
    expect(html).toContain('alt="The coast road above the sea"');
    expect(html).toContain('width="6"');
    expect(html).toContain('height="4"');
    expect(html).toContain('loading="lazy"');
    expect(html).toContain(`href="${mediaPath(ride, 'ride.gpx')}"`);
    expect(readingMinutes).toBe(1);
    expect(coverImage(ride)).toEqual({
      src: mediaPath(ride, 'cover.png'),
      alt: 'The coast road above Funchal in the morning',
      width: 12,
      height: 8,
    });
  });

  it('fails the build on a picture without alt text, naming the file', () => {
    const { root, file } = tempPost(VALID.join('\n'), '![](photo.png)\n', { 'photo.png': 'x' });
    try {
      expect(() => renderPost(findPost('en', 'post')!)).toThrow(/photo.png has no alt text/);
      expect(() => renderPost(findPost('en', 'post')!)).toThrow(path.relative(process.cwd(), file).split(path.sep).join('/'));
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });

  it('fails the build on a picture that is not beside the post, or not on this site', () => {
    for (const body of ['![A photo](missing.png)\n', '![A photo](https://example.com/a.png)\n']) {
      const { root } = tempPost(VALID.join('\n'), body);
      try {
        expect(() => renderPost(findPost('en', 'post')!), body).toThrow(/a.png|missing.png/);
      } finally {
        rmSync(root, { recursive: true, force: true });
      }
    }
  });

  it('answers only the current hash of a file beside a published post', () => {
    const ride = findPost('en', 'ride-madeira')!;
    const [, , , , hash] = mediaPath(ride, 'cover.png').split('/');
    expect(readMedia('en', 'ride-madeira', hash!, 'cover.png')?.contentType).toBe('image/png');
    expect(readMedia('en', 'ride-madeira', '000000000000', 'cover.png')).toBeNull();
    expect(readMedia('de', 'ride-madeira', hash!, 'cover.png')).toBeNull();
    expect(readMedia('en', 'ride-madeira', hash!, 'index.md')).toBeNull();
    expect(readMedia('en', 'ride-madeira', hash!, '../hello-world.md')).toBeNull();
    const [, , , , gpxHash] = mediaPath(ride, 'ride.gpx').split('/');
    expect(readMedia('en', 'ride-madeira', gpxHash!, 'ride.gpx')?.contentType).toBe('application/gpx+xml');
  });
});

describe('code in a post', () => {
  const html = (markdown: string) => renderBody(markdown, () => undefined).html;

  it('colours a fence that names its language, Dart included', () => {
    const dart = html("```dart\nfinal speak = Speak();\nawait speak('Turn left.');\n```");
    expect(dart).toContain('<span class="hljs-keyword">final</span>');
    expect(dart).toContain('<span class="hljs-keyword">await</span>');
    expect(dart).toContain("<span class=\"hljs-string\">'Turn left.'</span>");
    expect(html('```ts\nconst a = 1;\n```')).toContain('<span class="hljs-keyword">const</span>');
  });

  it('leaves a fence without a language, and inline code, as plain text', () => {
    expect(html('```\nfinal a = 1;\n```')).not.toContain('<span');
    expect(html('The `final` keyword.')).toContain('<code>final</code>');
  });

  it('lets no other class through on a span', () => {
    const out = html('A <span class="hljs-keyword evil">word</span> here.');
    expect(out).not.toContain('evil');
  });
});
