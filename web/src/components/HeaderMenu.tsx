// SPDX-License-Identifier: AGPL-3.0-only
// The header's small-screen menu, with everything it needs handed in. It lives
// apart from SiteHeader.tsx for the same reason LocaleSwitcherMenu.tsx does:
// that file pulls in the locale switcher, which reaches for next-intl's client
// navigation - ESM that only resolves inside a bundler - and this is the half
// worth asserting in a test.
import Link from 'next/link';
import { HeaderMenuClose } from './HeaderMenuClose';
import { CloseIcon, GitHubIcon, MenuIcon } from './Icons';

export interface HeaderLink {
  href: string;
  label: string;
  /** GitHub leaves the site, so it is a plain anchor rather than a router link. */
  external?: boolean;
}

/**
 * The menu below `md`: a `<details>` whose panel spans the header. It takes no
 * translated string and no locale, so the markup - which is the whole contract
 * of it - can be rendered in a test without an intl context.
 *
 * It is the browser's own disclosure, like the locale switcher and the docs
 * menu: no handler, no state, and the links still work with JavaScript off -
 * `HeaderMenuClose` only closes the panel behind a tap once JavaScript is
 * there. The
 * panel is absolute against the header, so opening it does not move the page,
 * and the header's `overflow-x-clip` cannot cut it off - `clip` on one axis
 * leaves the other visible.
 */
export function HeaderMenu({
  label,
  navLabel,
  links,
  download,
}: {
  /** What the hamburger is called. */
  label: string;
  /** The landmark the links sit in; the wide row's nav is hidden here, so this
      one carries the same name and only one of the two is ever in the tree. */
  navLabel: string;
  links: HeaderLink[];
  download: HeaderLink;
}) {
  return (
    <details data-header-menu className="group md:hidden">
      <summary
        aria-label={label}
        className="flex h-11 w-11 cursor-pointer list-none items-center justify-center rounded-full border border-line-soft text-fg [&::-webkit-details-marker]:hidden"
      >
        <MenuIcon width={20} height={20} className="group-open:hidden" />
        <CloseIcon width={20} height={20} className="hidden group-open:block" />
      </summary>
      <div className="absolute inset-x-0 top-full border-b border-line-soft bg-canvas shadow-lg">
        <div className="shell flex flex-col gap-1 py-3">
          <nav aria-label={navLabel} className="flex flex-col gap-1">
            {links.map((link) =>
              link.external ? (
                <a
                  key={link.href}
                  href={link.href}
                  rel="noreferrer"
                  className="flex min-h-11 items-center gap-2 rounded-2xl px-3 text-base font-bold text-muted"
                >
                  <GitHubIcon width={16} height={16} />
                  {link.label}
                </a>
              ) : (
                <Link
                  key={link.href}
                  href={link.href}
                  className="flex min-h-11 items-center rounded-2xl px-3 text-base font-bold text-muted"
                >
                  {link.label}
                </Link>
              ),
            )}
          </nav>
          <Link href={download.href} className="btn btn-primary mt-2 !min-h-12">
            {download.label}
          </Link>
        </div>
      </div>
      <HeaderMenuClose />
    </details>
  );
}
