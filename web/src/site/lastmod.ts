// SPDX-License-Identifier: AGPL-3.0-only
// When each content file last changed, for the sitemap's <lastmod>.
//
// The date is the last commit that touched the file, never the build time or
// a file's mtime (both say "today" for every page on every deploy, and a
// crawler learns to ignore a lastmod that always moves). The release artifact
// has no `.git`, so CI records the dates in build-info.json
// (scripts/build-info.mjs) before the upload; a local build asks git itself.
// With neither, pages simply carry no lastmod.
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import path from 'node:path';

/** Paths relative to web/, e.g. `content/en/docs/library.md`, to ISO dates. */
export type ContentDates = Record<string, string>;

/** The pathspecs whose dates are kept: everything a page's text comes from. */
export const DATED_PATHS = ['content', 'messages'] as const;

/**
 * Parses `git log --format=%x00%cI --name-only` output: a NUL-prefixed date
 * line per commit, newest first, then the files it touched. The first date a
 * file is seen with is its last change.
 */
export function parseGitLog(output: string): ContentDates {
  const dates: ContentDates = {};
  let current: string | null = null;
  for (const line of output.split('\n')) {
    if (line.startsWith('\0')) {
      current = line.slice(1).trim();
    } else if (current && line.trim() && !(line.trim() in dates)) {
      dates[line.trim()] = current;
    }
  }
  return dates;
}

function fromBuildInfo(cwd: string): ContentDates | null {
  try {
    const info = JSON.parse(readFileSync(/*turbopackIgnore: true*/ path.join(cwd, 'build-info.json'), 'utf-8')) as {
      contentDates?: unknown;
    };
    const dates = info.contentDates;
    if (dates && typeof dates === 'object' && Object.keys(dates).length > 0) return dates as ContentDates;
  } catch {
    // No build-info.json: a local build.
  }
  return null;
}

function fromGit(cwd: string): ContentDates | null {
  try {
    const output = execFileSync(
      'git',
      ['log', '--format=%x00%cI', '--name-only', '--relative', '--', ...DATED_PATHS],
      { cwd, encoding: 'utf-8', stdio: ['ignore', 'pipe', 'ignore'], maxBuffer: 64 * 1024 * 1024 },
    );
    return parseGitLog(output);
  } catch {
    return null;
  }
}

let cached: ContentDates | null = null;

/** Every dated file's last change, read once per process. */
export function contentDates(): ContentDates {
  if (!cached) {
    const cwd = process.cwd();
    cached = fromBuildInfo(cwd) ?? fromGit(cwd) ?? {};
  }
  return cached;
}

/** The latest of the files' dates, or undefined when none of them has one. */
export function lastModified(files: readonly string[], dates: ContentDates = contentDates()): Date | undefined {
  let latest: string | undefined;
  for (const file of files) {
    const date = dates[file];
    if (date && (!latest || Date.parse(date) > Date.parse(latest))) latest = date;
  }
  return latest ? new Date(latest) : undefined;
}
