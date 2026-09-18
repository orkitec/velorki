// SPDX-License-Identifier: AGPL-3.0-only
import Link from 'next/link';
import { useTranslations } from 'next-intl';
import { GITHUB_URL } from '@/site/config';
import { localePath } from '@/site/paths';
import { AppIcon } from './AppIcon';
import { GitHubIcon } from './Icons';
import { LocaleSwitcher } from './LocaleSwitcher';
import { ThemeSwitcher } from './ThemeSwitcher';

/** Features, Docs and Plus, in that order; Download is the call to action. */
const NAV = [
  { key: 'features', href: '/#features' },
  { key: 'docs', href: '/docs' },
  { key: 'plus', href: '/plus' },
] as const;

export function SiteHeader({ locale }: { locale: string }) {
  const t = useTranslations('nav');
  const home = localePath(locale, '/');
  return (
    <header className="sticky top-0 z-50 border-b border-line-soft bg-canvas/85 backdrop-blur-lg">
      <div className="shell flex h-16 items-center gap-3">
        <Link href={home} aria-label={t('home')} className="flex shrink-0 items-center gap-2">
          <AppIcon size={32} />
          <span className="font-display text-2xl leading-none font-bold tracking-tight text-fg">Velorki</span>
        </Link>

        <nav aria-label={t('primary')} className="ml-auto hidden items-center gap-1 md:flex">
          {NAV.map((item) => (
            <Link
              key={item.key}
              href={localePath(locale, item.href)}
              className="rounded-full px-3 py-2 text-sm font-bold text-muted transition-colors hover:bg-accent/10 hover:text-fg"
            >
              {t(item.key)}
            </Link>
          ))}
          <a
            href={GITHUB_URL}
            rel="noreferrer"
            className="flex items-center gap-1.5 rounded-full px-3 py-2 text-sm font-bold text-muted transition-colors hover:text-fg"
          >
            <GitHubIcon width={16} height={16} />
            {t('github')}
          </a>
        </nav>

        <div className="ml-auto flex items-center gap-2 md:ml-0">
          <ThemeSwitcher />
          <LocaleSwitcher />
          <Link href={localePath(locale, '/download')} className="btn btn-primary !min-h-10 px-4 text-sm">
            {t('download')}
          </Link>
        </div>
      </div>

      {/* Below md the links move to their own scrollable row: no menu button,
          no JavaScript, and nothing that can be left open. */}
      <nav aria-label={t('primary')} className="shell -mt-px flex gap-1 overflow-x-auto pb-2 md:hidden">
        {NAV.map((item) => (
          <Link
            key={item.key}
            href={localePath(locale, item.href)}
            className="shrink-0 rounded-full px-3 py-1.5 text-sm font-bold text-muted"
          >
            {t(item.key)}
          </Link>
        ))}
        <a href={GITHUB_URL} rel="noreferrer" className="shrink-0 rounded-full px-3 py-1.5 text-sm font-bold text-muted">
          {t('github')}
        </a>
      </nav>
    </header>
  );
}
