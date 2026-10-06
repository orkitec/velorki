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
import re

TABLE_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "translit.json")

# The meta row a transliterated file carries.
SEARCH_SCRIPT = "latin"

with open(TABLE_PATH, encoding="utf-8") as _handle:
    _TABLE = json.load(_handle)
LETTERS: dict[str, str] = _TABLE["letters"]
# Greek "μπ" is "b" at the start of a word ("Μπάρι"), "mp" inside one.
STARTS: dict[str, str] = _TABLE["starts"]
# Greek "ου" is "ou", "αυ"/"ευ" are "av"/"ev": not the sum of their letters.
DIGRAPHS: dict[str, str] = _TABLE["digraphs"]

_TRANSLATE = {ord(letter): latin for letter, latin in LETTERS.items()}
_STARTS = re.compile(r"(?<![^\W\d_])(" + "|".join(map(re.escape, STARTS)) + ")")
_DIGRAPHS = re.compile("|".join(map(re.escape, DIGRAPHS)))


def translit(name: str) -> str:
    """`name` as the index holds it: lower-cased, word starts, digraphs, then
    letter by letter."""
    text = name.lower()
    text = _STARTS.sub(lambda m: STARTS[m.group(1)], text)
    text = _DIGRAPHS.sub(lambda m: DIGRAPHS[m.group(0)], text)
    return text.translate(_TRANSLATE)
