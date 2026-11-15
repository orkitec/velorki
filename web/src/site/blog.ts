// SPDX-License-Identifier: AGPL-3.0-only
// The blog: posts read from content/<locale>/blog/ at build time.
//
// A post is `blog/<slug>.md`, or `blog/<slug>/index.md` with its pictures and
// a GPX beside it. Unlike the docs, posts are not translated: each one exists
// in the language it was written in, at that locale's address only, and a
// version in another language is a post of its own that names the same `key`.
// So `/de/blog/<english-slug>` is not a page, and nothing here falls back to
// English.
//
// The front matter is checked strictly, and a mistake throws with the file's
// path: a build that fails names the file, where a lenient default would
// publish a post with no date or no author.
//
// Like content.ts, everything is synchronous (see markdown.ts) and every path
// is marked `turbopackIgnore`; `next.config.ts` traces `./content/**/*` into
// the standalone output, pictures included.
import { createHash } from 'node:crypto';
import fs, { existsSync, fstatSync, openSync, readFileSync, readSync, readdirSync, statSync } from 'node:fs';
import path from 'node:path';
import matter from 'gray-matter';
import { routing } from '@/i18n/routing';
import { AUTHOR_IDS, findAuthor } from './authors';
import { type HastNode, type Heading, renderBody, stripLeadingH1 } from './markdown';
import { localeUrl } from './paths';

export const BLOG_CATEGORIES = ['engineering', 'rides'] as const;
export type BlogCategory = (typeof BLOG_CATEGORIES)[number];

/** Path segments under /blog that are pages of their own, never a slug. */
const RESERVED_SLUGS = new Set(['category', 'authors']);

/** What a slug, key or locale may look like: one plain path segment. */
const SEGMENT_RE = /^[a-z0-9][a-z0-9-]*$/;
/** A file beside a post: a plain name, no directory, no leading dot. */
const FILE_RE = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const DESCRIPTION_MAX = 160;

/**
 * The files a post may carry and how they are served. SVG is left out on
 * purpose: opened on its own, an SVG from our origin is a document that runs
 * its inline script under a CSP that allows inline script.
 */
const MEDIA_TYPES: Readonly<Record<string, string>> = {
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.webp': 'image/webp',
  '.avif': 'image/avif',
  '.gpx': 'application/gpx+xml',
};
const IMAGE_EXTENSIONS = new Set(['.png', '.jpg', '.jpeg', '.gif', '.webp', '.avif']);

const FIELDS = new Set(['title', 'description', 'date', 'updated', 'author', 'category', 'key', 'image', 'imageAlt', 'gpx', 'draft']);

export interface BlogPost {
  locale: string;
  slug: string;
  /** Pairs the language versions of one post; the slug when not given. */
  key: string;
  title: string;
  description: string;
  /** `YYYY-MM-DD`. */
  date: string;
  /** `YYYY-MM-DD`, only when the content changed after `date`. */
  updated?: string;
  author: string;
  category: BlogCategory;
  /** A file name beside the post: the cover and the share picture. */
  image?: string;
  /** What the cover shows, for readers who cannot see it; required with `image`. */
  imageAlt?: string;
  /** A file name beside the post: the ride, drawn on a map and offered as a download. */
  gpx?: string;
  draft: boolean;
  /** Absolute path of the Markdown file. */
  file: string;
  /** The post's own folder, or null for a single-file post (which has no files beside it). */
  dir: string | null;
  /** The body without front matter and without a leading h1. */
  markdown: string;
}

/* ------------------------------------------------------------------ config */

interface BlogConfig {
  /** The directory holding `<locale>/blog/`; `content/` in the app. */
  root: string;
  /** Whether `draft: true` posts are part of the site. */
  drafts: boolean;
}

let override: Partial<BlogConfig> | null = null;
let cache: BlogPost[] | null = null;

