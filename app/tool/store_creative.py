#!/usr/bin/env python3
"""The App Store's creative assets, in the gallery's look.

    tool/store_creative.py [--locales en] [--images search] [--raw DIR] [--out DIR]

Two images per language, each on the website's background (accent glows
over faint contour lines), with phones from the store capture running past
the bottom edge. Only Apple's "art safe area" of each (from its Figma
template) is sure to be seen; everything else is cropped per device or lies
under the store's own UI, so it only carries the backdrop on.

* universal.png (5244x2950, dark): behind the product page's header and in
  the featuring. One line of copy ("universal" in creative_<locale>.json,
  a **phrase** in the accent) at the top of the safe area (1402x962 at
  1921,660), the route coloured by the rain under the radar in the dark
  phone below it, the light cycle map and stops to either side. Apple's
  rules for these images allow no price word, so "free" stays out of it.
* search.png (3840x2560, light): in the search results, in place of the
  first three screenshots, so it says what the app is. The copy of
  store/creative_<locale>.json ("search": chip, headline with a **phrase**
  in the accent, subline) on the left of the safe area (2168x1030 at
  836,765), over the front phone's map enlarged and soft. On the right the
  rain on the route in the light look, the cycle map in the dark and the
  ride's charts behind it; left of the copy the ride under way; under the
  copy the time control and the rain's key, cut out of the real screen.

Input:  build/store_screenshots/raw/dark/<locale>/{weather,cyclemap,navigation}.png,
        build/store_screenshots/raw/light/<locale>/{weather,ride,cyclemap,stops}.png
Output: build/store_screenshots/creative/<locale>/universal.png and
        search.png, and each with -debug beside it: the safe area outlined,
        on the universal one also the 3:2 and 2.33:1 crops (centred).

Needs Google Chrome (CHROME overrides its path), and ffmpeg for the search
image's cut-outs.
"""
import argparse
import html
import os
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from store_gallery import STYLES, headline, subline  # noqa: E402
from store_slides import BUILD, CHROME, FONTS, STORE, load_json, photograph, url  # noqa: E402

W, H = 5244, 2950

# Apple's art safe area: left, top, width, height.
SAFE = (1921, 660, 1402, 962)

# The search results' image and its safe area.
SEARCH_W, SEARCH_H = 3840, 2560
SEARCH_SAFE = (836, 765, 2168, 1030)

# The raw screens' size.
SCREEN_W, SCREEN_H = 1320, 2868

# The front phone: its screen this many times the raw screen, placed so the
# map under the bike chips (from SHOWN_TOP down) starts at the safe area's
# top and the phone runs past the bottom edge.
FRONT_SCALE = 1.0
SHOWN_TOP = 310

CSS = """
@font-face { font-family: Barlow; src: url('FONTS/BarlowCondensed-Bold.ttf'); font-weight: 700; }
html, body { margin: 0; width: %(w)dpx; height: %(h)dpx; overflow: hidden; }
.htext { position: absolute; z-index: 5; text-align: center; color: var(--fg); }
.htext h1 { font-family: Barlow; font-weight: 700; font-size: 270px; line-height: 0.93; margin: 0;
  letter-spacing: 0.005em; text-wrap: balance; }
.htext h1 em { font-style: normal; color: var(--accent); }
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

SEARCH_CSS = """
@font-face { font-family: Barlow; src: url('FONTS/BarlowCondensed-Bold.ttf'); font-weight: 700; }
@font-face { font-family: Manrope; src: url('FONTS/Manrope-SemiBold.ttf'); font-weight: 600; }
@font-face { font-family: Manrope; src: url('FONTS/Manrope-Bold.ttf'); font-weight: 700; }
html, body { margin: 0; width: %(w)dpx; height: %(h)dpx; overflow: hidden; }
body { position: relative; font-family: Manrope, sans-serif; color: var(--fg);
  background:
    radial-gradient(1300px 1000px at 66%% 40%%, var(--glow), transparent 70%%),
    radial-gradient(1200px 900px at 8%% 100%%, var(--glow), transparent 70%%),
    linear-gradient(160deg, var(--canvas), var(--deep)); }
.contours { position: absolute; inset: 0; }
.text { position: absolute; display: flex; flex-direction: column; justify-content: center; }
.copy { display: flex; flex-direction: column; }
.chip { align-self: flex-start; display: inline-flex; align-items: center; gap: 22px;
  padding: 24px 52px 24px 40px; border-radius: 999px; background: var(--chip);
  font-size: 74px; font-weight: 600; margin-bottom: 56px; }
