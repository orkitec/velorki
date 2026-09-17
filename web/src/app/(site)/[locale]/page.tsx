// SPDX-License-Identifier: AGPL-3.0-only
import type { Metadata } from 'next';
import Link from 'next/link';
import { useTranslations } from 'next-intl';
import { getTranslations, setRequestLocale } from 'next-intl/server';
import { AppearanceProvider, AppearanceSwitcher } from '@/components/Appearance';
import { CheckIcon, DashIcon } from '@/components/Icons';
import { JsonLd } from '@/components/JsonLd';
import { PhoneFrame } from '@/components/PhoneFrame';
import { StoreBadges } from '@/components/StoreBadges';
import { routing } from '@/i18n/routing';
import { GITHUB_URL } from '@/site/config';
import { faqJsonLd } from '@/site/jsonld';
import { localePath } from '@/site/paths';
import type { Screen } from '@/site/screenshots';
import { pageMetadata } from '@/site/seo';

/** The six feature sections, each with the screen that shows it. */
const FEATURES: ReadonlyArray<{ id: string; screen: Screen }> = [
  { id: 'plan', screen: 'planner' },
  { id: 'loops', screen: 'loop' },
  { id: 'offline', screen: 'search' },
  { id: 'navigate', screen: 'navigation' },
  { id: 'record', screen: 'recording' },
  { id: 'files', screen: 'library' },
];

const BULLETS = ['one', 'two', 'three'] as const;

const FREE_ITEMS = ['routing', 'loops', 'search', 'maps', 'navigation', 'recording', 'files'] as const;

/** Free vs Plus, from docs/ARCHITECTURE.md: free is everything on the phone. */
const COMPARISON: ReadonlyArray<{ id: string; free: boolean }> = [
  { id: 'planning', free: true },
  { id: 'elevation', free: true },
  { id: 'loops', free: true },
  { id: 'offlineMaps', free: true },
  { id: 'offlineSearch', free: true },
  { id: 'navigation', free: true },
  { id: 'recording', free: true },
  { id: 'library', free: true },
  { id: 'files', free: true },
  { id: 'assistant', free: false },
  { id: 'strava', free: false },
  { id: 'rwgps', free: false },
  { id: 'sharing', free: false },
];

const OPEN_SOURCE_CARDS = ['license', 'device', 'data', 'osm'] as const;

const FAQ_IDS = ['account', 'offline', 'price', 'plus', 'data', 'osm', 'opensource', 'selfhost'] as const;

export function generateStaticParams() {
  return routing.locales.map((locale) => ({ locale }));
}

export async function generateMetadata({ params }: { params: Promise<{ locale: string }> }): Promise<Metadata> {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: 'home.meta' });
  return pageMetadata({ locale, path: '/', title: t('title'), description: t('description'), absoluteTitle: true });
}

export default async function LandingPage({ params }: { params: Promise<{ locale: string }> }) {
  const { locale } = await params;
  setRequestLocale(locale);
  const faq = await getTranslations({ locale, namespace: 'home.faq' });

  return (
    <AppearanceProvider>
      <Hero locale={locale} />
      <FreeBand />
      <Features />
      <Comparison locale={locale} />
      <OpenSource locale={locale} />
      <Faq />
      <FinalCta locale={locale} />
      <JsonLd
        data={faqJsonLd(FAQ_IDS.map((id) => ({ question: faq(`items.${id}.q`), answer: faq(`items.${id}.a`) })))}
      />
    </AppearanceProvider>
  );
}

