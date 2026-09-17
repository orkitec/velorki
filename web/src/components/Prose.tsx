// SPDX-License-Identifier: AGPL-3.0-only
/**
 * Rendered Markdown. The HTML comes from content/ in the repository, which is
 * ours and reviewed, and the pipeline in src/site/markdown.ts produces it — no
 * user input reaches this.
 */
export function Prose({ html, className }: { html: string; className?: string }) {
  return <div className={className ? `prose ${className}` : 'prose'} dangerouslySetInnerHTML={{ __html: html }} />;
}
