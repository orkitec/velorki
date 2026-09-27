// SPDX-License-Identifier: AGPL-3.0-only
'use client';

import { useEffect, useState } from 'react';

/** Set when the notice has been read, so it appears once per browser. */
export const COOKIE_NOTICE_KEY = 'velorki.cookie-notice';
/** Dispatched by the footer's Cookies button to open it again. */
export const COOKIE_NOTICE_EVENT = 'velorki:cookie-notice';

export interface CookieNoticeStrings {
  body: string;
  link: string;
  dismiss: string;
  label: string;
}

/**
 * The card itself, with no state: the strings come from the server (the site
 * layout holds the translations) so this file needs no intl context, and a test
 * can render it directly.
 */
export function CookieNoticeCard({
  strings,
  href,
  onDismiss,
}: {
  strings: CookieNoticeStrings;
  href: string;
  onDismiss?: () => void;
}) {
  return (
    <div
      role="region"
      aria-label={strings.label}
      // The support chat's launcher is a 56 px circle at bottom/right 20 px and
      // renders above this, so on a narrow screen - where the card spans the
      // full width - it would sit on the dismiss button. Hence the bottom
      // clearance there and not above `sm`, where a centred max-w-md card never
      // reaches that corner.
      className="fixed inset-x-0 bottom-0 z-50 p-4 pb-24 sm:pb-6"
    >
      <div className="hairline mx-auto max-w-md rounded-2xl bg-canvas-deep p-4 shadow-lg">
        <p className="text-sm text-muted">
          {strings.body}{' '}
          <a href={href} className="text-fg underline decoration-dotted hover:no-underline">
            {strings.link}
          </a>
        </p>
        <div className="mt-3 flex justify-end">
          <button
            type="button"
            onClick={onDismiss}
            className="rounded-full bg-accent px-4 py-2 text-sm font-semibold text-on-accent"
          >
            {strings.dismiss}
          </button>
        </div>
      </div>
    </div>
  );
}

/**
 * A notice, not a consent gate. velorki.com stores nothing on a visitor's
 * device until they ask for it - a language choice, a theme, the support chat's
 * own state - and none of it is tracking, so under section 25 (2) TTDSG there
 * is nothing to consent to and nothing to refuse. It therefore has one button,
 * blocks nothing, and is shown once per browser; the footer's Cookies entry
 * brings it back.
 *
 * The dismissal itself is the only thing this writes, and it writes it to local
 * storage rather than a cookie.
 */
export function CookieNotice({ strings, href }: { strings: CookieNoticeStrings; href: string }) {
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    // A browser that refuses storage (private mode, a strict setting) throws on
    // read. Nothing to remember then, and a notice on every page would be worse
    // than none, so stay closed and leave the footer button as the way in.
    try {
      if (window.localStorage.getItem(COOKIE_NOTICE_KEY)) return;
    } catch {
      return;
    }
    // Late enough not to cover the page as it paints.
    const timer = setTimeout(() => setVisible(true), 1200);
    return () => clearTimeout(timer);
  }, []);

  useEffect(() => {
    const open = () => setVisible(true);
    window.addEventListener(COOKIE_NOTICE_EVENT, open);
    return () => window.removeEventListener(COOKIE_NOTICE_EVENT, open);
  }, []);

  if (!visible) return null;

  return (
    <CookieNoticeCard
      strings={strings}
      href={href}
      onDismiss={() => {
        try {
          window.localStorage.setItem(COOKIE_NOTICE_KEY, '1');
        } catch {
          // Refused storage: the notice simply comes back next time.
        }
        setVisible(false);
      }}
    />
  );
}

/** The footer entry that opens the notice again. */
export function CookieNoticeButton({ label }: { label: string }) {
  return (
    <button
      type="button"
      onClick={() => window.dispatchEvent(new Event(COOKIE_NOTICE_EVENT))}
      className="hover:text-fg"
    >
      <span aria-hidden="true">🍪</span> {label}
    </button>
  );
}