function Hero({ locale }: { locale: string }) {
  const t = useTranslations('home.hero');
  return (
    <section className="relative overflow-hidden">
      <div className="aurora" />
      <div className="shell relative grid gap-12 py-16 sm:py-24 lg:grid-cols-[minmax(0,1fr)_auto] lg:items-center">
        <div className="max-w-2xl">
          <p className="chip">
            <span className="h-2 w-2 rounded-full bg-accent" aria-hidden="true" />
            {t('eyebrow')}
          </p>
          <h1 className="mt-5 text-6xl leading-[0.95] sm:text-7xl lg:text-8xl">{t('title')}</h1>
          <p className="mt-6 text-xl leading-snug font-bold text-fg sm:text-2xl">{t('lead')}</p>
          <p className="mt-4 max-w-xl text-lg text-muted">{t('body')}</p>
          <div className="mt-8 flex flex-wrap gap-3">
            <Link href={localePath(locale, '/download')} className="btn btn-primary">
              {t('primaryCta')}
            </Link>
            <Link href={localePath(locale, '/docs')} className="btn btn-secondary">
              {t('secondaryCta')}
            </Link>
          </div>
          <StoreBadges className="mt-10" />
        </div>
        <div className="flex justify-center lg:justify-end">
          <PhoneFrame screen="planner" priority />
        </div>
      </div>
    </section>
  );
}

