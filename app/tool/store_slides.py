#!/usr/bin/env python3
"""Turns the raw store screenshots into the App Store slides.

    tool/store_slides.py [--locales en,de] [--styles dark,light]
                         [--sizes 6.9,6.5] [--shots same|light|dark]

Each slide is an HTML page at the target resolution, laid out in vw so one
page serves every size, and photographed by headless Chrome: a headline in
Barlow Condensed with one emphasised word, a subline in Manrope, an optional
badge, contour lines behind, and the screenshot in a phone frame bleeding off
the bottom edge. The fonts are the app's own, from assets/fonts.

The copy comes from store/slides_<locale>.json (English is the source,
Crowdin writes the rest): per slide id a `headline`, where **word** is the
emphasis, a `subline` and an optional `badge`. A slide a translation lacks
falls back to English, with a warning.

Two styles: `dark`, deep green with lime, and `light`, a pale lime ground with
deep green. By default each style shows the app in the matching theme
(`--shots same`); `--shots light` or `--shots dark` puts the same app theme in
both.

Input:  build/store_screenshots/raw/<theme>/<locale>/NN-name.png
Output: build/store_screenshots/slides/<style>/<size>/<locale>/NN-name.png
"""
import argparse
import html
import json
import math
import os
import re
import signal
import subprocess
import sys
import tempfile
import time

APP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONTS = os.path.join(APP, "assets", "fonts")
COPY = os.path.join(APP, "store")
BUILD = os.path.join(APP, "build", "store_screenshots")
CHROME = os.environ.get(
    "CHROME", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
)

SIZES = {"6.9": (1320, 2868), "6.5": (1284, 2778)}

STYLES = {
    "dark": {
        "ground": "radial-gradient(120% 70% at 20% 0%, #3f7a00 0%, #24480a 45%, #13260a 100%)",
        "text": "#f4f7ee",
        "emphasis": "#c8f542",
        "subline_color": "#dfe8d2",
        "contour": "#c8f542",
        "contour_opacity": "0.09",
        "badge_bg": "rgba(200, 245, 66, 0.14)",
        "badge_border": "rgba(200, 245, 66, 0.55)",
        "badge_text": "#e6fbb0",
        "shadow": "0 5vw 12vw rgba(0, 0, 0, 0.55)",
        "rim": "rgba(255, 255, 255, 0.08)",
    },
    "light": {
        "ground": "radial-gradient(120% 70% at 20% 0%, #e3f8a6 0%, #eef6d2 40%, #f7f6ef 100%)",
        "text": "#16210d",
        "emphasis": "#3f7a00",
        "subline_color": "#3b4731",
        "contour": "#3f7a00",
        "contour_opacity": "0.13",
        "badge_bg": "rgba(63, 122, 0, 0.08)",
        "badge_border": "rgba(63, 122, 0, 0.38)",
        "badge_text": "#2f5c00",
        "shadow": "0 3vw 9vw rgba(38, 64, 12, 0.24), 0 0.8vw 2.4vw rgba(38, 64, 12, 0.14)",
        "rim": "rgba(255, 255, 255, 0.10)",
    },
}

