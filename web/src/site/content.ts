// SPDX-License-Identifier: AGPL-3.0-only
// Reads content/<locale>/{docs,legal}/*.md from disk.
//
// English is the source: the set of pages and their order come from
// content/en, and a locale that has no file for a page falls back to the
// English text with a notice. Reads are synchronous (see markdown.ts).
//
// The paths are built at runtime, so Turbopack cannot see which files are
// read and would trace the whole project into the server bundle. They are
// marked `turbopackIgnore` instead: `next.config.ts` already traces
// `./content/**/*` into the standalone output by hand.
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import path from 'node:path';
import { routing } from '@/i18n/routing';
import { type FrontMatter, type RenderedMarkdown, readFrontMatter, renderMarkdown } from './markdown';

const CONTENT_DIR = path.join(process.cwd(), 'content');
const SOURCE_LOCALE = routing.defaultLocale;

/** The three legal documents, in footer order. */
export const LEGAL_DOCS = ['privacy', 'terms', 'imprint'] as const;
export type LegalDoc = (typeof LEGAL_DOCS)[number];

export interface DocEntry extends FrontMatter {
  slug: string;
}

export interface LoadedPage extends RenderedMarkdown {
  slug: string;
  /** False when the locale has no file of its own and English is shown. */
  translated: boolean;
}

function titleFromSlug(slug: string): string {
  return slug
    .split('-')
    .map((word) => (word ? word[0]!.toUpperCase() + word.slice(1) : word))
    .join(' ');
}

function filePath(locale: string, kind: 'docs' | 'legal', slug: string): string {
  return path.join(CONTENT_DIR, locale, kind, `${slug}.md`);
}

/** What a slug or locale segment may look like: one path segment, nothing else. */
const SEGMENT_RE = /^[a-z0-9][a-z0-9-]*$/;

/** The file for `slug` in `locale`, or the English one, or null. */
function resolveFile(locale: string, kind: 'docs' | 'legal', slug: string): { file: string; translated: boolean } | null {
  // The slug comes from the URL. Only a plain segment may become a file name;
  // anything else (`..`, a slash, an encoded path) is simply not a page.
  if (!SEGMENT_RE.test(slug) || !SEGMENT_RE.test(locale)) return null;
  const own = filePath(locale, kind, slug);
  if (existsSync(own)) return { file: own, translated: true };
  const source = filePath(SOURCE_LOCALE, kind, slug);
  if (existsSync(source)) return { file: source, translated: false };
  return null;
}

/** Every docs slug, from the English source directory, in sidebar order. */
export function docSlugs(): string[] {
  return listDocs(SOURCE_LOCALE).map((doc) => doc.slug);
}

/**
 * The docs sidebar for `locale`: the English page set, with each entry's title
 * and description taken from the locale's file when it has one.
 */
export function listDocs(locale: string): DocEntry[] {
  const dir = path.join(CONTENT_DIR, SOURCE_LOCALE, 'docs');
  if (!existsSync(dir)) return [];
  const slugs = readdirSync(dir)
    .filter((name) => name.endsWith('.md'))
    .map((name) => name.slice(0, -3))
    .filter((slug) => slug !== 'index');
  const entries: DocEntry[] = [];
  for (const slug of slugs) {
    const resolved = resolveFile(locale, 'docs', slug);
    if (!resolved) continue;
    const front = readFrontMatter(readFileSync(/*turbopackIgnore: true*/ resolved.file, 'utf8'), titleFromSlug(slug));
    entries.push({ slug, ...front });
  }
  entries.sort((a, b) => a.order - b.order || a.slug.localeCompare(b.slug));
  return entries;
}

/** One docs page, or null when the slug does not exist in any locale. */
export function loadDoc(locale: string, slug: string): LoadedPage | null {
  const resolved = resolveFile(locale, 'docs', slug);
  if (!resolved) return null;
  const rendered = renderMarkdown(readFileSync(/*turbopackIgnore: true*/ resolved.file, 'utf8'), titleFromSlug(slug));
  return { slug, translated: resolved.translated, ...rendered };
}

/** The optional intro Markdown shown above the docs index. */
export function loadDocsIndex(locale: string): LoadedPage | null {
  const resolved = resolveFile(locale, 'docs', 'index');
  if (!resolved) return null;
  const rendered = renderMarkdown(readFileSync(/*turbopackIgnore: true*/ resolved.file, 'utf8'), 'Documentation');
  return { slug: 'index', translated: resolved.translated, ...rendered };
}

/** One legal document, or null when it has not been written yet. */
export function loadLegal(locale: string, doc: LegalDoc): LoadedPage | null {
  const resolved = resolveFile(locale, 'legal', doc);
  if (!resolved) return null;
  const rendered = renderMarkdown(readFileSync(/*turbopackIgnore: true*/ resolved.file, 'utf8'), titleFromSlug(doc));
  return { slug: doc, translated: resolved.translated, ...rendered };
}

/**
 * Front matter of the English source of one legal document, or null when the
 * document has not been written yet. The sitemap and llms.txt read it to leave
 * a `draft: true` text out of both.
 */
export function legalFrontMatter(doc: LegalDoc): FrontMatter | null {
  const resolved = resolveFile(SOURCE_LOCALE, 'legal', doc);
  if (!resolved) return null;
  return readFrontMatter(readFileSync(/*turbopackIgnore: true*/ resolved.file, 'utf8'), titleFromSlug(doc));
}

/** The legal documents that are written and reviewed, in footer order. */
export function publishedLegalDocs(): LegalDoc[] {
  return LEGAL_DOCS.filter((doc) => legalFrontMatter(doc)?.draft === false);
}