/**
 * Points the loader at another content root, or shows or hides drafts; null
 * restores the defaults. For tests, which read fixtures rather than the real
 * posts.
 */
export function configureBlog(next: Partial<BlogConfig> | null): void {
  override = next;
  cache = null;
}

function contentRoot(): string {
  return override?.root ?? path.join(/*turbopackIgnore: true*/ process.cwd(), 'content');
}

/**
 * Drafts are visible under `next dev` and nowhere else: a production build
 * leaves them out entirely, so they cannot leak through a listing, the
 * sitemap, a feed or a guessed URL.
 */
function showDrafts(): boolean {
  return override?.drafts ?? process.env.NODE_ENV === 'development';
}

/** A path for an error message: relative to web/, as a reader would look for it. */
function rel(file: string): string {
  return path.relative(process.cwd(), file).split(path.sep).join('/');
}

/* ------------------------------------------------------------ validation */

function fail(file: string, problem: string): never {
  throw new Error(`${rel(file)}: ${problem}`);
}

/** A YAML date (gray-matter turns `2026-11-15` into a Date) or a quoted one. */
function isoDate(value: unknown, field: string, file: string): string {
  let text: string | null = null;
  if (value instanceof Date && !Number.isNaN(value.getTime())) text = value.toISOString().slice(0, 10);
  else if (typeof value === 'string' && DATE_RE.test(value.trim())) text = value.trim();
  if (text === null || Number.isNaN(Date.parse(`${text}T00:00:00Z`)) || new Date(`${text}T00:00:00Z`).toISOString().slice(0, 10) !== text) {
    fail(file, `\`${field}\` must be a date written YYYY-MM-DD`);
  }
  return text;
}

function requiredString(data: Record<string, unknown>, field: string, file: string): string {
  const value = data[field];
  if (typeof value !== 'string' || value.trim() === '') fail(file, `\`${field}\` is required`);
  return value.trim();
}

function optionalString(data: Record<string, unknown>, field: string, file: string): string | undefined {
  const value = data[field];
  if (value === undefined || value === null) return undefined;
  if (typeof value !== 'string' || value.trim() === '') fail(file, `\`${field}\` must be a non-empty string`);
  return value.trim();
}

