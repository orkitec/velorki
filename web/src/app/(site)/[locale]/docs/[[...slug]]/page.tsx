// SPDX-License-Identifier: AGPL-3.0-only
import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { useTranslations } from 'next-intl';
import { getTranslations, setRequestLocale } from 'next-intl/server';
import { Breadcrumbs, DocsSidebar, DraftNotice, PrevNext, TranslationNotice } from '@/components/DocsNav';
import { JsonLd } from '@/components/JsonLd';
import { Prose } from '@/components/Prose';
import { routing } from '@/i18n/routing';
import { type DocEntry, docSlugs, listDocs, loadDoc, loadDocsIndex } from '@/site/content';
import { breadcrumbJsonLd, techArticleJsonLd } from '@/site/jsonld';
import { localePath } from '@/site/paths';
import { pageMetadata } from '@/site/seo';

interface DocsParams {
  locale: string;
  slug?: string[];
}

/** Every locale × every English docs slug, plus the index of each locale. */
export function generateStaticParams(): DocsParams[] {
  const slugs = docSlugs();
  return routing.locales.flatMap((locale) => [
    { locale, slug: [] },
    ...slugs.map((slug) => ({ locale, slug: [slug] })),
  ]);
}

function docPath(slug?: string[]): string {
  return slug && slug.length > 0 ? `/docs/${slug.join('/')}` : '/docs';
}

export async function generateMetadata({ params }: { params: Promise<DocsParams> }): Promise<Metadata> {
  const { locale, slug } = await params;
  const t = await getTranslations({ locale, namespace: 'docs' });

  if (!slug || slug.length === 0) {
    const meta = await getTranslations({ locale, namespace: 'docs.meta' });
    return pageMetadata({ locale, path: '/docs', title: meta('title'), description: meta('description') });
  }

  const page = slug.length === 1 ? loadDoc(locale, slug[0]!) : null;
  if (!page) return pageMetadata({ locale, path: docPath(slug), title: t('title'), description: t('lead') });

  return pageMetadata({
    locale,
    path: docPath(slug),
    title: page.frontMatter.title,
    description: page.frontMatter.description || t('lead'),
    // An unreviewed text is served, but it is not offered to a crawler.
    noIndex: page.frontMatter.draft,
  });
}

export default async function DocsPage({ params }: { params: Promise<DocsParams> }) {
  const { locale, slug } = await params;
  setRequestLocale(locale);
  const t = await getTranslations({ locale, namespace: 'docs' });
  const docs = listDocs(locale);

  if (!slug || slug.length === 0) return <DocsIndex locale={locale} docs={docs} />;
  if (slug.length !== 1) notFound();

  const page = loadDoc(locale, slug[0]!);
  if (!page) notFound();

  const index = docs.findIndex((doc) => doc.slug === page.slug);
  const prev = index > 0 ? docs[index - 1] : undefined;
  const next = index >= 0 && index < docs.length - 1 ? docs[index + 1] : undefined;

  return (
    <DocsShell locale={locale} docs={docs} current={page.slug}>
      <DocArticle
        locale={locale}
        title={page.frontMatter.title}
        description={page.frontMatter.description}
        html={page.html}
        translated={page.translated}
        draft={page.frontMatter.draft}
      />
      <PrevNext locale={locale} prev={prev} next={next} />
      <JsonLd
        data={[
          techArticleJsonLd({
            locale,
            path: `/docs/${page.slug}`,
            title: page.frontMatter.title,
            description: page.frontMatter.description,
          }),
          // The crumb names are the visible ones, so the German page does not
          // claim an English trail.
          breadcrumbJsonLd(locale, [
            { name: 'Velorki', path: '/' },
            { name: t('breadcrumb'), path: '/docs' },
            { name: page.frontMatter.title, path: `/docs/${page.slug}` },
          ]),
        ]}
      />
    </DocsShell>
  );
}

function DocsShell({
  locale,
  docs,
  current,
  children,
}: {
  locale: string;
  docs: DocEntry[];
  current?: string;
  children: React.ReactNode;
}) {
  // The article comes first in the source order: below `lg` the sidebar is a
  // closed disclosure under it, and from `lg` the explicit grid placement puts
  // it back into the left column.
  return (
    <div className="shell grid gap-12 py-12 lg:grid-cols-[15rem_minmax(0,1fr)] lg:gap-16">
      <div className="min-w-0 lg:col-start-2 lg:row-start-1">{children}</div>
      <DocsSidebar locale={locale} docs={docs} current={current} />
    </div>
  );
}

function DocArticle({
  locale,
  title,
  description,
  html,
  translated,
  draft,
}: {
  locale: string;
  title: string;
  description: string;
  html: string;
  translated: boolean;
  draft: boolean;
}) {
  const t = useTranslations('docs');
  return (
    <article>
      <Breadcrumbs
        items={[
          { name: t('home'), href: localePath(locale, '/') },
          { name: t('breadcrumb'), href: localePath(locale, '/docs') },
          { name: title },
        ]}
      />
      {draft && <DraftNotice />}
      {!translated && <TranslationNotice />}
      <h1 className="text-4xl sm:text-5xl">{title}</h1>
      {description && <p className="mt-4 max-w-2xl text-lg text-muted">{description}</p>}
      <Prose html={html} className="mt-10" />
    </article>
  );
}

function DocsIndex({ locale, docs }: { locale: string; docs: DocEntry[] }) {
  const t = useTranslations('docs');
  const intro = loadDocsIndex(locale);
  return (
    <DocsShell locale={locale} docs={docs}>
      <article>
        <Breadcrumbs items={[{ name: t('home'), href: localePath(locale, '/') }, { name: t('breadcrumb') }]} />
        {intro?.frontMatter.draft === true && <DraftNotice />}
        {intro && !intro.translated && <TranslationNotice />}
        <h1 className="text-4xl sm:text-5xl">{t('title')}</h1>
        <p className="mt-4 max-w-2xl text-lg text-muted">{t('lead')}</p>
        {intro && <Prose html={intro.html} className="mt-8" />}
        {docs.length === 0 ? (
          <p className="mt-10 max-w-2xl text-muted">{t('empty')}</p>
        ) : (
          <ul className="mt-10 grid gap-4 sm:grid-cols-2">
            {docs.map((doc) => (
              <li key={doc.slug}>
                <Link
                  href={localePath(locale, `/docs/${doc.slug}`)}
                  className="panel block h-full p-5 transition-colors hover:border-accent"
                >
                  <h2 className="font-display text-2xl">{doc.title}</h2>
                  {doc.description && <p className="mt-2 text-sm text-muted">{doc.description}</p>}
                </Link>
              </li>
            ))}
          </ul>
        )}
      </article>
      <JsonLd
        data={breadcrumbJsonLd(locale, [
          { name: 'Velorki', path: '/' },
          { name: t('breadcrumb'), path: '/docs' },
        ])}
      />
    </DocsShell>
  );
}
