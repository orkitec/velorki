// SPDX-License-Identifier: AGPL-3.0-only
import { existsSync } from 'node:fs';
import path from 'node:path';
import Image from 'next/image';
import { getLocale, getTranslations } from 'next-intl/server';
import { DEFAULT_SHOT_LOCALE } from '@/site/screenshots';

/**
 * The Apple Watch beside the sensor tiles on the landing page: a case drawn in
 * CSS — no bezel asset — around the watch app's ride screen.
 *
 * The screen is a drawing, because the screenshot pipeline runs on Android
 * emulators and has no watch. A capture from the watch simulator on a Mac
 * drops into `public/screenshots/<lang>/watch/ride.png` (see the README there)
 * and is used instead, in the page's own language where it exists and in
 * English where it does not, exactly as `PhoneFrame` falls back. The check is
 * a filesystem read and so happens here, on the server, at build time.
 *
 * The words on the drawn screen are the watch app's own, and those are English
 * whatever language the phone is in (`app/ios/VelorkiWatch/README.md`), so they
 * are not translated; the `title` says why. The whole thing is `aria-hidden`:
 * it illustrates the copy beside it, which carries the same facts in prose.
 */

/** The capture slot, at the watch simulator's own portrait size. */
const SHOT_WIDTH = 396;
const SHOT_HEIGHT = 484;

/** The ride capture for `locale`, the English one, or nothing. */
function watchShot(locale: string): string | null {
  const languages = locale === DEFAULT_SHOT_LOCALE ? [DEFAULT_SHOT_LOCALE] : [locale, DEFAULT_SHOT_LOCALE];
  for (const language of languages) {
    if (existsSync(path.join(process.cwd(), 'public', 'screenshots', language, 'watch', 'ride.png'))) {
      return `/screenshots/${language}/watch/ride.png`;
    }
  }
  return null;
}

export async function WatchMock() {
  const locale = await getLocale();
  const t = await getTranslations('home.features.sensors.panel');
  const shot = watchShot(locale);
  return (
    <div className="watch" aria-hidden="true" title={t('watchNote')}>
      <div className="watch-screen">
        {shot ? (
          <Image src={shot} alt="" width={SHOT_WIDTH} height={SHOT_HEIGHT} sizes="180px" />
        ) : (
          <div className="watch-app">
            <p className="watch-name">Velorki</p>
            <p className="watch-heart">
              <span className="watch-glyph">♥</span>
              <span className="watch-bpm">142</span>
              <span className="watch-unit">bpm</span>
            </p>
            <p className="watch-distance">24.6 km</p>
            <p className="watch-elapsed">01:12</p>
            <p className="watch-buttons">
              <span className="watch-button">Pause</span>
              <span className="watch-button">Finish</span>
            </p>
          </div>
        )}
      </div>
    </div>
  );
}
