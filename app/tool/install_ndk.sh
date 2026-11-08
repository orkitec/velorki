#!/usr/bin/env bash
# The NDK version Flutter's Gradle plugin asks for, installed before a build
# rather than during it.
#
# The Android Gradle plugin downloads it with no check of its own: an archive
# that arrived broken ("Error on ZipFile unknown archive") failed a build. So
# it is installed here first, verified by the file the plugin looks for, and
# fetched again on a bad archive. Called by the APK jobs in
# .github/workflows/app.yml.
set -euo pipefail

sdk="${ANDROID_SDK_ROOT:-$ANDROID_HOME}"
root="$(dirname "$(dirname "$(command -v flutter)")")"
ver="$(sed -n 's/.*val ndkVersion: String = "\([^"]*\)".*/\1/p' \
  "$root/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt")"
[ -n "$ver" ] || { echo "::error::no ndkVersion in Flutter's FlutterExtension.kt"; exit 1; }

for try in 1 2 3; do
  printf 'y\n%.0s' {1..30} \
    | "$sdk/cmdline-tools/latest/bin/sdkmanager" --install "ndk;$ver" || true
  if [ -f "$sdk/ndk/$ver/source.properties" ]; then
    echo "==> ndk;$ver in place"
    exit 0
  fi
  echo "==> ndk;$ver did not install cleanly (try $try of 3); fetching it again"
  rm -rf "$sdk/ndk/$ver" "$sdk/.temp"
  sleep 20
done
echo "::error::ndk;$ver could not be installed"
exit 1
