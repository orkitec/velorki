#!/usr/bin/env bash
# The Gradle distribution the wrapper asks for, fetched before a build
# rather than during it.
#
# The wrapper downloads it once, with no retry of its own: a 504 from the
# download server failed a build before it had started. So it is fetched
# here first, by running the wrapper, and fetched again after a failed
# download. A cached distribution makes this a no-op. Called by the Android
# jobs in .github/workflows/ before they build, from app/.
#
# `gradlew` and its jar are not in the repository (android/.gitignore):
# Flutter copies them in from its cache when it first builds, which is after
# this runs. So they are copied from the same place here. Without them, or
# without a Flutter to copy from, this step says so and leaves the download
# to the build, as it was before there was a step.
set -euo pipefail

cd "$(dirname "$0")/../android"
url="$(sed -n 's/^distributionUrl=//p' gradle/wrapper/gradle-wrapper.properties | tr -d '\\')"
name="$(basename "$url" .zip)"
[ -n "$name" ] || { echo "::error::no distributionUrl in gradle-wrapper.properties"; exit 1; }

if [ ! -x ./gradlew ] || [ ! -f gradle/wrapper/gradle-wrapper.jar ]; then
  flutter_root="${FLUTTER_ROOT:-}"
  if [ -z "$flutter_root" ] && command -v flutter >/dev/null; then
    flutter_root="$(cd "$(dirname "$(command -v flutter)")/.." && pwd)"
  fi
  wrapper="$flutter_root/bin/cache/artifacts/gradle_wrapper"
  if [ -z "$flutter_root" ] || [ ! -f "$wrapper/gradlew" ] || [ ! -f "$wrapper/gradle/wrapper/gradle-wrapper.jar" ]; then
    echo "::warning::no Gradle wrapper to run yet (looked in ${wrapper}); the build will download $name itself"
    exit 0
  fi
  cp "$wrapper/gradlew" ./gradlew
  chmod +x ./gradlew
  cp "$wrapper/gradle/wrapper/gradle-wrapper.jar" gradle/wrapper/gradle-wrapper.jar
  echo "==> Gradle wrapper copied from Flutter's cache"
fi

for try in 1 2 3; do
  if ./gradlew --version --no-daemon --quiet >/dev/null; then
    echo "==> $name in place"
    exit 0
  fi
  echo "==> $name did not download (try $try of 3); fetching it again"
  # A broken download leaves a part file and a lock beside the zip.
  rm -rf "${GRADLE_USER_HOME:-$HOME/.gradle}/wrapper/dists/$name"
  sleep 30
done
echo "::error::$name could not be downloaded"
exit 1
