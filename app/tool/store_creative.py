#!/usr/bin/env python3
"""The App Store's universal creative asset (5244x2950), in the gallery's look.

    tool/store_creative.py [--locales en] [--raw DIR] [--out DIR]

The art behind the product page's header, the search results and the
featuring: the website's background (two accent glows over faint contour
lines) in the dark style, with three phones from the store capture: the
route coloured by the rain under the radar in front, the cycle map and the
stops behind it to either side, all running past the bottom edge.

Only Apple's "art safe area" (1402x962 at 1921,660, from its Figma
template) is sure to be seen; everything else is cropped per device or lies
under the store's own UI, so it only carries the backdrop on. The front
phone's map, with the rain on the route, fills the safe area. There is no
text: a headline in the safe area would cover the map it is about.

Input:  build/store_screenshots/raw/dark/<locale>/{weather,cyclemap,stops}.png
Output: build/store_screenshots/creative/<locale>/universal.png, and
        universal-debug.png with the safe area and the 3:2 and 2.33:1 crops
        (centred) outlined.

Needs Google Chrome (CHROME overrides its path).
"""
import argparse
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from store_gallery import STYLES  # noqa: E402
from store_slides import BUILD, CHROME, photograph, url  # noqa: E402

W, H = 5244, 2950

# Apple's art safe area: left, top, width, height.
SAFE = (1921, 660, 1402, 962)

# The raw screens' size.
SCREEN_W, SCREEN_H = 1320, 2868

# The front phone: its screen this many times the raw screen, placed so the
# map under the bike chips (from SHOWN_TOP down) starts at the safe area's
# top and the phone runs past the bottom edge.
FRONT_SCALE = 1.0
SHOWN_TOP = 310

CSS = """
html, body { margin: 0; width: %(w)dpx; height: %(h)dpx; overflow: hidden; }
body { position: relative;
  background:
    radial-gradient(1500px 1100px at 50%% 38%%, var(--glow), transparent 70%%),
    radial-gradient(1300px 900px at 12%% 100%%, var(--glow), transparent 70%%),
    radial-gradient(1300px 900px at 88%% 100%%, var(--glow), transparent 70%%),
    linear-gradient(160deg, var(--canvas), var(--deep)); }
.contours { position: absolute; inset: 0; }
.phone { position: absolute; padding: 26px; border-radius: 160px;
  background: linear-gradient(160deg, #2a3039, #0e1115 45%%, #1b1f26);
  box-shadow: 0 0 0 4px rgb(255 255 255 / 0.10), 0 120px 240px -60px rgb(0 0 0 / 0.6),
    0 0 280px -80px var(--glow); }
.screen { overflow: hidden; border-radius: 132px; aspect-ratio: 1320 / 2868; background: #000; }
.screen img { display: block; width: 100%%; }
.back .screen img { filter: brightness(0.78); }
.box { position: absolute; box-sizing: border-box; border: 8px solid; z-index: 10; }
.box span { position: absolute; left: 12px; top: 6px; font: 600 44px sans-serif; }
"""


def contours(style: str) -> str:
    """Faint concentric rings, like the website's contour lines."""
    col = STYLES[style]["line"]
    rings = "".join(
        f'<ellipse cx="{cx}" cy="{cy}" rx="{r}" ry="{r * 0.72}" fill="none" stroke="{col}" '
        f'stroke-width="5"/>'
        for cx, cy, base in ((4300, 700, 200), (900, 2700, 260))
        for r in range(base, base + 3000, 190))
    return f'<svg class="contours" viewBox="0 0 {W} {H}">{rings}</svg>'


def phone(src: str, width: float, left: float, top: float, rot: float, z: int,
          back: bool = False) -> str:
    cls = "phone back" if back else "phone"
    return (f'<div class="{cls}" style="width:{width:.0f}px;left:{left:.0f}px;top:{top:.0f}px;'
            f'rotate:{rot}deg;z-index:{z}"><div class="screen"><img src="{url(src)}"></div></div>')


def boxes() -> str:
    """The safe area and the centred 3:2 and 2.33:1 crops, outlined."""
    def box(x, y, w, h, colour, label):
        return (f'<div class="box" style="left:{x}px;top:{y}px;width:{w}px;height:{h}px;'
                f'border-color:{colour};color:{colour}"><span>{label}</span></div>')

    x, y, w, h = SAFE
    wide_h = round(W / 2.33)
    three_w = round(H * 3 / 2)
    return (box(x, y, w, h, "#ff3b30", "art safe area 1402x962")
            + box((W - three_w) // 2, 0, three_w, H, "#0a84ff", "3:2")
            + box(0, (H - wide_h) // 2, W, wide_h, "#ffd60a", "2.33:1"))


def page(raw: str, locale: str, debug: bool) -> tuple[str, list]:
    style = "dark"
    tokens = ";".join(f"--{k}:{v}" for k, v in STYLES[style].items())

    def shot(screen: str) -> str:
        return os.path.join(raw, style, locale, f"{screen}.png")

    front, left, right = shot("weather"), shot("cyclemap"), shot("stops")
    x, y, w, _ = SAFE
    pad = 26
    width = SCREEN_W * FRONT_SCALE + 2 * pad
    front_left = x + w / 2 - width / 2
    front_top = y - pad - SHOWN_TOP * FRONT_SCALE
    back_width = width * 0.86
    stage = (phone(left, back_width, front_left - 900, front_top + 260, -7, 1, back=True)
             + phone(right, back_width, front_left + width - back_width + 900, front_top + 260,
                     7, 1, back=True)
             + phone(front, width, front_left, front_top, 0, 2))
    css = CSS % {"w": W, "h": H}
    body = (f'<!doctype html><meta charset="utf-8"><style>{css}</style>'
            f'<body style="{tokens}">{contours(style)}{stage}'
            f'{boxes() if debug else ""}</body>')
    return body, [front, left, right]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--locales", default="en,de,fr,es,it,nl")
    parser.add_argument("--raw", default=os.path.join(BUILD, "raw"))
    parser.add_argument("--out", default=os.path.join(BUILD, "creative"))
    args = parser.parse_args()

    if not os.access(CHROME, os.X_OK):
        print(f"store_creative: no Chrome at {CHROME}; install Google Chrome or set CHROME "
              "to a Chrome or Chromium binary.", file=sys.stderr)
        return 1
    missing = set()
    with tempfile.TemporaryDirectory() as work:
        for locale in args.locales.split(","):
            out = os.path.join(args.out, locale)
            os.makedirs(out, exist_ok=True)
            for name, debug in (("universal", False), ("universal-debug", True)):
                html_text, needs = page(args.raw, locale, debug)
                absent = [n for n in needs if not os.path.isfile(n)]
                if absent:
                    missing.update(absent)
                    break
                page_file = os.path.join(work, f"{name}.html")
                with open(page_file, "w", encoding="utf-8") as f:
                    f.write(html_text)
                target = os.path.join(out, f"{name}.png")
                photograph(page_file, target, W, H, work)
                print(target)
    if missing:
        print("store_creative: missing input, those locales were skipped:", file=sys.stderr)
        for path in sorted(missing):
            print(f"  {path}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
