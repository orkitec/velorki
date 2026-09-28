#!/usr/bin/env python3
"""Turns the raw store screenshots into the App Store slides.

    tool/store_slides.py [--locales en,de] [--sizes 6.9,6.5]
                         [--shots same|light|dark] [--watch DIR]

Each slide is an HTML page at the target resolution, laid out in vw so one
page serves every size, and photographed by headless Chrome. The look is the
website's hero: an eyebrow chip with an accent dot, a sentence-case headline
in Barlow Condensed with one phrase in the accent colour, a bold Manrope
subline, two soft accent glows over faint contour lines, and the screenshot in
a phone frame bleeding off the bottom edge. The fonts are the app's own.

What goes on a slide comes from store/:
* slides_<locale>.json: per slide an `eyebrow`, a `headline` (**phrase** is
  the accent) and a `subline`. English is the source, Crowdin writes the
  rest; a slide a translation lacks falls back to English, with a warning.
* slide_set.json: the set that is uploaded, in order. Per entry the slide,
  its `layout`, the raw `screen` it shows and the `style` it takes in the set.

Layouts: `phone` (one screenshot, running off the bottom edge), `whole` (one
screenshot, the phone sized to show all of it), `watch` (the phone with the Apple Watch
beside it), `lock` (the Lock Screen with the ride's Live Activity, drawn from
the app's own layout in ios/VelorkiLiveActivity and the figures the test
recorded) and `split` (the same screen light and dark, cut diagonally).

Every slide but a split one is made in both styles, `dark` and `light`, each
showing the app in the matching theme unless --shots says otherwise, so the
set can be re-mixed without a new capture. The set is then assembled from
them, with a contact sheet per locale.

Input:  build/store_screenshots/raw/<theme>/<locale>/<screen>.png (and
        activity.json), the watch screenshots in --watch/<locale>/2-riding.png
Output: build/store_screenshots/slides/<style>/<size>/<locale>/<slide>.png
        build/store_screenshots/slides/set/<size>/<locale>/NN-<slide>.png
        build/store_screenshots/slides/set/contact-<locale>.png
"""
import argparse
import datetime
import html
import json
import math
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time

APP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONTS = os.path.join(APP, "assets", "fonts")
STORE = os.path.join(APP, "store")
BUILD = os.path.join(APP, "build", "store_screenshots")
CHROME = os.environ.get(
    "CHROME", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
)

SIZES = {"6.9": (1320, 2868), "6.5": (1284, 2778)}

# The website's tokens (web/src/app/globals.css), per style.
STYLES = {
    "dark": {
        "canvas": "#0e1115", "deep": "#0a0d10", "fg": "#f1f3f5", "muted": "#aab2bc",
        "accent": "#c8f542", "glow": "rgb(200 245 66 / 0.24)",
        "soft": "rgb(200 245 66 / 0.14)", "line": "rgb(255 255 255 / 0.14)",
        "panel": "rgb(27 31 38 / 0.78)", "contour": "rgb(200 245 66 / 0.07)",
        "shadow": "0 6vw 14vw -4vw rgb(0 0 0 / 0.7)",
    },
    "light": {
        "canvas": "#f5f6f3", "deep": "#e9ebe6", "fg": "#14171a", "muted": "#5b636c",
        "accent": "#3f7a00", "glow": "rgb(63 122 0 / 0.20)",
        "soft": "rgb(63 122 0 / 0.12)", "line": "rgb(0 0 0 / 0.10)",
        "panel": "rgb(255 255 255 / 0.82)", "contour": "rgb(63 122 0 / 0.09)",
        "shadow": "0 5vw 12vw -5vw rgb(20 40 0 / 0.35)",
    },
}

