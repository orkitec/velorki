// SPDX-License-Identifier: AGPL-3.0-only
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import type { NextConfig } from 'next';
import createNextIntlPlugin from 'next-intl/plugin';

// `next dev` serves the site on localhost and the relay under api.localhost,
// /__api/* or `x-velorki-host: api`. Production keeps the strict host gate,
// where a loopback Host is the API role for Orkify's health probe.
if (process.env.NODE_ENV === 'development') process.env.DEV_HOSTS ??= '1';
const withNextIntl = createNextIntlPlugin('./src/i18n/request.ts');

// One policy for every HTML page, share page included. No third-party script
// source exists at all; MapLibre is bundled and its workers are blob: URLs. The
// only remote hosts are the map tiles. 'unsafe-inline' for scripts is what the
// React Server Components payload needs without a per-request nonce (a nonce
// would force dynamic rendering and defeat the cacheable share page).
// React's development build needs eval() for its debugging features; the
// production policy never allows it.
const SCRIPT_SRC =
  process.env.NODE_ENV === 'development'
    ? "script-src 'self' 'unsafe-inline' 'unsafe-eval'"
    : "script-src 'self' 'unsafe-inline'";

// The support chat (src/components/SupportChat.tsx) is the one third party in
// the page, and only when a widget key was set at build time - no key, no
// widget, and none of these sources granted. The script source is pinned to the
// single file, not to the host: a path in a CSP source expression matches that
// URL exactly, so `orkify.com` and `cdnjs.cloudflare.com` cannot serve anything
// else here. cdnjs is the widget's own hard-coded lottie URL, used to play
// animated stickers; blocked, the sticker renders as a text placeholder, so it
// is only listed when the chat is.
// `||`, not `??`: .env.example ships the variable as an empty line, and a copy of
// it must mean "default", not a URL of '' that fails the whole build.
const CHAT_WIDGET_SRC =
  process.env.NEXT_PUBLIC_CHAT_WIDGET_SRC || 'https://orkify.com/orkify-chat.js';
const CHAT_API_ORIGIN = new URL(CHAT_WIDGET_SRC).origin;
const CHAT_ENABLED = Boolean(process.env.NEXT_PUBLIC_CHAT_WIDGET_KEY);
const LOTTIE_SRC = 'https://cdnjs.cloudflare.com/ajax/libs/lottie-web/5.12.2/lottie.min.js';
// Staff avatars and message attachments come from Discord's CDN; the sticker
// picker's previews from Klipy, whose media host is wildcarded because the API
// returns absolute URLs we do not control.
const CHAT_IMG = ['https://cdn.discordapp.com', 'https://media.discordapp.net', 'https://*.klipy.com'];
const CHAT_CONNECT = [CHAT_API_ORIGIN, 'https://api.klipy.com'];

const chat = (sources: string[]) => (CHAT_ENABLED ? ` ${sources.join(' ')}` : '');

const CSP = [
  "default-src 'none'",
  `${SCRIPT_SRC}${chat([CHAT_WIDGET_SRC, LOTTIE_SRC])}`,
  "style-src 'self' 'unsafe-inline'",
  `img-src 'self' data: blob: https://tiles.openfreemap.org${chat(CHAT_IMG)}`,
  `connect-src 'self' https://tiles.openfreemap.org${chat(CHAT_CONNECT)}`,
  'worker-src blob:',
  'child-src blob:',
  "font-src 'self'",
  "manifest-src 'self'",
  "base-uri 'none'",
  "form-action 'none'",
  "frame-ancestors 'none'",
].join('; ');

