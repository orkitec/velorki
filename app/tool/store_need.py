#!/usr/bin/env python3
"""The store pictures a platform's capture has to take.

    tool/store_need.py <platform>     # ios, ipad, duo, android or android-tablet

Prints the screens, each in the themes the platform's slide set uses, as
`screen:theme` pairs separated by commas, then a space and the theme of the
watch slide (`-` when the set has none). A split slide needs its screen in
both themes and the dark one in its other accent too (`<screen>-accent`).
Beside the slides, the iPhone's capture feeds the App Store's creative assets
(tool/store_creative.py) and Android's the website (tool/screenshots.sh), so
their screens are added. tool/store_screenshots.sh hands the pairs to the test
as VELORKI_STORE_NEED.
"""
import json
import os
import sys

STORE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "store")

# What tool/store_creative.py draws the product page header and the search
# results image from.
CREATIVE = {"dark": ["weather", "cyclemap", "navigation"],
            "light": ["weather", "ride", "cyclemap", "stops"]}

# What tool/screenshots.sh takes for the website from the Android capture,
# in every look it shows.
WEBSITE = ["ai", "paywall-active", "cyclemap", "layers"]


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    platform = sys.argv[1]
    name = {"ios": "slide_set.json", "android": "slide_set_android.json"}.get(
        platform, "slide_set_ipad.json")
    with open(os.path.join(STORE, name), encoding="utf-8") as f:
        slides = json.load(f)
    need, watch = set(), "-"
    for entry in slides:
        if entry["layout"] == "lock":
            # The Live Activity's figures, sent with the live screen.
            continue
        if entry["layout"] == "split":
            need |= {(entry["screen"], "light"), (entry["screen"], "dark"),
                     (entry["screen"] + "-accent", "dark")}
        else:
            need.add((entry["screen"], entry["style"]))
        if entry["layout"] == "watch":
            watch = entry["style"]
    if platform == "ios":
        need |= {(s, theme) for theme, screens in CREATIVE.items() for s in screens}
    if platform == "android":
        need |= {(s, theme) for s in WEBSITE for theme in ("light", "dark")}
    print(",".join(sorted(f"{s}:{t}" for s, t in need)), watch)
    return 0


if __name__ == "__main__":
    sys.exit(main())
