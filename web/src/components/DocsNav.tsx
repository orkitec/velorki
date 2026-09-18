// SPDX-License-Identifier: AGPL-3.0-only
import Link from 'next/link';
import { useTranslations } from 'next-intl';
import type { DocEntry } from '@/site/content';
import { localePath } from '@/site/paths';
import type { TocSection } from '@/site/toc';
import { ArrowIcon } from './Icons';

/**
 * The page list, with the open page unfolded into its own sections: one tree,
 * the sections a step in and a step quieter than the page titles, the h3s a
 * step in again. No heading over them - the indent is what says whose they are.
 *
 * It takes no translated string, so the markup - which is the whole contract
 * of this component - can be rendered in a test without an intl context.
 * `data-toc-id` is what TocSpy attaches to; without it the anchors are still
 * ordinary in-page links and still work.
 */
export function DocsList({
  locale,
  docs,
  current,
  sections,
}: {
  locale: string;
  docs: DocEntry[];
  current?: string;
  /** The open page's h2/h3 tree, empty when there is nothing to navigate. */
  sections: TocSection[];
}) {
  return (
    <ul className="space-y-0.5 border-l border-line">
      {docs.map((doc) => {
        const active = doc.slug === current;
        return (
          <li key={doc.slug}>
            <Link
              href={localePath(locale, `/docs/${doc.slug}`)}
              aria-current={active ? 'page' : undefined}
              className={`-ml-px block border-l-2 py-1.5 pl-4 text-sm transition-colors ${
                active ? 'border-accent font-bold text-fg' : 'border-transparent text-muted hover:border-line hover:text-fg'
              }`}
            >
              {doc.title}
            </Link>
            {active && sections.length > 0 && (
              <ul className="mb-2 space-y-0.5">
                {sections.map((section) => (
                  <li key={section.id}>
                    <a href={`#${section.id}`} data-toc-id={section.id} className="toc-link pl-7">
                      {section.text}
                    </a>
                    {section.children.length > 0 && (
                      <ul className="space-y-0.5">
                        {section.children.map((child) => (
                          <li key={child.id}>
                            <a href={`#${child.id}`} data-toc-id={child.id} className="toc-link pl-11">
                              {child.text}
                            </a>
                          </li>
                        ))}
                      </ul>
                    )}
                  </li>
                ))}
              </ul>
            )}
          </li>
        );
      })}
    </ul>
  );
}

/**
 * The docs menu: every page in front-matter order, straight from the content
 * directory, with the open page unfolded into its sections.
 *
 * Below `lg` the full list would push the heading of the page a screen and a
 * half down, so there it is a closed disclosure above the article, summarised
 * by the page the reader is on and - once TocSpy is running - by the section
 * they are in. From `lg` it is the left column: sticky under the header, and
 * its own scroller when the page has more sections than the viewport is tall.
 * Only one of the two is ever in the layout, so the nav landmark stays single.
 */
export function DocsSidebar({
  locale,
  docs,
  current,
  sections = [],
}: {
  locale: string;
  docs: DocEntry[];
  current?: string;
  sections?: TocSection[];
}) {
  const t = useTranslations('docs');
  const currentTitle = docs.find((doc) => doc.slug === current)?.title ?? t('sidebar');
  const list = <DocsList locale={locale} docs={docs} current={current} sections={sections} />;
  return (
    <nav aria-label={t('sidebar')}>
      <details className="panel p-4 lg:hidden">
        {/* The one line of the menu on screen while reading: which page, and
            once TocSpy is running which section of it. */}
        <summary className="cursor-pointer text-sm font-bold">
          {currentTitle}
          <span className="font-normal text-muted" data-toc-summary-section hidden />
        </summary>
        <div className="mt-3">{list}</div>
      </details>
      <div
        data-toc-scroll
        className="hidden lg:sticky lg:top-24 lg:block lg:max-h-[calc(100vh-7rem)] lg:overflow-y-auto lg:pb-8"
      >
        <h2 className="overline mb-3">{t('sidebar')}</h2>
        {list}
      </div>
    </nav>
  );
}

export interface Crumb {
  name: string;
  href?: string;
}

export function Breadcrumbs({ items }: { items: Crumb[] }) {
  const t = useTranslations('docs');
  return (
    <nav aria-label={t('breadcrumbLabel')} className="mb-6 text-sm text-muted">
      <ol className="flex flex-wrap items-center gap-1.5">
        {items.map((item, index) => (
          <li key={item.name} className="flex items-center gap-1.5">
            {index > 0 && <span aria-hidden="true">/</span>}
            {item.href ? (
              <Link href={item.href} className="hover:text-fg">
                {item.name}
              </Link>
            ) : (
              <span aria-current="page" className="text-fg">
                {item.name}
              </span>
            )}
          </li>
        ))}
      </ol>
    </nav>
  );
}

/** Previous and next page in sidebar order. */
export function PrevNext({ locale, prev, next }: { locale: string; prev?: DocEntry; next?: DocEntry }) {
  const t = useTranslations('docs');
  if (!prev && !next) return null;
  return (
    <nav aria-label={t('pagination')} className="hairline mt-16 grid gap-3 pt-8 sm:grid-cols-2">
      {prev ? (
        <Link href={localePath(locale, `/docs/${prev.slug}`)} className="panel group p-4 transition-colors hover:border-accent">
          <span className="overline flex items-center gap-1.5">
            <ArrowIcon width={14} height={14} className="rotate-180" />
            {t('prev')}
          </span>
          <span className="mt-1 block font-bold">{prev.title}</span>
        </Link>
      ) : (
        <span />
      )}
      {next && (
        <Link
          href={localePath(locale, `/docs/${next.slug}`)}
          className="panel group p-4 text-right transition-colors hover:border-accent sm:col-start-2"
        >
          <span className="overline flex items-center justify-end gap-1.5">
            {t('next')}
            <ArrowIcon width={14} height={14} />
          </span>
          <span className="mt-1 block font-bold">{next.title}</span>
        </Link>
      )}
    </nav>
  );
}

/** Shown above an unreviewed text, i.e. one whose front matter says `draft: true`. */
export function DraftNotice() {
  const t = useTranslations('docs');
  return (
    <aside role="note" className="mb-8 rounded-[var(--radius-panel)] border border-line bg-panel-2 p-4 text-sm">
      <p className="text-muted">{t('draft')}</p>
    </aside>
  );
}

/** Shown when the locale has no file of its own and English is rendered. */
export function TranslationNotice() {
  const t = useTranslations('docs');
  return (
    <aside role="note" className="mb-8 rounded-[var(--radius-panel)] border border-line bg-panel-2 p-4 text-sm">
      <p className="font-bold">{t('untranslatedTitle')}</p>
      <p className="mt-1 text-muted">{t('untranslatedBody')}</p>
    </aside>
  );
}
