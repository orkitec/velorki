// SPDX-License-Identifier: AGPL-3.0-only
import { getTranslations } from 'next-intl/server';
import { ScreenshotImage } from './ScreenshotImage';
import { availableVariants } from '@/site/screenshot-files';
import type { Screen } from '@/site/screenshots';

/**
 * A phone drawn in CSS — no bezel image asset — around one app screenshot.
 * The existence check runs here, on the server, at build time.
 */
export async function PhoneFrame({ screen, priority = false }: { screen: Screen; priority?: boolean }) {
  const t = await getTranslations('screenshots');
  const available = availableVariants(screen);
  return (
    <div className="phone">
      <div className="phone-screen">
        <ScreenshotImage screen={screen} available={available} alt={t(`alt.${screen}`)} priority={priority} />
      </div>
    </div>
  );
}