CSS = """
@font-face { font-family: Barlow; src: url('FONTS/BarlowCondensed-Bold.ttf'); font-weight: 700; }
@font-face { font-family: Manrope; src: url('FONTS/Manrope-SemiBold.ttf'); font-weight: 600; }
@font-face { font-family: Manrope; src: url('FONTS/Manrope-Bold.ttf'); font-weight: 700; }
html, body { margin: 0; width: Wpx; height: Hpx; overflow: hidden; }
.layer { position: absolute; inset: 0; overflow: hidden; font-family: Manrope, sans-serif;
  background: linear-gradient(180deg, var(--canvas), var(--deep)); color: var(--fg); }
.aurora { position: absolute; inset: 0;
  background: radial-gradient(130vw 75vw at 12% -6%, var(--glow), transparent 62%),
              radial-gradient(95vw 60vw at 98% 2%, var(--soft), transparent 66%); }
.topo { position: absolute; inset: 0; width: 100%; height: 100%; }
.topo path { fill: none; stroke: var(--contour); stroke-width: 0.12; }
.copy { position: relative; padding: 8.4vw 7vw 0; }
.chip { display: inline-flex; align-items: center; gap: 1.7vw; padding: 1.5vw 3.4vw;
  border-radius: 999px; border: 0.22vw solid var(--line); background: var(--panel);
  font-size: 3.3vw; font-weight: 600; letter-spacing: 0.01em; }
.chip i { width: 1.9vw; height: 1.9vw; border-radius: 50%; background: var(--accent); }
h1 { font-family: Barlow, sans-serif; font-weight: 700; font-size: 13.6vw; line-height: 0.95;
  letter-spacing: -0.01em; margin: 4.4vw 0 0; text-wrap: balance; }
h1 em { font-style: normal; color: var(--accent); }
p.sub { font-size: 4.7vw; line-height: 1.3; margin: 3.8vw 0 0; font-weight: 700;
  max-width: 84vw; text-wrap: pretty; }
.stage { position: relative; margin-top: 7vw; height: 200vw; }
.phone { position: absolute; left: 50%; top: 0; width: 78vw; translate: -50% 0; padding: 2.1vw;
  border-radius: 11vw; background: linear-gradient(160deg, #2a3039, #0e1115 45%, #1b1f26);
  box-shadow: 0 0 0 0.25vw rgb(255 255 255 / 0.10), var(--shadow), 0 0 14vw -5vw var(--glow); }
.screen { position: relative; overflow: hidden; border-radius: 8.9vw; aspect-ratio: 1320 / 2868;
  background: #000; }
.screen > img { display: block; width: 100%; }
.watch-slide .phone { left: 41%; width: 70vw; }
.watch { position: absolute; right: 4vw; top: 46vw; width: 40vw; padding: 1.9vw; border-radius: 11.5vw;
  background: linear-gradient(160deg, #3a4048, #14171a 45%, #23282f);
  box-shadow: 0 0 0 0.25vw rgb(255 255 255 / 0.12), 0 5vw 10vw -3vw rgb(0 0 0 / 0.6),
    0 0 12vw -4vw var(--glow); }
.watch::after { content: ''; position: absolute; top: 28%; right: -0.9vw; width: 1.2vw; height: 7vw;
  border-radius: 999px; background: linear-gradient(90deg, #3a4048, #8b929b); }
.watch .face { overflow: hidden; border-radius: 9.6vw; background: #000; aspect-ratio: 422 / 514; }
.watch .face img { display: block; width: 100%; }
.missing { display: flex; height: 100%; align-items: center; justify-content: center; padding: 4vw;
  text-align: center; color: #aab2bc; font-size: 3vw;
  background: repeating-linear-gradient(135deg, rgb(255 255 255 / 0.05) 0 2vw, transparent 2vw 4vw), #0e1115; }
.seam { position: absolute; inset: 0; width: 100%; height: 100%; pointer-events: none; }
"""

