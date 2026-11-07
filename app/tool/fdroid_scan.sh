#!/usr/bin/env bash
# Fail if an APK carries a class from a closed-source Google or store library.
#
# The promise the F-Droid flavour makes, checked against the artifact rather
# than against the sources: a dex holds its type names as plain strings
# (`Lcom/google/android/gms/common/ConnectionResult;`), so grepping the
# unpacked dex for the package paths finds a reference wherever it came from —
# an import, a transitive Gradle dependency, a plugin nobody noticed.
#
# Usage: bash tool/fdroid_scan.sh <path to .apk>
set -euo pipefail

apk=${1:?usage: fdroid_scan.sh <apk>}
[ -f "$apk" ] || { echo "fdroid_scan: no such file: $apk" >&2; exit 1; }

# Written as a dex writes them, so a slash and not a dot.
forbidden=(
  com/google/android/gms
  com/google/android/play
  com/google/firebase
  com/android/billingclient
  com/revenuecat
)

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

unzip -q -o -j "$apk" 'classes*.dex' -d "$work"
dex=("$work"/classes*.dex)
[ -f "${dex[0]}" ] || { echo "fdroid_scan: no dex in $apk" >&2; exit 1; }
echo "fdroid_scan: ${#dex[@]} dex file(s) in $(basename "$apk")"

found=0
for name in "${forbidden[@]}"; do
  if hits=$(grep -l -a -F "$name" "${dex[@]}"); then
    echo "::error::$name is referenced by $(basename "$apk"): $(echo "$hits" | xargs -n99 basename -a | tr '\n' ' ')"
    found=1
  else
    echo "  ok: no $name"
  fi
done

[ "$found" -eq 0 ] || exit 1
echo "fdroid_scan: clean"
