// SPDX-License-Identifier: AGPL-3.0-only
// https://llmstxt.org/ — an H1, a blockquote summary, optional prose, then
// sections of links with a short description each. Everything here is the
// English source; llms-full.txt carries the whole guide inline.
import { GITHUB_URL, MIN_ANDROID, MIN_IOS, SITE_URL } from '@/site/config';
import { LEGAL_DOCS, listDocs } from '@/site/content';
import { localeUrl } from '@/site/paths';

const SUMMARY =
  'Velorki is a free, open-source bike route planner and ride recorder for Android and iOS. ' +
  'Planning, loops, offline maps, offline place search, turn-by-turn navigation, recording and ' +
  'GPX/FIT files all run on the phone, on OpenStreetMap data, with no account and no connection.';

const LEGAL_DESCRIPTIONS: Record<string, string> = {
  privacy: 'What is stored on the device, what leaves it and what never does.',
  terms: 'Terms for the app, the Velorki Plus subscription and shared links.',
  imprint: 'The provider of velorki.com and how to reach it.',
};

function body(): string {
  const docs = listDocs('en');
  const lines: string[] = [
    '# Velorki',
    '',
    `> ${SUMMARY}`,
    '',
    'Everything that runs on the phone is free, for everyone, for good: planning, loops, offline',
    'maps and routing, place search, turn-by-turn navigation with spoken cues, ride recording,',
    'ride statistics, and GPX and FIT import and export. Velorki Plus is a small subscription',
    'only for the parts that need a server or a partner account: the AI assistant, the Strava',
    'connection, the Ride with GPS connection and share links. The price is shown in the app by',
    'the store, and is deliberately not quoted on the website.',
    '',
    `The app is Apache-2.0; the relay and this website are AGPL-3.0-only. Requires Android ${MIN_ANDROID}+ or iOS ${MIN_IOS}+.`,
    'Map data © OpenStreetMap contributors (ODbL), routing by BRouter, vector tiles by OpenFreeMap,',
    'online place search by Photon, cycling overlay by CyclOSM.',
    '',
    '## Product',
    '',
    `- [Velorki](${localeUrl('en', '/')}): what the app does, the feature tour, Free vs Plus, and the FAQ.`,
    `- [Download](${localeUrl('en', '/download')}): the stores, the APK from GitHub Releases, and the minimum system versions.`,
    `- [Velorki Plus](${localeUrl('en', '/plus')}): what the subscription includes, how to restore it and how to cancel it.`,
    '',
    '## Documentation',
    '',
    `- [Documentation index](${localeUrl('en', '/docs')}): the user guide.`,
  ];

  for (const doc of docs) {
    const description = doc.description ? `: ${doc.description}` : '';
    lines.push(`- [${doc.title}](${localeUrl('en', `/docs/${doc.slug}`)})${description}`);
  }

  lines.push('', '## Legal', '');
  for (const doc of LEGAL_DOCS) {
    const title = doc[0]!.toUpperCase() + doc.slice(1);
    lines.push(`- [${title}](${localeUrl('en', `/${doc}`)}): ${LEGAL_DESCRIPTIONS[doc] ?? ''}`);
  }

  lines.push(
    '',
    '## Optional',
    '',
    `- [Full documentation as one file](${SITE_URL}/llms-full.txt): every documentation page, in Markdown.`,
    `- [Source code](${GITHUB_URL}): the app, the relay and this website.`,
    `- [Sitemap](${SITE_URL}/sitemap.xml): every page in every language.`,
    '',
  );

  return lines.join('\n');
}

export function GET(): Response {
  return new Response(body(), {
    headers: {
      'content-type': 'text/plain; charset=utf-8',
      'cache-control': 'public, max-age=3600',
    },
  });
}
