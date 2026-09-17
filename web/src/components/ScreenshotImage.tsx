'use client';
// SPDX-License-Identifier: AGPL-3.0-only
import Image from 'next/image';
import { useTranslations } from 'next-intl';
import { useAppearance } from './Appearance';
import {
  SHOT_HEIGHT,
  SHOT_WIDTH,
  type Screen,
  type ScreenshotLocales,
  resolveVariant,
  screenshotSrc,
} from '@/site/screenshots';

/**
 * The screen inside the phone frame. `available` is computed on the server at
 * build time — which variants exist, and in which language — so a variant the
 * pipeline has not produced never turns into a broken image: the frame shows a
 * labelled placeholder naming the missing file in the page's own language.
 */
export function ScreenshotImage({
  screen,
  locale,
  available,
  alt,
  priority = false,
  eager = false,
}: {
  screen: Screen;
  /** The page's locale: the language the app in the shot is shown in. */
  locale: string;
  available: ScreenshotLocales;
  alt: string;
  priority?: boolean;
  /** Load at once without preloading; see PhoneFrame. */
  eager?: boolean;
}) {
  const t = useTranslations('screenshots');
  const { mode, accent } = useAppearance();
  const variant = resolveVariant(available, mode, accent);

  if (!variant) {
    return (
      <div className="phone-placeholder">
        <span className="overline">{t('missing')}</span>
        <code className="text-xs break-all opacity-70">{screenshotSrc(locale, mode, accent, screen)}</code>
      </div>
    );
  }

  return (
    <Image
      src={screenshotSrc(variant.locale, variant.mode, variant.accent, screen)}
      alt={alt}
      width={SHOT_WIDTH}
      height={SHOT_HEIGHT}
      sizes="(min-width: 1024px) 304px, 70vw"
      priority={priority}
      loading={!priority && eager ? 'eager' : undefined}
    />
  );
}
