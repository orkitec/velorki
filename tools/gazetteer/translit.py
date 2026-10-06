"""The text the FTS index holds for a name: lower-cased, Cyrillic and Greek
letters written in Latin.

translit.json, next to this file, is the table, shared with the app, which
reads queries the same way. A file built with it says so in its meta row
`search_script` = `latin`. Every character not in the table stays as it is:
Latin with diacritics is left to the tokenizer (`remove_diacritics 2`).

Standard library only: merge.py and check.py use it.
"""

from __future__ import annotations

import json
import os

TABLE_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "translit.json")

# The meta row a transliterated file carries.
SEARCH_SCRIPT = "latin"

with open(TABLE_PATH, encoding="utf-8") as _handle:
    LETTERS: dict[str, str] = json.load(_handle)["letters"]

_TRANSLATE = {ord(letter): latin for letter, latin in LETTERS.items()}


def translit(name: str) -> str:
    """`name` as the index holds it: lower-cased, then letter by letter."""
    return name.lower().translate(_TRANSLATE)