// What this build is, for the footer and for /health's `version`. Neither fact
// can be read at runtime: Orkify passes NEXT_DEPLOYMENT_ID
// (`v<release>-<artifact>`) into the build only, and the release artifact has
// no `.git` for the box to ask. See src/build-meta.ts for the whole story.
//
// build-info.json is written by scripts/build-info.mjs in CI before the upload;
// `git rev-parse` is the fallback that gives a local build a real commit too.
function buildCommit(): string {
  try {
    const raw = readFileSync(new URL('./build-info.json', import.meta.url), 'utf-8');
    const commit = (JSON.parse(raw) as { commit?: unknown }).commit;
    if (typeof commit === 'string' && commit) return commit;
  } catch {
    // No build-info.json: a local build, or a `next build` outside CI.
  }
  try {
    return execFileSync('git', ['rev-parse', 'HEAD'], {
      encoding: 'utf-8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
  } catch {
    return '';
  }
}

const SECURITY_HEADERS = [
  { key: 'content-security-policy', value: CSP },
  { key: 'x-content-type-options', value: 'nosniff' },
  { key: 'referrer-policy', value: 'strict-origin-when-cross-origin' },
  { key: 'permissions-policy', value: 'camera=(), microphone=(), geolocation=(), payment=()' },
  { key: 'x-frame-options', value: 'DENY' },
];

const nextConfig: NextConfig = {
  output: 'standalone',
  // `next dev` otherwise writes AGENTS.md and CLAUDE.md into web/ on every run
  // (node_modules/next/dist/server/lib/generate-agent-files.js). The repo keeps
  // its own agent notes at the root; a second, regenerated pair here is noise
  // in every diff.
  agentRules: false,
  cacheComponents: true,
  // Every rewrite `src/proxy.ts` returns - next-intl's `/` -> `/en` included -
  // would otherwise be treated as a rewrite to a different origin, and Next
  // would re-issue the request over loopback HTTP instead of routing it
  // internally. `NextURL` rewrites a loopback hostname to the literal
  // `localhost` (`REGEX_LOCALHOST_HOSTNAME`, next/dist/server/web/next-url.js)
  // while the router compares the rewrite against `http://<HOSTNAME>:<PORT>`,
  // and the deployment binds `HOSTNAME=127.0.0.1` (orkify.yml), so the two
  // origins never matched. The second request arrives with
  // `Host: localhost:<PORT>`, which the host gate reads as the api role, and
  // the landing page answers the api host's JSON 404. This keeps the request
  // URL the proxy sees exactly as Next built it, so a rewrite resolved against
  // `request.url` lands on the origin the router expects and stays internal.
  // The flag also stops Next from stripping its internal search params
  // (`_rsc`) before the proxy sees them, which changes nothing here: every
  // branch decides on `nextUrl.pathname` and only ever forwards the search
  // string verbatim.
  skipProxyUrlNormalize: true,
  // Next's own caches, not @orkify/next's handlers: those key pages by path
  // alone and keep them across a rolling reload, so after a deploy every
  // worker served the previous build's HTML, whose stylesheet no longer
  // existed. Each worker's cache lives and dies with its build; the relay's
  // shared state (rate limits, entitlements) uses @orkify/cache directly.
  deploymentId: process.env.NEXT_DEPLOYMENT_ID || undefined,
  // Inlined into every bundle as string literals, so nothing reads the
  // environment at runtime - which is the point, the values only exist while
  // the artifact is being built. Both are validated where they are consumed.
  env: {
    VELORKI_RELEASE: process.env.NEXT_DEPLOYMENT_ID ?? '',
    VELORKI_COMMIT: buildCommit(),
  },
  experimental: { serverSourceMaps: true },
  // Files read at runtime with readFileSync must be traced into the standalone
  // output by hand: the prompts, the markdown content, the message catalogues.
  outputFileTracingIncludes: {
    '/ai/plan': ['./src/ai/prompts/*.md'],
    '/**': ['./content/**/*', './messages/*.json'],
  },
  async rewrites() {
    return {
      beforeFiles: [{ source: '/.well-known/:file', destination: '/well-known/:file' }],
      afterFiles: [],
      fallback: [],
    };
  },
  async headers() {
    return [{ source: '/:path*', headers: SECURITY_HEADERS }];
  },
};

export default withNextIntl(nextConfig);
