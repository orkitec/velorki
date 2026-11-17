// SPDX-License-Identifier: AGPL-3.0-only
import type { TocSection } from '@/site/toc';

/**
 * A post's sections, the left column of a post from `lg`: sticky under the
 * header like the docs menu, with the same entries TocSpy marks. Below `lg`
 * it is not rendered at all; a post is read top to bottom, and a disclosure
 * above it would only push the title down.
 */
export function PostToc({ label, sections }: { label: string; sections: TocSection[] }) {
  if (sections.length === 0) return null;
  return (
    <nav aria-label={label} className="hidden lg:block">
      <div data-toc-scroll className="sticky top-24 max-h-[calc(100vh-7rem)] overflow-y-auto pb-8">
        <h2 className="overline mb-3">{label}</h2>
        <ul className="space-y-0.5 border-l border-line">
          {sections.map((section) => (
            <li key={section.id}>
              <a href={`#${section.id}`} data-toc-id={section.id} className="toc-link pl-4">
                {section.text}
              </a>
              {section.children.length > 0 && (
                <ul className="space-y-0.5">
                  {section.children.map((child) => (
                    <li key={child.id}>
                      <a href={`#${child.id}`} data-toc-id={child.id} className="toc-link pl-8">
                        {child.text}
                      </a>
                    </li>
                  ))}
                </ul>
              )}
            </li>
          ))}
        </ul>
      </div>
    </nav>
  );
}
