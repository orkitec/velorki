// SPDX-License-Identifier: AGPL-3.0-only
import Link from 'next/link';
import { useLocale, useTranslations } from 'next-intl';
import { localePath } from '@/site/paths';

export default function NotFound() {
  const t = useTranslations('notFound');
  const locale = useLocale();
  return (
    <section className="shell flex min-h-[60vh] flex-col justify-center py-24">
      <p className="overline">404</p>
      <h1 className="mt-3 text-5xl sm:text-6xl">{t('title')}</h1>
      <p className="mt-4 max-w-lg text-lg text-muted">{t('body')}</p>
      <div className="mt-8 flex flex-wrap gap-3">
        <Link href={localePath(locale, '/')} className="btn btn-primary">
          {t('home')}
        </Link>
        <Link href={localePath(locale, '/docs')} className="btn btn-secondary">
          {t('docs')}
        </Link>
      </div>
    </section>
  );
}
