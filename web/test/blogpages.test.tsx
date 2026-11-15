// SPDX-License-Identifier: AGPL-3.0-only
// The blog's pages and the proxy in front of them, against test/fixtures/blog.
// next-intl's server half only resolves inside a bundler, so it stands in here
// as a catalogue lookup on messages/en.json; what is asserted is the pages'
// own decisions, not the translations.
import path from 'node:path';
import { renderToStaticMarkup } from 'react-dom/server';
import { NextRequest, NextResponse } from 'next/server';
import { getRewrittenUrl, isRewrite, unstable_doesMiddlewareMatch } from 'next/experimental/testing/server';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { LocaleSwitcherMenu } from '@/components/LocaleSwitcherMenu';
import { blogSwitchPairs, configureBlog } from '@/site/blog';
import messages from '../messages/en.json';
import { withEnv } from './helpers';

const FIXTURES = path.join(process.cwd(), 'test', 'fixtures', 'blog');
const SITE = 'https://velorki.com';

/** `t('a.b', {x})` over the English catalogue, with ICU arguments filled in plainly. */
function translator(namespace?: string) {
  const lookup = (key: string, values: Record<string, unknown> = {}): string => {
    const full = namespace ? `${namespace}.${key}` : key;
    let node: unknown = messages;
    for (const part of full.split('.')) node = (node as Record<string, unknown>)[part];
    if (typeof node !== 'string') throw new Error(`no message ${full}`);
    return node.replace(/\{(\w+)[^{}]*\}/g, (_, name: string) => `${values[name] as string | number | undefined ?? ''}`);
  };
  return Object.assign(lookup, { rich: lookup });
}

vi.mock('next-intl/server', () => ({
  getTranslations: async (options: { namespace?: string } | string) =>
    translator(typeof options === 'string' ? options : options.namespace),
  setRequestLocale: () => undefined,
}));

// Negotiation stands in as a redirect of everything to German, so a path that
// reaches it shows up as a `location`.
vi.mock('next-intl/middleware', () => ({
  default: () => (request: NextRequest): NextResponse =>
    NextResponse.redirect(new URL(`/de${request.nextUrl.pathname}`, request.url)),
}));

class NotFound extends Error {}
vi.mock('next/navigation', () => ({
  notFound: () => {
    throw new NotFound();
  },
}));

beforeEach(() => configureBlog({ root: FIXTURES, drafts: false }));
afterEach(() => configureBlog(null));

const params = <T,>(value: T) => ({ params: Promise.resolve(value) });

describe('the post page', () => {
  it('renders a post at its own address', async () => {
    const { generateMetadata, generateStaticParams } = await import('@/app/(site)/[locale]/blog/[slug]/page');
    expect(generateStaticParams()).toEqual([
      { locale: 'en', slug: 'ride-madeira' },
      { locale: 'de', slug: 'hallo-welt' },
      { locale: 'en', slug: 'hello-world' },
    ]);
    const meta = await generateMetadata(params({ locale: 'en', slug: 'ride-madeira' }));
    expect(meta.alternates?.canonical).toBe(`${SITE}/blog/ride-madeira`);
  });

  it('is notFound under another language', async () => {
    const { default: Page } = await import('@/app/(site)/[locale]/blog/[slug]/page');
    await expect(Page(params({ locale: 'de', slug: 'ride-madeira' }))).rejects.toBeInstanceOf(NotFound);
  });
});

