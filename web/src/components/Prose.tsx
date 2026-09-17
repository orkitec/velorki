// SPDX-License-Identifier: AGPL-3.0-only
/**
 * Rendered Markdown. The HTML is produced by the pipeline in
 * src/site/markdown.ts, which sanitises it: content/ is translated on Crowdin,
 * so every non-English page is written outside this repository and merged by a
 * bot, and only the tags, attributes and URL schemes the allowlist permits
 * reach this.
 */
export function Prose({ html, className }: { html: string; className?: string }) {
  return <div className={className ? `prose ${className}` : 'prose'} dangerouslySetInnerHTML={{ __html: html }} />;
}
