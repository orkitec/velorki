// SPDX-License-Identifier: AGPL-3.0-only
import Link from 'next/link';
import { useTranslations } from 'next-intl';
import { GITHUB_URL } from '@/site/config';
import { localePath } from '@/site/paths';
import { AppIcon } from './AppIcon';
import { HeaderMenu, type HeaderLink } from './HeaderMenu';
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
  const links: HeaderLink[] = [
    ...NAV.map((item) => ({ href: localePath(locale, item.href), label: t(item.key) })),
    { href: GITHUB_URL, label: t('github'), external: true },
  ];
  const download: HeaderLink = { href: localePath(locale, '/download'), label: t('download') };
  return (
    // The header is `sticky`, so it is a positioned element already and the
    // menu panel below hangs off it without a `relative` that would fight it.
    // `overflow-x-clip`: belt and braces. The row fits from 320 px up, and if a
    // longer translation ever stops fitting, the page still must not scroll
    // sideways. `clip` rather than `hidden`, because the language menu and the
    // menu panel drop out of the header and only the horizontal axis is cut.
    <header className="sticky top-0 z-50 overflow-x-clip border-b border-line-soft bg-canvas/85 backdrop-blur-lg">
      <div className="shell flex h-16 items-center gap-2 md:gap-3">
        <Link href={home} aria-label={t('home')} className="flex shrink-0 items-center gap-2">
          <AppIcon size={32} />
          <span className="font-display text-xl leading-none font-bold tracking-tight text-fg sm:text-2xl">
            Velorki
          </span>
        </Link>

        <nav aria-label={t('primary')} className="ml-auto hidden items-center gap-1 md:flex">
          {NAV.map((item) => (
            <Link
              key={item.key}
              href={localePath(locale, item.href)}
              className="rounded-full px-2 py-2 text-sm font-bold text-muted transition-colors hover:bg-accent/10 hover:text-fg lg:px-3"
            >
              {t(item.key)}
            </Link>
          ))}
          {/* The word only from `lg`: at 768 the German labels and the right
              cluster together are wider than the row, and the mark alone still
              says GitHub. `sr-only` rather than `hidden`, so the link keeps
              its name for anyone who is not looking at it. */}
          <a
            href={GITHUB_URL}
            rel="noreferrer"
            className="flex items-center gap-1.5 rounded-full px-2 py-2 text-sm font-bold text-muted transition-colors hover:text-fg lg:px-3"
          >
            <GitHubIcon width={16} height={16} />
            <span className="sr-only lg:not-sr-only">{t('github')}</span>
          </a>
        </nav>

        {/* Below `md` the links live in the menu and the Download pill with
            them: three 44 px controls and the wordmark are what a 320 px
            viewport holds. From `md` the pill is back in the row. */}
        <div className="ml-auto flex items-center gap-1.5 md:ml-0 md:gap-2">
          <ThemeSwitcher />
          <LocaleSwitcher />
          {/* The wrapper, not a `hidden` on the pill: `.btn` is unlayered CSS
              and would beat the utility's `display: none`. */}
          <div className="hidden md:block">
            <Link href={download.href} className="btn btn-primary !min-h-10 px-4 text-sm">
              {download.label}
            </Link>
          </div>
          <HeaderMenu label={t('menu')} navLabel={t('primary')} links={links} download={download} />
        </div>
      </div>
    </header>
  );
}
