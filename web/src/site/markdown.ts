// SPDX-License-Identifier: AGPL-3.0-only
// The Markdown pipeline for content/: docs pages and the legal texts.
//
// Everything here is synchronous on purpose. With `cacheComponents: true` an
// awaited, uncached data source turns the page dynamic; `processSync` keeps
// every content page a plain static render. All plugins in the chain are
// synchronous, which is what `processSync` requires.
import matter from 'gray-matter';
import rehypeAutolinkHeadings, { type Options as AutolinkOptions } from 'rehype-autolink-headings';
import rehypeSanitize, { defaultSchema, type Options as SanitizeOptions } from 'rehype-sanitize';
import rehypeSlug from 'rehype-slug';
import rehypeStringify from 'rehype-stringify';
import remarkGfm from 'remark-gfm';
import remarkParse from 'remark-parse';
import remarkRehype from 'remark-rehype';
import { unified } from 'unified';

/**
 * The label the heading anchor carries for a screen reader. The visible glyph
 * is a '#', which says nothing out loud, and the link is a real tab stop: it
 * is how a keyboard user reaches a section's permalink at all, which is why it
 * carries neither `aria-hidden` nor `tabindex=-1`.
 */
const ANCHOR_LABEL = 'Link to this section';

// A '#' appended inside the heading, revealed on hover and on focus.
const autolinkOptions: AutolinkOptions = {
  behavior: 'append',
  properties: { className: ['anchor'], ariaLabel: ANCHOR_LABEL },
  content: { type: 'element', tagName: 'span', properties: {}, children: [{ type: 'text', value: '#' }] },
};

/**
 * GitHub's own allowlist, with two changes.
 *
 * `content/` is translated on Crowdin, so every non-English page is written
 * outside this repository and merged by a bot: it is not our HTML any more.
 * The schema drops anything the pipeline did not produce - a `javascript:`
 * href above all, which the production CSP would otherwise allow.
 *
 * The heading ids come from `rehype-slug` and the anchor class from the plugin
 * above, i.e. from us, so both are kept: clobbering would rewrite every id to
 * `user-content-<id>` and leave the anchors, the in-page links and the
 * breadcrumbs pointing at nothing.
 */
const sanitizeSchema: SanitizeOptions = {
  ...defaultSchema,
  attributes: {
    ...defaultSchema.attributes,
    // One entry per property: the default already constrains `className` on a
    // link (to GFM's footnote class), and a second entry for the same property
    // would be ignored rather than merged.
    a: [
      ...(defaultSchema.attributes?.a ?? []).filter(
        (attribute) => !(Array.isArray(attribute) && attribute[0] === 'className'),
      ),
      ['className', 'data-footnote-backref', 'anchor'],
    ],
  },
  clobber: [],
};

const processor = unified()
  .use(remarkParse)
  .use(remarkGfm)
  .use(remarkRehype)
  .use(rehypeSlug)
  .use(rehypeAutolinkHeadings, autolinkOptions)
  .use(rehypeSanitize, sanitizeSchema)
  .use(rehypeStringify)
  .freeze();

/** The front matter every content file carries. */
export interface FrontMatter {
  title: string;
  description: string;
  /** Sidebar position; docs only. Files without one sort last, then by slug. */
  order: number;
  /**
   * An unreviewed text. It still renders, with a banner and `noindex`, but it
   * is left out of the sitemap, of llms.txt and of llms-full.txt.
   */
  draft: boolean;
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

function bool(value: unknown): boolean {
  return value === true;
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
      // The sanitiser rebuilds the attributes, so the anchor is matched by its
      // class wherever that ends up in the tag.
      .replace(/<a\b[^>]*class="anchor"[^>]*>[\s\S]*?<\/a>/g, '')
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
      draft: bool(data.draft),
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
    draft: bool(data.draft),
  };
}
