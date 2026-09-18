'use client';
// SPDX-License-Identifier: AGPL-3.0-only
// A `<details>` menu of plain `<a>` links, one per locale, all pointing at the
// page the reader is on: no handler, no router call, and the disclosure is the
// browser's own, so the switch works with JavaScript switched off. Adding a
// language is adding messages/<locale>.json - the list comes from the routing
// config and the names from site/locales.ts.
//
// This file is a client component only because it has to know which page it is
// on; LocaleSwitcherMenu.tsx holds the markup, and the comment there says why
// the entries must not be `next/link`.
import { useLocale, useTranslations } from 'next-intl';
import { usePathname } from '@/i18n/navigation';
import { LocaleSwitcherMenu } from './LocaleSwitcherMenu';

export function LocaleSwitcher() {
  const t = useTranslations('localeSwitcher');
  const current = useLocale();
  // next-intl's pathname has the locale prefix removed already.
  const pathname = usePathname();
  return <LocaleSwitcherMenu current={current} pathname={pathname} label={t('label')} />;
}
