'use client';
// SPDX-License-Identifier: AGPL-3.0-only
import Image, { getImageProps } from 'next/image';
import { useTranslations } from 'next-intl';
import { useAppearance, useSystemLook } from './Appearance';
import {
  SHOT_HEIGHT,
  SHOT_WIDTH,
  type Screen,
  type ScreenshotLocales,
  resolveVariant,
  screenshotSrc,
} from '@/site/screenshots';

const SIZES = '(min-width: 1024px) 304px, 70vw';
const DARK = '(prefers-color-scheme: dark)';
const LIGHT = '(prefers-color-scheme: light)';

/**
 * The screen inside the phone frame. `available` is computed on the server at
 * build time — which variants exist, and in which language — so a variant the
 * pipeline has not produced never turns into a broken image: the frame shows a
 * labelled placeholder naming the missing file in the page's own language.
 *
 * Which variant that is comes from `useAppearance`: the site's own palette
 * until somebody uses the appearance switcher. The alt text is built here
 * rather than passed in, because it names the look as well as the screen and
 * so changes with it.
 *
 * While the look follows the system (nobody picked a mode, no `data-theme`),
 * the frame is a `<picture>` with one source per colour scheme, so the browser
 * picks the right shot from the HTML itself, before any script runs: the
 * server cannot know the visitor's scheme, and a single `<img>` would show
 * the default look's shot until hydration, which for a light-scheme visitor
 * made the real image a late discovery and the preloaded one a waste. The
 * preloads carry the same media queries, so only the matching shot is
 * fetched, at high priority for the frame above the fold.
 */
export function ScreenshotImage({
  screen,
  locale,
  available,
  priority = false,
  eager = false,
}: {
  screen: Screen;
  /** The page's locale: the language the app in the shot is shown in. */
  locale: string;
  available: ScreenshotLocales;
  priority?: boolean;
  /** Load at once without preloading; see PhoneFrame. */
  eager?: boolean;
}) {
  const t = useTranslations('screenshots');
  const { look } = useAppearance();
  const systemLook = useSystemLook();
  const variant = resolveVariant(available, look.mode, look.accent);

  if (!variant) {
    return (
      <div className="phone-placeholder">
        <span className="overline">{t('missing')}</span>
        <code className="text-xs break-all opacity-70">{screenshotSrc(locale, look.mode, look.accent, screen)}</code>
      </div>
    );
  }

  const alt = t(`look.${variant.mode}`, { description: t(`alt.${screen}`) });
  const loading = priority || eager ? ('eager' as const) : undefined;

  const dark = systemLook ? resolveVariant(available, 'dark', look.accent) : null;
  const light = systemLook ? resolveVariant(available, 'light', look.accent) : null;
  if (dark && light && dark.mode === 'dark' && light.mode === 'light') {
    const shot = (v: { mode: 'dark' | 'light'; accent: typeof look.accent; locale: string }) =>
      getImageProps({
        src: screenshotSrc(v.locale, v.mode, v.accent, screen),
        alt,
        width: SHOT_WIDTH,
        height: SHOT_HEIGHT,
        sizes: SIZES,
        priority,
        fetchPriority: priority ? 'high' : undefined,
        loading,
      }).props;
    const darkProps = shot(dark);
    const lightProps = shot(light);
    const shown = variant.mode === 'dark' ? darkProps : lightProps;
    return (
      <>
        {priority && (
          <>
            <link
              rel="preload"
              as="image"
              media={DARK}
              imageSrcSet={darkProps.srcSet}
              imageSizes={SIZES}
              fetchPriority="high"
            />
            <link
              rel="preload"
              as="image"
              media={LIGHT}
              imageSrcSet={lightProps.srcSet}
              imageSizes={SIZES}
              fetchPriority="high"
            />
          </>
        )}
        <picture>
          <source media={DARK} srcSet={darkProps.srcSet} sizes={SIZES} />
          <source media={LIGHT} srcSet={lightProps.srcSet} sizes={SIZES} />
          <img {...shown} alt={alt} />
        </picture>
      </>
    );
  }

  return (
    <Image
      src={screenshotSrc(variant.locale, variant.mode, variant.accent, screen)}
      alt={alt}
      width={SHOT_WIDTH}
      height={SHOT_HEIGHT}
      sizes={SIZES}
      priority={priority}
      fetchPriority={priority ? 'high' : undefined}
      loading={!priority && eager ? 'eager' : undefined}
    />
  );
}
