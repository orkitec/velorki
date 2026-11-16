'use client';
// SPDX-License-Identifier: AGPL-3.0-only
// The stored theme, put back on <html> before anything is painted, so a reader
// who forced a palette never sees a flash of the other one.
//
// On the first load that is an inline script in the server's HTML, the first
// thing in <body>: parser-blocking, ahead of every element that could paint
// ('unsafe-inline' in next.config's script-src allows it). A navigation that
// changes the language renders this layout again in the browser, <html>
// included, so the attribute is gone and the script would not run again -
// React never executes a script it creates, and reports every one it meets.
// There the component renders nothing and puts the theme back itself, in a
// layout effect, which also runs before the browser paints.
import { useLayoutEffect, useSyncExternalStore } from 'react';
import { THEME_STORAGE_KEY } from '@/site/theme';

function applyStoredTheme() {
  try {
    const theme = localStorage.getItem(THEME_STORAGE_KEY);
    if (theme === 'light' || theme === 'dark') document.documentElement.setAttribute('data-theme', theme);
  } catch {
    // Storage blocked: the system theme, as with nothing stored.
  }
}

/** The same as `applyStoredTheme`, as text: a minifier may rename anything in a function's own source. */
const SOURCE = `(function(){try{var t=localStorage.getItem(${JSON.stringify(THEME_STORAGE_KEY)});
if(t==="light"||t==="dark")document.documentElement.setAttribute("data-theme",t)}catch(e){}})()`;

const noSubscription = () => () => {};

export function ThemeScript() {
  // True while the server renders and while the browser hydrates that HTML,
  // false for a render that starts in the browser.
  const fromServer = useSyncExternalStore(
    noSubscription,
    () => false,
    () => true,
  );
  useLayoutEffect(applyStoredTheme, []);
  if (!fromServer) return null;
  return <script dangerouslySetInnerHTML={{ __html: SOURCE }} />;
}
