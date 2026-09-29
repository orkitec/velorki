#!/usr/bin/env python3
"""Cuts the App Store preview video out of the recorded clips.

    tool/store_preview.py [--locales en] [--frame none|phone] [--clips DIR] [--out DIR]

tool/store_screenshots.sh --preview records the clips (see
integration_test/store/store_preview_test.dart); this puts them together as
store/preview_set.json says: the framing, the clip the poster is taken from,
and per clip, in the order they play, its theme, the slide whose eyebrow and
headline caption it, where the caption sits and how many seconds it gets.

Two framings of the same footage:
* `none`: the app full-bleed at 886 x 1920, with the caption on a floating
  frosted card in the slides' palette, near the top or the bottom: the app
  behind it blurred and tinted, a hairline border and a soft shadow. It
  slides and fades in at the start of a clip and fades out before the
  crossfade. A top card ends above the planner's bike chips; a bottom one
  above the figures bar.
* `phone`: the app scaled whole into the lower part of the frame under the
  caption, on the slides' ground, as on the slides.

A clip longer than its seconds is played up to 1.5 times as fast, and then
its end is kept, which is where each clip shows its result. The clips are
joined by 0.3 s crossfades.

What App Store Connect takes for the 6.9", 6.5", 6.3" and 6.1" iPhone slots:
886 x 1920 portrait, 15 to 30 s, up to 30 fps, H.264 High Profile level 4.0 at
11 Mbit/s constant, with a stereo AAC track at 256 kbit/s; here a silent one.

Output: <out>/<locale>/preview.mp4 (preview-<frame>.mp4 for a --frame other
than the set's), poster.png, and frames/ (stills every few seconds).
"""
import argparse
import html
import json
import os
import subprocess
import sys
import tempfile

import store_slides as slides

APP = slides.APP
STORE = slides.STORE
BUILD = slides.BUILD
FFMPEG = os.environ.get("FFMPEG", "/opt/homebrew/bin/ffmpeg")
FFPROBE = os.environ.get("FFPROBE", "/opt/homebrew/bin/ffprobe")

W, H = 886, 1920
# Where the app's screen goes: its whole width fits between the margins, its
# top below the caption band, and its bottom runs off the frame.
TOP = 330
SCREEN_W = 732
SCREEN_H = round(SCREEN_W * 2868 / 1320) // 2 * 2
LEFT = (W - SCREEN_W) // 2
RADIUS = 46
FADE = 0.3
MAX_SPEED = 1.5
STILLS = (0.5, 2, 5, 9, 13, 17, 21, 24)

# The full-bleed caption card: a frosted card like a notification, inset by
# MARGIN, with the eyebrow chip and a headline of up to two lines. A top card
# sits between the status bar and the planner's bike chips (they start at
# 285), and is wide and tall enough to cover the search field (24 to 862
# across, down to 256), whose edges would otherwise show round it; a bottom
# card ends above the figures bar (from 1630) with a gap.
MARGIN = 36
MARGIN_TOP = 18
TOP_MIN_END = 262
RADIUS_CARD = 40
TOP_CARD = (44, 272)
BOTTOM_CARD_END = 1598
SLIDE_PX = 26
CARD_IN = 0.35
CARD_OUT = 0.25
BLUR = 26
TINT = {"dark": "rgb(14 17 21 / 0.76)", "light": "rgb(245 246 243 / 0.82)"}

CARD_CSS = """
html, body { margin: 0; width: 886px; height: 1920px; background: transparent; overflow: hidden; }
.card { position: absolute; left: MARGINpx; right: MARGINpx; box-sizing: border-box;
  padding: 26px 30px 30px; border-radius: RADIUSpx; font-family: Manrope, sans-serif;
  background: var(--tint); color: var(--fg); border: 1.5px solid var(--line);
  box-shadow: 0 18px 44px -12px rgb(0 0 0 / 0.45), 0 2px 8px rgb(0 0 0 / 0.18); }
.card.top { top: TOPpx; left: EDGEpx; right: EDGEpx; min-height: MINHpx;
  display: flex; flex-direction: column; justify-content: center; align-items: flex-start; }
.card.bottom { bottom: BOTTOMpx; }
.chip { display: inline-flex; align-items: center; gap: 10px; padding: 7px 17px; border-radius: 999px;
  border: 1.5px solid var(--line); background: var(--panel); font-size: 23px; font-weight: 600; }
.chip i { width: 12px; height: 12px; border-radius: 50%; background: var(--accent); }
h1 { font-family: Barlow, sans-serif; font-weight: 700; font-size: 80px; line-height: 0.95;
  letter-spacing: -0.01em; margin: 12px 0 0; text-wrap: balance; }
h1 em { font-style: normal; color: var(--accent); }
/* The mask: the card's shape alone, white on black. */
body.mask { background: #000; }
body.mask .card { background: #fff; border-color: #fff; box-shadow: none; }
body.mask .card * { visibility: hidden; }
"""

