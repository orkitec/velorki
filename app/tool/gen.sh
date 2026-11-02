#!/usr/bin/env bash
# Regenerate everything that is not committed: build_runner output (*.g.dart,
# *.freezed.dart, *.drift.dart), the localisations in lib/l10n/generated, and
# the in-app guide in assets/guide (copied from the website's Markdown).
set -euo pipefail
cd "$(dirname "$0")/.."

# The guide: web/content/<locale>/docs/*.md, the website's own pages, into
# assets/guide/<locale>/, leaving out `draft: true` pages. pubspec.yaml lists
# one asset folder per locale.
guide_src=../web/content
guide_out=assets/guide
if [ ! -d "$guide_src/en/docs" ]; then
  echo "gen.sh: $guide_src/en/docs not found; the guide is copied from the website's content" >&2
  exit 1
fi
rm -rf "$guide_out"
for dir in "$guide_src"/*/docs; do
  locale=$(basename "$(dirname "$dir")")
  mkdir -p "$guide_out/$locale"
  for page in "$dir"/*.md; do
    # The front matter is the block between the first two `---` lines.
    if awk 'NR == 1 && $0 != "---" { exit 1 } NR > 1 && $0 == "---" { exit 1 }
            NR > 1 && /^draft:[[:space:]]*true[[:space:]]*$/ { found = 1; exit 0 }
            END { exit !found }' "$page"; then
      continue
    fi
    cp "$page" "$guide_out/$locale/"
  done
  if ! ls "$guide_out/$locale"/*.md > /dev/null 2>&1; then
    echo "gen.sh: no guide pages for $locale in $dir" >&2
    exit 1
  fi
done

dart run build_runner build
flutter gen-l10n
