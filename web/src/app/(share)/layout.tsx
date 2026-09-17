// SPDX-License-Identifier: AGPL-3.0-only
import type { ReactNode } from 'react';

/**
 * The share page is its own document root: it is not part of the localised
 * website, it is a link handed to someone who may never have heard of Velorki.
 * The palette lives here rather than in a stylesheet import so the page has no
 * render-blocking request of its own.
 */
const BASE_CSS = `
  :root {
    color-scheme: light dark;
    --bg: #ffffff;
    --fg: #16181d;
    --muted: #5d6470;
    --line: #e3e6ea;
    --accent: #d1481f;
  }
  @media (prefers-color-scheme: dark) {
    :root { --bg: #14161a; --fg: #eceef1; --muted: #9aa2ae; --line: #2a2e35; --accent: #ff7a4d; }
  }
  * { box-sizing: border-box; }
  html, body { height: 100%; }
  body {
    margin: 0;
    background: var(--bg);
    color: var(--fg);
    font: 15px/1.5 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
    display: flex;
    flex-direction: column;
  }
`;

export default function ShareLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <head>
        <meta charSet="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <style>{BASE_CSS}</style>
      </head>
      <body>{children}</body>
    </html>
  );
}
