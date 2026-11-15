# Site content

The Markdown behind `/docs`, the legal pages and the blog. One directory per
locale; the site reads them at build time through `gray-matter` plus the
remark/rehype pipeline in `web/src/site`.

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
    blog/                not translated; see Blog below
  de/                    after the first Crowdin sync, written by Crowdin
    docs/*.md
    legal/*.md
    blog/                German posts, written by hand
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
| `order` | `docs/` | yes | integer, the position in the sidebar; the guide runs 1 to 17 |
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

## Blog

Posts are the one part of `content/` that is not translated. Each post is
written in one language and exists only there: an English post is at
`/blog/<slug>` and nowhere else, `/de/blog/<slug>` is a 404. Crowdin ignores
`content/en/blog/` and `npm run locales -- --check` does not ask for copies.
A version in another language is a post of its own, with its own slug, written
by hand and paired with the original through the same `key`; the pair get
hreflang links to each other and the language switcher moves between them.
The other languages' blog indexes list the English posts after their own,
under "In English".

```
content/en/blog/
  porting-brouter-to-dart.md       a post on its own
  ride-madeira/                    a post with files beside it
    index.md
    cover.jpg                      named by `image:`
    coast.jpg                      ![The coast road above Funchal](coast.jpg)
    ride.gpx                       named by `gpx:`
content/de/blog/
  brouter-nach-dart.md             key: porting-brouter-to-dart
```

The slug is the file or folder name: lower case letters, digits and hyphens,
not `category` or `authors`.

| Field | Required | What it is |
|---|---|---|
| `title` | yes | the h1 and the feed title |
| `description` | yes | one sentence, 160 characters or fewer; quote it if it contains a colon |
| `date` | yes | `YYYY-MM-DD`, the day it was published |
| `updated` | no | `YYYY-MM-DD`, only when the content changed |
| `author` | yes | an id from `src/site/authors.ts` (`steffen`) |
| `category` | yes | `engineering` or `rides` |
| `key` | no | pairs the language versions of one post; the slug when left out |
| `image` | no | a picture beside the post: the cover and the share picture |
| `gpx` | no | a GPX beside the post: drawn on a map, with a download link |
| `draft` | no | `true` shows the post under `npm run dev` only: never in a production build, the sitemap or a feed |

The loader checks all of it and fails the build with the file's path on a
missing or invalid field, an unknown one, or a file that is not there.

Pictures and files sit beside `index.md` and are linked by their name. Every
picture needs alt text (`![](photo.jpg)` fails the build), and only files
beside the post work: anything remote is blocked by the site's CSP. PNG, JPEG,
GIF, WebP and AVIF; no SVG. The site serves them from the post's folder under
`/blog-media/<locale>/<slug>/<hash>/<file>`, with their size and lazy loading;
the hash changes with the file, so they can be cached for good.
