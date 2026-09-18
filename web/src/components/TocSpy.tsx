'use client';
// SPDX-License-Identifier: AGPL-3.0-only
// The only script the docs menu needs. It renders nothing: the section list is
// static markup from the server and every entry is a real `<a href="#id">`, so
// the page works without this. What it adds on top is the three things markup
// cannot do - mark the section in view, scroll to a section smoothly instead of
// jumping, and close the mobile disclosure once a section has been chosen.
import { useEffect } from 'react';
import { activeHeadingId, type HeadingTop } from '@/site/toc';

/** How far the menu keeps the marked entry from its own top and bottom edge. */
const REVEAL_PADDING = 16;

/**
 * Where a heading has to land: its own `scroll-margin-top`, which globals.css
 * keeps equal to the sticky header plus a little. Reading it back means the
 * offset is written once, in CSS, and the two breakpoints stay in step here.
 */
function scrollOffset(heading: Element): number {
  const margin = Number.parseFloat(getComputedStyle(heading).scrollMarginTop);
  return Number.isFinite(margin) ? margin : 0;
}

/** Bring `link` into view inside the menu's own scroller, not the page's. */
function reveal(link: HTMLElement) {
  const scroller = link.closest('[data-toc-scroll]');
  if (!(scroller instanceof HTMLElement) || scroller.scrollHeight <= scroller.clientHeight) return;
  const box = scroller.getBoundingClientRect();
  const rect = link.getBoundingClientRect();
  if (rect.top < box.top + REVEAL_PADDING) scroller.scrollTop -= box.top + REVEAL_PADDING - rect.top;
  else if (rect.bottom > box.bottom - REVEAL_PADDING) scroller.scrollTop += rect.bottom - box.bottom + REVEAL_PADDING;
}

/**
 * @param ids every h2 and h3 of the article, in document order.
 */
export function TocSpy({ ids }: { ids: string[] }) {
  // The array is rebuilt on every render; the joined string is what the effect
  // actually depends on, so a re-render with the same page does not re-attach.
  const key = ids.join(' ');

  useEffect(() => {
    const headings = key
      .split(' ')
      .map((id) => document.getElementById(id))
      .filter((element): element is HTMLElement => element !== null);
    if (headings.length === 0) return;

    const links = Array.from(document.querySelectorAll<HTMLAnchorElement>('a[data-toc-id]'));
    // Below `lg` the menu is collapsed, so the summary carries the section as
    // well - it is the only line of the menu on screen while reading.
    const summaries = Array.from(document.querySelectorAll<HTMLElement>('[data-toc-summary-section]'));
    let current: string | null = null;

    function mark(id: string | null) {
      if (id === current) return;
      current = id;
      let marked: HTMLAnchorElement | null = null;
      for (const link of links) {
        if (link.dataset.tocId === id) {
          link.setAttribute('aria-current', 'location');
          link.dataset.active = 'true';
          if (!marked) marked = link;
        } else {
          link.removeAttribute('aria-current');
          delete link.dataset.active;
        }
      }
      const text = marked?.textContent?.trim() ?? '';
      for (const summary of summaries) {
        summary.textContent = text === '' ? '' : ` · ${text}`;
        summary.hidden = text === '';
      }
      // Both copies of the list are in the DOM; only the one on screen has a
      // scroller, and `reveal` leaves the other alone.
      for (const link of links) if (link.dataset.tocId === id) reveal(link);
    }

    function update() {
      const tops: HeadingTop[] = headings.map((heading) => ({
        id: heading.id,
        top: heading.getBoundingClientRect().top + window.scrollY,
      }));
      mark(
        activeHeadingId(tops, {
          scrollY: window.scrollY,
          viewportHeight: window.innerHeight,
          documentHeight: document.documentElement.scrollHeight,
        }),
      );
    }

    let frame = 0;
    function schedule() {
      if (frame !== 0) return;
      frame = requestAnimationFrame(() => {
        frame = 0;
        update();
      });
    }

    // The observer is what drives this while reading: a heading crossing the
    // top third is the only event that can change the answer. The scroll
    // listener is the backstop for a jump that crosses no boundary at all -
    // `scrollTo` from one long section into another fires no intersection.
    const observer = new IntersectionObserver(schedule, { rootMargin: '0px 0px -66% 0px', threshold: 0 });
    for (const heading of headings) observer.observe(heading);
    window.addEventListener('scroll', schedule, { passive: true });
    window.addEventListener('resize', schedule, { passive: true });

    function onClick(event: MouseEvent) {
      // Anything but a plain left click belongs to the browser: a new tab, a
      // new window, a saved link.
      if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) {
        return;
      }
      const target = event.target;
      const link = target instanceof Element ? target.closest<HTMLAnchorElement>('a[data-toc-id]') : null;
      if (!link) return;
      const id = link.dataset.tocId;
      if (!id) return;
      const heading = document.getElementById(id);
      if (!heading) return;
      event.preventDefault();

      // Closing the disclosure first: it is above the article on mobile, so
      // the heading's position is only final once the menu is out of the flow.
      link.closest('details[open]')?.removeAttribute('open');

      const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
      const top = heading.getBoundingClientRect().top + window.scrollY - scrollOffset(heading);
      window.scrollTo({ top: Math.max(0, top), behavior: reduced ? 'instant' : 'smooth' });
      // The reader asked for this section; the address bar says so, and the
      // Back button is left alone.
      history.replaceState(null, '', `#${id}`);
      // A heading is not focusable by itself, so a keyboard reader would carry
      // on from the menu; this puts them at the text they jumped to.
      heading.setAttribute('tabindex', '-1');
      heading.focus({ preventScroll: true });
      mark(id);
    }

    document.addEventListener('click', onClick);
    update();

    return () => {
      observer.disconnect();
      window.removeEventListener('scroll', schedule);
      window.removeEventListener('resize', schedule);
      document.removeEventListener('click', onClick);
      if (frame !== 0) cancelAnimationFrame(frame);
    };
  }, [key]);

  return null;
}
