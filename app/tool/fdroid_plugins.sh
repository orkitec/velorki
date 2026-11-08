# shellcheck shell=bash
# The pub packages the F-Droid build does without, as one list.
#
# Sourced by tool/fdroid_strip.sh, which removes them from pubspec.yaml, and
# by tool/itest.sh, which skips the integration tests that import one of them
# — a test that drives a plugin the build no longer has cannot pass on it.
# One list, so the two can never disagree. docs/FDROID.md is the whole
# picture.
#
# The google_sign_in platform packages are named too: the app pins them, so
# they would survive the removal of google_sign_in itself.
# shellcheck disable=SC2034 # read by the scripts that source this file
fdroid_plugins=(
  purchases_flutter
  google_sign_in
  google_sign_in_android
  google_sign_in_ios
  google_sign_in_web
  google_sign_in_platform_interface
  googleapis
  in_app_update
  in_app_review
  watch_connectivity
  live_activities
)
