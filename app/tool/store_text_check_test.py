#!/usr/bin/env python3
"""Unit tests for store_text_check.py."""

import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import store_text_check  # noqa: E402


def write(path: pathlib.Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


class CheckLocaleDirTests(unittest.TestCase):
    def test_within_limit_is_ok(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            locale_dir = root / "en-US"
            write(locale_dir / "name.txt", "Velorki\n")
            errors = store_text_check.check_locale_dir(
                locale_dir, {"name.txt": 30}, root
            )
            self.assertEqual(errors, [])

    def test_over_limit_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            locale_dir = root / "en-US"
            write(locale_dir / "name.txt", "x" * 31 + "\n")
            errors = store_text_check.check_locale_dir(
                locale_dir, {"name.txt": 30}, root
            )
            self.assertEqual(len(errors), 1)
            self.assertIn("31 characters", errors[0])
            self.assertIn("over the 30 limit", errors[0])
            self.assertIn("en-US/name.txt", errors[0])

    def test_exactly_at_limit_is_ok(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            locale_dir = root / "en-US"
            write(locale_dir / "name.txt", "x" * 30 + "\n")
            errors = store_text_check.check_locale_dir(
                locale_dir, {"name.txt": 30}, root
            )
            self.assertEqual(errors, [])

    def test_empty_required_file_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            locale_dir = root / "en-US"
            write(locale_dir / "name.txt", "")
            errors = store_text_check.check_locale_dir(
                locale_dir, {"name.txt": 30}, root
            )
            self.assertEqual(len(errors), 1)
            self.assertIn("empty, but required", errors[0])

    def test_whitespace_only_file_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            locale_dir = root / "en-US"
            write(locale_dir / "name.txt", "\n")
            errors = store_text_check.check_locale_dir(
                locale_dir, {"name.txt": 30}, root
            )
            self.assertEqual(len(errors), 1)
            self.assertIn("empty, but required", errors[0])

    def test_missing_file_is_not_checked(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            locale_dir = root / "en-US"
            locale_dir.mkdir(parents=True)
            errors = store_text_check.check_locale_dir(
                locale_dir, {"name.txt": 30}, root
            )
            self.assertEqual(errors, [])

    def test_trailing_newline_not_counted(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            locale_dir = root / "en-US"
            # 30 chars plus a trailing newline must still pass: the newline
            # is stripped before counting, the way the stores count.
            write(locale_dir / "name.txt", "x" * 30 + "\n")
            errors = store_text_check.check_locale_dir(
                locale_dir, {"name.txt": 30}, root
            )
            self.assertEqual(errors, [])

    def test_keywords_counted_as_whole_string(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            locale_dir = root / "en-US"
            # A comma-separated list at exactly the 100-char limit passes;
            # one character more fails, counted as one string, not per word.
            write(locale_dir / "keywords.txt", "x" * 100)
            errors = store_text_check.check_locale_dir(
                locale_dir, {"keywords.txt": 100}, root
            )
            self.assertEqual(errors, [])

            write(locale_dir / "keywords.txt", "x" * 101)
            errors = store_text_check.check_locale_dir(
                locale_dir, {"keywords.txt": 100}, root
            )
            self.assertEqual(len(errors), 1)

    def test_unicode_counted_as_code_points(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            locale_dir = root / "en-US"
            # Multi-byte characters (German umlauts) count as one each.
            write(locale_dir / "name.txt", "ä" * 30)
            errors = store_text_check.check_locale_dir(
                locale_dir, {"name.txt": 30}, root
            )
            self.assertEqual(errors, [])

            write(locale_dir / "name.txt", "ä" * 31)
            errors = store_text_check.check_locale_dir(
                locale_dir, {"name.txt": 30}, root
            )
            self.assertEqual(len(errors), 1)


class CheckStoreTests(unittest.TestCase):
    def test_review_information_is_skipped(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            store_dir = root / "ios"
            write(store_dir / "en-US" / "name.txt", "Velorki")
            # No length limit applies to review notes; an over-limit file
            # here must not fail the check.
            write(store_dir / "review_information" / "notes.txt", "x" * 5000)
            errors, ok_lines = store_text_check.check_store(
                store_dir, store_text_check.IOS_LIMITS, root
            )
            self.assertEqual(errors, [])
            self.assertEqual(len(ok_lines), 1)

    def test_missing_store_dir_is_not_an_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            errors, ok_lines = store_text_check.check_store(
                root / "does-not-exist", store_text_check.IOS_LIMITS, root
            )
            self.assertEqual(errors, [])
            self.assertEqual(ok_lines, [])

    def test_one_bad_locale_does_not_hide_another(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            store_dir = root / "ios"
            write(store_dir / "en-US" / "name.txt", "Velorki")
            write(store_dir / "de-DE" / "name.txt", "x" * 31)
            errors, ok_lines = store_text_check.check_store(
                store_dir, store_text_check.IOS_LIMITS, root
            )
            self.assertEqual(len(errors), 1)
            self.assertIn("de-DE", errors[0])
            self.assertEqual(len(ok_lines), 1)
            self.assertIn("en-US", ok_lines[0])


class MainOnRealFilesTests(unittest.TestCase):
    def test_main_passes_on_the_committed_texts(self):
        # The committed store texts must already satisfy the limits; a
        # regression here should fail this test rather than only CI.
        self.assertEqual(store_text_check.main(), 0)


if __name__ == "__main__":
    unittest.main()