# The Lock Screen, in fractions of the screen width (cqw): the wallpaper,
# the date and the clock, and the Live Activity card as RideLockScreenView
# lays it out; the expanded Dynamic Island as the widget's
# DynamicIslandExpandedRegion lays it out, floating above the phone.
LOCK_CSS = """
.lock { position: absolute; inset: 0;
  font-family: -apple-system, 'SF Pro Text', system-ui, sans-serif; color: #fff;
  background: radial-gradient(120% 60% at 30% 20%, #2d4a1a, transparent 70%),
              radial-gradient(90% 60% at 90% 90%, #1a3340, transparent 70%), #0b1210; }
.lock-inner { position: absolute; inset: 0; container-type: inline-size; }
.lock .icons { position: absolute; top: 6.2cqw; right: 8cqw; display: flex; gap: 1.6cqw; align-items: center; }
.lock .date { position: absolute; top: 25cqw; width: 100%; text-align: center; font-weight: 600;
  font-size: 4.6cqw; opacity: 0.9; }
.lock .clock { position: absolute; top: 29cqw; width: 100%; text-align: center; font-weight: 700;
  font-size: 30cqw; letter-spacing: -0.01em; font-family: 'SF Pro Rounded', -apple-system, system-ui;
  opacity: 0.95; }
.card { position: absolute; left: 3.6cqw; right: 3.6cqw; top: 68cqw; padding: 3.6cqw;
  border-radius: 5.5cqw; background: rgb(0 0 0 / 0.6); backdrop-filter: blur(20px); }
.card .big { display: flex; justify-content: space-between; align-items: baseline;
  font-family: 'SF Pro Rounded', -apple-system, system-ui; font-weight: 600; font-size: 9.1cqw;
  font-variant-numeric: tabular-nums; }
.card .row { display: flex; gap: 4.5cqw; margin-top: 2.7cqw; font-size: 3.4cqw; color: rgb(235 235 245 / 0.6);
  font-variant-numeric: tabular-nums; }
.card .row span, .island span.lbl { display: inline-flex; align-items: center; gap: 1.2cqw; }
.turn { display: flex; gap: 2.7cqw; align-items: center; margin-top: 2.7cqw; }
.turn .t1 { font-weight: 600; font-size: 3.9cqw; }
.turn .t2 { font-size: 2.7cqw; color: rgb(235 235 245 / 0.6); }
.lock .bottom { position: absolute; bottom: 7cqw; left: 11cqw; right: 11cqw; display: flex;
  justify-content: space-between; }
.lock .bottom b { width: 11.4cqw; height: 11.4cqw; border-radius: 50%; background: rgb(255 255 255 / 0.16);
  backdrop-filter: blur(10px); display: flex; align-items: center; justify-content: center; }
.lock .home { position: absolute; bottom: 1.8cqw; left: 50%; translate: -50% 0; width: 32cqw;
  height: 1.2cqw; border-radius: 999px; background: #fff; }
.lock .isl { position: absolute; top: 2.5cqw; left: 50%; translate: -50% 0; width: 28.5cqw; height: 8.4cqw;
  border-radius: 999px; background: #000; }
.island { position: absolute; left: 50%; translate: -50% 0; top: 0; width: 70vw; padding: 5vw 6vw 4.6vw;
  border-radius: 12vw; background: #000; color: #fff; container-type: inline-size;
  font-family: -apple-system, 'SF Pro Text', system-ui, sans-serif;
  box-shadow: 0 0 0 0.25vw rgb(255 255 255 / 0.10), 0 4vw 10vw -2vw rgb(0 0 0 / 0.6); z-index: 2; }
.island .top { display: flex; justify-content: space-between; align-items: flex-start; }
.island .d { font-weight: 600; font-size: 8.4cqw; font-variant-numeric: tabular-nums; }
.island .e, .island .h { font-size: 4.2cqw; color: rgb(235 235 245 / 0.6); margin-top: 0.6cqw;
  font-variant-numeric: tabular-nums; }
.island .s { font-weight: 500; font-size: 7cqw; text-align: right; font-variant-numeric: tabular-nums; }
.island .turn .t1 { font-size: 5.6cqw; }
.island .turn .t2 { font-size: 4cqw; }
.island .turn { margin-top: 3.4cqw; gap: 3.4cqw; }
"""