BAND_CSS = """
.copy { padding: 52px 56px 0; }
.chip { gap: 11px; padding: 9px 20px; font-size: 25px; border-width: 1.5px; }
.chip i { width: 13px; height: 13px; }
h1 { font-size: 86px; line-height: 0.95; margin: 20px 0 0; max-width: 780px; }
.layer { -webkit-mask: url("MASK"); mask: url("MASK"); }
"""


def window_mask() -> str:
    """An SVG mask, opaque everywhere but the app's window."""
    path = (
        f"M0 0H{W}V{H}H0Z "
        f"M{LEFT + RADIUS} {TOP}H{LEFT + SCREEN_W - RADIUS}"
        f"A{RADIUS} {RADIUS} 0 0 1 {LEFT + SCREEN_W} {TOP + RADIUS}"
        f"V{H + 10}H{LEFT}V{TOP + RADIUS}A{RADIUS} {RADIUS} 0 0 1 {LEFT + RADIUS} {TOP}Z"
    )
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}">'
           f'<path fill-rule="evenodd" fill="#000" d="{path}"/></svg>')
    return "data:image/svg+xml;utf8," + svg.replace('"', "'").replace("#", "%23")


def band_page(style: str, text: dict) -> str:
    tokens = ";".join(f"--{k}:{v}" for k, v in slides.STYLES[style].items())
    css = (slides.CSS.replace("FONTS", "file://" + slides.FONTS)
           .replace("Wpx", f"{W}px").replace("Hpx", f"{H}px")
           + BAND_CSS.replace("MASK", window_mask()))
    body = (
        f'<div class="layer" style="{tokens}"><div class="aurora"></div>{slides.TOPO}'
        f'<div class="copy"><div class="chip"><i></i>{html.escape(text["eyebrow"])}</div>'
        f'<h1>{slides.rich(text["headline"])}</h1></div></div>'
    )
    fit = """
document.fonts.ready.then(() => {
  const h = document.querySelector('h1');
  let size = parseFloat(getComputedStyle(h).fontSize);
  while (h.scrollHeight > parseFloat(getComputedStyle(h).lineHeight) * 2 + 1 && size > 56) {
    size -= 1;
    h.style.fontSize = size + 'px';
  }
});"""
    return (f'<!doctype html><html><head><meta charset="utf-8"><style>{css}'
            f"html, body {{ background: transparent; }}</style></head>"
            f"<body>{body}<script>{fit}</script></body></html>")


def card_page(style: str, text: dict, where: str, mask: bool = False) -> str:
    """The caption card for the full-bleed framing, alone on a transparent
    frame, or with [mask] its shape in white on black. The headline takes two
    lines at most, and shrinks until the card fits its place."""
    tokens = ";".join(f"--{k}:{v}" for k, v in slides.STYLES[style].items())
    fonts = slides.CSS[:slides.CSS.index("html, body")].replace("FONTS", "file://" + slides.FONTS)
    css = fonts + (CARD_CSS.replace("MARGINpx", f"{MARGIN}px").replace("RADIUSpx", f"{RADIUS_CARD}px")
                   .replace("TOPpx", f"{TOP_CARD[0]}px")
                   .replace("EDGEpx", f"{MARGIN_TOP}px")
                   .replace("MINHpx", f"{TOP_MIN_END - TOP_CARD[0]}px")
                   .replace("BOTTOMpx", f"{H - BOTTOM_CARD_END}px"))
    body = (
        f'<div class="card {where}" style="{tokens};--tint:{TINT[style]}">'
        f'<div class="chip"><i></i>{html.escape(text["eyebrow"])}</div>'
        f'<h1>{slides.rich(text["headline"])}</h1></div>'
    )
    limit = TOP_CARD[1] if where == "top" else 0
    fit = f"""
document.fonts.ready.then(() => {{
  const h = document.querySelector('h1');
  const card = document.querySelector('.card');
  let size = parseFloat(getComputedStyle(h).fontSize);
  const tooBig = () =>
    h.scrollHeight > parseFloat(getComputedStyle(h).lineHeight) * 2 + 1 ||
    ({limit} > 0 && card.getBoundingClientRect().bottom > {limit});
  while (tooBig() && size > 40) {{
    size -= 1;
    h.style.fontSize = size + 'px';
  }}
}});"""
    return (f'<!doctype html><html><head><meta charset="utf-8"><style>{css}</style></head>'
            f'<body class="{"mask" if mask else ""}">{body}<script>{fit}</script></body></html>')


