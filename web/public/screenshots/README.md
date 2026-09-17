# Screenshots

`app/tool/screenshots.sh` writes into this directory. Nothing here is committed
by hand, and nothing here is required for the site to build: a file that is
missing renders as a labelled placeholder inside the phone frame.

## Layout

```
public/screenshots/<lang>/<mode>-<accent>/<screen>.png
```

- `<lang>`: the app's own language setting for the run — `en` (the app on
  System, which is English here) or `de`
- `<mode>`: `light` or `dark`
- `<accent>`: `volt`, `ember`, `glacier` or `berry`
- `<screen>`: `planner`, `loop`, `search`, `navigation`, `recording`, `ride`,
  `library`, `offline`, `settings`

So `public/screenshots/en/dark-volt/planner.png` is the planner in the app's
default look. One run of the pipeline takes one language
(`tool/screenshots.sh --lang de`), so the sets need not be in step; the site
falls back per file. The manifest that lists the grid is `src/site/screenshots.ts`;
`src/site/screenshot-files.ts` is what checks, at build time, which of those
files exist and in which language. `manifest.json` beside these directories is
the pipeline's own record of a run, and lists the languages it found.

## Format

PNG, portrait, **1080 × 2400** (the aspect the CSS phone frame is cut to —
`aspect-ratio: 1080 / 2400` in `src/app/globals.css`). Other sizes still work:
the image is drawn with `object-fit: cover` from the top, so a taller shot is
cropped at the bottom rather than distorted. Keep the status bar in the frame;
it is part of how the app looks on a phone.

## What the site uses

The landing page shows `planner`, `loop`, `search`, `navigation`, `recording`
and `library`; `/plus` shows `settings`, `/download` shows `ride`, and
`offline` is held for the docs. A page in a locale asks for that locale's
screenshot and falls back to `en/` for any file the pipeline has not taken in
it yet, so `/de` shows the German app and `/` the English one. The appearance
switcher on the landing page swaps mode and accent for every frame on the page
at once; when a variant is missing the site falls back to the same mode in
volt, then to `dark-volt`, and only then to the placeholder.

iPhone captures later replace the same file names.
