// SPDX-License-Identifier: AGPL-3.0-only
import { createRequire } from 'node:module';
import type { NextConfig } from 'next';
import createNextIntlPlugin from 'next-intl/plugin';

const require = createRequire(import.meta.url);
const withNextIntl = createNextIntlPlugin('./src/i18n/request.ts');

// One policy for every HTML page, share page included. No third-party script
// source exists at all; MapLibre is bundled and its workers are blob: URLs. The
// only remote hosts are the map tiles. 'unsafe-inline' for scripts is what the
// React Server Components payload needs without a per-request nonce (a nonce
// would force dynamic rendering and defeat the cacheable share page).
const CSP = [
  "default-src 'none'",
  "script-src 'self' 'unsafe-inline'",
  "style-src 'self' 'unsafe-inline'",
  "img-src 'self' data: blob: https://tiles.openfreemap.org",
  "connect-src 'self' https://tiles.openfreemap.org",
  'worker-src blob:',
  'child-src blob:',
  "font-src 'self'",
  "manifest-src 'self'",
  "base-uri 'none'",
  "form-action 'none'",
  "frame-ancestors 'none'",
].join('; ');

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
  cacheHandlers: { default: require.resolve('@orkify/next/use-cache') },
  cacheHandler: require.resolve('@orkify/next/isr-cache'),
  cacheMaxMemorySize: 0,
  deploymentId: process.env.NEXT_DEPLOYMENT_ID || undefined,
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
