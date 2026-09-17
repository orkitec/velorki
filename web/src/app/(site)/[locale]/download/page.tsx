// SPDX-License-Identifier: AGPL-3.0-only
import type { Metadata } from 'next';
import { useTranslations } from 'next-intl';
import { getTranslations, setRequestLocale } from 'next-intl/server';
import { GitHubIcon } from '@/components/Icons';
import { PhoneFrame } from '@/components/PhoneFrame';
import { StoreBadges } from '@/components/StoreBadges';
import { routing } from '@/i18n/routing';
import { GITHUB_URL, MIN_ANDROID, MIN_IOS, RELEASES_URL } from '@/site/config';
import { pageMetadata } from '@/site/seo';

export function generateStaticParams() {
  return routing.locales.map((locale) => ({ locale }));
}

export async function generateMetadata({ params }: { params: Promise<{ locale: string }> }): Promise<Metadata> {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: 'download.meta' });
  return pageMetadata({ locale, path: '/download', title: t('title'), description: t('description') });
}

export default async function DownloadPage({ params }: { params: Promise<{ locale: string }> }) {
  const { locale } = await params;
  setRequestLocale(locale);
  return <DownloadContent />;
}

function DownloadContent() {
  const t = useTranslations('download');
  return (
    <>
      <section className="relative overflow-hidden">
        <div className="aurora" />
        <div className="shell relative grid gap-12 py-16 lg:grid-cols-[minmax(0,1fr)_auto] lg:items-center">
          <div className="max-w-2xl">
            <p className="overline">{t('eyebrow')}</p>
            <h1 className="mt-3 text-6xl sm:text-7xl">{t('title')}</h1>
            <p className="mt-5 text-xl text-muted">{t('lead')}</p>
            {/* StoreBadges says by itself that the stores are not live yet. */}
            <StoreBadges className="mt-8" />
          </div>
          <div className="flex justify-center lg:justify-end">
            <PhoneFrame screen="ride" priority />
          </div>
        </div>
      </section>

      <section aria-labelledby="requirements" className="shell max-w-3xl py-12">
        <h2 id="requirements" className="text-3xl">
          {t('requirementsTitle')}
        </h2>
        {/* Verified in the app sources: android/app/build.gradle.kts has
            minSdk = 26 (Android 8.0) and the iOS project sets
            IPHONEOS_DEPLOYMENT_TARGET = 15.0. */}
        <dl className="mt-6 grid gap-4 sm:grid-cols-2">
          <div className="panel p-5">
            <dt className="overline">{t('android')}</dt>
            <dd className="stat mt-2 text-3xl">{t('androidRequirement', { version: MIN_ANDROID })}</dd>
          </div>
          <div className="panel p-5">
            <dt className="overline">{t('ios')}</dt>
            <dd className="stat mt-2 text-3xl">{t('iosRequirement', { version: MIN_IOS })}</dd>
          </div>
        </dl>
        <p className="mt-6 text-muted">{t('storage')}</p>

        <h2 className="mt-14 text-3xl">{t('apkTitle')}</h2>
        <p className="mt-3 text-muted">{t('apkBody')}</p>
        <p className="mt-5">
          <a href={RELEASES_URL} rel="noreferrer" className="btn btn-secondary">
            <GitHubIcon />
            {t('apkLink')}
          </a>
        </p>

        <h2 className="mt-14 text-3xl">{t('sourceTitle')}</h2>
        <p className="mt-3 text-muted">{t('sourceBody')}</p>
        <p className="mt-5">
          <a href={GITHUB_URL} rel="noreferrer" className="link-accent font-bold">
            {t('sourceLink')}
          </a>
        </p>
      </section>
    </>
  );
}
