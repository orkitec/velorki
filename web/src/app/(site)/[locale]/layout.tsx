// SPDX-License-Identifier: AGPL-3.0-only
import type { AbstractIntlMessages } from 'next-intl';
import type { Metadata, Viewport } from 'next';
import { Barlow_Condensed, Manrope } from 'next/font/google';
import { notFound } from 'next/navigation';
import { NextIntlClientProvider, hasLocale } from 'next-intl';
import { getMessages, getTranslations, setRequestLocale } from 'next-intl/server';
import { JsonLd } from '@/components/JsonLd';
import { SiteFooter } from '@/components/SiteFooter';
import { SiteHeader } from '@/components/SiteHeader';
import { routing } from '@/i18n/routing';
import { ORG_NAME, ORG_URL } from '@/site/config';
import { mobileApplicationJsonLd, organizationJsonLd, webSiteJsonLd } from '@/site/jsonld';
import { languageAlternates } from '@/site/paths';
import { METADATA_BASE } from '@/site/seo';
import '../../globals.css';

// The app's two typefaces, self-hosted by next/font: Barlow Condensed for
// headlines and figures, Manrope for everything else (app/lib/app/theme.dart).
const barlow = Barlow_Condensed({
  subsets: ['latin'],
  weight: ['600', '700'],
  display: 'swap',
  variable: '--font-barlow',
});

const manrope = Manrope({
  subsets: ['latin'],
  weight: ['400', '500', '700'],
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
    screenshots: catalogue.screenshots,
    errors: catalogue.errors,
  };

  // `data-scroll-behavior`: globals.css sets `scroll-behavior: smooth` on
  // `html`, and Next 16 wants the attribute alongside it, or it warns and
  // animates the scroll on every route change.
  return (
    <html lang={locale} data-scroll-behavior="smooth" className={`${barlow.variable} ${manrope.variable}`}>
      <body className="min-h-dvh bg-canvas text-fg antialiased">
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