FIT_JS = """
// A translation longer than the English shrinks until it fits: the headline
// in three lines at most, the subline in two.
function fit(el, lines, floor) {
  let size = parseFloat(getComputedStyle(el).fontSize);
  const line = () => parseFloat(getComputedStyle(el).lineHeight);
  while (el.scrollHeight > line() * lines + 1 && size > floor) {
    size -= 1;
    el.style.fontSize = size + 'px';
  }
}
document.fonts.ready.then(() => {
  for (const h of document.querySelectorAll('h1')) fit(h, 3, W * 0.09);
  for (const p of document.querySelectorAll('p.sub')) fit(p, 2, W * 0.036);
  // A `whole` phone is sized to end just above the bottom edge, for a
  // screen whose bottom matters as much as its top.
  for (const phone of document.querySelectorAll('.phone.whole')) {
    const room = H - phone.getBoundingClientRect().top - W * 0.05;
    for (let i = 0; i < 2; i++) {
      phone.style.width = (phone.offsetWidth * room / phone.offsetHeight) + 'px';
    }
  }
});
"""

# Stand-ins for the SF Symbols the Live Activity uses, drawn at 1em.
SYMBOLS = {
    "clock": '<svg viewBox="0 0 24 24" width="1em" height="1em" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></svg>',
    "speedometer": '<svg viewBox="0 0 24 24" width="1em" height="1em" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 17a8 8 0 1 1 16 0"/><path d="M12 17l4-5"/></svg>',
    "heart": '<svg viewBox="0 0 24 24" width="1em" height="1em" fill="currentColor"><path d="M12 21s-7.5-4.6-9.5-9.2C1.2 8.7 3.3 5 6.8 5c2.1 0 3.6 1.2 5.2 3 1.6-1.8 3.1-3 5.2-3 3.5 0 5.6 3.7 4.3 6.8C19.5 16.4 12 21 12 21z"/></svg>',
    "left": '<svg viewBox="0 0 24 24" width="1em" height="1em" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M17 21V11a3 3 0 0 0-3-3H5"/><path d="M9 4L5 8l4 4"/></svg>',
    "right": '<svg viewBox="0 0 24 24" width="1em" height="1em" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M7 21V11a3 3 0 0 1 3-3h9"/><path d="M15 4l4 4-4 4"/></svg>',
    "straight": '<svg viewBox="0 0 24 24" width="1em" height="1em" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M12 21V4"/><path d="M7 9l5-5 5 5"/></svg>',
    "bicycle": '<svg viewBox="0 0 24 24" width="1em" height="1em" fill="none" stroke="currentColor" stroke-width="2"><circle cx="6" cy="16" r="4"/><circle cx="18" cy="16" r="4"/><path d="M6 16l4-8h5l3 8M10 8l3 8"/></svg>',
    "signal": '<svg viewBox="0 0 20 12" height="0.8em"><rect x="0" y="8" width="3.4" height="4" rx="1" fill="#fff"/><rect x="5.2" y="5.5" width="3.4" height="6.5" rx="1" fill="#fff"/><rect x="10.4" y="3" width="3.4" height="9" rx="1" fill="#fff"/><rect x="15.6" y="0" width="3.4" height="12" rx="1" fill="#fff"/></svg>',
    "wifi": '<svg viewBox="0 0 18 13" height="0.8em" fill="#fff"><path d="M9 13l3-3.6a4.6 4.6 0 0 0-6 0zM2.2 6.4a10 10 0 0 1 13.6 0l1.6-1.9A12.6 12.6 0 0 0 .6 4.5zM4.4 9a7 7 0 0 1 9.2 0l1.6-1.9a9.6 9.6 0 0 0-12.4 0z"/></svg>',
    "battery": '<svg viewBox="0 0 28 13" height="0.8em"><rect x="0.5" y="0.5" width="24" height="12" rx="3.5" fill="none" stroke="#fff" stroke-opacity="0.45"/><rect x="2" y="2" width="21" height="9" rx="2.2" fill="#fff"/><path d="M26 4.5v4a2 2 0 0 0 0-4z" fill="#fff" fill-opacity="0.45"/></svg>',
    "torch": '<svg viewBox="0 0 24 24" width="1.4em" height="1.4em" fill="none" stroke="#fff" stroke-width="1.8"><path d="M8 3h8v4l-2 3v10h-4V10L8 7z"/></svg>',
    "camera": '<svg viewBox="0 0 24 24" width="1.4em" height="1.4em" fill="none" stroke="#fff" stroke-width="1.8"><rect x="3" y="7" width="18" height="13" rx="3"/><circle cx="12" cy="13.5" r="3.5"/><path d="M9 7l1.5-2.5h3L15 7"/></svg>',
}