/** A file named in the front matter: beside the post, of an allowed kind. */
function besideFile(
  name: string | undefined,
  field: string,
  kinds: ReadonlySet<string>,
  dir: string | null,
  file: string,
): string | undefined {
  if (name === undefined) return undefined;
  const clean = name.replace(/^\.\//, '');
  if (dir === null) fail(file, `\`${field}\` needs the post in a folder (blog/<slug>/index.md) with the file beside it`);
  if (!FILE_RE.test(clean) || !kinds.has(path.extname(clean).toLowerCase())) {
    fail(file, `\`${field}\` must name a ${[...kinds].join('/')} file beside the post`);
  }
  if (!existsSync(path.join(/*turbopackIgnore: true*/ dir, clean))) fail(file, `\`${field}\`: ${clean} is not beside the post`);
  return clean;
}

/** One post's front matter, checked; throws with the file's path. */
function parsePost(locale: string, slug: string, file: string, dir: string | null): BlogPost {
  let parsed: matter.GrayMatterFile<string>;
  try {
    parsed = matter(readFileSync(/*turbopackIgnore: true*/ file, 'utf8'));
  } catch (error) {
    fail(file, `the front matter is not valid YAML (${(error as Error).message})`);
  }
  const data = parsed.data as Record<string, unknown>;
  for (const field of Object.keys(data)) {
    if (!FIELDS.has(field)) fail(file, `unknown front-matter field \`${field}\``);
  }

  const title = requiredString(data, 'title', file);
  const description = requiredString(data, 'description', file);
  if (description.length > DESCRIPTION_MAX) {
    fail(file, `\`description\` is ${description.length} characters; ${DESCRIPTION_MAX} at most`);
  }
  if (data.date === undefined) fail(file, '`date` is required');
  const date = isoDate(data.date, 'date', file);
  const updated = data.updated === undefined || data.updated === null ? undefined : isoDate(data.updated, 'updated', file);
  if (updated !== undefined && updated < date) fail(file, '`updated` is before `date`');

  const author = requiredString(data, 'author', file);
  if (findAuthor(author) === null) fail(file, `\`author\` ${author} is not in src/site/authors.ts (${AUTHOR_IDS.join(', ')})`);
  const category = requiredString(data, 'category', file);
  if (!(BLOG_CATEGORIES as readonly string[]).includes(category)) {
    fail(file, `\`category\` must be one of ${BLOG_CATEGORIES.join(', ')}`);
  }
  const key = optionalString(data, 'key', file) ?? slug;
  if (!SEGMENT_RE.test(key)) fail(file, '`key` must be lower case letters, digits and hyphens');
  if (data.draft !== undefined && typeof data.draft !== 'boolean') fail(file, '`draft` must be true or false');

  const image = besideFile(optionalString(data, 'image', file), 'image', IMAGE_EXTENSIONS, dir, file);
  if (image !== undefined && dir !== null && imageSize(path.join(/*turbopackIgnore: true*/ dir, image)) === null) {
    fail(file, `\`image\`: the size of ${image} cannot be read`);
  }
  const imageAlt = optionalString(data, 'imageAlt', file);
  if (image !== undefined && imageAlt === undefined) fail(file, '`imageAlt` must describe the cover named in `image`');
  if (image === undefined && imageAlt !== undefined) fail(file, '`imageAlt` without an `image`');
  const gpx = besideFile(optionalString(data, 'gpx', file), 'gpx', new Set(['.gpx']), dir, file);

  return {
    locale,
    slug,
    key,
    title,
    description,
    date,
    ...(updated !== undefined ? { updated } : {}),
    author,
    category: category as BlogCategory,
    ...(image !== undefined ? { image } : {}),
    ...(imageAlt !== undefined ? { imageAlt } : {}),
    ...(gpx !== undefined ? { gpx } : {}),
    draft: data.draft === true,
    file,
    dir,
    markdown: stripLeadingH1(parsed.content).trim(),
  };
}

/* ---------------------------------------------------------------- loading */

/** Every post of one locale, drafts included, unsorted. */
function readLocale(locale: string): BlogPost[] {
  const base = path.join(/*turbopackIgnore: true*/ contentRoot(), locale, 'blog');
  if (!existsSync(base)) return [];
  const posts: BlogPost[] = [];
  const seen = new Map<string, string>();
  for (const name of readdirSync(/*turbopackIgnore: true*/ base).sort()) {
    if (name.startsWith('.')) continue;
    const full = path.join(/*turbopackIgnore: true*/ base, name);
    let slug: string;
    let file: string;
    let dir: string | null;
    if (statSync(full).isDirectory()) {
      slug = name;
      file = path.join(/*turbopackIgnore: true*/ full, 'index.md');
      dir = full;
      if (!existsSync(file)) fail(full, 'a post folder needs an index.md');
    } else if (name.endsWith('.md')) {
      slug = name.slice(0, -3);
      file = full;
      dir = null;
    } else {
      fail(full, 'only posts belong here: <slug>.md, or <slug>/index.md with its files beside it');
    }
    if (!SEGMENT_RE.test(slug) || RESERVED_SLUGS.has(slug)) {
      fail(file, `\`${slug}\` cannot be a slug: lower case letters, digits and hyphens, and not ${[...RESERVED_SLUGS].join(' or ')}`);
    }
    if (seen.has(slug)) fail(file, `the slug ${slug} is taken by ${seen.get(slug)}`);
    seen.set(slug, rel(file));
    posts.push(parsePost(locale, slug, file, dir));
  }
  const keys = new Map<string, string>();
  for (const post of posts) {
    const other = keys.get(post.key);
    if (other !== undefined) fail(post.file, `the key ${post.key} is taken by ${other} in the same language`);
    keys.set(post.key, rel(post.file));
  }
  return posts;
}

function byNewest(a: BlogPost, b: BlogPost): number {
  return b.date.localeCompare(a.date) || a.slug.localeCompare(b.slug);
}

/**
 * Every post the site shows, in every locale, newest first. Read once per
 * process in production; under `next dev` on every call, so a post being
 * written shows up without a restart.
 */
export function allPosts(): BlogPost[] {
  if (cache !== null && process.env.NODE_ENV !== 'development') return cache;
  const drafts = showDrafts();
  const posts = routing.locales
    .flatMap((locale) => readLocale(locale))
    .filter((post) => drafts || !post.draft)
    .sort(byNewest);
  cache = posts;
  return posts;
}

/** The posts written in `locale`, newest first. */
export function postsIn(locale: string): BlogPost[] {
  return allPosts().filter((post) => post.locale === locale);
}

/**
 * The posts that count for search engines, feeds and llms.txt: never a draft,
 * not even under `next dev`, where drafts are shown.
 */
export function publishedPosts(): BlogPost[] {
  return allPosts().filter((post) => !post.draft);
}

/** One post, at its own locale's address only; null everywhere else. */
export function findPost(locale: string, slug: string): BlogPost | null {
  return allPosts().find((post) => post.locale === locale && post.slug === slug) ?? null;
}

/* ------------------------------------------------------------------ paths */

export function postPath(post: Pick<BlogPost, 'slug'>): string {
  return `/blog/${post.slug}`;
}

export function postUrl(post: Pick<BlogPost, 'locale' | 'slug'>): string {
  return localeUrl(post.locale, postPath(post));
}

export function categoryPath(category: BlogCategory): string {
  return `/blog/category/${category}`;
}

export function authorPath(author: string): string {
  return `/blog/authors/${author}`;
}

export const FEED_PATH = '/blog/feed.xml';

/**
 * Locale to path of every version of `post`: itself and the posts in other
 * languages that share its key. Each keeps its own slug, so this is what
 * hreflang, the sitemap and the language switcher read.
 */
export function postVersions(post: BlogPost, posts: readonly BlogPost[] = allPosts()): Record<string, string> {
  const versions: Record<string, string> = {};
  for (const other of posts) {
    if (other.key === post.key) versions[other.locale] = postPath(other);
  }
  versions[post.locale] = postPath(post);
  return versions;
}

/**
 * For the language switcher in the header: each post of `locale` that has a
 * version in another language, by its path, with the paths of its versions.
 * A post with no version elsewhere is not listed; the switcher sends that
 * language to its blog index (src/site/blog-switch.ts).
 */
export function blogSwitchPairs(locale: string): Record<string, Record<string, string>> {
  const pairs: Record<string, Record<string, string>> = {};
  for (const post of postsIn(locale)) {
    const versions = postVersions(post);
    if (Object.keys(versions).length > 1) pairs[postPath(post)] = versions;
  }
  return pairs;
}

/**
 * Whether `/blog/<rest>` is a page in `locale`. The proxy asks before the
 * request reaches the router, for the reason it settles unknown docs slugs:
 * under `cacheComponents` a `notFound()` in the page lands after the 200.
 */
export function blogRouteExists(locale: string, rest: readonly string[]): boolean {
  if (rest.length === 0) return true;
  const [first, second, ...more] = rest;
  if (more.length > 0) return false;
  if (first === 'feed.xml') return second === undefined;
  if (first === 'category') return second !== undefined && (BLOG_CATEGORIES as readonly string[]).includes(second);
  if (first === 'authors') return second !== undefined && findAuthor(second) !== null;
  if (second !== undefined && second !== 'og-card') return false;
  return first !== undefined && findPost(locale, first) !== null;
}

/* --------------------------------------------------------------- indexing */

/**
 * Whether a locale's blog index is offered to search engines: English always,
 * any other language once it has a published post of its own. Until then its
 * index only lists English posts under a translated heading, which is a thin
 * copy of the English index; it renders with `noindex, follow` and stays out of
 * the sitemap and of the other indexes' hreflang.
 */
export function blogIndexed(locale: string): boolean {
  return locale === routing.defaultLocale || publishedPosts().some((post) => post.locale === locale);
}

/** The same rule for a category page: a published post of its own in that category. */
export function categoryIndexed(locale: string, category: BlogCategory): boolean {
  return publishedPosts().some((post) => post.locale === locale && post.category === category);
}

/** The same rule for an author page: a published post of their own in that language. */
export function authorIndexed(locale: string, author: string): boolean {
  return publishedPosts().some((post) => post.locale === locale && post.author === author);
}

export function indexedBlogLocales(): string[] {
  return routing.locales.filter((locale) => blogIndexed(locale));
}

export function indexedCategoryLocales(category: BlogCategory): string[] {
  return routing.locales.filter((locale) => categoryIndexed(locale, category));
}

export function indexedAuthorLocales(author: string): string[] {
  return routing.locales.filter((locale) => authorIndexed(locale, author));
}

/**
 * What a locale's index lists: its own posts, and outside English the English
 * posts after them, under their own heading. Never another translation's
 * posts: a reader of the Dutch index can be expected to read English, not
 * German.
 */
export function blogListing(locale: string, posts: readonly BlogPost[] = postsIn(locale)): {
  own: BlogPost[];
  english: BlogPost[];
} {
  const english = locale === routing.defaultLocale ? [] : postsIn(routing.defaultLocale);
  // An English post that has a version in this language is already listed.
  const keys = new Set(posts.map((post) => post.key));
  return { own: [...posts], english: english.filter((post) => !keys.has(post.key)) };
}

/** The files a post is made of, relative to web/, for the sitemap's lastmod. */
export function postFiles(post: BlogPost): string[] {
  if (post.dir === null) return [rel(post.file)];
  return readdirSync(/*turbopackIgnore: true*/ post.dir)
    .filter((name) => !name.startsWith('.'))
    .map((name) => rel(path.join(/*turbopackIgnore: true*/ post.dir!, name)));
}

/* ------------------------------------------------------------------ media */

/**
 * Pictures and GPX files are served by a route handler straight from the
 * post's folder (src/app/(site)/blog-media/), not copied into public/ at
 * build time. A copy would need a step before `next dev` and `next build`,
 * leave stale files behind when a post is renamed, and give no control over
 * caching; the handler reads the same traced `content/` the pages do.
 *
 * The URL carries a hash of the file, so it can be cached for a year: a
 * changed picture gets a new URL, and the old one stops answering.
 * `/blog-media/<locale>/<slug>/<hash>/<file>`.
 */
export const MEDIA_PREFIX = '/blog-media';

/**
 * Up to `limit` bytes of a binary file (all of it by default).
 *
 * Not `readFileSync`: Node reads a file as bytes in JavaScript and closes it
 * with `fs.closeSync`, and under `next dev` Tailwind's compiler has loaded
 * graceful-fs, which wraps `closeSync` with a call to `Date.now()`. Next
 * reports any clock read during a prerender as an error, so every page with a
 * picture logged one. (Text never meets this: Node reads UTF-8 natively, which
 * is why the docs never did.) graceful-fs keeps Node's own function under
 * `Symbol.for('graceful-fs.previous')`; wherever it is not loaded, as in
 * production, the plain one is used.
 */
function readBytes(file: string, limit = Infinity): Buffer {
  const patched = fs.closeSync as typeof fs.closeSync & { [key: symbol]: unknown };
  const previous = patched[Symbol.for('graceful-fs.previous')];
  const close = typeof previous === 'function' ? (previous as typeof fs.closeSync) : fs.closeSync;
  const fd = openSync(/*turbopackIgnore: true*/ file, 'r');
  try {
    const size = Math.min(fstatSync(fd).size, limit);
    const bytes = Buffer.alloc(size);
    let read = 0;
    while (read < size) {
      const n = readSync(fd, bytes, read, size - read, read);
      if (n === 0) break;
      read += n;
    }
    return bytes.subarray(0, read);
  } finally {
    close(fd);
  }
}

function fileHash(file: string): string {
  return createHash('sha256').update(readBytes(file)).digest('hex').slice(0, 12);
}

/** The URL path of a file beside `post`. */
export function mediaPath(post: BlogPost, name: string): string {
  if (post.dir === null) throw new Error(`${rel(post.file)}: has no folder for ${name}`);
  return `${MEDIA_PREFIX}/${post.locale}/${post.slug}/${fileHash(path.join(/*turbopackIgnore: true*/ post.dir, name))}/${name}`;
}

export interface MediaFile {
  body: Buffer;
  contentType: string;
}

/** A file the media route may serve, or null for anything else. */
export function readMedia(locale: string, slug: string, hash: string, name: string): MediaFile | null {
  if (!FILE_RE.test(name)) return null;
  const contentType = MEDIA_TYPES[path.extname(name).toLowerCase()];
  if (contentType === undefined) return null;
  const post = findPost(locale, slug);
  if (post?.dir == null) return null;
  const file = path.join(/*turbopackIgnore: true*/ post.dir, name);
  if (!existsSync(file) || fileHash(file) !== hash) return null;
  return { body: readBytes(file), contentType };
}

/** Every file the media route serves, for its static params. */
export function allMedia(): Array<{ locale: string; slug: string; hash: string; file: string }> {
  return allPosts().flatMap((post) => {
    if (post.dir === null) return [];
    const dir = post.dir;
    return readdirSync(/*turbopackIgnore: true*/ dir)
      .filter((name) => FILE_RE.test(name) && MEDIA_TYPES[path.extname(name).toLowerCase()] !== undefined)
      .map((name) => ({ locale: post.locale, slug: post.slug, hash: fileHash(path.join(/*turbopackIgnore: true*/ dir, name)), file: name }));
  });
}

/**
 * Width and height from a picture's header, so the page reserves the space
 * before the picture arrives and does not jump. PNG, GIF, JPEG and WebP;
 * null for anything else (AVIF), which then renders without the two.
 */
const HEADER_BYTES = 64 * 1024;

export function imageSize(file: string): { width: number; height: number } | null {
  // The header is enough; a 20 MB photo need not be read for its size.
  let bytes: Buffer;
  try {
    bytes = readBytes(file, HEADER_BYTES);
  } catch {
    return null;
  }
  // PNG: the IHDR chunk follows the 8-byte signature.
  if (bytes.length >= 24 && bytes.readUInt32BE(0) === 0x89504e47) {
    return { width: bytes.readUInt32BE(16), height: bytes.readUInt32BE(20) };
  }
  // GIF87a / GIF89a: logical screen size, little-endian.
  if (bytes.length >= 10 && bytes.toString('ascii', 0, 3) === 'GIF') {
    return { width: bytes.readUInt16LE(6), height: bytes.readUInt16LE(8) };
  }
  // JPEG: walk the segments to the first start-of-frame.
  if (bytes.length >= 4 && bytes[0] === 0xff && bytes[1] === 0xd8) {
    let offset = 2;
    while (offset + 9 < bytes.length) {
      if (bytes[offset] !== 0xff) return null;
      const marker = bytes[offset + 1]!;
      const length = bytes.readUInt16BE(offset + 2);
      const isFrame = marker >= 0xc0 && marker <= 0xcf && marker !== 0xc4 && marker !== 0xc8 && marker !== 0xcc;
      if (isFrame) return { height: bytes.readUInt16BE(offset + 5), width: bytes.readUInt16BE(offset + 7) };
      offset += 2 + length;
    }
    return null;
  }
  // WebP: lossy (VP8), lossless (VP8L) or extended (VP8X).
  if (bytes.length >= 30 && bytes.toString('ascii', 0, 4) === 'RIFF' && bytes.toString('ascii', 8, 12) === 'WEBP') {
    const chunk = bytes.toString('ascii', 12, 16);
    if (chunk === 'VP8 ') return { width: bytes.readUInt16LE(26) & 0x3fff, height: bytes.readUInt16LE(28) & 0x3fff };
    if (chunk === 'VP8L') {
      const bits = bytes.readUInt32LE(21);
      return { width: (bits & 0x3fff) + 1, height: ((bits >> 14) & 0x3fff) + 1 };
    }
    if (chunk === 'VP8X') return { width: bytes.readUIntLE(24, 3) + 1, height: bytes.readUIntLE(27, 3) + 1 };
  }
  return null;
}

/* -------------------------------------------------------------- rendering */

export interface RenderedPost {
  html: string;
  headings: Heading[];
  /** Whole minutes, at least one. */
  readingMinutes: number;
}

/** Words a reader gets through in a minute, for the reading time. */
const WORDS_PER_MINUTE = 220;

function isRelative(url: string): boolean {
  return !/^(?:[a-z][a-z0-9+.-]*:|\/|#|\?)/i.test(url);
}

/**
 * The post's pictures and file links, made to work on the site. A relative
 * `![…](photo.jpg)` is a file beside the post and is pointed at the media
 * route, with its size; every picture loads lazily; a picture without alt text
 * fails the build, as does one that is not beside the post (anything remote
 * is blocked by the CSP and would render as a broken picture).
 */
function postTransform(post: BlogPost): (tree: HastNode) => void {
  const local = (url: string): string | null => {
    const name = decodeURI(url.replace(/^\.\//, ''));
    if (!FILE_RE.test(name) || post.dir === null) return null;
    return existsSync(path.join(/*turbopackIgnore: true*/ post.dir, name)) ? name : null;
  };
  const visit = (node: HastNode): void => {
    if (node.type === 'element' && node.properties) {
      const props = node.properties;
      if (node.tagName === 'img') {
        const src = typeof props.src === 'string' ? props.src : '';
        const alt = typeof props.alt === 'string' ? props.alt.trim() : '';
        if (alt === '') fail(post.file, `the picture ${src || '(no source)'} has no alt text: write ![what it shows](${src})`);
        if (/^(?:[a-z][a-z0-9+.-]*:|\/\/)/i.test(src)) {
          fail(post.file, `the picture ${src} is not on this site; put the file beside the post`);
        }
        if (isRelative(src)) {
          const name = local(src);
          if (name === null || !IMAGE_EXTENSIONS.has(path.extname(name).toLowerCase())) {
            fail(post.file, `the picture ${src} is not beside the post (blog/${post.slug}/)`);
          }
          props.src = mediaPath(post, name);
          const size = imageSize(path.join(/*turbopackIgnore: true*/ post.dir!, name));
          if (size) {
            props.width = size.width;
            props.height = size.height;
          }
        }
        props.loading = 'lazy';
        props.decoding = 'async';
      } else if (node.tagName === 'a' && typeof props.href === 'string' && isRelative(props.href)) {
        // `[the GPX](ride.gpx)`: a link to a file beside the post.
        const name = local(props.href);
        if (name !== null && MEDIA_TYPES[path.extname(name).toLowerCase()] !== undefined) {
          props.href = mediaPath(post, name);
        }
      }
    }
    for (const child of node.children ?? []) visit(child);
  };
  return visit;
}

/** The post's HTML, through the docs' pipeline plus the pass above. */
export function renderPost(post: BlogPost): RenderedPost {
  const { html, headings } = renderBody(post.markdown, postTransform(post));
  const words = post.markdown
    .replace(/```[\s\S]*?```/g, ' ')
    .replace(/!\[[^\]]*\]\([^)]*\)/g, ' ')
    .split(/\s+/)
    .filter((word) => /\p{L}/u.test(word)).length;
  return { html, headings, readingMinutes: Math.max(1, Math.round(words / WORDS_PER_MINUTE)) };
}

/** The cover picture, if the post has one: its URL path, size and description. */
export function coverImage(post: BlogPost): { src: string; alt: string; width?: number; height?: number } | null {
  if (post.image === undefined || post.dir === null) return null;
  const size = imageSize(path.join(/*turbopackIgnore: true*/ post.dir, post.image));
  return { src: mediaPath(post, post.image), alt: post.imageAlt ?? '', ...(size ?? {}) };
}

/* ------------------------------------------------------------------- feed */

function xml(text: string): string {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

/** RFC 822, which RSS 2.0 asks for: midnight UTC of the post's day. */
function rfc822(date: string): string {
  return new Date(`${date}T00:00:00Z`).toUTCString();
}

export interface FeedStrings {
  title: string;
  description: string;
  /** Localised category names. */
  categories: Readonly<Record<BlogCategory, string>>;
}

/** The posts a locale's feed carries: its own, and outside English the English ones. Never a draft. */
export function feedPosts(locale: string): BlogPost[] {
  const published = publishedPosts();
  const own = published.filter((post) => post.locale === locale);
  // As on the index: an English post with a version in this language is
  // carried as that version only.
  const keys = new Set(own.map((post) => post.key));
  return published.filter(
    (post) =>
      post.locale === locale ||
      (locale !== routing.defaultLocale && post.locale === routing.defaultLocale && !keys.has(post.key)),
  );
}

/** A locale's RSS 2.0 feed, newest first. */
export function feedXml(locale: string, strings: FeedStrings): string {
  const posts = feedPosts(locale);
  const self = localeUrl(locale, FEED_PATH);
  const items = posts.map((post) => {
    const author = findAuthor(post.author);
    return [
      '    <item>',
      `      <title>${xml(post.title)}</title>`,
      `      <link>${xml(postUrl(post))}</link>`,
      `      <guid isPermaLink="true">${xml(postUrl(post))}</guid>`,
      `      <pubDate>${rfc822(post.date)}</pubDate>`,
      `      <description>${xml(post.description)}</description>`,
      `      <category>${xml(strings.categories[post.category])}</category>`,
      ...(author ? [`      <dc:creator>${xml(author.name)}</dc:creator>`] : []),
      // RSS has no per-item language; Dublin Core does, for the English
      // posts in another language's feed.
      `      <dc:language>${post.locale}</dc:language>`,
      '    </item>',
    ].join('\n');
  });
  const newest = posts[0];
  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom" xmlns:dc="http://purl.org/dc/elements/1.1/">',
    '  <channel>',
    `    <title>${xml(strings.title)}</title>`,
    `    <link>${xml(localeUrl(locale, '/blog'))}</link>`,
    `    <description>${xml(strings.description)}</description>`,
    `    <language>${locale}</language>`,
    `    <atom:link href="${xml(self)}" rel="self" type="application/rss+xml"/>`,
    ...(newest ? [`    <lastBuildDate>${rfc822(newest.updated ?? newest.date)}</lastBuildDate>`] : []),
    ...items,
    '  </channel>',
    '</rss>',
    '',
  ].join('\n');
}

/* ---------------------------------------------------------------- display */

/** A post's date as the reader's language writes it; the date is a day, not a moment, so UTC. */
export function formatPostDate(date: string, locale: string): string {
  return new Intl.DateTimeFormat(locale, { dateStyle: 'long', timeZone: 'UTC' }).format(new Date(`${date}T00:00:00Z`));
}
