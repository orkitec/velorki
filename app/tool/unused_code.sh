#!/usr/bin/env bash
# Dead code the analyzer does not see: public declarations nothing uses and
# whole files nothing imports. Two passes: over lib, test and
# integration_test, then over lib alone, which finds app code only tests
# use (test fakes under lib/**/testing are left out of that pass). The
# analyzer's own unused_element/unused_import already cover private code.
#
# dart_code_linter runs as a pinned global tool, outside the app's own
# dependency graph, so its analyzer cannot clash with riverpod_lint's.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=4.4.2
dart pub global activate dart_code_linter "$VERSION" >/dev/null

check() {
  local exclude=$1
  shift
  dart pub global run dart_code_linter:metrics check-unused-files "$@" \
    --exclude="$exclude" --fatal-unused
  dart pub global run dart_code_linter:metrics check-unused-code "$@" \
    --exclude="$exclude" --fatal-unused
}

generated='/**.g.dart,/**.freezed.dart,lib/l10n/generated/**'
check "{$generated}" lib test integration_test
check "{$generated,lib/**/testing/**}" lib