def turn_symbol(name: str) -> str:
    if "left" in name:
        return SYMBOLS["left"]
    if "right" in name:
        return SYMBOLS["right"]
    return SYMBOLS["straight"] if name else SYMBOLS["bicycle"]


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


TOPO = contours()


def rich(text: str) -> str:
    """HTML for a headline: escaped, with **phrase** as the accent."""
    return re.sub(r"\*\*(.+?)\*\*", r"<em>\1</em>", html.escape(text))


def url(path: str) -> str:
    return "file://" + os.path.abspath(path)


def image_or_missing(path: str) -> str:
    if os.path.isfile(path):
        return f'<img src="{url(path)}">'
    return f'<div class="missing">missing: {html.escape(os.path.relpath(path, APP))}</div>'


def lock_screen(activity: dict, locale: str) -> tuple[str, str]:
    """The phone's screen and the floating Dynamic Island for a `lock` slide."""
    a = {k: html.escape(str(v)) for k, v in activity.items()}
    ride_day = datetime.date(2026, 9, 20)
    date = ride_day.strftime("%A, %-d %B") if locale == "en" else None
    if locale == "de":
        days = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"]
        date = f"{days[ride_day.weekday()]}, {ride_day.day}. September"
    heart = a.get("heartRate", "")
    turn = ""
    if a.get("turnLabel") and a.get("turnIcon"):
        turn = (f'<div class="turn"><span style="font-size:6cqw">{turn_symbol(activity["turnIcon"])}</span>'
                f'<div><div class="t1">{a["turnLabel"]}</div>'
                f'<div class="t2">{a.get("turnDistance", "")}</div></div></div>')
    card = (
        f'<div class="card"><div class="big"><span>{a["distance"]}</span></div>'
        f'<div class="row"><span>{SYMBOLS["clock"]}{a["elapsed"]}</span>'
        f'<span>{SYMBOLS["speedometer"]}{a["speed"]}</span>'
        + (f'<span>{SYMBOLS["heart"]}{heart}</span>' if heart else "")
        + f"</div>{turn}</div>"
    )
    screen = (
        '<div class="lock"><div class="lock-inner">'
        f'<div class="isl"></div><div class="icons" style="font-size:4.2cqw">'
        f'{SYMBOLS["signal"]}{SYMBOLS["wifi"]}{SYMBOLS["battery"]}</div>'
        f'<div class="date">{date}</div><div class="clock">9:41</div>{card}'
        f'<div class="bottom"><b>{SYMBOLS["torch"]}</b><b>{SYMBOLS["camera"]}</b></div>'
        '<div class="home"></div></div></div>'
    )
    island = (
        '<div class="island"><div class="top">'
        f'<div><div class="d">{a["distance"]}</div><div class="e">{a["elapsed"]}</div></div>'
        f'<div><div class="s">{a["speed"]}</div>'
        + (f'<div class="h" style="text-align:right"><span class="lbl">{SYMBOLS["heart"]}{heart}</span></div>' if heart else "")
        + f"</div></div>{turn}</div>"
    )
    return screen, island


