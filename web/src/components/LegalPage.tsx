// SPDX-License-Identifier: AGPL-3.0-only
import { useTranslations } from 'next-intl';
import { Breadcrumbs, TranslationNotice } from './DocsNav';
import { Prose } from './Prose';
import { SECURITY_EMAIL } from '@/site/config';
import { type LegalDoc, loadLegal } from '@/site/content';
import { localePath } from '@/site/paths';

/**
 * One legal document. The Markdown lives in content/<locale>/legal/<doc>.md and
 * falls back to English with a notice, exactly like the docs pages. A document
 * that has not been written yet renders its heading and a pointer to the
 * security address rather than a 404, so the links the app and both store
 * listings already publish are never dead.
 */
export function LegalPage({ locale, doc }: { locale: string; doc: LegalDoc }) {
  const t = useTranslations('legal');
  const nav = useTranslations('docs');
  const page = loadLegal(locale, doc);

  return (
    <div className="shell max-w-3xl py-12">
      <article>
        <Breadcrumbs items={[{ name: nav('home'), href: localePath(locale, '/') }, { name: t(`${doc}.title`) }]} />
        {page && !page.translated && <TranslationNotice />}
        <h1 className="text-4xl sm:text-5xl">{page?.frontMatter.title ?? t(`${doc}.title`)}</h1>
        <p className="mt-4 text-lg text-muted">{page?.frontMatter.description || t(`${doc}.description`)}</p>
        {page ? (
          <Prose html={page.html} className="mt-10" />
        ) : (
          <p className="mt-10 text-muted">{t('missing', { email: SECURITY_EMAIL })}</p>
        )}
      </article>
    </div>
  );
}
