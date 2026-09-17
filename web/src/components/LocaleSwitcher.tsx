'use client';
// SPDX-License-Identifier: AGPL-3.0-only
// Plain links, one per locale, pointing at the same page: no handler, no
// router call, works with JavaScript disabled. It is a client component only
// because it has to know which page it is on.
import Link from 'next/link';
import { useLocale, useTranslations } from 'next-intl';
import { usePathname } from '@/i18n/navigation';
import { LOCALES, switchPath } from '@/site/paths';
import { GlobeIcon } from './Icons';

const LOCALE_LABEL: Record<string, string> = { en: 'EN', de: 'DE' };

export function LocaleSwitcher() {
  const t = useTranslations('localeSwitcher');
  const current = useLocale();
  // next-intl's pathname has the locale prefix removed already.
  const pathname = usePathname();

  return (
    <nav aria-label={t('label')} className="flex items-center gap-1">
      <GlobeIcon className="mr-1 text-muted" width={16} height={16} />
      {LOCALES.map((locale) => {
        const active = locale === current;
        return (
          <Link
            key={locale}
            href={switchPath(locale, pathname)}
            hrefLang={locale}
            lang={locale}
            aria-current={active ? 'true' : undefined}
            className={`rounded-full px-2.5 py-1 text-xs font-bold tracking-wide transition-colors ${
              active ? 'bg-accent text-on-accent' : 'text-muted hover:text-fg'
            }`}
          >
            <span className="sr-only">{t(locale)}</span>
            <span aria-hidden="true">{LOCALE_LABEL[locale] ?? locale.toUpperCase()}</span>
          </Link>
        );
      })}
    </nav>
  );
}
