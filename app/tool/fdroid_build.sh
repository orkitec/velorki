#!/usr/bin/env bash
# Build the Google-free F-Droid APK from this checkout and leave the checkout
# as it was.
#
#   bash tool/fdroid_build.sh            # release, signed with the debug key
#   bash tool/fdroid_build.sh --debug    # anything after it goes to flutter build
#
# tool/fdroid_strip.sh rewrites pubspec.yaml, pubspec.lock and
# android/gradle.properties and patches the pub cache; on F-Droid's throwaway
# VM that is fine, on a laptop it is not. So this saves the three files first
# and puts them back on every exit (a failed build and Ctrl-C included), and points PUB_CACHE at a cache of its own under
# .dart_tool/, so the machine's ~/.pub-cache is never patched. The APK is
# dex-scanned (tool/fdroid_scan.sh) and copied to build/fdroid/, where an
# ordinary release build does not overwrite it.
#
# Expects tool/gen.sh to have run. docs/FDROID.md is the whole picture.
set -euo pipefail
cd "$(dirname "$0")/.."

mode=release
if [ "${1:-}" = --debug ]; then
  mode=debug
  shift
fi

saved=$(mktemp -d)
cp pubspec.yaml pubspec.lock "$saved/"
cp android/gradle.properties "$saved/"
normal_cache=${PUB_CACHE:-}

restore() {
  cp "$saved/pubspec.yaml" "$saved/pubspec.lock" .
  cp "$saved/gradle.properties" android/
  rm -rf "$saved"
  # Back to the full dependency set in the machine's own cache, so the next
  # ordinary build finds every plugin where it expects it.
  if [ -n "$normal_cache" ]; then
    PUB_CACHE=$normal_cache flutter pub get >/dev/null
  else
    env -u PUB_CACHE flutter pub get >/dev/null
  fi
  echo 'fdroid_build: pubspec.yaml, pubspec.lock and gradle.properties restored'
}
trap restore EXIT

export PUB_CACHE=$PWD/.dart_tool/fdroid-pub-cache
bash tool/fdroid_strip.sh
flutter build apk "--$mode" --target lib/main_fdroid.dart \
  --dart-define-from-file=env/fdroid.json "$@"

apk=build/app/outputs/flutter-apk/app-$mode.apk
bash tool/fdroid_scan.sh "$apk"
mkdir -p build/fdroid
cp "$apk" "build/fdroid/velorki-fdroid-$mode.apk"
echo "fdroid_build: build/fdroid/velorki-fdroid-$mode.apk"