function FreeBand() {
  const t = useTranslations('home.free');
  return (
    <section aria-labelledby="free-title" className="hairline bg-panel/40 py-14">
      <div className="shell">
        <h2 id="free-title" className="text-4xl sm:text-5xl">
          {t('title')}
        </h2>
        <p className="mt-4 max-w-3xl text-lg text-muted">{t('body')}</p>
        <ul className="mt-8 flex flex-wrap gap-2">
          {FREE_ITEMS.map((item) => (
            <li key={item} className="chip">
              <CheckIcon width={15} height={15} className="text-accent" />
              {t(`items.${item}`)}
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}

function Features() {
  const t = useTranslations('home.features');
  return (
    <section id="features" aria-labelledby="features-title" className="scroll-mt-24 py-20">
      <div className="shell">
        <h2 id="features-title" className="text-4xl sm:text-5xl">
          {t('title')}
        </h2>
        <p className="mt-4 max-w-2xl text-lg text-muted">{t('lead')}</p>
        <div className="mt-8">
          <AppearanceSwitcher />
        </div>
      </div>

      <div className="mt-6">
        {FEATURES.map((feature, index) => (
          <article
            key={feature.id}
            className={`shell grid items-center gap-10 py-14 lg:grid-cols-2 lg:gap-16 ${
              index % 2 === 1 ? 'lg:[&>*:first-child]:order-2' : ''
            }`}
          >
            <div className="max-w-xl">
              <p className="overline">{t(`${feature.id}.eyebrow`)}</p>
              <h3 className="mt-3 text-3xl sm:text-4xl">{t(`${feature.id}.title`)}</h3>
              <p className="mt-4 text-lg text-muted">{t(`${feature.id}.body`)}</p>
              <ul className="mt-6 space-y-2.5">
                {BULLETS.map((bullet) => (
                  <li key={bullet} className="flex gap-3">
                    <CheckIcon width={18} height={18} className="mt-1 shrink-0 text-accent" />
                    <span>{t(`${feature.id}.bullets.${bullet}`)}</span>
                  </li>
                ))}
              </ul>
            </div>
            <div className="flex justify-center">
              <PhoneFrame screen={feature.screen} />
            </div>
          </article>
        ))}
      </div>
    </section>
  );
}

function Comparison({ locale }: { locale: string }) {
  const t = useTranslations('home.comparison');
  return (
    <section aria-labelledby="comparison-title" className="hairline bg-panel/40 py-20">
      <div className="shell">
        <p className="overline">{t('eyebrow')}</p>
        <h2 id="comparison-title" className="mt-3 text-4xl sm:text-5xl">
          {t('title')}
        </h2>
        <p className="mt-4 max-w-3xl text-lg text-muted">{t('lead')}</p>

        <div className="panel mt-10 overflow-x-auto">
          <table className="w-full border-collapse text-left">
            <caption className="sr-only">{t('title')}</caption>
            <thead>
              <tr className="border-b border-line">
                <th scope="col" className="p-4 text-sm font-bold">
                  {t('feature')}
                </th>
                <th scope="col" className="w-24 p-4 text-center text-sm font-bold">
                  {t('free')}
                </th>
                <th scope="col" className="w-24 p-4 text-center text-sm font-bold text-accent">
                  {t('plus')}
                </th>
              </tr>
            </thead>
            <tbody>
              {COMPARISON.map((row) => (
                <tr key={row.id} className="border-b border-line-soft last:border-0">
                  <th scope="row" className="p-4 text-sm font-medium">
                    {t(`rows.${row.id}`)}
                  </th>
                  <td className="p-4">
                    <span className="flex justify-center">
                      {row.free ? <CheckIcon className="text-accent" /> : <DashIcon className="text-muted" />}
                      <span className="sr-only">{row.free ? t('included') : t('notIncluded')}</span>
                    </span>
                  </td>
                  <td className="p-4">
                    <span className="flex justify-center">
                      <CheckIcon className="text-accent" />
                      <span className="sr-only">{t('included')}</span>
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <p className="mt-6 max-w-2xl text-sm text-muted">{t('note')}</p>
        <p className="mt-4">
          <Link href={localePath(locale, '/plus')} className="link-accent font-bold">
            Velorki Plus →
          </Link>
        </p>
      </div>
    </section>
  );
}

function OpenSource({ locale }: { locale: string }) {
  const t = useTranslations('home.openSource');
  return (
    <section aria-labelledby="open-source-title" className="py-20">
      <div className="shell">
        <p className="overline">{t('eyebrow')}</p>
        <h2 id="open-source-title" className="mt-3 text-4xl sm:text-5xl">
          {t('title')}
        </h2>
        <p className="mt-4 max-w-3xl text-lg text-muted">{t('body')}</p>
        <ul className="mt-10 grid gap-4 sm:grid-cols-2">
          {OPEN_SOURCE_CARDS.map((card) => (
            <li key={card} className="panel p-6">
              <h3 className="font-display text-2xl">{t(`cards.${card}.title`)}</h3>
              <p className="mt-2 text-muted">{t(`cards.${card}.body`)}</p>
            </li>
          ))}
        </ul>
        <div className="mt-8 flex flex-wrap gap-4">
          <Link href={localePath(locale, '/privacy')} className="link-accent font-bold">
            {t('privacyLink')}
          </Link>
          <a href={GITHUB_URL} rel="noreferrer" className="link-accent font-bold">
            {t('sourceLink')}
          </a>
        </div>
      </div>
    </section>
  );
}

function Faq() {
  const t = useTranslations('home.faq');
  return (
    <section aria-labelledby="faq-title" className="hairline bg-panel/40 py-20">
      <div className="shell max-w-3xl">
        <p className="overline">{t('eyebrow')}</p>
        <h2 id="faq-title" className="mt-3 text-4xl sm:text-5xl">
          {t('title')}
        </h2>
        <div className="mt-10">
          {FAQ_IDS.map((id) => (
            /* <details> is the native disclosure: no JavaScript, keyboard
               accessible, and the answer is in the markup for crawlers. */
            <details key={id} className="hairline group py-4">
              <summary className="flex cursor-pointer list-none items-center justify-between gap-4">
                <h3 className="font-sans text-lg font-bold">{t(`items.${id}.q`)}</h3>
                <span aria-hidden="true" className="text-2xl text-accent transition-transform group-open:rotate-45">
                  +
                </span>
              </summary>
              <p className="mt-3 text-muted">{t(`items.${id}.a`)}</p>
            </details>
          ))}
        </div>
      </div>
    </section>
  );
}

function FinalCta({ locale }: { locale: string }) {
  const t = useTranslations('home.cta');
  return (
    <section aria-labelledby="cta-title" className="relative overflow-hidden py-24">
      <div className="aurora" />
      <div className="shell relative text-center">
        <h2 id="cta-title" className="text-5xl sm:text-6xl">
          {t('title')}
        </h2>
        <p className="mx-auto mt-5 max-w-xl text-lg text-muted">{t('body')}</p>
        <div className="mt-8 flex justify-center">
          <Link href={localePath(locale, '/download')} className="btn btn-primary">
            {t('action')}
          </Link>
        </div>
      </div>
    </section>
  );
}
