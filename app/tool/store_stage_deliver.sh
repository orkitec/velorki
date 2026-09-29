#!/usr/bin/env bash
# Lays the store screenshots out the way fastlane deliver reads them.
#
#   tool/store_stage_deliver.sh <assets-dir> <out-dir>
#
# <assets-dir> is app/build/store_screenshots or the store-assets workflow's
# artifact: slides/set/<size>/<locale>/NN-<slide>.png and
# watch/<theme>/<locale>/store/N-<state>.png. Every locale with a slide set
# becomes <out-dir>/<store locale>/, holding its 6.9" and 6.5" slides and the
# four watch shots. deliver tells the devices apart by pixel size and orders each device's
# screenshots by file name, so the NN- prefix is the upload order.
#
# The store locale is the folder fastlane/metadata/ios already has for the
# language (Crowdin names them, see crowdin.yml), else the one below. The watch
# shots are those of the theme the set's watch slide shows (the watch app looks
# the same in both), as JPEGs: App Store Connect refuses a screenshot with an
# alpha channel, which the simulator's PNGs have.
# Needs macOS (sips).
set -euo pipefail

IN="$(cd "$1" && pwd)"
mkdir -p "$2"
OUT="$(cd "$2" && pwd)"
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
METADATA=fastlane/metadata/ios

die() { printf 'store_stage_deliver: %s\n' "$*" >&2; exit 1; }

store_locale() {
  local found=()
  for dir in "$METADATA/$1" "$METADATA/$1"-*; do
    [ -d "$dir" ] && found+=("$(basename "$dir")")
  done
  if [ "${#found[@]}" = 1 ]; then echo "${found[0]}"; return; fi
  case "$1" in
    en) echo en-US ;;
    de) echo de-DE ;;
    fr) echo fr-FR ;;
    es) echo es-ES ;;
    it) echo it ;;
    nl) echo nl-NL ;;
    pt) echo pt-BR ;;
    ja) echo ja ;;
    zh) echo zh-Hans ;;
    *) die "no App Store locale for $1; add it here" ;;
  esac
}

watch_theme="$(python3 -c '
import json, sys
slides = [s for s in json.load(open(sys.argv[1])) if s["layout"] == "watch"]
style = slides[0]["style"] if slides else ""
print(style if style in ("light", "dark") else "dark")
' store/slide_set.json)"

[ -d "$IN/slides/set/6.9" ] || die "no slide set under $IN/slides/set"
count=0
for dir in "$IN/slides/set/6.9"/*/; do
  locale="$(basename "$dir")"
  target="$OUT/$(store_locale "$locale")"
  mkdir -p "$target"
  for size in 6.9 6.5; do
    [ -d "$IN/slides/set/$size/$locale" ] || die "no $size slides for $locale"
    for slide in "$IN/slides/set/$size/$locale"/*.png; do
      cp "$slide" "$target/$size-$(basename "$slide")"
    done
  done
  watch="$IN/watch/$watch_theme/$locale/store"
  for state in 1-riding-turn 2-riding 3-paused 4-idle; do
    [ -f "$watch/$state.png" ] || die "missing $watch/$state.png"
    sips -s format jpeg -s formatOptions 100 "$watch/$state.png" \
      --out "$target/watch-$state.jpg" > /dev/null
  done
  echo "$locale -> $(basename "$target"): $(find "$target" -type f | wc -l | tr -d ' ') screenshots"
  count=$((count + 1))
done
[ "$count" -gt 0 ] || die "no locales under $IN/slides/set/6.9"
