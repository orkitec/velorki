#!/usr/bin/env python3
"""Landscape gallery images (3:2, 2400x1600) in the store slides' look.

    tool/store_gallery.py [--locales en] [--raw DIR] [--watch DIR] [--out DIR]

For pages that want wide pictures rather than the stores' tall slides, such
as a hackathon or press page: the copy on the left (an eyebrow chip with an
accent dot, a Barlow Condensed headline with one phrase in the accent colour,
a bold Manrope subline), and on the right two phones from the store capture,
a phone with the Apple Watch, or a grid of figures. The background is the
website's: two accent glows over faint contour lines, in the dark or the
light style. Each image is an HTML page photographed by headless Chrome, as
tool/store_slides.py does.

Which screens each image shows is GALLERY below; the copy is
store/gallery_<locale>.json, per image a `chip`, a `headline` (**phrase** is
the accent, \\n breaks the line) and a `subline` (**words** in the text
colour), and for the figures image its `stats`.

Input:  build/store_screenshots/raw/<theme>/<locale>/<screen>.png (from
        tool/store_screenshots.sh, with the paywall shots),
        --watch/light/<locale>/store/1-riding-turn.png (tool/store_watch.sh)
Output: build/store_screenshots/gallery/<locale>/<image>.png and .jpg
        (JPEG quality 88), and contact.png beside them.

Needs Google Chrome (CHROME overrides its path) and macOS's sips for the
JPEGs.
"""
import argparse
import html
import os
import re
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from store_slides import APP_ICON, BUILD, CHROME, FONTS, STORE, load_json, photograph, url  # noqa: E402

W, H = 2400, 1600

STYLES = {
    "dark": dict(canvas="#0e1115", deep="#0a0d10", fg="#f1f3f5", muted="#aab2bc",
                 accent="#c8f542", glow="rgb(200 245 66 / 0.22)", chip="rgb(255 255 255 / 0.08)",
                 line="rgb(255 255 255 / 0.05)"),
    "light": dict(canvas="#f5f6f3", deep="#e6e9e2", fg="#14171a", muted="#5b636c",
                  accent="#3f7a00", glow="rgb(63 122 0 / 0.18)", chip="rgb(0 0 0 / 0.05)",
                  line="rgb(0 0 0 / 0.05)"),
}

CSS = """
@font-face { font-family: Barlow; src: url('FONTS/BarlowCondensed-Bold.ttf'); font-weight: 700; }
@font-face { font-family: Manrope; src: url('FONTS/Manrope-SemiBold.ttf'); font-weight: 600; }
@font-face { font-family: Manrope; src: url('FONTS/Manrope-Bold.ttf'); font-weight: 700; }
html, body { margin: 0; width: 2400px; height: 1600px; overflow: hidden; }
body { position: relative; font-family: Manrope, sans-serif; color: var(--fg);
  background:
    radial-gradient(900px 700px at 78% 30%, var(--glow), transparent 70%),
    radial-gradient(800px 600px at 8% 105%, var(--glow), transparent 70%),
    linear-gradient(160deg, var(--canvas), var(--deep)); }
.contours { position: absolute; inset: 0; }
.text { position: absolute; left: 150px; top: 0; bottom: 0; width: 1000px; display: flex;
  flex-direction: column; justify-content: center; }
.brand { display: flex; align-items: center; gap: 26px; margin-bottom: 44px; }
.brand img { width: 104px; height: 104px; border-radius: 23px; }
.brand span { font-family: Barlow; font-weight: 700; font-size: 84px; }
.chip { align-self: flex-start; display: inline-flex; align-items: center; gap: 16px;
  padding: 14px 30px 14px 24px; border-radius: 999px; background: var(--chip);
  font-size: 34px; font-weight: 600; margin-bottom: 36px; }
.chip i { width: 18px; height: 18px; border-radius: 50%; background: var(--accent); }
h1 { font-family: Barlow; font-weight: 700; font-size: 150px; line-height: 0.95; margin: 0;
  letter-spacing: 0.005em; }
h1 em { font-style: normal; color: var(--accent); }
p { font-size: 46px; line-height: 1.32; font-weight: 700; color: var(--muted); margin: 40px 0 0;
  max-width: 900px; }
p b { color: var(--fg); }
.stage { position: absolute; right: 0; top: 0; bottom: 0; width: 1250px; }
.phone { position: absolute; width: 560px; padding: 15px; border-radius: 80px;
  background: linear-gradient(160deg, #2a3039, #0e1115 45%, #1b1f26);
  box-shadow: 0 0 0 2px rgb(255 255 255 / 0.10), 0 60px 120px -30px rgb(0 0 0 / 0.55),
    0 0 140px -40px var(--glow); }
.screen { overflow: hidden; border-radius: 65px; aspect-ratio: 1320 / 2868; background: #000; }
.screen img { display: block; width: 100%; }
.watch { position: absolute; width: 400px; padding: 18px; border-radius: 110px;
  background: linear-gradient(160deg, #3a4048, #14171a 45%, #23282f);
  box-shadow: 0 0 0 2px rgb(255 255 255 / 0.12), 0 50px 100px -30px rgb(0 0 0 / 0.6),
    0 0 120px -40px var(--glow); }
.watch::after { content: ''; position: absolute; top: 28%; right: -9px; width: 12px; height: 70px;
  border-radius: 999px; background: linear-gradient(90deg, #3a4048, #8b929b); }
.watch .face { overflow: hidden; border-radius: 92px; background: #000; aspect-ratio: 422 / 514; }
.watch .face img { display: block; width: 100%; }
.stats { position: absolute; right: 150px; top: 50%; translate: 0 -50%; width: 1000px;
  display: grid; grid-template-columns: 1fr 1fr; gap: 36px; }
.stat { border-radius: 40px; background: var(--chip); padding: 44px 48px;
  box-shadow: inset 0 0 0 2px var(--line); }
.stat b { display: block; font-family: Barlow; font-size: 124px; line-height: 1; color: var(--accent); }
.stat span { display: block; font-size: 36px; font-weight: 600; margin-top: 14px; color: var(--muted); }
"""

