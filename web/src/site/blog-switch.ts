// SPDX-License-Identifier: AGPL-3.0-only
// Where the language switcher sends a reader, kept apart from blog.ts because
// the switcher is a client component and blog.ts reads the disk.
//
// Every page of the site exists at the same path in every language, so the
// switcher normally keeps the path and swaps the prefix. A blog post does not:
// it exists in the language it was written in, and a version in another
// language, if there is one, has a slug of its own. The same path would be a
// 404, so on a post the switcher links the version in that language, or that
// language's blog index when there is none.
import { switchPath } from './paths';

/** Post path to the paths of its versions by locale, as `blogSwitchPairs` builds it. */
export type BlogSwitchPairs = Readonly<Record<string, Readonly<Record<string, string>>>>;

/** `/blog/<slug>`: a post, not the index, a category, an author or the feed. */
const POST_PATH_RE = /^\/blog\/([^/]+)\/?$/;
const NOT_POSTS = new Set(['category', 'authors', 'feed.xml']);

export function isBlogPostPath(pathname: string): boolean {
  const slug = POST_PATH_RE.exec(pathname)?.[1];
  return slug !== undefined && !NOT_POSTS.has(slug);
}

/**
 * The switcher's link to `target` from `pathname` (without its locale prefix)
 * in `current`. Prefixed for every locale, as `switchPath` explains.
 */
export function localeSwitchHref(
  target: string,
  current: string,
  pathname: string,
  pairs: BlogSwitchPairs = {},
): string {
  if (target === current || !isBlogPostPath(pathname)) return switchPath(target, pathname);
  const key = pathname.replace(/\/$/, '');
  return switchPath(target, pairs[key]?.[target] ?? '/blog');
}
