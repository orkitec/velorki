// SPDX-License-Identifier: AGPL-3.0-only
import Link from 'next/link';
import { useTranslations } from 'next-intl';
import type { DocEntry } from '@/site/content';
import { localePath } from '@/site/paths';
import { ArrowIcon } from './Icons';

function DocsList({ locale, docs, current }: { locale: string; docs: DocEntry[]; current?: string }) {
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
          </li>
        );
      })}
    </ul>
  );
}

/**
 * The docs sidebar, in front-matter order, straight from the content directory.
 *
 * Below `lg` the full list would push the heading of the page a screen and a
 * half down, so there it is a closed disclosure above the article; from `lg` it
 * is the sticky column and the summary is not rendered at all. Only one of the
 * two is ever in the layout, so the nav landmark stays single.
 */
export function DocsSidebar({ locale, docs, current }: { locale: string; docs: DocEntry[]; current?: string }) {
  const t = useTranslations('docs');
  return (
    <nav aria-label={t('sidebar')} className="lg:sticky lg:top-24">
      <details className="panel p-4 lg:hidden">
        <summary className="overline cursor-pointer">{t('sidebar')}</summary>
        <div className="mt-3">
          <DocsList locale={locale} docs={docs} current={current} />
        </div>
      </details>
      <div className="hidden lg:block">
        <h2 className="overline mb-3">{t('sidebar')}</h2>
        <DocsList locale={locale} docs={docs} current={current} />
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