def layer(style: str, text: dict, stage: str, extra_class: str = "", clip: str = "") -> str:
    tokens = STYLES[style]
    variables = ";".join(f"--{k}:{v}" for k, v in tokens.items())
    return (
        f'<div class="layer {extra_class}" style="{variables};{clip}">'
        f'<div class="aurora"></div>{TOPO}'
        f'<div class="copy"><div class="chip"><i></i>{html.escape(text["eyebrow"])}</div>'
        f'<h1>{rich(text["headline"])}</h1><p class="sub">{html.escape(text["subline"])}</p></div>'
        f'<div class="stage">{stage}</div></div>'
    )


def page(w: int, h: int, body: str) -> str:
    css = (CSS + LOCK_CSS).replace("FONTS", "file://" + FONTS).replace("Wpx", f"{w}px").replace("Hpx", f"{h}px")
    js = FIT_JS.replace("W *", f"{w} *").replace("H -", f"{h} -")
    return (f'<!doctype html><html><head><meta charset="utf-8"><style>{css}</style></head>'
            f"<body>{body}<script>{js}</script></body></html>")


def slide_html(layout: str, style: str, text: dict, raw: str, screen: str, theme: str,
               locale: str, watch: str, w: int, h: int) -> tuple[str, list[str]]:
    """The page for one slide, and the input files it needs."""
    needs = []
    if layout == "split":
        light = os.path.join(raw, "light", locale, f"{screen}.png")
        dark = os.path.join(raw, "dark", locale, f"{screen}.png")
        needs = [light, dark]
        # The seam runs from (x0, 0) to (x1, h) across the whole slide; the
        # dark layer is everything right of it, the phone's screen included,
        # so the copy and the app switch theme along one line.
        x0, x1 = 0.66, 0.34
        clip = f"clip-path: polygon({x0 * 100}% 0, 100% 0, 100% 100%, {x1 * 100}% 100%)"
        body = (layer("light", text, f'<div class="phone"><div class="screen">{image_or_missing(light)}</div></div>')
                + layer("dark", text, f'<div class="phone"><div class="screen">{image_or_missing(dark)}</div></div>',
                        clip=clip)
                + f'<svg class="seam" viewBox="0 0 {w} {h}"><line x1="{x0 * w}" y1="0" x2="{x1 * w}" y2="{h}" '
                  f'stroke="#c8f542" stroke-opacity="0.9" stroke-width="{w * 0.0035}"/></svg>')
        return page(w, h, body), needs
    if layout == "lock":
        data = os.path.join(raw, theme, locale, f"{screen}.json")
        needs = [data]
        if not os.path.isfile(data):
            return "", needs
        with open(data, encoding="utf-8") as f:
            activity = json.load(f)
        screen_html, island = lock_screen(activity, locale)
        # The island floats above the phone, the way it opens out of the
        # top of the screen when the ride is running behind another app.
        stage = (f'{island}<div class="phone" style="top:31vw">'
                 f'<div class="screen">{screen_html}</div></div>')
        return page(w, h, layer(style, text, stage)), needs
    shot = os.path.join(raw, theme, locale, f"{screen}.png")
    needs = [shot]
    whole = " whole" if layout == "whole" else ""
    phone = f'<div class="phone{whole}"><div class="screen">{image_or_missing(shot)}</div></div>'
    if layout == "watch":
        face = os.path.join(watch, locale, "2-riding.png")
        stage = phone + f'<div class="watch"><div class="face">{image_or_missing(face)}</div></div>'
        return page(w, h, layer(style, text, stage, "watch-slide")), needs
    return page(w, h, layer(style, text, phone)), needs


