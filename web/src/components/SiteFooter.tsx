// SPDX-License-Identifier: AGPL-3.0-only
import Link from 'next/link';
import { useTranslations } from 'next-intl';
import { COPYRIGHT_YEAR, GITHUB_URL, OSM_COPYRIGHT_URL, SECURITY_EMAIL } from '@/site/config';
import { LEGAL_DOCS } from '@/site/content';
import { localePath } from '@/site/paths';
import { GitHubIcon, VelorkiMark } from './Icons';

const PRODUCT = [
  { key: 'features', href: '/#features' },
  { key: 'plus', href: '/plus' },
  { key: 'download', href: '/download' },
] as const;

export function SiteFooter({ locale }: { locale: string }) {
  const t = useTranslations('footer');
  const nav = useTranslations('nav');
  const legal = useTranslations('legal');
  // A literal, not new Date(): reading the clock is a dynamic API under
  // cacheComponents and would cost every page its static render.
  const year = COPYRIGHT_YEAR;

  return (
    <footer className="hairline mt-24 bg-canvas-deep/40">
      <div className="shell grid gap-10 py-14 sm:grid-cols-2 lg:grid-cols-4">
        <div className="lg:col-span-1">
          <Link href={localePath(locale, '/')} className="flex items-center gap-2 text-accent">
            <VelorkiMark width={24} height={24} />
            <span className="font-display text-xl leading-none font-bold text-fg">Velorki</span>
          </Link>
          <p className="mt-3 max-w-xs text-sm text-muted">{t('tagline')}</p>
        </div>

        <nav aria-labelledby="footer-product">
          <h2 id="footer-product" className="overline">
            {t('product')}
          </h2>
          <ul className="mt-3 space-y-2 text-sm">
            {PRODUCT.map((item) => (
              <li key={item.key}>
                <Link href={localePath(locale, item.href)} className="text-muted hover:text-fg">
                  {nav(item.key)}
                </Link>
              </li>
            ))}
          </ul>
        </nav>

        <nav aria-labelledby="footer-resources">
          <h2 id="footer-resources" className="overline">
            {t('resources')}
          </h2>
          <ul className="mt-3 space-y-2 text-sm">
            <li>
              <Link href={localePath(locale, '/docs')} className="text-muted hover:text-fg">
                {nav('docs')}
              </Link>
            </li>
            <li>
              <a href={GITHUB_URL} rel="noreferrer" className="inline-flex items-center gap-1.5 text-muted hover:text-fg">
                <GitHubIcon width={15} height={15} />
                {t('github')}
              </a>
            </li>
            <li>
              <a href={`mailto:${SECURITY_EMAIL}`} className="text-muted hover:text-fg">
                {t('security', { email: SECURITY_EMAIL })}
              </a>
            </li>
          </ul>
        </nav>

        <nav aria-labelledby="footer-legal">
          <h2 id="footer-legal" className="overline">
            {t('legalHeading')}
          </h2>
          <ul className="mt-3 space-y-2 text-sm">
            {LEGAL_DOCS.map((doc) => (
              <li key={doc}>
                <Link href={localePath(locale, `/${doc}`)} className="text-muted hover:text-fg">
                  {legal(`${doc}.title`)}
                </Link>
              </li>
            ))}
          </ul>
        </nav>
      </div>

      <div className="shell hairline flex flex-col gap-2 py-6 text-xs text-muted sm:flex-row sm:items-center sm:justify-between">
        <p>
          <a href={OSM_COPYRIGHT_URL} rel="noreferrer" className="hover:text-fg">
            {t('osm')}
          </a>{' '}
          · {t('credits')}
        </p>
        <p>{t('copyright', { year })}</p>
      </div>
    </footer>
  );
}
