#!/usr/bin/env python3
"""Checks the App Store, Play Store and F-Droid listing texts against each
store's length limits, and that their velorki.com links go to the pages in
the listing's own language.

Walks app/fastlane/metadata/ios/*/ and app/fastlane/metadata/android/*/,
skips review_information/ (no store limit applies to it), and fails loudly
on any file that is empty or over its store's limit. Length is counted in
Unicode code points after stripping the file's trailing newline, which is
how both stores count.

The F-Droid texts are metadata/<locale>/ at the repository root
(docs/FDROID.md). A link to velorki.com in a listing must carry the
listing's language (velorki.com/nl/privacy in nl-NL, no prefix in en-US): a
listing in one language linking the English pages, as the Dutch App Store
URLs once did, is caught here.

Usage: python3 app/tool/store_text_check.py
"""

from __future__ import annotations

import pathlib
import re
import sys

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]


def _display(path: pathlib.Path, root: pathlib.Path) -> str:
    """Path relative to root when possible, for readable messages."""
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)

# file name -> character limit, per store. Every file listed here is
# required and must be non-empty.
IOS_LIMITS = {
    "name.txt": 30,
    "subtitle.txt": 30,
    "keywords.txt": 100,
    "promotional_text.txt": 170,
    "description.txt": 4000,
}

ANDROID_LIMITS = {
    "title.txt": 30,
    "short_description.txt": 80,
    "full_description.txt": 4000,
}


FDROID_LIMITS = {
    "title.txt": 50,
    "short_description.txt": 80,
    "full_description.txt": 4000,
}

# The website's languages; English has no prefix.
SITE_LANGUAGES = {"de", "fr", "es", "it", "nl"}

_SITE_LINK = re.compile(r"https://velorki\.com(/[^\s)\"'>]*)?")


def link_errors(
    locale_dir: pathlib.Path, root: pathlib.Path = REPO_ROOT
) -> list[str]:
    """One message per velorki.com link in locale_dir's texts that does not
    go to the pages in the folder's language. app.velorki.com and other
    hosts are not the website and are left alone."""
    language = locale_dir.name.split("-")[0]
    errors = []
    for path in sorted(locale_dir.rglob("*.txt")):
        text = path.read_text(encoding="utf-8")
        for match in _SITE_LINK.finditer(text):
            first = (match.group(1) or "/").strip("/").split("/")[0]
            prefixed = first in SITE_LANGUAGES
            if language in SITE_LANGUAGES:
                ok = first == language
            else:
                ok = not prefixed
            if not ok:
                errors.append(
                    f"{_display(path, root)}: {match.group(0)} is not the "
                    f"{language} page"
                )
    return errors


def check_locale_dir(
    locale_dir: pathlib.Path, limits: dict[str, int], root: pathlib.Path = REPO_ROOT
) -> list[str]:
    """Returns one error message per file in locale_dir that fails a check."""
    errors = []
    for file_name, limit in limits.items():
        path = locale_dir / file_name
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8").rstrip("\n")
        length = len(text)
        if not text:
            errors.append(f"{_display(path, root)}: empty, but required")
        elif length > limit:
            errors.append(
                f"{_display(path, root)}: {length} characters, "
                f"over the {limit} limit"
            )
    return errors


def check_store(
    store_dir: pathlib.Path, limits: dict[str, int], root: pathlib.Path = REPO_ROOT
) -> tuple[list[str], list[str]]:
    """Returns (errors, ok_lines) for every locale folder under store_dir."""
    errors: list[str] = []
    ok_lines: list[str] = []
    if not store_dir.is_dir():
        return errors, ok_lines
    for locale_dir in sorted(store_dir.iterdir()):
        if not locale_dir.is_dir():
            continue
        # review_information/ is not a store locale and has no length limit.
        if locale_dir.name == "review_information":
            continue
        locale_errors = check_locale_dir(locale_dir, limits, root)
        locale_errors += link_errors(locale_dir, root)
        if locale_errors:
            errors.extend(locale_errors)
        else:
            ok_lines.append(f"OK  {_display(locale_dir, root)}")
    return errors, ok_lines


def main() -> int:
    ios_dir = REPO_ROOT / "app" / "fastlane" / "metadata" / "ios"
    android_dir = REPO_ROOT / "app" / "fastlane" / "metadata" / "android"
    fdroid_dir = REPO_ROOT / "metadata"

    ios_errors, ios_ok = check_store(ios_dir, IOS_LIMITS)
    android_errors, android_ok = check_store(android_dir, ANDROID_LIMITS)
    fdroid_errors, fdroid_ok = check_store(fdroid_dir, FDROID_LIMITS)

    for line in ios_ok + android_ok + fdroid_ok:
        print(line)

    errors = ios_errors + android_errors + fdroid_errors
    if errors:
        print("\nstore_text_check failed:")
        for error in errors:
            print(f"  {error}")
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
