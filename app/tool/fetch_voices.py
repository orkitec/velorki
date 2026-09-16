#!/usr/bin/env python3
"""Builds assets/voices/catalogue.json from the recommended-voices project.

The phone's text-to-speech engine names its voices for machines, not for
riders: Android hands out "en-us-x-iog-local", and iOS hands out an Apple
name with no hint of how good it sounds. HadrienGardeur's
web-speech-recommended-voices collects friendly labels, genders and a
quality grade for both, under CC0-1.0.

The upstream repository moved its JSON files to the Readium Speech project
in December 2025 and now only keeps them in its history, so the script looks
for json/ on the default branch and, when it is gone, falls back to the last
commit that still had it. The CC0 licence is the reason the data is taken
from this repository rather than from its successor, which is BSD-3-Clause.

Run from app/:

    python3 tool/fetch_voices.py

Writes assets/voices/catalogue.json. The result is committed, so the app
never needs the network for it; re-run when upstream adds voices.
"""

from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

REPO = "HadrienGardeur/web-speech-recommended-voices"
API = f"https://api.github.com/repos/{REPO}"
RAW = f"https://raw.githubusercontent.com/{REPO}"

# The prefix Chrome and the catalogue put in front of a Google voice on
# Android; what follows it is the identifier the engine itself reports.
ANDROID_PREFIX = "Android Speech Recognition and Synthesis from Google "

# Upstream grades a voice on a five-step scale; the app only tells four
# steps apart, and "veryLow" is not worth its own word.
QUALITY = {
    "veryhigh": "premium",
    "high": "enhanced",
    "normal": "normal",
    "low": "low",
    "verylow": "low",
}
QUALITY_ORDER = ["low", "normal", "enhanced", "premium"]

# Only voices that can turn up on a phone are worth carrying; Windows and
# ChromeOS entries would just make the asset bigger.
PHONE_SYSTEMS = {"android", "ios", "ipados"}
APPLE_SYSTEMS = {"ios", "ipados"}


def fetch(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": "velorki-voices"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.read()


def fetch_json(url: str):
    return json.loads(fetch(url))


def json_ref() -> str:
    """The commit or branch whose json/ directory is read."""
    try:
        fetch_json(f"{API}/contents/json?ref=main")
        return "main"
    except urllib.error.HTTPError as error:
        if error.code != 404:
            raise
    # The directory was deleted; the commit before the one that deleted it
    # still has every file.
    commits = fetch_json(f"{API}/commits?path=json&per_page=2")
    if len(commits) < 2:
        raise SystemExit("json/ is gone from main and there is no earlier commit")
    return commits[1]["sha"]


def language_files(ref: str) -> list[str]:
    entries = fetch_json(f"{API}/contents/json?ref={ref}")
    return sorted(
        entry["name"]
        for entry in entries
        if entry["type"] == "file" and entry["name"].endswith(".json")
    )


def systems(voice: dict) -> set[str]:
    raw = voice.get("os") or []
    if isinstance(raw, str):
        raw = [raw]
    return {str(name).lower() for name in raw}


def best_quality(voice: dict) -> str | None:
    """The best grade upstream lists for the voice.

    Upstream lists every grade the voice can be installed in, so the best of
    them says what the voice is worth once the rider has downloaded it. It
    is only ever a fallback: both platforms report the grade of the voice
    that is actually installed.
    """
    grades = voice.get("quality") or []
    if isinstance(grades, str):
        grades = [grades]
    known = [QUALITY[g.lower()] for g in grades if g.lower() in QUALITY]
    if not known:
        return None
    return max(known, key=QUALITY_ORDER.index)


def identifiers(voice: dict) -> list[str]:
    """The keys the app can look this voice up by, lower-cased."""
    names = [voice.get("name")] + list(voice.get("altNames") or [])
    keys: list[str] = []
    if "android" in systems(voice):
        for native in voice.get("nativeID") or []:
            keys.append(str(native))
        for name in names:
            if isinstance(name, str) and name.startswith(ANDROID_PREFIX):
                keys.append(name[len(ANDROID_PREFIX) :])
    if systems(voice) & APPLE_SYSTEMS:
        # Apple voices go by their plain name ("Samantha"); the app cuts the
        # com.apple.… identifier down to that before looking them up.
        for name in names:
            if isinstance(name, str) and name and not name.startswith(ANDROID_PREFIX):
                keys.append(name)
    return [key.strip().lower() for key in keys if key and key.strip()]


def reduce_voice(voice: dict) -> dict | None:
    label = voice.get("label")
    language = voice.get("language")
    if not isinstance(label, str) or not label:
        return None
    entry: dict[str, str] = {"label": label}
    gender = voice.get("gender")
    if isinstance(gender, str) and gender in ("female", "male"):
        entry["gender"] = gender
    quality = best_quality(voice)
    if quality:
        entry["quality"] = quality
    if isinstance(language, str) and language:
        entry["language"] = language
    return entry


def build(ref: str) -> dict[str, dict]:
    catalogue: dict[str, dict] = {}
    for file in language_files(ref):
        data = json.loads(fetch(f"{RAW}/{ref}/json/{file}"))
        for voice in data.get("voices") or []:
            if not systems(voice) & PHONE_SYSTEMS:
                continue
            entry = reduce_voice(voice)
            if entry is None:
                continue
            for key in identifiers(voice):
                # First file wins, so a re-run gives the same bytes.
                catalogue.setdefault(key, entry)
        print(f"  {file}: {len(catalogue)} voices so far", file=sys.stderr)
    return catalogue


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--out",
        default=str(Path(__file__).resolve().parent.parent / "assets/voices/catalogue.json"),
        help="where the catalogue is written",
    )
    parser.add_argument("--ref", default=None, help="branch or commit to read json/ from")
    args = parser.parse_args()

    ref = args.ref or json_ref()
    print(f"Reading json/ at {ref}", file=sys.stderr)
    catalogue = build(ref)
    if not catalogue:
        raise SystemExit("no voices found")

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    ordered = {key: catalogue[key] for key in sorted(catalogue)}
    out.write_text(json.dumps(ordered, ensure_ascii=False, indent=1, sort_keys=False) + "\n")
    print(f"Wrote {len(ordered)} voices to {out}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
