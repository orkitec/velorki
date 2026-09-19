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
import { WatchMock } from '@/components/WatchMock';
import { routing } from '@/i18n/routing';
import { GITHUB_URL } from '@/site/config';
import { faqJsonLd } from '@/site/jsonld';
import { localePath } from '@/site/paths';
import type { Screen } from '@/site/screenshots';
import { pageMetadata } from '@/site/seo';

/** The screenshot in the hero; it is preloaded there and shown again below. */
const HERO_SCREEN: Screen = 'planner';

/**
 * The seven feature sections, each with the screen that shows it. `sensors`
 * has none: no capture carries sensor data, so that section draws its figures
 * instead (see `SensorShowcase`).
 */
const FEATURES: ReadonlyArray<{ id: string; screen: Screen | null }> = [
  { id: 'plan', screen: 'planner' },
  { id: 'loops', screen: 'loop' },
  { id: 'offline', screen: 'search' },
  { id: 'navigate', screen: 'navigation' },
  { id: 'record', screen: 'recording' },
  { id: 'sensors', screen: null },
  { id: 'files', screen: 'library' },
];

const BULLETS = ['one', 'two', 'three'] as const;

const FREE_ITEMS = ['routing', 'loops', 'search', 'maps', 'navigation', 'recording', 'sensors', 'files'] as const;

/** Free vs Plus, from docs/ARCHITECTURE.md: free is everything on the phone. */
const COMPARISON: ReadonlyArray<{ id: string; free: boolean }> = [
  { id: 'planning', free: true },
  { id: 'elevation', free: true },
  { id: 'loops', free: true },
  { id: 'offlineMaps', free: true },
  { id: 'offlineSearch', free: true },
  { id: 'navigation', free: true },
  { id: 'recording', free: true },
  { id: 'sensors', free: true },
  { id: 'library', free: true },
  { id: 'files', free: true },
  { id: 'assistant', free: false },
  { id: 'strava', free: false },
  { id: 'rwgps', free: false },
  { id: 'sharing', free: false },
];

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
      <Features locale={locale} />
      <Comparison locale={locale} />
      <OpenSource locale={locale} />
      <Faq locale={locale} />
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
          <PhoneFrame screen={HERO_SCREEN} priority />
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

function Features({ locale }: { locale: string }) {
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
              {/* The sensor section is the one with a guide behind it. */}
              {feature.id === 'sensors' && (
                <p className="mt-6">
                  <Link href={localePath(locale, '/docs/sensors-and-watch')} className="link-accent font-bold">
                    {t('sensors.link')}
                  </Link>
                </p>
              )}
            </div>
            <div className="flex justify-center">
              {feature.screen ? (
                <PhoneFrame screen={feature.screen} eager={feature.screen === HERO_SCREEN} />
              ) : (
                <SensorShowcase />
              )}
            </div>
          </article>
        ))}
      </div>
    </section>
  );
}

/**
 * What the sensor section shows instead of a screenshot: the three figures as
 * the app's record sheet has them, and the watch app beside them. Both are
 * drawings — there is no capture with a heart rate in it — so both are
 * `aria-hidden` and the copy beside them carries the facts. The accent comes
 * from the appearance switcher above, like every frame on the page.
 */
function SensorShowcase() {
  const t = useTranslations('home.features.sensors.panel');
  const tiles = [
    { label: t('heart'), value: '142', unit: t('bpm') },
    { label: t('cadence'), value: '88', unit: t('rpm') },
    { label: t('power'), value: '210', unit: t('watts') },
  ];
  return (
    <div className="flex w-full flex-col items-center gap-8 lg:flex-row lg:items-center lg:justify-center">
      <ul aria-hidden="true" className="grid w-full max-w-xs gap-3">
        {tiles.map((tile) => (
          <li key={tile.label} className="panel flex items-baseline justify-between gap-4 px-5 py-4">
            <span className="overline">{tile.label}</span>
            <span className="flex items-baseline gap-1.5">
              <span className="stat text-4xl text-accent">{tile.value}</span>
              <span className="text-sm font-bold text-muted">{tile.unit}</span>
            </span>
          </li>
        ))}
      </ul>
      <WatchMock />
    </div>
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

        {/* Tight cells below `sm`: with the roomy ones the German table paints
            past the edge of a 320 px screen. */}
        <div className="panel mt-10 overflow-x-auto">
          <table className="w-full border-collapse text-left">
            <caption className="sr-only">{t('title')}</caption>
            <thead>
              <tr className="border-b border-line">
                <th scope="col" className="px-2 py-4 text-sm font-bold sm:px-4">
                  {t('feature')}
                </th>
                <th scope="col" className="w-20 px-2 py-4 text-center text-sm font-bold sm:w-24 sm:px-4">
                  {t('free')}
                </th>
                <th scope="col" className="w-20 px-2 py-4 text-center text-sm font-bold text-accent sm:w-24 sm:px-4">
                  {t('plus')}
                </th>
              </tr>
            </thead>
            <tbody>
              {COMPARISON.map((row) => (
                <tr key={row.id} className="border-b border-line-soft last:border-0">
                  <th scope="row" className="px-2 py-4 text-sm font-medium sm:px-4">
                    {t(`rows.${row.id}`)}
                  </th>
                  <td className="px-2 py-4 sm:px-4">
                    <span className="flex justify-center">
                      {row.free ? <CheckIcon className="text-accent" /> : <DashIcon className="text-muted" />}
                      <span className="sr-only">{row.free ? t('included') : t('notIncluded')}</span>
                    </span>
                  </td>
                  <td className="px-2 py-4 sm:px-4">
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
            {t('plusLink')}
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
      <div className="shell max-w-3xl">
        <h2 id="open-source-title" className="text-4xl sm:text-5xl">
          {t('title')}
        </h2>
        <p className="mt-4 text-lg text-muted">{t('body')}</p>
        <div className="mt-8 flex flex-wrap gap-4">
          <a href={GITHUB_URL} rel="noreferrer" className="link-accent font-bold">
            {t('githubLink')}
          </a>
          <Link href={localePath(locale, '/credits')} className="link-accent font-bold">
            {t('creditsLink')}
          </Link>
        </div>
      </div>
    </section>
  );
}

function Faq({ locale }: { locale: string }) {
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
              {/* The open-data answer stays short and sends the detail to /credits. */}
              {id === 'osm' && (
                <p className="mt-3">
                  <Link href={localePath(locale, '/credits')} className="link-accent font-bold">
                    {t('creditsLink')}
                  </Link>
                </p>
              )}
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