# Per image, in order: its style and what stands on the right. `two` is two
# phones, the back one first, each a (theme, screen) of the raw capture;
# `watch` the phone with the Apple Watch; `stats` the copy's figures.
GALLERY = [
    {"name": "01-cover", "style": "dark", "brand": True,
     "two": [("dark", "plan"), ("light", "variants")]},
    {"name": "02-offline", "style": "light",
     "two": [("light", "offline"), ("light", "navigation")]},
    {"name": "03-navigate", "style": "dark",
     "two": [("dark", "loop"), ("dark", "navigation")]},
    {"name": "04-watch", "style": "light", "watch": ("light", "live")},
    {"name": "05-stats", "style": "dark",
     "two": [("dark", "library"), ("dark", "ride")]},
    {"name": "06-plus", "style": "light",
     "two": [("light", "ai"), ("light", "paywall-top")]},
    {"name": "07-built-with-ai", "style": "dark", "stats": True},
]


def contours(style: str) -> str:
    """Faint concentric rings, like the website's contour lines."""
    col = STYLES[style]["line"]
    rings = "".join(
        f'<ellipse cx="{cx}" cy="{cy}" rx="{r}" ry="{r * 0.72}" fill="none" stroke="{col}" '
        f'stroke-width="3"/>'
        for cx, cy, base in ((1900, 420, 120), (300, 1500, 160))
        for r in range(base, base + 1400, 110))
    return f'<svg class="contours" viewBox="0 0 {W} {H}">{rings}</svg>'


def phone(src: str, left: int, top: int, rot: float, z: int) -> str:
    return (f'<div class="phone" style="left:{left}px;top:{top}px;rotate:{rot}deg;z-index:{z}">'
            f'<div class="screen"><img src="{url(src)}"></div></div>')


def watch(src: str, left: int, top: int, rot: float) -> str:
    return (f'<div class="watch" style="left:{left}px;top:{top}px;rotate:{rot}deg;z-index:3">'
            f'<div class="face"><img src="{url(src)}"></div></div>')


def headline(text: str) -> str:
    return re.sub(r"\*\*(.+?)\*\*", r"<em>\1</em>", html.escape(text)).replace("\n", "<br>")


def subline(text: str) -> str:
    return re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", html.escape(text))


def page(style: str, text: dict, right: str, brand: bool) -> str:
    tokens = ";".join(f"--{k}:{v}" for k, v in STYLES[style].items())
    brand_html = (f'<div class="brand"><img src="{url(APP_ICON)}"><span>Velorki</span></div>'
                  if brand else "")
    chip = text.get("chip")
    chip_html = f'<div class="chip"><i></i>{html.escape(chip)}</div>' if chip else ""
    return (f'<!doctype html><meta charset="utf-8"><style>{CSS.replace("FONTS", "file://" + FONTS)}'
            f'</style><body style="{tokens}">{contours(style)}'
            f'<div class="text">{brand_html}{chip_html}<h1>{headline(text["headline"])}</h1>'
            f'<p>{subline(text["subline"])}</p></div>{right}</body>')


