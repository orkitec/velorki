#!/usr/bin/env bash
# Dead code the analyzer does not see: public declarations nothing uses and
# whole files nothing imports, across lib, test and integration_test (test
# fakes under lib/**/testing are only used from the tests). The analyzer's
# own unused_element/unused_import already cover private code.
#
# dart_code_linter runs as a pinned global tool, outside the app's own
# dependency graph, so its analyzer cannot clash with riverpod_lint's.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=4.4.2
dart pub global activate dart_code_linter "$VERSION" >/dev/null

paths=(lib test integration_test)
exclude='{/**.g.dart,/**.freezed.dart,lib/l10n/generated/**}'
dart pub global run dart_code_linter:metrics check-unused-files "${paths[@]}" \
  --exclude="$exclude" --fatal-unused
dart pub global run dart_code_linter:metrics check-unused-code "${paths[@]}" \
  --exclude="$exclude" --fatal-unused
