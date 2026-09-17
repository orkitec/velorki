// SPDX-License-Identifier: AGPL-3.0-only
import type { Metadata } from 'next';
import Link from 'next/link';
import { useTranslations } from 'next-intl';
import { getTranslations, setRequestLocale } from 'next-intl/server';
import { CheckIcon } from '@/components/Icons';
import { PhoneFrame } from '@/components/PhoneFrame';
import { routing } from '@/i18n/routing';
import { GITHUB_URL } from '@/site/config';
import { localePath } from '@/site/paths';
import { pageMetadata } from '@/site/seo';

const PLUS_FEATURES = ['assistant', 'strava', 'rwgps', 'sharing'] as const;

export function generateStaticParams() {
  return routing.locales.map((locale) => ({ locale }));
}

export async function generateMetadata({ params }: { params: Promise<{ locale: string }> }): Promise<Metadata> {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: 'plus.meta' });
  return pageMetadata({ locale, path: '/plus', title: t('title'), description: t('description') });
}

export default async function PlusPage({ params }: { params: Promise<{ locale: string }> }) {
  const { locale } = await params;
  setRequestLocale(locale);
  return <PlusContent locale={locale} />;
}

function PlusContent({ locale }: { locale: string }) {
  const t = useTranslations('plus');
  return (
    <>
      <section className="relative overflow-hidden">
        <div className="aurora" />
        <div className="shell relative grid gap-12 py-16 lg:grid-cols-[minmax(0,1fr)_auto] lg:items-center">
          <div className="max-w-2xl">
            <p className="overline">{t('eyebrow')}</p>
            <h1 className="mt-3 text-6xl sm:text-7xl">{t('title')}</h1>
            <p className="mt-5 text-xl text-muted">{t('lead')}</p>
          </div>
          <div className="flex justify-center lg:justify-end">
            <PhoneFrame screen="settings" priority />
          </div>
        </div>
      </section>

      <section aria-labelledby="plus-includes" className="shell py-12">
        <h2 id="plus-includes" className="text-4xl">
          {t('includes')}
        </h2>
        <ul className="mt-8 grid gap-4 sm:grid-cols-2">
          {PLUS_FEATURES.map((feature) => (
            <li key={feature} className="panel p-6">
              <h3 className="flex items-center gap-2 font-display text-2xl">
                <CheckIcon width={20} height={20} className="text-accent" />
                {t(`features.${feature}.title`)}
              </h3>
              <p className="mt-2 text-muted">{t(`features.${feature}.body`)}</p>
            </li>
          ))}
        </ul>
      </section>

      <section aria-labelledby="plus-free" className="hairline bg-panel/40 py-12">
        <div className="shell max-w-3xl">
          <h2 id="plus-free" className="text-3xl">
            {t('freeTitle')}
          </h2>
          <p className="mt-3 text-lg text-muted">{t('freeBody')}</p>
        </div>
      </section>

      <section aria-labelledby="plus-price" className="shell max-w-3xl py-12">
        <h2 id="plus-price" className="text-3xl">
          {t('priceTitle')}
        </h2>
        <p className="mt-3 text-lg text-muted">{t('priceBody')}</p>

        <h2 className="mt-12 text-3xl">{t('restoreTitle')}</h2>
        <p className="mt-3 text-lg text-muted">{t('restoreBody')}</p>

        <h2 className="mt-12 text-3xl">{t('cancelTitle')}</h2>
        <p className="mt-3 text-lg text-muted">{t('cancelBody')}</p>

        <h2 className="mt-12 text-3xl">{t('selfHostTitle')}</h2>
        <p className="mt-3 text-lg text-muted">{t('selfHostBody')}</p>

        <ul className="mt-10 flex flex-wrap gap-5 text-sm font-bold">
          <li>
            <Link href={localePath(locale, '/terms')} className="link-accent">
              {t('termsLink')}
            </Link>
          </li>
          <li>
            <Link href={localePath(locale, '/privacy')} className="link-accent">
              {t('privacyLink')}
            </Link>
          </li>
          <li>
            <a href={GITHUB_URL} rel="noreferrer" className="link-accent">
              GitHub
            </a>
          </li>
        </ul>
      </section>
    </>
  );
}
