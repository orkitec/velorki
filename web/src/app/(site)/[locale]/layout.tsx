// SPDX-License-Identifier: AGPL-3.0-only
import type { AbstractIntlMessages } from 'next-intl';
import type { Metadata, Viewport } from 'next';
import localFont from 'next/font/local';
import { notFound } from 'next/navigation';
import { NextIntlClientProvider, hasLocale } from 'next-intl';
import { getMessages, getTranslations, setRequestLocale } from 'next-intl/server';
import { JsonLd } from '@/components/JsonLd';
import { SiteFooter } from '@/components/SiteFooter';
import { SiteHeader } from '@/components/SiteHeader';
import { ThemeScript } from '@/components/ThemeScript';
import { routing } from '@/i18n/routing';
import { ORG_NAME, ORG_URL } from '@/site/config';
import { mobileApplicationJsonLd, organizationJsonLd, webSiteJsonLd } from '@/site/jsonld';
import { languageAlternates } from '@/site/paths';
import { METADATA_BASE } from '@/site/seo';
import '../../globals.css';

// The app's two typefaces, served from this repository: Barlow Condensed for
// headlines and figures, Manrope for everything else (app/lib/app/theme.dart).
//
// The files under `src/app/fonts` are the upstream latin subsets, fetched
// once and pinned there rather than downloaded while the site compiles: a
// build that fetches its fonts fails outright on a runner that cannot reach
// fonts.googleapis.com, which is what happened. See web/README.md.
//
// Only the weights below are loaded, as before, and the two glyphs the docs
// use outside the latin subset were never in it either, so they fall back to
// the system stack as they always have.
const barlow = localFont({
  src: [
    { path: '../../fonts/BarlowCondensed-SemiBold-latin.woff2', weight: '600', style: 'normal' },
    { path: '../../fonts/BarlowCondensed-Bold-latin.woff2', weight: '700', style: 'normal' },
  ],
  display: 'swap',
  variable: '--font-barlow',
});

// One file three times: Manrope is a variable font, and upstream serves the
// same latin file for each weight it is asked for. Naming the three weights
// separately rather than a `400 700` range keeps what the site renders
// exactly as it was — a class asking for 600 still snaps to a neighbour
// instead of finding a real 600 instance.
const manrope = localFont({
  src: [
    { path: '../../fonts/Manrope-latin.woff2', weight: '400', style: 'normal' },
    { path: '../../fonts/Manrope-latin.woff2', weight: '500', style: 'normal' },
    { path: '../../fonts/Manrope-latin.woff2', weight: '700', style: 'normal' },
  ],
  display: 'swap',
  variable: '--font-manrope',
});

export function generateStaticParams() {
  return routing.locales.map((locale) => ({ locale }));
}

export const viewport: Viewport = {
  themeColor: [
    { media: '(prefers-color-scheme: light)', color: '#f5f6f3' },
    { media: '(prefers-color-scheme: dark)', color: '#0e1115' },
  ],
  colorScheme: 'light dark',
};

export async function generateMetadata({ params }: { params: Promise<{ locale: string }> }): Promise<Metadata> {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: 'site' });
  return {
    metadataBase: METADATA_BASE,
    title: { default: t('name'), template: '%s · Velorki' },
    description: t('description'),
    applicationName: 'Velorki',
    generator: 'Next.js',
    keywords: [
      'bike route planner',
      'cycling navigation',
      'offline maps',
      'OpenStreetMap',
      'GPX',
      'FIT',
      'ride recorder',
      'bikepacking',
      'open source',
    ],
    authors: [{ name: ORG_NAME, url: ORG_URL }],
    creator: ORG_NAME,
    publisher: ORG_NAME,
    manifest: '/manifest.webmanifest',
    alternates: { languages: languageAlternates('/') },
    icons: {
      icon: [
        { url: '/favicon.ico', sizes: '48x48 32x32 16x16', type: 'image/x-icon' },
        { url: '/icon.svg', type: 'image/svg+xml' },
        { url: '/icons/favicon-32.png', sizes: '32x32', type: 'image/png' },
      ],
      apple: [{ url: '/icons/apple-touch-icon.png', sizes: '180x180' }],
    },
    formatDetection: { telephone: false, address: false },
    other: { 'apple-mobile-web-app-title': 'Velorki' },
  };
}

export default async function SiteLayout({
  children,
  params,
}: {
  children: React.ReactNode;
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  if (!hasLocale(routing.locales, locale)) notFound();
  // Static rendering: without this next-intl reads the request and every page
  // under this layout turns dynamic.
  setRequestLocale(locale);

  const messages = await getMessages();
  const t = await getTranslations({ locale, namespace: 'nav' });
  const description = (await getTranslations({ locale, namespace: 'site' }))('description');

  // Only the namespaces the three client components need cross to the browser;
  // the rest of the catalogue stays on the server.
  const catalogue = messages as Record<string, AbstractIntlMessages | string>;
  const clientMessages = {
    appearance: catalogue.appearance,
    localeSwitcher: catalogue.localeSwitcher,
    theme: catalogue.theme,
    screenshots: catalogue.screenshots,
    errors: catalogue.errors,
  };

  // `data-scroll-behavior`: globals.css sets `scroll-behavior: smooth` on
  // `html`, and Next 16 wants the attribute alongside it, or it warns and
  // animates the scroll on every route change.
  // `suppressHydrationWarning`: `ThemeScript` puts `data-theme` on this very
  // element before React hydrates, which is the whole point of it. The flag is
  // shallow — only this element's own attributes — so nothing else is hidden.
  return (
    <html
      lang={locale}
      data-scroll-behavior="smooth"
      className={`${barlow.variable} ${manrope.variable}`}
      suppressHydrationWarning
    >
      <body className="min-h-dvh bg-canvas text-fg antialiased">
        <ThemeScript />
        <NextIntlClientProvider locale={locale} messages={clientMessages}>
          <a href="#main" className="skip-link">
            {t('skip')}
          </a>
          <SiteHeader locale={locale} />
          <main id="main">{children}</main>
          <SiteFooter locale={locale} />
          <JsonLd data={[organizationJsonLd(), webSiteJsonLd(locale), mobileApplicationJsonLd(description)]} />
        </NextIntlClientProvider>
      </body>
    </html>
  );
}
