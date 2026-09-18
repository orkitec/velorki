// SPDX-License-Identifier: AGPL-3.0-only
import type { Metadata } from 'next';
import { useTranslations } from 'next-intl';
import { getTranslations, setRequestLocale } from 'next-intl/server';
import { Breadcrumbs } from '@/components/DocsNav';
import { JsonLd } from '@/components/JsonLd';
import { routing } from '@/i18n/routing';
import { breadcrumbJsonLd } from '@/site/jsonld';
import { localePath } from '@/site/paths';
import { pageMetadata } from '@/site/seo';

interface CreditLink {
  /** Shown as written, in every language: a project or a licence name. */
  label: string;
  href: string;
}

/**
 * The data, services, fonts and frameworks Velorki is built on, in the order
 * the ride uses them: the data, the routing, the tiles, the search, then the
 * type and the toolkit. The wording and the licence names follow
 * `app/lib/app/licenses.dart`, which registers the same list in the app, so
 * the website and the About screen cannot drift apart.
 */
const CREDITS: ReadonlyArray<{ id: string; links: readonly CreditLink[] }> = [
  {
    id: 'osm',
    links: [
      { label: 'openstreetmap.org/copyright', href: 'https://www.openstreetmap.org/copyright' },
      { label: 'ODbL 1.0', href: 'https://opendatacommons.org/licenses/odbl/1-0/' },
    ],
  },
  { id: 'brouter', links: [{ label: 'github.com/abrensch/brouter', href: 'https://github.com/abrensch/brouter' }] },
  {
    id: 'openfreemap',
    links: [
      { label: 'openfreemap.org', href: 'https://openfreemap.org/' },
      { label: 'openmaptiles.org', href: 'https://openmaptiles.org/' },
    ],
  },
  { id: 'cyclosm', links: [{ label: 'cyclosm.org', href: 'https://www.cyclosm.org/' }] },
  { id: 'photon', links: [{ label: 'photon.komoot.io', href: 'https://photon.komoot.io/' }] },
  {
    id: 'fonts',
    links: [
      { label: 'Barlow Condensed', href: 'https://github.com/jpt/barlow' },
      { label: 'Manrope', href: 'https://github.com/sharanda/manrope' },
      { label: 'SIL Open Font License 1.1', href: 'https://openfontlicense.org/' },
    ],
  },
  { id: 'maplibre', links: [{ label: 'maplibre.org', href: 'https://maplibre.org/' }] },
  { id: 'flutter', links: [{ label: 'flutter.dev', href: 'https://flutter.dev/' }] },
];

export function generateStaticParams() {
  return routing.locales.map((locale) => ({ locale }));
}

export async function generateMetadata({ params }: { params: Promise<{ locale: string }> }): Promise<Metadata> {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: 'credits.meta' });
  return pageMetadata({ locale, path: '/credits', title: t('title'), description: t('description') });
}

export default async function CreditsPage({ params }: { params: Promise<{ locale: string }> }) {
  const { locale } = await params;
  setRequestLocale(locale);
  return <CreditsContent locale={locale} />;
}

function CreditsContent({ locale }: { locale: string }) {
  const t = useTranslations('credits');
  const nav = useTranslations('docs');
  return (
    <div className="shell max-w-3xl py-12">
      <article>
        <Breadcrumbs items={[{ name: nav('home'), href: localePath(locale, '/') }, { name: t('title') }]} />
        <h1 className="text-4xl sm:text-5xl">{t('title')}</h1>
        <p className="mt-4 text-lg text-muted">{t('lead')}</p>

        <ul className="mt-10 grid gap-4">
          {CREDITS.map((credit) => (
            <li key={credit.id} className="panel p-6">
              <h2 className="font-display text-2xl">{t(`items.${credit.id}.title`)}</h2>
              <p className="mt-2 text-muted">{t(`items.${credit.id}.body`)}</p>
              <p className="mt-3 text-sm text-muted">
                <span className="overline">{t('licenceLabel')}</span> {t(`items.${credit.id}.licence`)}
              </p>
              <p className="mt-3 flex flex-wrap gap-x-4 gap-y-1 text-sm">
                {credit.links.map((link) => (
                  <a key={link.href} href={link.href} rel="noreferrer" className="link-accent font-bold">
                    {link.label}
                  </a>
                ))}
              </p>
            </li>
          ))}
        </ul>

        <p className="mt-10 text-muted">{t('appNote')}</p>
      </article>
      <JsonLd
        data={breadcrumbJsonLd(locale, [
          { name: 'Velorki', path: '/' },
          { name: t('title'), path: '/credits' },
        ])}
      />
    </div>
  );
}