def photograph(page_file: str, target: str, w: int, h: int, work: str) -> None:
    """Has headless Chrome save [page_file] as [target] at w x h.

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
         f"--window-size={w},{h}", f"--screenshot={target}", "file://" + page_file],
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


def render(html_text: str, target: str, w: int, h: int, work: str) -> None:
    page_file = os.path.join(work, "slide.html")
    with open(page_file, "w", encoding="utf-8") as f:
        f.write(html_text)
    os.makedirs(os.path.dirname(target), exist_ok=True)
    photograph(page_file, target, w, h, work)
    print(target)


def load_json(path: str):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--locales", help="comma-separated; default: every slides_*.json")
    parser.add_argument("--sizes", default=",".join(SIZES))
    parser.add_argument("--shots", default="same", choices=["same", "light", "dark"],
                        help="which app theme each style shows")
    parser.add_argument("--raw", default=os.path.join(BUILD, "raw"))
    parser.add_argument("--watch", default=os.path.join(BUILD, "watch"),
                        help="the watch screenshots, <locale>/2-riding.png")
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
            m.group(1) for m in (re.match(r"slides_(.+)\.json$", n) for n in os.listdir(STORE)) if m
        )
    sizes = args.sizes.split(",")
    for name in sizes:
        if name not in SIZES:
            print(f"store_slides: unknown size {name!r}", file=sys.stderr)
            return 2

    english = load_json(os.path.join(STORE, "slides_en.json"))
    chosen = load_json(os.path.join(STORE, "slide_set.json"))
    missing = set()
    made = 0
    with tempfile.TemporaryDirectory() as work:
        for locale in locales:
            copy = load_json(os.path.join(STORE, f"slides_{locale}.json"))
            for entry in chosen:
                slide = entry["slide"]
                text = copy.get(slide)
                if text is None:
                    print(f"store_slides: warning: {locale} has no {slide}; using English")
                    text = english[slide]
                styles = ["split"] if entry["layout"] == "split" else ["dark", "light"]
                for style in styles:
                    theme = style if args.shots == "same" else args.shots
                    for size in sizes:
                        w, h = SIZES[size]
                        markup, needs = slide_html(entry["layout"], style, text, args.raw,
                                                   entry["screen"], theme, locale, args.watch, w, h)
                        absent = [n for n in needs if not os.path.isfile(n)]
                        if absent:
                            missing.update(absent)
                            continue
                        render(markup, os.path.join(args.out, style, size, locale, f"{slide}.png"),
                               w, h, work)
                        made += 1

            # The set: the chosen style of each slide, numbered in order.
            for size in sizes:
                folder = os.path.join(args.out, "set", size, locale)
                if os.path.isdir(folder):
                    shutil.rmtree(folder)
                os.makedirs(folder)
                for n, entry in enumerate(chosen, 1):
                    source = os.path.join(args.out, entry["style"], size, locale, f"{entry['slide']}.png")
                    if os.path.isfile(source):
                        shutil.copyfile(source, os.path.join(folder, f"{n:02d}-{entry['slide']}.png"))
            # The contact sheet: the 6.9" set small, side by side.
            folder = os.path.join(args.out, "set", sizes[0], locale)
            images = "".join(
                f'<img src="{url(os.path.join(folder, n))}">' for n in sorted(os.listdir(folder))
            )
            sheet = (
                '<!doctype html><html><head><style>html,body{margin:0;background:#6b7078}'
                'body{display:flex;gap:16px;padding:24px;width:max-content}'
                'img{width:300px;border-radius:14px;display:block}</style></head>'
                f"<body>{images}</body></html>"
            )
            count = len(os.listdir(folder))
            render(sheet, os.path.join(args.out, "set", f"contact-{locale}.png"),
                   48 + count * 300 + max(0, count - 1) * 16, 48 + 652, work)
    if missing:
        print("store_slides: missing input, those slides were skipped:", file=sys.stderr)
        for path in sorted(missing):
            print(f"  {path}", file=sys.stderr)
        return 1
    print(f"store_slides: {made} slides in {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
