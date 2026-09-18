// SPDX-License-Identifier: AGPL-3.0-only
// The locale switcher's markup, with everything it needs handed in. It lives
// apart from LocaleSwitcher.tsx for one reason: that file reaches for
// next-intl's client navigation, which is published as ESM that only resolves
// inside a bundler, and this is the half worth asserting in a test.
import { localeName, localeNames } from '@/site/locales';
import { switchPath } from '@/site/paths';
import { ChevronDownIcon, GlobeIcon } from './Icons';

export function LocaleSwitcherMenu({
  current,
  pathname,
  label,
}: {
  current: string;
  pathname: string;
  label: string;
}) {
  return (
    <nav aria-label={label} className="relative">
      <details className="group">
        <summary className="flex cursor-pointer list-none items-center gap-1.5 rounded-full px-2.5 py-1.5 text-xs font-bold tracking-wide text-muted transition-colors hover:text-fg [&::-webkit-details-marker]:hidden">
          <GlobeIcon width={16} height={16} />
          <span>{localeName(current)}</span>
          <ChevronDownIcon width={14} height={14} className="transition-transform group-open:rotate-180" />
        </summary>
        <ul className="absolute right-0 z-50 mt-1 min-w-40 rounded-2xl border border-line-soft bg-panel p-1 shadow-lg">
          {localeNames().map(({ locale, name }) => {
            const active = locale === current;
            return (
              <li key={locale}>
                {/*
                  A plain `<a>`, never `next/link`. A soft navigation fetches
                  the target as an RSC request (`sec-fetch-dest: empty`), and
                  next-intl's middleware refuses to touch NEXT_LOCALE on
                  anything but a document request - a prefetch of `/en` would
                  otherwise flip the reader's language behind their back. So
                  the 307 that `/en` answers with came back without its
                  `Set-Cookie`, the follow-up request for `/` still carried
                  NEXT_LOCALE=de and was sent straight back to `/de`, and the
                  click did nothing at all. A real navigation is a document
                  request, gets the cookie, and lands on the English page -
                  with JavaScript switched off as well.
                */}
                <a
                  href={switchPath(locale, pathname)}
                  hrefLang={locale}
                  lang={locale}
                  aria-current={active ? 'page' : undefined}
                  className={`block rounded-xl px-3 py-2 text-sm font-bold transition-colors ${
                    active ? 'bg-accent text-on-accent' : 'text-muted hover:bg-accent/10 hover:text-fg'
                  }`}
                >
                  {name}
                </a>
              </li>
            );
          })}
        </ul>
      </details>
    </nav>
  );
}
