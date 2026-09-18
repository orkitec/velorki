// SPDX-License-Identifier: AGPL-3.0-only
// The in-page section list: the h2/h3 headings of the open docs page, shown
// under its entry in the docs menu.
//
// Everything here is pure and free of DOM and of Node, because both halves of
// the feature share it: the server builds the static list from `Heading[]`,
// and the client component that marks the section in view (TocSpy) decides
// which id that is with `activeHeadingId`.
import type { Heading } from './markdown';

/** One h2 with the h3s that follow it, i.e. one entry of the section list. */
export interface TocSection {
  id: string;
  text: string;
  /** The h3s below this h2, in document order. */
  children: { id: string; text: string }[];
}

/**
 * Fewer headings than this and the list is not rendered at all: a page with a
 * single section has nothing to navigate, and an entry that always jumps to
 * the text already on screen is noise.
 */
export const TOC_MIN_HEADINGS = 2;

/**
 * The section list for one page, or an empty list when the page has too few
 * headings to be worth one. An h3 before the first h2 stands on its own rather
 * than being dropped - the spy tracks every heading, so every heading is
 * reachable from the list.
 */
export function docToc(headings: readonly Heading[]): TocSection[] {
  if (headings.length < TOC_MIN_HEADINGS) return [];
  const sections: TocSection[] = [];
  for (const heading of headings) {
    const last = sections[sections.length - 1];
    if (heading.depth === 3 && last) last.children.push({ id: heading.id, text: heading.text });
    else sections.push({ id: heading.id, text: heading.text, children: [] });
  }
  return sections;
}

/** A heading's id and its distance from the top of the document. */
export interface HeadingTop {
  id: string;
  top: number;
}

/** Where the reader is, in the units `HeadingTop.top` is measured in. */
export interface ViewPort {
  scrollY: number;
  viewportHeight: number;
  /** The scrollable height of the document; omitted, the bottom rule is off. */
  documentHeight?: number;
}

/**
 * The heading the reader is in: the last one above the viewport's top third.
 *
 * The top third rather than the very top, because a heading sitting just under
 * the sticky header is what a reader calls "here"; with the line at the top
 * edge the marker would jump to the next section while its heading is still
 * being read.
 *
 * Two edges: above the first heading nothing is marked (the reader is in the
 * page's intro, not in a section), and at the very bottom the last heading is,
 * because a final section shorter than two thirds of the viewport can never
 * reach the line on its own.
 */
export function activeHeadingId(headings: readonly HeadingTop[], view: ViewPort): string | null {
  if (headings.length === 0) return null;
  const { scrollY, viewportHeight, documentHeight } = view;
  if (documentHeight !== undefined && scrollY + viewportHeight >= documentHeight - 1) {
    return headings[headings.length - 1]!.id;
  }
  const line = scrollY + viewportHeight / 3;
  let active: string | null = null;
  for (const heading of headings) {
    if (heading.top > line) break;
    active = heading.id;
  }
  return active;
}
