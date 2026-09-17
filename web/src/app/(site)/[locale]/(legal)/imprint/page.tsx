// SPDX-License-Identifier: AGPL-3.0-only
import type { Metadata } from 'next';
import { getTranslations, setRequestLocale } from 'next-intl/server';
import { LegalPage } from '@/components/LegalPage';
import { routing } from '@/i18n/routing';
import { loadLegal } from '@/site/content';
import { pageMetadata } from '@/site/seo';

const DOC = 'imprint' as const;

export function generateStaticParams() {
  return routing.locales.map((locale) => ({ locale }));
}

export async function generateMetadata({ params }: { params: Promise<{ locale: string }> }): Promise<Metadata> {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: `legal.${DOC}` });
  const page = loadLegal(locale, DOC);
  return pageMetadata({
    locale,
    path: `/${DOC}`,
    title: page?.frontMatter.title ?? t('title'),
    description: page?.frontMatter.description || t('description'),
    // An unreviewed text is served, but it is not offered to a crawler.
    noIndex: page?.frontMatter.draft ?? true,
  });
}

export default async function Page({ params }: { params: Promise<{ locale: string }> }) {
  const { locale } = await params;
  setRequestLocale(locale);
  return <LegalPage locale={locale} doc={DOC} />;
}
