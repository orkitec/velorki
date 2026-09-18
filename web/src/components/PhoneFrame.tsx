// SPDX-License-Identifier: AGPL-3.0-only
import { getLocale } from 'next-intl/server';
import { ScreenshotImage } from './ScreenshotImage';
import { availableVariants } from '@/site/screenshot-files';
import type { Screen } from '@/site/screenshots';

/**
 * A phone drawn in CSS — no bezel image asset — around one app screenshot.
 * The existence check runs here, on the server, at build time.
 *
 * The page's locale picks the language the app is shown in: `/de` gets the
 * German capture where the pipeline has taken one, and the English file where
 * it has not. The alt text is translated either way — it describes the screen
 * and the look, not the labels on it — and is built in `ScreenshotImage`,
 * which is where the look is known.
 *
 * `priority` preloads the shot, and belongs to the one above the fold.
 * `eager` is for a second frame showing a screenshot the page has already
 * preloaded: same URL, so it costs no extra request, and it keeps Next's
 * development LCP bookkeeping - which is keyed by src, not by element - from
 * reporting the preloaded copy as lazily loaded.
 */
export async function PhoneFrame({
  screen,
  priority = false,
  eager = false,
}: {
  screen: Screen;
  priority?: boolean;
  eager?: boolean;
}) {
  const locale = await getLocale();
  return (
    <div className="phone">
      <div className="phone-screen">
        <ScreenshotImage
          screen={screen}
          locale={locale}
          available={availableVariants(screen, locale)}
          priority={priority}
          eager={eager}
        />
      </div>
    </div>
  );
}
