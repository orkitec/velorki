// SPDX-License-Identifier: AGPL-3.0-only
// The Markdown pipeline for content/: docs pages and the legal texts.
//
// Everything here is synchronous on purpose. With `cacheComponents: true` an
// awaited, uncached data source turns the page dynamic; `processSync` keeps
// every content page a plain static render. All plugins in the chain are
// synchronous, which is what `processSync` requires.
import matter from 'gray-matter';
import rehypeAutolinkHeadings, { type Options as AutolinkOptions } from 'rehype-autolink-headings';
import rehypeSlug from 'rehype-slug';
import rehypeStringify from 'rehype-stringify';
import remarkGfm from 'remark-gfm';
import remarkParse from 'remark-parse';
import remarkRehype from 'remark-rehype';
import { unified } from 'unified';

// A '#' appended inside the heading, revealed on hover and on focus.
const autolinkOptions: AutolinkOptions = {
  behavior: 'append',
  properties: { className: ['anchor'], ariaHidden: 'true', tabIndex: -1 },
  content: { type: 'element', tagName: 'span', properties: {}, children: [{ type: 'text', value: '#' }] },
};

const processor = unified()
  .use(remarkParse)
  .use(remarkGfm)
  .use(remarkRehype)
  .use(rehypeSlug)
  .use(rehypeAutolinkHeadings, autolinkOptions)
  .use(rehypeStringify)
  .freeze();

/** The front matter every content file carries. */
export interface FrontMatter {
  title: string;
  description: string;
  /** Sidebar position; docs only. Files without one sort last, then by slug. */
  order: number;
}

/** One heading of a rendered page, for breadcrumbs and in-page navigation. */
export interface Heading {
  depth: 2 | 3;
  id: string;
  text: string;
}

export interface RenderedMarkdown {
  frontMatter: FrontMatter;
  html: string;
  headings: Heading[];
  /** The body without front matter, for llms-full.txt. */
  markdown: string;
}

function str(value: unknown, fallback: string): string {
  return typeof value === 'string' && value.trim() !== '' ? value.trim() : fallback;
}

function num(value: unknown, fallback: number): number {
  return typeof value === 'number' && Number.isFinite(value) ? value : fallback;
}

/**
 * Headings straight out of the produced HTML, so the ids are exactly the ones
 * `rehype-slug` minted; re-slugging the Markdown would be a second guess.
 */
function collectHeadings(html: string): Heading[] {
  const headings: Heading[] = [];
  const pattern = /<h([23]) id="([^"]+)"[^>]*>([\s\S]*?)<\/h\1>/g;
  let match: RegExpExecArray | null;
  while ((match = pattern.exec(html)) !== null) {
    const depth = match[1] === '3' ? 3 : 2;
    const text = (match[3] ?? '')
      .replace(/<a class="anchor"[\s\S]*?<\/a>/g, '')
      .replace(/<[^>]*>/g, '')
      .replace(/\s+/g, ' ')
      .trim();
    if (text) headings.push({ depth, id: match[2] ?? '', text });
  }
  return headings;
}

/**
 * Renders one content file. A leading `# Heading` is dropped: the page renders
 * the front-matter title as its single `h1`, and two would be one too many.
 */
export function renderMarkdown(source: string, fallbackTitle: string): RenderedMarkdown {
  const parsed = matter(source);
  const data = parsed.data as Record<string, unknown>;
  const body = parsed.content.replace(/^\s*#\s+.*\r?\n+/, '');
  const html = String(processor.processSync(body));
  return {
    frontMatter: {
      title: str(data.title, fallbackTitle),
      description: str(data.description, ''),
      order: num(data.order, 1000),
    },
    html,
    headings: collectHeadings(html),
    markdown: body.trim(),
  };
}

/** Front matter only, for sidebars and listings. */
export function readFrontMatter(source: string, fallbackTitle: string): FrontMatter {
  const data = matter(source).data as Record<string, unknown>;
  return {
    title: str(data.title, fallbackTitle),
    description: str(data.description, ''),
    order: num(data.order, 1000),
  };
}
