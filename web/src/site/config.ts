// SPDX-License-Identifier: AGPL-3.0-only
// Every constant the site needs about itself. Anything that can differ per
// deployment comes from NEXT_PUBLIC_* so it is inlined at build time and no
// page has to read a request header to know it.

const rawSiteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? 'https://velorki.com';

/** Origin of the public site, without a trailing slash. */
export const SITE_URL = rawSiteUrl.replace(/\/+$/, '');

/** The organisation behind Velorki. */
export const ORG_NAME = 'Orkitec';
export const ORG_URL = 'https://orkitec.com';

export const GITHUB_URL = 'https://github.com/orkitec/velorki';
export const RELEASES_URL = `${GITHUB_URL}/releases`;
export const SECURITY_EMAIL = 'ride@velorki.com';

export const OSM_COPYRIGHT_URL = 'https://www.openstreetmap.org/copyright';

/** Licence: the whole repository — app, relay and this site — is AGPL-3.0-only. */
export const LICENSE_URL = 'https://www.gnu.org/licenses/agpl-3.0.html';

/**
 * Store links. Empty until the listings exist; every badge that has no URL is
 * left out of the markup entirely rather than rendered as a dead link.
 */
export const STORE_URL_IOS = process.env.NEXT_PUBLIC_STORE_URL_IOS ?? '';
export const STORE_URL_ANDROID = process.env.NEXT_PUBLIC_STORE_URL_ANDROID ?? '';

/**
 * Minimum operating systems, verified from the app sources:
 * `app/android/app/build.gradle.kts` has `minSdk = 26` (Android 8.0 Oreo) and
 * `app/ios/Runner.xcodeproj` has `IPHONEOS_DEPLOYMENT_TARGET = 15.0`.
 */
export const MIN_ANDROID = '8.0';
export const MIN_IOS = '15';

/**
 * The year in the footer. A literal on purpose: `new Date()` is a dynamic API
 * under `cacheComponents` and would take every page off the static path for a
 * number that changes once a year. Bump it with the new year's first release.
 */
export const COPYRIGHT_YEAR = 2026;
