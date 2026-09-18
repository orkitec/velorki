// SPDX-License-Identifier: AGPL-3.0-only
// The stored theme, put back on <html> before anything is painted, so a reader
// who forced a palette never sees a flash of the other one. It is the first
// thing in <body>: parser-blocking, ahead of every element that could paint,
// and out of the way of Next's own <head> handling. Inline, which the site's
// content-security policy allows for scripts ('unsafe-inline' in next.config).
import { THEME_STORAGE_KEY } from '@/site/theme';

const SOURCE = `(function(){try{var t=localStorage.getItem(${JSON.stringify(THEME_STORAGE_KEY)});
if(t==="light"||t==="dark")document.documentElement.setAttribute("data-theme",t)}catch(e){}})()`;

export function ThemeScript() {
  return <script dangerouslySetInnerHTML={{ __html: SOURCE }} />;
}
