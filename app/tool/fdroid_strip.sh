#!/usr/bin/env bash
# Turn this checkout into the Google-free tree the F-Droid build compiles.
#
# Three kinds of change, all of which this script makes and none of which is
# committed:
#
#  1. `pubspec.yaml` and `pubspec.lock` lose the six closed-source plugins.
#     Flutter compiles the Android half of every plugin in `pubspec.yaml`
#     whether Dart calls it or not, so dropping them is the only way their
#     classes stay out of the dex. Nothing reachable from
#     `lib/main_fdroid.dart` imports them (see lib/app/proprietary_services.dart),
#     which is what makes dropping them compile.
#
#  2. THE PUB CACHE IS MODIFIED IN PLACE. Two plugins Velorki keeps —
#     geolocator_android and maplibre_gl — ask Google Play Services for a
#     location provider and fall back by themselves when it is missing; the
#     fallback is no use here, because the *reference* is what has to go. Both
#     are patched where pub unpacked them, so `$PUB_CACHE` (or `~/.pub-cache`)
#     is left changed for every other project on the machine until
#     `flutter pub cache repair`. F-Droid's build runs in a throwaway VM with
#     its own PUB_CACHE and does not care; a laptop does. Run it against a
#     PUB_CACHE of its own if that matters:
#
#       PUB_CACHE=$PWD/.pub-cache bash tool/fdroid_strip.sh
#
#  3. `android/gradle.properties` gains `maplibre_gl.playServicesLocation=false`
#     where the maplibre_gl in use has that switch (0.28 on) instead of
#     needing the patch.
#
# Idempotent: every edit is skipped where it has already been made, so a
# second run (or a run over a cache another flavour already patched) is a
# no-op. Ends by grepping the patched plugin sources for
# com.google.android.gms and failing if any is left.
#
# After it, build with:
#   flutter build apk --release --target lib/main_fdroid.dart
#
# docs/FDROID.md is the whole picture.
set -euo pipefail
cd "$(dirname "$0")/.."

say() { printf '%s\n' "fdroid_strip: $*"; }

# ---------------------------------------------------------------------------
# 1. The plugins that go
# ---------------------------------------------------------------------------

# The one list, shared with tool/itest.sh; see tool/fdroid_plugins.sh.
# shellcheck source=tool/fdroid_plugins.sh
. tool/fdroid_plugins.sh
# shellcheck disable=SC2154 # set by tool/fdroid_plugins.sh, sourced above
plugins=("${fdroid_plugins[@]}")

strip_pubspec() {
  local removed=0 name
  for name in "${plugins[@]}"; do
    if grep -qE "^  $name:" pubspec.yaml; then
      # The entry, its version or description lines, and any comment block
      # directly above it (which only ever describes that entry).
      python3 - "$name" <<'PY'
import re
import sys

name = sys.argv[1]
lines = open('pubspec.yaml').read().splitlines(keepends=True)
out = []
i = 0
while i < len(lines):
    if re.match(rf'^  {re.escape(name)}:', lines[i]):
        # Drop the comment block directly above the entry with it.
        while out and out[-1].lstrip().startswith('#'):
            out.pop()
        i += 1
        # ...and any continuation lines (a `sdk:`/`version:` under it).
        while i < len(lines) and re.match(r'^    \S', lines[i]):
            i += 1
        continue
    out.append(lines[i])
    i += 1
open('pubspec.yaml', 'w').writelines(out)
PY
      removed=$((removed + 1))
    fi
  done
  if [ "$removed" -gt 0 ]; then
    say "removed $removed plugin(s) from pubspec.yaml"
  else
    say 'pubspec.yaml already stripped'
  fi
}

strip_lock() {
  if [ ! -f pubspec.lock ]; then
    say 'no pubspec.lock to strip'
    return
  fi
  python3 - "${plugins[@]}" <<'PY'
import re
import sys

names = set(sys.argv[1:])
lines = open('pubspec.lock').read().splitlines(keepends=True)
out = []
i = 0
dropped = 0
while i < len(lines):
    m = re.match(r'^  ([A-Za-z0-9_]+):\s*$', lines[i])
    if m and m.group(1) in names:
        i += 1
        while i < len(lines) and (lines[i].startswith('    ') or not lines[i].strip()):
            i += 1
        dropped += 1
        continue
    out.append(lines[i])
    i += 1
open('pubspec.lock', 'w').writelines(out)
print(f'fdroid_strip: dropped {dropped} entr{"y" if dropped == 1 else "ies"} from pubspec.lock')
PY
}

strip_pubspec
strip_lock

