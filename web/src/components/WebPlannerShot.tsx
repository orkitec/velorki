'use client';
// SPDX-License-Identifier: AGPL-3.0-only
import Image from 'next/image';
import { useAppearance } from './Appearance';

/** The web planner in a 1440 × 900 browser window, light and dark (public/screenshots/web). */
export const WEB_SHOT = { width: 1600, height: 1000 } as const;

export function webShotSrc(mode: 'light' | 'dark'): string {
  return `/screenshots/web/planner-${mode}.webp`;
}

/**
 * The landing page's web planner capture, in the look the phone frames are
 * in: the site's palette, or the one the appearance switcher picked
 * (`useAppearance`), so the two pictures never disagree.
 */
export function WebPlannerShot({ alt }: { alt: string }) {
  const { look } = useAppearance();
  return (
    <Image
      src={webShotSrc(look.mode)}
      alt={alt}
      width={WEB_SHOT.width}
      height={WEB_SHOT.height}
      sizes="(min-width: 1024px) 600px, 100vw"
      className="block h-auto w-full"
    />
  );
}