PAGE = """<!doctype html><html><head><meta charset="utf-8"><style>
@font-face {{ font-family: Barlow; src: url('{fonts}/BarlowCondensed-Bold.ttf'); }}
@font-face {{ font-family: Manrope; src: url('{fonts}/Manrope-Medium.ttf'); font-weight: 500; }}
@font-face {{ font-family: Manrope; src: url('{fonts}/Manrope-Bold.ttf'); font-weight: 700; }}
html, body {{ margin: 0; width: {w}px; height: {h}px; overflow: hidden; }}
body {{
  background: {ground};
  font-family: Manrope, sans-serif; color: {text}; position: relative;
}}
.topo {{ position: absolute; inset: 0; width: 100%; height: 100%; }}
.topo path {{ fill: none; stroke: {contour}; stroke-opacity: {contour_opacity}; stroke-width: 0.12; }}
.copy {{ position: relative; padding: 9.2vw 7.5vw 0; }}
h1 {{
  font-family: Barlow, sans-serif; font-size: 15.2vw; line-height: 0.95;
  letter-spacing: -0.02em; margin: 0; text-transform: uppercase;
  text-wrap: balance; font-weight: 700;
}}
h1 em {{ font-style: normal; color: {emphasis}; }}
p {{ font-size: 4.3vw; line-height: 1.38; margin: 3.6vw 0 0; color: {subline_color}; font-weight: 500;
  max-width: 82vw; }}
.badge {{ display: inline-block; margin-top: 4vw; padding: 1.7vw 3.4vw; border-radius: 999px;
  background: {badge_bg}; border: 0.25vw solid {badge_border};
  color: {badge_text}; font-weight: 700; font-size: 3.1vw; letter-spacing: 0.02em; }}
.phone {{
  position: relative; margin: 7vw auto 0; width: 78vw; border-radius: 10.5vw; background: #0b0f08;
  padding: 2.1vw; box-shadow: {shadow}, 0 0 0 0.35vw {rim} inset;
}}
.phone img {{ display: block; width: 100%; border-radius: 8.6vw; }}
</style></head><body>
{topo}
<div class="copy"><h1 id="h">{headline}</h1><p id="s">{subline}</p>{badge}</div>
<div class="phone"><img src="{img}"></div>
<script>
// A translation longer than the English shrinks until it fits: the headline
// in three lines at most, the subline in three.
function fit(id, lines, floor) {{
  const el = document.getElementById(id);
  let size = parseFloat(getComputedStyle(el).fontSize);
  const line = () => parseFloat(getComputedStyle(el).lineHeight);
  while (el.scrollHeight > line() * lines + 1 && size > floor) {{
    size -= 1;
    el.style.fontSize = size + 'px';
  }}
}}
document.fonts.ready.then(() => {{
  fit('h', 3, {w} * 0.09);
  fit('s', 3, {w} * 0.034);
}});
</script>
</body></html>"""


def contours() -> str:
    """Nested, slightly irregular closed curves, like a height map."""
    paths = []
    for cx, cy, rings in [(0.15, 0.12, 9), (0.92, 0.38, 8), (0.3, 0.95, 10)]:
        for r in range(1, rings + 1):
            pts = []
            for i in range(73):
                a = i / 72 * 2 * math.pi
                wobble = 1 + 0.08 * math.sin(3 * a + r) + 0.05 * math.cos(5 * a - r)
                rad = r * 0.055 * wobble
                pts.append((cx + rad * math.cos(a), cy + rad * math.sin(a) * 0.46))
            d = "M" + " L".join(f"{x * 100:.2f} {y * 217:.2f}" for x, y in pts) + " Z"
            paths.append(f'<path d="{d}"/>')
    return (
        '<svg class="topo" viewBox="0 0 100 217" preserveAspectRatio="none">'
        + "".join(paths)
        + "</svg>"
    )


def rich(text: str) -> str:
    """HTML for a headline: escaped, with **word** as the emphasis."""
    return re.sub(r"\*\*(.+?)\*\*", r"<em>\1</em>", html.escape(text))


def load_copy(locale: str) -> dict:
    with open(os.path.join(COPY, f"slides_{locale}.json"), encoding="utf-8") as f:
        return json.load(f)


