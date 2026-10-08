#!/usr/bin/env bash
# Lays the Google Play listing out the way fastlane supply reads it.
#
#   tool/store_stage_supply.sh <set-dir> <out-dir>
#
# <set-dir> is app/build/store_screenshots/android/slides/set or the
# store-assets workflow's artifact `store-assets-android`: <locale>/NN-<slide>.png
# and <locale>/feature-graphic.png per language, icon-512.png beside them.
# <out-dir> becomes a supply metadata folder: a copy of fastlane/metadata/android
# (the texts of every language there), and for every language with a set
# <out-dir>/<Play locale>/images/phoneScreenshots/NN-<slide>.png,
# images/featureGraphic.png and images/icon.png. supply uploads the
# screenshots in file-name order, so the NN- prefix is the order on Play.
#
# The Play locale is the folder fastlane/metadata/android already has for the
# language (Crowdin names them, see crowdin.yml), else the one below.
set -euo pipefail

IN="$(cd "$1" && pwd)"
mkdir -p "$2"
OUT="$(cd "$2" && pwd)"
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
METADATA=fastlane/metadata/android

die() { printf 'store_stage_supply: %s\n' "$*" >&2; exit 1; }

play_locale() {
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
    it) echo it-IT ;;
    nl) echo nl-NL ;;
    pt) echo pt-BR ;;
    ja) echo ja-JP ;;
    zh) echo zh-CN ;;
    *) die "no Google Play locale for $1; add it here" ;;
  esac
}

cp -R "$METADATA/." "$OUT/"
[ -f "$IN/icon-512.png" ] || die "no icon-512.png in $IN"
count=0
for dir in "$IN"/*/; do
  locale="$(basename "$dir")"
  shots=("$dir"[0-9][0-9]-*.png)
  [ -e "${shots[0]}" ] || continue
  [ "${#shots[@]}" -ge 2 ] && [ "${#shots[@]}" -le 8 ] \
    || die "$locale has ${#shots[@]} screenshots; Play takes 2 to 8"
  [ -f "$dir/feature-graphic.png" ] || die "no feature-graphic.png for $locale"
  images="$OUT/$(play_locale "$locale")/images"
  rm -rf "$images"
  mkdir -p "$images/phoneScreenshots"
  cp "${shots[@]}" "$images/phoneScreenshots/"
  cp "$dir/feature-graphic.png" "$images/featureGraphic.png"
  cp "$IN/icon-512.png" "$images/icon.png"
  echo "$locale -> $(play_locale "$locale"): ${#shots[@]} screenshots, feature graphic, icon"
  count=$((count + 1))
done
[ "$count" -gt 0 ] || die "no locales with screenshots under $IN"
