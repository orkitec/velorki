# Site content

The Markdown behind `/docs` and the legal pages. One directory per locale; the
site reads them at build time through `gray-matter` plus the remark/rehype
pipeline in `web/src/site`.

## Layout

```
content/
  README.md              this file, not a page
  en/                    the source locale, the only one edited by hand
    docs/*.md            the end-user guide, one file per topic
    legal/
      privacy.md         served at /privacy
      terms.md           served at /terms
      imprint.md         served at /imprint
  de/                    after the first Crowdin sync, written by Crowdin
    docs/*.md
    legal/*.md
```

The URL slug is the file name without `.md`: `content/en/docs/loops.md` is
`/docs/loops`, and `/de/docs/loops` in German. File names are stable identifiers:
renaming one breaks every inbound link and orphans its translations in
Crowdin, so rename only deliberately and add a redirect.

## Front matter

Every file starts with a YAML block.

| Field | Where | Required | What it is |
|---|---|---|---|
| `title` | all | yes | the page's h1 and its entry in the sidebar |
| `description` | all | yes | one sentence, 160 characters or fewer, used as the meta description and the search snippet |
| `order` | `docs/` | yes | integer, the position in the sidebar; the guide runs 1 to 16 |
| `draft` | any | no | `true` keeps the page out of production builds and out of the sitemap |

```markdown
---
title: Offline maps and routing
description: Download the map you look at and the routing data your routes are computed from, so planning keeps working with no signal.
order: 5
---
```

A `description` containing a colon must be quoted, or the YAML will not parse.

## House style

- GitHub-flavoured Markdown. Tables, task lists and fenced code all work.
- The `title` is the h1, so the body starts at `##`. Never write an h1.
- Open every page with a two-sentence summary: what the feature is, and when a
  rider would use it. Search engines and assistants quote that paragraph, so it
  has to stand on its own.
- Short paragraphs, numbered lists for procedures, tables for anything with
  more than three parallel cases.
- Use the app's own words for anything the reader has to tap, in bold:
  **Search online for "…"**, **Download the visible area**. They come from
  `app/lib/l10n/app_en.arb`; if a string is not in there, the app does not say
  it.
- Plain and friendly. No marketing, no exclamation marks, no em dashes.
- Do not describe features that do not exist. When in doubt, grep the ARB.
- End each page with a `## Related` list linking sibling pages by relative
  slug: `- [Search](./search)`. Legal pages link each other the same way;
  `/privacy` and `/terms` are absolute because they are not under `/docs`.

## Locales and fallback

`content/en` is the source of truth. Every other locale is produced by Crowdin
from it (`crowdin.yml` at the repository root maps
`web/content/en/**/*.md` to `web/content/<locale>/…`), and a translated file
must never be edited in the repository: the next download overwrites it.

At render time the site looks for `content/<locale>/<section>/<slug>.md` and
falls back to `content/en/<section>/<slug>.md` when it is missing. A page shown
from the fallback carries a notice saying it has not been translated yet, so a
half-translated locale is usable rather than broken. The locale list itself
comes from `messages/*.json` through `src/i18n/locales.generated.ts`, so a
locale exists as soon as its UI catalogue does, with or without content.

The front matter is translated along with the body, so `title` and
`description` arrive localised; `order` and `draft` are copied through and must
stay identical to the English file.

## Adding a page

1. Create `content/en/docs/<slug>.md`. Pick a slug that reads as a URL:
   lower case, hyphens, no numbers.
2. Write the front matter. Give it an `order` and renumber the siblings if it
   goes in the middle. The numbers only have to be increasing, not contiguous,
   so leaving gaps is fine.
3. Write the page, starting at `##`, and finish with the `## Related` list.
4. Add a link to it from the `## Related` list of at least two related pages.
   The sidebar is generated from `order`, but the cross-links are what a reader
   arriving from a search engine follows.
5. Commit only the English file. Crowdin picks it up on the next upload and the
   other locales appear through the weekly translation PR.

Deleting a page is the same in reverse: remove the English file, remove the
links to it, and add a redirect if the URL was ever published.