def photograph(page: str, target: str, w: int, h: int, work: str) -> None:
    """Has headless Chrome save [page] as [target] at w x h.

    Chrome writes the picture within a second or two but can take half a
    minute more to quit, while its updater wakes up and goes back to sleep;
    so the picture is waited for, not the process, which is then stopped.
    """
    if os.path.exists(target):
        os.remove(target)
    chrome = subprocess.Popen(
        [CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
         "--allow-file-access-from-files", "--force-device-scale-factor=1",
         "--virtual-time-budget=4000", "--no-first-run",
         # A profile of its own each time: a second Chrome on the same one
         # hands its work to the first and waits for it.
         f"--user-data-dir={tempfile.mkdtemp(dir=work)}",
         f"--window-size={w},{h}", f"--screenshot={target}", "file://" + page],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True,
    )
    deadline = time.monotonic() + 90
    size = -1
    try:
        while time.monotonic() < deadline:
            if chrome.poll() is not None and not os.path.exists(target):
                raise RuntimeError(f"Chrome quit without writing {target}")
            if os.path.exists(target):
                now = os.path.getsize(target)
                if now > 0 and now == size:
                    return
                size = now
            time.sleep(0.4)
        raise RuntimeError(f"Chrome did not write {target} within 90 s")
    finally:
        if chrome.poll() is None:
            os.killpg(chrome.pid, signal.SIGTERM)
            try:
                chrome.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(chrome.pid, signal.SIGKILL)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--locales", help="comma-separated; default: every slides_*.json")
    parser.add_argument("--styles", default="dark,light")
    parser.add_argument("--sizes", default=",".join(SIZES))
    parser.add_argument("--shots", default="same", choices=["same", "light", "dark"],
                        help="which app theme each style shows")
    parser.add_argument("--raw", default=os.path.join(BUILD, "raw"))
    parser.add_argument("--out", default=os.path.join(BUILD, "slides"))
    args = parser.parse_args()

    if not os.access(CHROME, os.X_OK):
        print(f"store_slides: no Chrome at {CHROME}; install Google Chrome or set CHROME "
              "to a Chrome or Chromium binary.", file=sys.stderr)
        return 1
    if args.locales:
        locales = args.locales.split(",")
    else:
        locales = sorted(
            m.group(1) for m in (re.match(r"slides_(.+)\.json$", n) for n in os.listdir(COPY)) if m
        )
    styles = args.styles.split(",")
    sizes = args.sizes.split(",")
    for name in styles:
        if name not in STYLES:
            print(f"store_slides: unknown style {name!r}", file=sys.stderr)
            return 2
    for name in sizes:
        if name not in SIZES:
            print(f"store_slides: unknown size {name!r}", file=sys.stderr)
            return 2

    english = load_copy("en")
    topo = contours()
    missing = []
    made = 0
    with tempfile.TemporaryDirectory() as work:
        for locale in locales:
            copy = load_copy(locale)
            for slide, source in english.items():
                text = copy.get(slide)
                if text is None:
                    print(f"store_slides: warning: {locale} has no {slide}; using English")
                    text = source
                for style in styles:
                    theme = style if args.shots == "same" else args.shots
                    shot = os.path.join(args.raw, theme, locale, f"{slide}.png")
                    if not os.path.isfile(shot):
                        missing.append(shot)
                        continue
                    for size in sizes:
                        w, h = SIZES[size]
                        badge = text.get("badge")
                        page = PAGE.format(
                            w=w, h=h, fonts="file://" + FONTS, topo=topo,
                            headline=rich(text["headline"]),
                            subline=html.escape(text["subline"]),
                            badge=f'<div class="badge">{html.escape(badge)}</div>' if badge else "",
                            img="file://" + os.path.abspath(shot),
                            **STYLES[style],
                        )
                        page_file = os.path.join(work, "slide.html")
                        with open(page_file, "w", encoding="utf-8") as f:
                            f.write(page)
                        target = os.path.join(args.out, style, size, locale, f"{slide}.png")
                        os.makedirs(os.path.dirname(target), exist_ok=True)
                        photograph(page_file, target, w, h, work)
                        made += 1
                        print(target)
    if missing:
        print("store_slides: no raw screenshot for:", file=sys.stderr)
        for path in missing:
            print(f"  {path}", file=sys.stderr)
        return 1
    print(f"store_slides: {made} slides in {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
