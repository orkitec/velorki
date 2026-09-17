'use client';
// SPDX-License-Identifier: AGPL-3.0-only
import { useTranslations } from 'next-intl';

export default function SiteError({ reset }: { error: Error & { digest?: string }; reset: () => void }) {
  const t = useTranslations('errors');
  return (
    <section className="shell flex min-h-[60vh] flex-col justify-center py-24">
      <h1 className="text-4xl sm:text-5xl">{t('title')}</h1>
      <p className="mt-4 max-w-lg text-lg text-muted">{t('body')}</p>
      <div className="mt-8">
        <button type="button" onClick={reset} className="btn btn-primary">
          {t('retry')}
        </button>
      </div>
    </section>
  );
}