def duration(path: str) -> float:
    out = subprocess.run(
        [FFPROBE, "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
        check=True, capture_output=True, text=True,
    )
    return float(out.stdout.strip())


def run(args: list[str]) -> None:
    subprocess.run([FFMPEG, "-hide_banner", "-loglevel", "error", "-y", *args], check=True)


def segment(clip: str, band: str, seconds: float, frame: str, target: str,
            first: bool = False, last: bool = False, where: str = "top",
            mask: str | None = None) -> None:
    """One clip, [seconds] long, with its caption, lossless enough to cut
    again. [band] is the caption picture; for the full-bleed framing [mask]
    is the card's shape, where the app behind it is frosted."""
    # The recorder's first frames can still be the last state before it.
    lead = 0.25
    length = duration(clip) - lead
    speed = min(MAX_SPEED, max(1.0, length / seconds))
    start = lead + max(0.0, length - seconds * speed)
    # A clip shorter than its seconds holds its last frame; a crossfade
    # past the end of one of its inputs would cut the video short.
    timing = (f"trim=start={start:.3f},setpts=(PTS-STARTPTS)/{speed:.4f},fps=30,"
              f"tpad=stop_mode=clone:stop_duration={seconds:.3f}")
    if length < seconds:
        print(f"store_preview: warning: {os.path.basename(clip)} is {length:.1f} s, "
              f"shorter than its {seconds} s; its last frame is held")
    inputs = ["-i", clip, "-loop", "1", "-framerate", "30", "-i", band]
    if frame == "phone":
        graph = (
            f"[0:v]{timing},scale={SCREEN_W}:{SCREEN_H}:flags=lanczos,"
            f"pad={W}:{H}:{LEFT}:{TOP}:color=black,trim=duration={seconds:.3f},"
            f"setpts=PTS-STARTPTS[app];[app][1:v]overlay=0:0:format=auto,format=yuv420p[v]"
        )
    else:
        inputs += ["-loop", "1", "-framerate", "30", "-i", mask]
        # The card slides in from its edge with an ease-out and fades in
        # over the same time, holds, and fades out before the crossfade; the
        # first clip's card is there from the first frame, and the last
        # clip's stays to the end.
        sign = -1 if where == "top" else 1
        if first:
            dy = "0"
        else:
            dy = f"{sign * SLIDE_PX}*pow(1-min(t/{CARD_IN},1),3)"
        fades = []
        if not first:
            fades.append(f"fade=t=in:st=0:d={CARD_IN}")
        if not last:
            fades.append(f"fade=t=out:st={seconds - FADE - CARD_OUT:.3f}:d={CARD_OUT}")
        alpha_fades = ",".join(f + ":alpha=1" for f in fades)
        luma_fades = ",".join(fades)
        graph = (
            # The whole screen, 1320 x 2868 scaled to the frame's width,
            # loses six rows of the home indicator at the bottom.
            f"[0:v]{timing},scale={W}:-2:flags=lanczos,crop={W}:{H}:0:0,"
            f"trim=duration={seconds:.3f},setpts=PTS-STARTPTS,format=yuv444p,split[app][under];"
            f"[under]gblur=sigma={BLUR}[frost];"
            f"color=black:s={W}x{H}:r=30:d={seconds:.3f}[canvas];"
            f"[2:v]format=gray[shape];"
            f"[canvas][shape]overlay=x=0:y='{dy}':eval=frame:shortest=1,format=gray"
            f"{',' + luma_fades if luma_fades else ''}[moving];"
            f"[frost][moving]alphamerge[glass];"
            f"[1:v]format=rgba{',' + alpha_fades if alpha_fades else ''}[card];"
            f"[app][glass]overlay=0:0:format=auto[frosted];"
            f"[frosted][card]overlay=x=0:y='{dy}':eval=frame:format=auto:shortest=1,"
            f"format=yuv420p[v]"
        )
    run([*inputs, "-filter_complex", graph,
         "-map", "[v]", "-t", f"{seconds:.3f}", "-r", "30", "-c:v", "libx264", "-crf", "10",
         "-preset", "medium", target])
    print(f"store_preview: {os.path.basename(clip)} {length:.1f} s at {speed:.2f}x "
          f"-> {seconds} s")


def join(parts: list[tuple[str, float]], target: str) -> float:
    """Crossfades [parts] into the final encode; hands back its length."""
    inputs, graph = [], []
    for path, _ in parts:
        inputs += ["-i", path]
    label, offset = "[0:v]", 0.0
    for i in range(1, len(parts)):
        offset += parts[i - 1][1] - FADE
        out = f"[x{i}]"
        graph.append(f"{label}[{i}:v]xfade=transition=fade:duration={FADE}:offset={offset:.3f}{out}")
        label = out
    total = offset + parts[-1][1]
    graph.append(f"{label}format=yuv420p[v]")
    run([*inputs, "-f", "lavfi", "-t", f"{total:.3f}",
         "-i", "anullsrc=channel_layout=stereo:sample_rate=48000",
         "-filter_complex", ";".join(graph), "-map", "[v]", "-map", f"{len(parts)}:a",
         "-r", "30", "-c:v", "libx264", "-profile:v", "high", "-level", "4.0",
         "-pix_fmt", "yuv420p",
         # Apple's target is 10 to 12 Mbit/s; a variable rate falls far below
         # it on the calm clips, so the rate is held at 11.
         "-b:v", "11M", "-minrate", "11M", "-maxrate", "11M", "-bufsize", "11M",
         "-x264-params", "nal-hrd=cbr",
         "-c:a", "aac", "-b:a", "256k", "-ar", "48000", "-ac", "2",
         "-t", f"{total:.3f}", "-movflags", "+faststart", target])
    return total


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--locales", default="en,de")
    parser.add_argument("--frame", choices=["none", "phone"],
                        help="the framing; default: the set's")
    parser.add_argument("--clips", default=os.path.join(BUILD, "raw", "preview"))
    parser.add_argument("--out", default=os.path.join(BUILD, "preview"))
    args = parser.parse_args()
    for tool in (FFMPEG, FFPROBE):
        if not os.access(tool, os.X_OK):
            print(f"store_preview: no {tool}; install ffmpeg or set FFMPEG and FFPROBE",
                  file=sys.stderr)
            return 1

    preview_set = slides.load_json(os.path.join(STORE, "preview_set.json"))
    chosen = preview_set["clips"]
    frame = args.frame or preview_set.get("frame", "none")
    name = "preview.mp4" if frame == preview_set.get("frame", "none") else f"preview-{frame}.mp4"
    english = slides.load_json(os.path.join(STORE, "slides_en.json"))
    with tempfile.TemporaryDirectory() as work:
        for locale in args.locales.split(","):
            copy = slides.load_json(os.path.join(STORE, f"slides_{locale}.json"))
            out = os.path.join(args.out, locale)
            os.makedirs(os.path.join(out, "frames"), exist_ok=True)
            parts = []
            for n, entry in enumerate(chosen):
                clip = os.path.join(args.clips, locale, f"{entry['clip']}.mp4")
                if not os.path.isfile(clip):
                    print(f"store_preview: missing {clip}; record it first", file=sys.stderr)
                    return 1
                text = copy.get(entry["slide"]) or english[entry["slide"]]
                where = entry.get("caption", "top")
                page = os.path.join(work, "band.html")
                band = os.path.join(work, f"{locale}-{n}.png")
                shape = None
                with open(page, "w", encoding="utf-8") as f:
                    if frame == "phone":
                        f.write(band_page(entry["theme"], text))
                    else:
                        f.write(card_page(entry["theme"], text, where))
                slides.photograph(page, band, W, H, work, transparent=True)
                if frame != "phone":
                    with open(page, "w", encoding="utf-8") as f:
                        f.write(card_page(entry["theme"], text, where, mask=True))
                    shape = os.path.join(work, f"{locale}-{n}-mask.png")
                    slides.photograph(page, shape, W, H, work)
                part = os.path.join(work, f"{locale}-{n}.mp4")
                # The first clip opens with its caption already there: the
                # video starts muted, and its first second has to say it.
                segment(clip, band, float(entry["seconds"]), frame, part,
                        first=n == 0, last=n == len(chosen) - 1, where=where, mask=shape)
                parts.append((part, float(entry["seconds"])))
            video = os.path.join(out, name)
            total = join(parts, video)
            # The poster: the end of the poster clip, just before its fade out.
            poster = preview_set.get("poster", chosen[0]["clip"])
            at, end = 0.0, 0.0
            for i, entry in enumerate(chosen):
                end = at + float(entry["seconds"])
                if entry["clip"] == poster:
                    break
                at = end - FADE
            suffix = "" if name == "preview.mp4" else f"-{frame}"
            run(["-ss", f"{end - FADE - 0.2:.2f}", "-i", video, "-frames:v", "1",
                 os.path.join(out, f"poster{suffix}.png")])
            for t in STILLS:
                if t < total:
                    run(["-ss", str(t), "-i", video, "-frames:v", "1",
                         os.path.join(out, "frames", f"{frame}-t{t:04.1f}.png")])
            print(f"store_preview: {video} ({total:.1f} s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