def right_side(entry: dict, text: dict, raw: str, watch_dir: str, locale: str) -> tuple[str, list]:
    """The markup right of the copy, and the files it needs."""
    def shot(theme: str, screen: str) -> str:
        return os.path.join(raw, theme, locale, f"{screen}.png")

    if "two" in entry:
        # The back phone higher and left, the front one lower and right.
        back, front = (shot(*s) for s in entry["two"])
        stage = phone(back, 90, 150, -4, 1) + phone(front, 600, 330, 3, 2)
        return f'<div class="stage">{stage}</div>', [back, front]
    if "watch" in entry:
        live = shot(*entry["watch"])
        face = os.path.join(watch_dir, "light", locale, "store", "1-riding-turn.png")
        stage = phone(live, 150, 170, -3, 1) + watch(face, 640, 520, 4)
        return f'<div class="stage">{stage}</div>', [live, face]
    cells = "".join(f'<div class="stat"><b>{html.escape(a)}</b><span>{html.escape(b)}</span></div>'
                    for a, b in text["stats"])
    return f'<div class="stats">{cells}</div>', []


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--locales", help="comma-separated; default: every gallery_*.json")
    parser.add_argument("--raw", default=os.path.join(BUILD, "raw"))
    parser.add_argument("--watch", default=os.path.join(BUILD, "watch"),
                        help="the watch screenshots, <theme>/<locale>/store/1-riding-turn.png")
    parser.add_argument("--out", default=os.path.join(BUILD, "gallery"))
    args = parser.parse_args()

    if not os.access(CHROME, os.X_OK):
        print(f"store_gallery: no Chrome at {CHROME}; install Google Chrome or set CHROME "
              "to a Chrome or Chromium binary.", file=sys.stderr)
        return 1
    if not shutil.which("sips"):
        print("store_gallery: sips (macOS) is needed for the JPEGs", file=sys.stderr)
        return 1
    locales = (args.locales.split(",") if args.locales else sorted(
        m.group(1) for m in (re.match(r"gallery_(.+)\.json$", n) for n in os.listdir(STORE)) if m))
    english = load_json(os.path.join(STORE, "gallery_en.json"))
    missing = set()
    with tempfile.TemporaryDirectory() as work:
        for locale in locales:
            copy = load_json(os.path.join(STORE, f"gallery_{locale}.json"))
            out = os.path.join(args.out, locale)
            os.makedirs(out, exist_ok=True)
            made = []
            for entry in GALLERY:
                name = entry["name"]
                text = copy.get(name)
                if text is None:
                    print(f"store_gallery: warning: {locale} has no {name}; using English")
                    text = english[name]
                right, needs = right_side(entry, text, args.raw, args.watch, locale)
                absent = [n for n in needs if not os.path.isfile(n)]
                if absent:
                    missing.update(absent)
                    continue
                page_file = os.path.join(work, f"{name}.html")
                with open(page_file, "w", encoding="utf-8") as f:
                    f.write(page(entry["style"], text, right, entry.get("brand", False)))
                png = os.path.join(out, f"{name}.png")
                photograph(page_file, png, W, H, work)
                jpg = os.path.join(out, f"{name}.jpg")
                subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", "88",
                                png, "--out", jpg], check=True, stdout=subprocess.DEVNULL)
                made.append(png)
                print(jpg)

            # The contact sheet: every image small, four to a row.
            if made:
                images = "".join(f'<img src="{url(p)}">' for p in made)
                rows = (len(made) + 3) // 4
                sheet = ('<!doctype html><html><head><style>html,body{margin:0;background:#6b7078}'
                         'body{display:grid;grid-template-columns:repeat(4,600px);gap:16px;'
                         'padding:24px;width:max-content}'
                         'img{width:600px;border-radius:10px;display:block}</style></head>'
                         f"<body>{images}</body></html>")
                page_file = os.path.join(work, "contact.html")
                with open(page_file, "w", encoding="utf-8") as f:
                    f.write(sheet)
                target = os.path.join(out, "contact.png")
                photograph(page_file, target, 48 + 4 * 600 + 3 * 16,
                           48 + rows * 400 + (rows - 1) * 16, work)
                print(target)
    if missing:
        print("store_gallery: missing input, those images were skipped:", file=sys.stderr)
        for path in sorted(missing):
            print(f"  {path}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
