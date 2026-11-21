// SPDX-License-Identifier: AGPL-3.0-only
// The Markdown pipeline for content/: docs pages and the legal texts.
//
// Everything here is synchronous on purpose. With `cacheComponents: true` an
// awaited, uncached data source turns the page dynamic; `processSync` keeps
// every content page a plain static render. All plugins in the chain are
// synchronous, which is what `processSync` requires.
import dart from 'highlight.js/lib/languages/dart';
import matter from 'gray-matter';
import { common } from 'lowlight';
import rehypeHighlight from 'rehype-highlight';
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

/**
 * The blog's images carry `loading` and `decoding`, which the pass in blog.ts
 * sets on every one. Only the blog's pipeline allows them; the docs schema is
 * left as it was.
 */
const blogSanitizeSchema: SanitizeOptions = {
  ...sanitizeSchema,
  attributes: {
    ...sanitizeSchema.attributes,
    img: [...(sanitizeSchema.attributes?.img ?? []), 'loading', 'decoding'],
    // The highlighter's token classes, and nothing else on a span.
    span: [...(sanitizeSchema.attributes?.span ?? []), ['className', /^hljs-[a-z_-]+$/]],
  },
};

/**
 * Syntax colours for a post's fenced code, when the fence names its language
 * (```dart); a fence without one is left as plain text, never guessed at.
 * highlight.js rather than a grammar engine: it is synchronous, which
 * `processSync` needs, and plain JavaScript (`npm run check:deps`). Dart is
 * not in its common set, so it is added by hand. The colours are the
 * `.hljs-*` rules in globals.css.
 */
const highlightOptions = { detect: false, languages: { ...common, dart } };

/** A hast node, as far as a pass over the rendered tree needs one. */
export interface HastNode {
  type: string;
  tagName?: string;
  properties?: Record<string, unknown>;
  children?: HastNode[];
}

/**
 * A pass over the HTML tree before it is sanitised: the blog rewrites its
 * image and file links there, and refuses an image without alt text.
 */
export type HastTransform = (tree: HastNode) => void;

function buildProcessor(transform?: HastTransform) {
  const base = unified()
    .use(remarkParse)
    .use(remarkGfm)
    .use(remarkRehype)
    .use(rehypeSlug)
    .use(rehypeAutolinkHeadings, autolinkOptions);
  // The transform runs before the sanitiser, so whatever it writes is held to
  // the same allowlist as the author's own Markdown.
  const withTransform = transform
    ? base.use(rehypeHighlight, highlightOptions).use(() => (tree) => transform(tree))
    : base;
  return withTransform
    .use(rehypeSanitize, transform ? blogSanitizeSchema : sanitizeSchema)
    .use(() => (tree, file) => {
      file.data.headings = collectHeadings(tree);
    })
    .use(rehypeStringify)
    .freeze();
}

/** Renders `body`; the headings come off the tree the HTML was written from. */
function render(processor: ReturnType<typeof buildProcessor>, body: string): { html: string; headings: Heading[] } {
  const file = processor.processSync(body);
  return { html: String(file), headings: (file.data.headings as Heading[] | undefined) ?? [] };
}

const processor = buildProcessor();

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

/** The text a reader sees in `node`, without the '#' anchor the pipeline appends. */
function textOf(node: HastNode): string {
  if (node.type === 'text') return (node as HastNode & { value?: string }).value ?? '';
  const className = node.properties?.className;
  if (node.tagName === 'a' && Array.isArray(className) && className.includes('anchor')) return '';
  return (node.children ?? []).map(textOf).join('');
}

/**
 * The h2 and h3 headings of the sanitised tree, so the ids are exactly the
 * ones `rehype-slug` minted (re-slugging the Markdown would be a second guess)
 * and the text is the decoded text, never HTML.
 */
function collectHeadings(tree: HastNode): Heading[] {
  const headings: Heading[] = [];
  const visit = (node: HastNode) => {
    if (node.type === 'element' && (node.tagName === 'h2' || node.tagName === 'h3')) {
      const id = node.properties?.id;
      const text = textOf(node).replace(/\s+/g, ' ').trim();
      if (typeof id === 'string' && id !== '' && text) {
        headings.push({ depth: node.tagName === 'h3' ? 3 : 2, id, text });
      }
      return;
    }
    node.children?.forEach(visit);
  };
  visit(tree);
  return headings;
}

/**
 * Renders one content file. A leading `# Heading` is dropped: the page renders
 * the front-matter title as its single `h1`, and two would be one too many.
 */
export function renderMarkdown(source: string, fallbackTitle: string): RenderedMarkdown {
  const parsed = matter(source);
  const data = parsed.data as Record<string, unknown>;
  const body = stripLeadingH1(parsed.content);
  const { html, headings } = render(processor, body);
  return {
    frontMatter: {
      title: str(data.title, fallbackTitle),
      description: str(data.description, ''),
      order: num(data.order, 1000),
      draft: bool(data.draft),
    },
    html,
    headings,
    markdown: body.trim(),
  };
}

/** The body without a leading `# Heading`: the page renders its own h1. */
export function stripLeadingH1(body: string): string {
  return body.replace(/^\s*#\s+.*\r?\n+/, '');
}

/**
 * The HTML and headings of a Markdown body that has no front matter left,
 * through the same pipeline as the docs, with `transform` run over the tree
 * before the sanitiser. The blog's entry point (src/site/blog.ts).
 */
export function renderBody(body: string, transform: HastTransform): { html: string; headings: Heading[] } {
  return render(buildProcessor(transform), body);
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
