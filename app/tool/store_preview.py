#!/usr/bin/env python3
"""Cuts the App Store preview video out of the recorded clips.

    tool/store_preview.py [--locales en,de] [--clips DIR] [--out DIR]

tool/store_screenshots.sh --preview records the clips (see
integration_test/store/store_preview_test.dart); this puts them together as
store/preview_set.json says: per clip its theme, the slide whose eyebrow and
headline caption it, and how many seconds it gets.

Each clip is the app's screen, scaled whole into the lower part of the
frame, under a caption band in the slides' style (tool/store_slides.py): the
same ground, glows, contour lines, eyebrow chip and headline. The band is a
picture with a transparent window where the app shows through, rendered by
headless Chrome. A clip longer than its seconds is played up to 1.5 times as
fast, and then its end is kept, which is where each clip shows its result.
The clips are joined by 0.3 s crossfades.

What App Store Connect takes for the 6.9", 6.5", 6.3" and 6.1" iPhone slots:
886 x 1920 portrait, 15 to 30 s, up to 30 fps, H.264 High Profile level 4.0 at
11 Mbit/s constant, with a stereo AAC track at 256 kbit/s; here a silent one.

Output: <out>/<locale>/preview.mp4, poster.png (the end of the first clip)
and frames/ (stills at 0, 3, 8, 13, 18 and 23 s, for looking at).
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
STILLS = (0, 3, 8, 13, 18, 23)

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


def duration(path: str) -> float:
    out = subprocess.run(
        [FFPROBE, "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
        check=True, capture_output=True, text=True,
    )
    return float(out.stdout.strip())


def run(args: list[str]) -> None:
    subprocess.run([FFMPEG, "-hide_banner", "-loglevel", "error", "-y", *args], check=True)


def segment(clip: str, band: str, seconds: float, target: str) -> None:
    """One clip, [seconds] long, in its band, lossless enough to cut again."""
    # The recorder's first frames can still be the last state before it.
    lead = 0.25
    length = duration(clip) - lead
    speed = min(MAX_SPEED, max(1.0, length / seconds))
    start = lead + max(0.0, length - seconds * speed)
    graph = (
        f"[0:v]trim=start={start:.3f},setpts=(PTS-STARTPTS)/{speed:.4f},fps=30,"
        f"scale={SCREEN_W}:{SCREEN_H}:flags=lanczos,"
        f"pad={W}:{H}:{LEFT}:{TOP}:color=black,trim=duration={seconds:.3f},"
        f"setpts=PTS-STARTPTS[app];[app][1:v]overlay=0:0:format=auto,format=yuv420p[v]"
    )
    run(["-i", clip, "-loop", "1", "-i", band, "-filter_complex", graph, "-map", "[v]",
         "-t", f"{seconds:.3f}", "-r", "30", "-c:v", "libx264", "-crf", "10",
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
    parser.add_argument("--clips", default=os.path.join(BUILD, "raw", "preview"))
    parser.add_argument("--out", default=os.path.join(BUILD, "preview"))
    args = parser.parse_args()
    for tool in (FFMPEG, FFPROBE):
        if not os.access(tool, os.X_OK):
            print(f"store_preview: no {tool}; install ffmpeg or set FFMPEG and FFPROBE",
                  file=sys.stderr)
            return 1

    chosen = slides.load_json(os.path.join(STORE, "preview_set.json"))
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
                page = os.path.join(work, "band.html")
                with open(page, "w", encoding="utf-8") as f:
                    f.write(band_page(entry["theme"], text))
                band = os.path.join(work, f"{locale}-{n}.png")
                slides.photograph(page, band, W, H, work, transparent=True)
                part = os.path.join(work, f"{locale}-{n}.mp4")
                segment(clip, band, float(entry["seconds"]), part)
                parts.append((part, float(entry["seconds"])))
            video = os.path.join(out, "preview.mp4")
            total = join(parts, video)
            # The poster: the first clip's result, just before the first fade.
            run(["-ss", f"{parts[0][1] - FADE - 0.2:.2f}", "-i", video, "-frames:v", "1",
                 os.path.join(out, "poster.png")])
            for t in STILLS:
                if t < total:
                    run(["-ss", str(t), "-i", video, "-frames:v", "1",
                         os.path.join(out, "frames", f"t{t:02d}.png")])
            print(f"store_preview: {video} ({total:.1f} s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
