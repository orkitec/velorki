// SPDX-License-Identifier: AGPL-3.0-only
import type { MetadataRoute } from 'next';
import { SITE_URL } from '@/site/config';

/** The `Host` directive takes a hostname, not a URL. */
const SITE_HOSTNAME = new URL(SITE_URL).hostname;

/**
 * Everything on the site is public and meant to be read — by people, by search
 * engines and by language models alike — so every crawler is allowed
 * explicitly, including the ones that are commonly blocked by default. The one
 * exception is `/s/`: share links are unguessable capability URLs to someone's
 * route or ride and must never be indexed.
 */
const AI_AND_SEARCH_AGENTS = [
  '*',
  'Googlebot',
  'Bingbot',
  'DuckDuckBot',
  'Applebot',
  'Applebot-Extended',
  'Google-Extended',
  'GPTBot',
  'OAI-SearchBot',
  'ChatGPT-User',
  'ClaudeBot',
  'Claude-Web',
  'Claude-SearchBot',
  'anthropic-ai',
  'PerplexityBot',
  'Perplexity-User',
  'CCBot',
  'Bytespider',
  'Amazonbot',
  'Meta-ExternalAgent',
  'cohere-ai',
  'YouBot',
  'Diffbot',
  'omgili',
];

export default function robots(): MetadataRoute.Robots {
  return {
    rules: AI_AND_SEARCH_AGENTS.map((userAgent) => ({
      userAgent,
      allow: '/',
      disallow: '/s/',
    })),
    sitemap: `${SITE_URL}/sitemap.xml`,
    host: SITE_HOSTNAME,
  };
}