describe('the index pages', () => {
  it('is indexed in English and in a language with posts of its own', async () => {
    const { generateMetadata } = await import('@/app/(site)/[locale]/blog/page');
    const en = await generateMetadata(params({ locale: 'en' }));
    const de = await generateMetadata(params({ locale: 'de' }));
    expect(en.robots).toMatchObject({ index: true });
    expect(de.robots).toMatchObject({ index: true });
    expect(en.alternates?.languages).toEqual({
      en: `${SITE}/blog`,
      de: `${SITE}/de/blog`,
      'x-default': `${SITE}/blog`,
    });
    expect(de.alternates?.types).toEqual({
      'application/rss+xml': [{ url: `${SITE}/de/blog/feed.xml`, title: messages.blog.feedTitle }],
    });
  });

  it('is noindex, follow in a language without, and left out of the hreflang set', async () => {
    const { generateMetadata } = await import('@/app/(site)/[locale]/blog/page');
    const es = await generateMetadata(params({ locale: 'es' }));
    expect(es.robots).toEqual({ index: false, follow: true });
    expect(es.alternates?.canonical).toBe(`${SITE}/es/blog`);
    expect(Object.keys(es.alternates?.languages ?? {})).not.toContain('es');
  });

  it('applies the rule per category', async () => {
    const { generateMetadata } = await import('@/app/(site)/[locale]/blog/category/[category]/page');
    const deRides = await generateMetadata(params({ locale: 'de', category: 'rides' }));
    const deEngineering = await generateMetadata(params({ locale: 'de', category: 'engineering' }));
    expect(deRides.robots).toEqual({ index: false, follow: true });
    expect(deEngineering.robots).toMatchObject({ index: true });
  });
});

describe('the language switcher', () => {
  it('sends a post to its version, or to the index, in the markup', () => {
    const html = (pathname: string) =>
      renderToStaticMarkup(
        <LocaleSwitcherMenu current="en" pathname={pathname} label="Language" blogPairs={blogSwitchPairs('en')} />,
      );
    expect(html('/blog/hello-world')).toContain('href="/de/blog/hallo-welt"');
    expect(html('/blog/hello-world')).toContain('href="/es/blog"');
    expect(html('/blog/ride-madeira')).toContain('href="/de/blog"');
    expect(html('/blog/ride-madeira')).toContain('href="/en/blog/ride-madeira"');
    expect(html('/blog/category/rides')).toContain('href="/de/blog/category/rides"');
  });
});

describe('the proxy', () => {
  function request(url: string, headers: Record<string, string> = {}): NextRequest {
    return new NextRequest(url, { headers: { host: new URL(url).host, ...headers } });
  }

  it('answers a post under another language, or an unknown one, with a real 404', async () => {
    const { default: proxy } = await import('@/proxy');
    await withEnv({}, async () => {
      for (const [pathname, target] of [
        ['/de/blog/ride-madeira', '/de/_missing'],
        ['/blog/hallo-welt', '/en/_missing'],
        ['/blog/nope', '/en/_missing'],
        ['/blog/category/news', '/en/_missing'],
        ['/es/blog/authors/nobody', '/es/_missing'],
      ] as const) {
        const res = await proxy(request(`${SITE}${pathname}`));
        expect(isRewrite(res), pathname).toBe(true);
        expect(getRewrittenUrl(res), pathname).toBe(`${SITE}${target}`);
      }
      for (const pathname of ['/blog', '/es/blog', '/blog/ride-madeira', '/de/blog/hallo-welt', '/blog/hello-world/og-card']) {
        const res = await proxy(request(`${SITE}${pathname}`));
        expect(isRewrite(res), pathname).toBe(false);
      }
    });
  });

  it('serves the English feed at /blog/feed.xml whatever the reader asks for', async () => {
    const { default: proxy, config } = await import('@/proxy');
    for (const pathname of ['/blog/feed.xml', '/de/blog/feed.xml']) {
      expect(unstable_doesMiddlewareMatch({ config, url: pathname }), pathname).toBe(true);
    }
    await withEnv({}, async () => {
      const en = await proxy(request(`${SITE}/blog/feed.xml`, { 'accept-language': 'de-DE,de;q=0.9' }));
      expect(getRewrittenUrl(en)).toBe(`${SITE}/en/blog/feed.xml`);
      const de = await proxy(request(`${SITE}/de/blog/feed.xml`));
      expect(isRewrite(de)).toBe(false);
      expect(de.headers.get('location')).toBeNull();
    });
  });

  it("lets a post's GPX through without locale negotiation", async () => {
    const { default: proxy } = await import('@/proxy');
    await withEnv({}, async () => {
      const res = await proxy(request(`${SITE}/blog-media/en/ride-madeira/0123456789ab/ride.gpx`));
      expect(isRewrite(res)).toBe(false);
      expect(res.headers.get('location')).toBeNull();
    });
  });
});
