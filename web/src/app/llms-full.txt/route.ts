// SPDX-License-Identifier: AGPL-3.0-only
// The whole English user guide as one Markdown file, for anything that would
// rather read once than crawl. Same source as /docs, same order as the sidebar.
import { GITHUB_URL, PLANNER_URL, SITE_URL } from '@/site/config';
import { listDocs, loadDoc, loadDocsIndex } from '@/site/content';
import { SYNC_LINES, plannerLines } from '@/site/llms';
import { localeUrl } from '@/site/paths';

function body(): string {
  const parts: string[] = [
    '# Velorki — full documentation',
    '',
    '> Velorki is a free, private bike route planner and ride recorder for Android and iOS.',
    '> Planning, loops, offline maps, offline place search, turn-by-turn navigation, recording and',
    '> GPX/FIT/TCX files all run on the phone, with no account. Your routes and rides stay with you:',
    '> on the phone, or in your own iCloud or Google Drive if you sync them, and they export any time.',
    '> The code is open source, so anyone can check that.',
    '',
    ...SYNC_LINES,
    '',
    ...(PLANNER_URL ? [...plannerLines(), ''] : []),
    `Source: ${GITHUB_URL} · Website: ${SITE_URL}${PLANNER_URL ? ` · Web planner: ${PLANNER_URL}` : ''} · Licence: AGPL-3.0-only.`,
    '',
  ];

  const intro = loadDocsIndex('en');
  if (intro && !intro.frontMatter.draft) {
    parts.push('---', '', intro.markdown, '');
  }

  // A `draft: true` page renders with `noindex`; it is not offered here either.
  for (const entry of listDocs('en').filter((doc) => !doc.draft)) {
    const page = loadDoc('en', entry.slug);
    if (!page) continue;
    parts.push(
      '---',
      '',
      `# ${page.frontMatter.title}`,
      '',
      `Source: ${localeUrl('en', `/docs/${page.slug}`)}`,
      '',
    );
    if (page.frontMatter.description) parts.push(page.frontMatter.description, '');
    parts.push(page.markdown, '');
  }

  return parts.join('\n');
}

export function GET(): Response {
  return new Response(body(), {
    headers: {
      'content-type': 'text/plain; charset=utf-8',
      'cache-control': 'public, max-age=3600',
    },
  });
}