.chip i { width: 34px; height: 34px; border-radius: 50%%; background: var(--accent); }
h1 { font-family: Barlow; font-weight: 700; font-size: 260px; line-height: 0.93; margin: 0;
  letter-spacing: 0.005em; text-wrap: balance; }
h1 em { font-style: normal; color: var(--accent); }
p { font-size: 84px; line-height: 1.25; font-weight: 700; color: var(--muted); margin: 40px 0 0;
  text-wrap: pretty; }
p b { color: var(--fg); }
.phone { position: absolute; padding: 18px; border-radius: 110px;
  background: linear-gradient(160deg, #2a3039, #0e1115 45%%, #1b1f26);
  box-shadow: 0 0 0 3px rgb(255 255 255 / 0.10), 0 90px 180px -50px rgb(0 0 0 / 0.45),
    0 0 220px -60px var(--glow); }
.screen { overflow: hidden; border-radius: 92px; aspect-ratio: 1320 / 2868; background: #000; }
.screen img { display: block; width: 100%%; }
.badge { position: absolute; z-index: 6; padding: 26px 34px; border-radius: 48px;
  background: #f5f6f3; box-shadow: 0 40px 90px -30px rgb(0 0 0 / 0.35),
    0 0 0 3px rgb(0 0 0 / 0.04); }
.backdrop { position: absolute; inset: 0; filter: blur(28px) saturate(1.15); opacity: 0.8; }
.veil { position: absolute; inset: 0;
  background: linear-gradient(90deg, rgb(245 246 243 / 0.92) 0%%, rgb(245 246 243 / 0.75) 35%%,
    rgb(245 246 243 / 0.2) 65%%, rgb(245 246 243 / 0) 100%%); }
.box { position: absolute; box-sizing: border-box; border: 6px solid; z-index: 10; }
.box span { position: absolute; left: 12px; top: 6px; font: 600 40px sans-serif; }
"""


def contours(style: str, w: int = W, h: int = H,
             centres=((4300, 700, 200), (900, 2700, 260)), step: int = 190,
             reach: int = 3000) -> str:
    """Faint concentric rings, like the website's contour lines."""
    col = STYLES[style]["line"]
    rings = "".join(
        f'<ellipse cx="{cx}" cy="{cy}" rx="{r}" ry="{r * 0.72}" fill="none" stroke="{col}" '
        f'stroke-width="5"/>'
        for cx, cy, base in centres
        for r in range(base, base + reach, step))
    return f'<svg class="contours" viewBox="0 0 {w} {h}">{rings}</svg>'


def phone(src: str, width: float, left: float, top: float, rot: float, z: int,
          back: bool = False) -> str:
    cls = "phone back" if back else "phone"
    return (f'<div class="{cls}" style="width:{width:.0f}px;left:{left:.0f}px;top:{top:.0f}px;'
            f'rotate:{rot}deg;z-index:{z}"><div class="screen"><img src="{url(src)}"></div></div>')


def boxes() -> str:
    """The safe area and the centred 3:2 and 2.33:1 crops, outlined."""
    x, y, w, h = SAFE
    wide_h = round(W / 2.33)
    three_w = round(H * 3 / 2)
    return (box(x, y, w, h, "#ff3b30", "art safe area 1402x962")
            + box((W - three_w) // 2, 0, three_w, H, "#0a84ff", "3:2")
            + box(0, (H - wide_h) // 2, W, wide_h, "#ffd60a", "2.33:1"))


def box(x: float, y: float, w: float, h: float, colour: str, label: str) -> str:
    """An outline for the debug images."""
    return (f'<div class="box" style="left:{x}px;top:{y}px;width:{w}px;height:{h}px;'
            f'border-color:{colour};color:{colour}"><span>{label}</span></div>')


def universal_page(raw: str, locale: str, debug: bool) -> tuple[str, list]:
    style = "dark"
    tokens = ";".join(f"--{k}:{v}" for k, v in STYLES[style].items())

    def shot(screen: str) -> str:
        return os.path.join(raw, style, locale, f"{screen}.png")

    english = load_json(os.path.join(STORE, "creative_en.json")).get("universal", {})
    copy = load_json(os.path.join(STORE, f"creative_{locale}.json")).get("universal", english)
    front = shot("weather")
    left = os.path.join(raw, "light", locale, "cyclemap.png")
    right = os.path.join(raw, "light", locale, "stops.png")
    x, y, w, _ = SAFE
    # The copy at the top of the safe area, as large as two lines of the
    # area's width allow, and the front phone starting under it. On a phone the
    # safe area is the copy and the top of the phone; wider crops show the
    # maps.
    text = (f'<div class="htext" style="left:{x}px;top:{y + 20}px;width:{w}px">'
            f'<h1>{headline(copy.get("headline", ""))}</h1></div>'
            # Measured once the fonts are in: the fallback face is wider.
            '<script>document.fonts.ready.then(() => {'
            'const h = document.querySelector(".htext h1"); let size = 270;'
            # Two line boxes plus the ascenders that overflow them.
            'const wraps = () => h.scrollWidth > h.clientWidth + 1 || h.scrollHeight > parseFloat(getComputedStyle(h).fontSize) * (0.93 * 2 + 0.5);'
            'while (wraps() && size > 120) { size -= 2; h.style.fontSize = size + "px"; } });</script>')
    pad = 26
    width = SCREEN_W * FRONT_SCALE + 2 * pad
    front_left = x + w / 2 - width / 2
    front_top = y + 560
    back_width = width * 0.86
    stage = (phone(left, back_width, front_left - 900, front_top + 260, -7, 1)
             + phone(right, back_width, front_left + width - back_width + 900, front_top + 260,
                     7, 1)
             + phone(front, width, front_left, front_top, 0, 2))
    css = (CSS % {"w": W, "h": H}).replace("FONTS", "file://" + FONTS)
    body = (f'<!doctype html><meta charset="utf-8"><style>{css}</style>'
            f'<body style="{tokens}">{contours(style)}{text}{stage}'
            f'{boxes() if debug else ""}</body>')
    return body, [front, left, right]


# Pieces of the raw light weather screen shown as floating cards on the
# search image: left, top (from the bottom of the Save button above them,
# [save_bottom]), width and height in the raw screen's pixels.
TIME_CONTROL = (40, 11, 1200, 173)
RAIN_KEY = (40, 541, 660, 66)


def save_bottom(src: str) -> int:
    """The last row of the Save button on a light planner screen: where the
    sheet's content under it starts, which a longer header in some languages
    pushes down."""
    column = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", src, "-vf", f"crop=1:{SCREEN_H}:{SCREEN_W // 2}:0",
         "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
        check=True, capture_output=True).stdout
    # The light accent, #3f7a00.
    rows = [i for i in range(1200, 2400)
            if abs(column[3 * i] - 0x3f) < 25 and abs(column[3 * i + 1] - 0x7a) < 25
            and column[3 * i + 2] < 40]
    if not rows:
        raise RuntimeError(f"no Save button found on {src}")
    return rows[-1]


def below_save(crop: tuple, src: str) -> tuple:
    """[crop], its top counted from [src]'s Save button, in the screen's
    pixels."""
    cx, cy, cw, ch = crop
    return cx, save_bottom(src) + cy, cw, ch


def badge(src: str, crop: tuple, scale: float, left: float, top: float, rot: float = 0) -> str:
    """A piece of a real screen as a card floating over the art."""
    cx, cy, cw, ch = crop
    return (f'<div class="badge" style="left:{left:.0f}px;top:{top:.0f}px;rotate:{rot}deg">'
            f'<div style="width:{cw * scale:.0f}px;height:{ch * scale:.0f}px;'
            f'background:url({url(src)}) {-cx * scale:.0f}px {-cy * scale:.0f}px / '
            f'{SCREEN_W * scale:.0f}px auto no-repeat"></div></div>')


def search_page(raw: str, locale: str, debug: bool) -> tuple[str, list]:
    style = "light"
    tokens = ";".join(f"--{k}:{v}" for k, v in STYLES[style].items())
    english = load_json(os.path.join(STORE, "creative_en.json"))["search"]
    copy = load_json(os.path.join(STORE, f"creative_{locale}.json")).get("search", english)

    def shot(theme: str, screen: str) -> str:
        return os.path.join(raw, theme, locale, f"{screen}.png")

    front, back = shot("light", "weather"), shot("dark", "cyclemap")
    ride, charts = shot("dark", "navigation"), shot("light", "ride")
    x, y, w, h = SEARCH_SAFE
    # The copy in the left half of the safe area, a margin inside it.
    margin = 60
    text = (f'<div class="text" style="left:{x + margin}px;top:{y + margin}px;'
            f'width:1240px;height:{h - 2 * margin}px"><div class="copy">'
            f'<div class="chip"><i></i>{html.escape(copy["chip"])}</div>'
            f'<h1>{headline(copy["headline"])}</h1><p>{subline(copy["subline"])}</p></div></div>'
            # A language whose copy runs long has it set smaller until it
            # fits the box, the headline no smaller than 230 px: on a phone
            # the safe area shows at about a fifth of this size, so the
            # headline is the one line sure to be read there.
            '<script>document.fonts.ready.then(() => { const box = document.querySelector(".text");'
            'const copy = box.firstElementChild;'
            'const h1 = copy.querySelector("h1"), p = copy.querySelector("p");'
            'const lines = () => h1.scrollWidth > h1.clientWidth + 1 || h1.scrollHeight > parseFloat(getComputedStyle(h1).fontSize) * (0.93 * 2 + 0.5);'
            'let hs = 260, ps = 84;'
            'while ((copy.offsetHeight > box.clientHeight || lines()) && hs > 200) {'
            'hs -= 4; ps = Math.max(64, ps - 1.5);'
            'h1.style.fontSize = hs + "px"; p.style.fontSize = ps + "px"; }'
            'while (copy.offsetHeight > box.clientHeight && ps > 52) {'
            'ps -= 1; p.style.fontSize = ps + "px"; } });</script>')
    # The front phone's map, enlarged and soft, behind everything, fading out
    # under the copy.
    crop_x, crop_y, crop_w = 0, 560, 1150
    zoom = SEARCH_W / crop_w
    backdrop = (f'<div class="backdrop" style="background:url({url(front)}) '
                f'{-crop_x * zoom:.0f}px {-crop_y * zoom:.0f}px / '
                f'{SCREEN_W * zoom:.0f}px auto no-repeat"></div><div class="veil"></div>')
    # On the right the front phone's map in the safe area, the cycle map in
    # the dark behind it and the ride's charts in the light furthest back;
    # left of the copy, mostly outside the safe area, the ride under way
    # with its card folded down. All past the bottom edge.
    pad = 18
    scale = 0.66
    width = SCREEN_W * scale + 2 * pad
    front_left = x + w - width + 40
    front_top = y - 60
    stage = (phone(charts, width, front_left + 960, front_top + 170, 10, 0)
             + phone(back, width, front_left + 480, front_top - 40, 5, 1)
             + phone(front, width, front_left, front_top, 0, 2)
             + phone(ride, width, -80, y + 220, -7, 1)
             # Under the copy, across the safe area's lower edge, clear of
             # the front phone beside them: the time control and the rain's
             # key.
             + badge(front, below_save(TIME_CONTROL, front), 0.85, x + margin, y + h + 30, -2)
             + badge(front, below_save(RAIN_KEY, front), 1.25, x + margin + 260, y + h + 300, 2))
    css = (SEARCH_CSS % {"w": SEARCH_W, "h": SEARCH_H}).replace("FONTS", "file://" + FONTS)
    rings = contours(style, SEARCH_W, SEARCH_H, ((3300, 400, 160), (300, 2500, 220)),
                     step=250, reach=2000)
    outline = box(x, y, w, h, "#ff3b30", "art safe area 2168x1030") if debug else ""
    body = (f'<!doctype html><meta charset="utf-8"><style>{css}</style>'
            f'<body style="{tokens}">{backdrop}{rings}{text}{stage}{outline}</body>')
    return body, [front, back, ride, charts]


# Each image: its name, its size and how its page is made.
IMAGES = [
    ("universal", W, H, universal_page),
    ("search", SEARCH_W, SEARCH_H, search_page),
]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--locales", default="en,de,fr,es,it,nl")
    parser.add_argument("--raw", default=os.path.join(BUILD, "raw"))
    parser.add_argument("--out", default=os.path.join(BUILD, "creative"))
    parser.add_argument("--images", help="comma-separated: universal, search; default both")
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
            for image, w, h, make in IMAGES:
                if args.images and image not in args.images.split(","):
                    continue
                for name, debug in ((image, False), (f"{image}-debug", True)):
                    html_text, needs = make(args.raw, locale, debug)
                    absent = [n for n in needs if not os.path.isfile(n)]
                    if absent:
                        missing.update(absent)
                        break
                    page_file = os.path.join(work, f"{name}.html")
                    with open(page_file, "w", encoding="utf-8") as f:
                        f.write(html_text)
                    target = os.path.join(out, f"{name}.png")
                    photograph(page_file, target, w, h, work)
                    print(target)
    if missing:
        print("store_creative: missing input, those images were skipped:", file=sys.stderr)
        for path in sorted(missing):
            print(f"  {path}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
