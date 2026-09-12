#!/usr/bin/env bash
# Regenerate everything that is not committed: build_runner output (*.g.dart,
# *.freezed.dart, *.drift.dart) and the localisations in lib/l10n/generated.
set -euo pipefail
cd "$(dirname "$0")/.."
dart run build_runner build
flutter gen-l10n