# `pub get` has to run before the cache can be patched: it is what unpacks the
# plugins, and it also rewrites pubspec.lock for the smaller dependency set.
say 'resolving the stripped dependency set'
flutter pub get >/dev/null

cache=${PUB_CACHE:-$HOME/.pub-cache}/hosted/pub.dev
say "patching plugins in $cache (THIS MODIFIES THE PUB CACHE)"

# ---------------------------------------------------------------------------
# 2. geolocator_android: no fused location provider
# ---------------------------------------------------------------------------
# The Immich recipe's patch, which this follows:
# gitlab.com/fdroid/fdroiddata/-/raw/master/metadata/app.alextran.immich.yml

patch_geolocator() {
  local dir
  for dir in "$cache"/geolocator_android-*/android; do
    [ -d "$dir" ] || continue
    local loc="$dir/src/main/java/com/baseflow/geolocator/location"
    sed -i.bak -e '/gms/d' "$dir/build.gradle" && rm -f "$dir/build.gradle.bak"
    rm -f "$loc/FusedLocationClient.java"
    # `createLocationClient` returns the LocationManager client always, and
    # `isGooglePlayServicesAvailable` goes with the imports it needed.
    # perl rather than sed: BSD and GNU sed disagree about multi-line edits,
    # and this script is run on a laptop as well as in F-Droid's VM.
    perl -0777 -pi -e '
      s{\n  public LocationClient createLocationClient\(.*?\n  \}\n}
       {\n  public LocationClient createLocationClient(\n      Context context,\n      boolean forceAndroidLocationManager,\n      \@Nullable LocationOptions locationOptions) {\n    return new LocationManagerClient(context, locationOptions);\n  }\n}s;
      s{\n  private boolean isGooglePlayServicesAvailable\(.*?\n  \}\n}{\n}s;
      s{^import com\.google\.android\.gms\..*\n}{}gm;
    ' "$loc/GeolocationManager.java"
    say "patched $(basename "$(dirname "$dir")")"
  done
}

# ---------------------------------------------------------------------------
# 3. maplibre_gl: the MapLibre GPS location engine, never the GMS one
# ---------------------------------------------------------------------------
# From 0.28 the plugin has a `maplibre_gl.playServicesLocation` Gradle
# property that does this without a patch; an older one has its sources
# edited instead.

patch_maplibre() {
  local dir
  for dir in "$cache"/maplibre_gl-*/android; do
    [ -d "$dir" ] || continue
    if grep -q 'playServicesLocation' "$dir/build.gradle"; then
      local props=android/gradle.properties
      if grep -q '^maplibre_gl.playServicesLocation=false' "$props" 2>/dev/null; then
        say 'maplibre_gl.playServicesLocation=false already set'
      else
        printf '\n# No Google Play Services in the F-Droid flavour.\nmaplibre_gl.playServicesLocation=false\n' >>"$props"
        say 'set maplibre_gl.playServicesLocation=false'
      fi
      continue
    fi
    local src="$dir/src/main/java/org/maplibre/maplibregl"
    sed -i.bak -e '/gms/d' "$dir/build.gradle" && rm -f "$dir/build.gradle.bak"
    rm -f "$src/GMSLocationEngine.java"
    perl -0777 -pi -e '
      s{\n    private fun isGooglePlayServicesAvailable\(.*?\n    \}\n}{\n}s;
      s{isGooglePlayServicesAvailable\(context\)}{true}g;
      s{\bGMSLocationEngine\b}{MapLibreGPSLocationEngine}g;
      s{^import com\.google\.android\.gms\..*\n}{}gm;
    ' "$src/LocationEngineFactory.kt"
    say "patched $(basename "$(dirname "$dir")")"
  done
}

patch_geolocator
patch_maplibre

# ---------------------------------------------------------------------------
# 4. The guard
# ---------------------------------------------------------------------------
# Only the two patched plugins are checked here: every other Google reference
# left anywhere in the cache belongs to a plugin this build no longer lists,
# and the `fdroid` job in .github/workflows/app.yml scans the dex, which is
# what proves that. A maplibre_gl with the Gradle switch keeps its Google
# sources on disk (Gradle leaves them out), so only the dex scan can check it.

patched=("$cache"/geolocator_android-*/android)
for dir in "$cache"/maplibre_gl-*/android; do
  [ -d "$dir" ] || continue
  grep -q 'playServicesLocation' "$dir/build.gradle" || patched+=("$dir")
done
left=$(grep -rl 'com\.google\.android\.gms' "${patched[@]}" 2>/dev/null || true)
if [ -n "$left" ]; then
  say 'com.google.android.gms is still referenced after patching:'
  printf '  %s\n' $left
  exit 1
fi

say 'done; build with: flutter build apk --release --target lib/main_fdroid.dart'
