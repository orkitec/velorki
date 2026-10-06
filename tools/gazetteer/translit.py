"""The text the FTS index holds for a name: lower-cased, Cyrillic and Greek
letters written in Latin.

translit.json, next to this file, is the table, shared with the app, which
reads queries the same way. A file built with it says so in its meta row
`search_script` = `latin`. Every character not in the table stays as it is:
Latin with diacritics is left to the tokenizer (`remove_diacritics 2`).

A name with і, ї, є or ґ, letters only Ukrainian writes, gets a second
spelling beside the first: `starts_uk` and `letters_uk`, the Ukrainian
national romanisation riders meet on signs and in the official spelling
(`Київ` -> `kyiv`, where the first table gives `kiyiv`). Any other Cyrillic
name (Bulgarian, Russian, Serbian) gets the first alone. `index_text` is what
the FTS index holds.

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

# The second Cyrillic spelling: the same letters, Ukrainian values.
STARTS_UK: dict[str, str] = _TABLE["starts_uk"]
LETTERS_UK: dict[str, str] = _TABLE["letters_uk"]

_TRANSLATE = {ord(letter): latin for letter, latin in LETTERS.items()}
_STARTS = re.compile(r"(?<![^\W\d_])(" + "|".join(map(re.escape, STARTS)) + ")")
_DIGRAPHS = re.compile("|".join(map(re.escape, DIGRAPHS)))
_TRANSLATE_UK = {ord(letter): latin for letter, latin in LETTERS_UK.items()}
_STARTS_UK = re.compile(r"(?<![^\W\d_])(" + "|".join(map(re.escape, STARTS_UK)) + ")")
_WORD = re.compile(r"[^\W_]+")
# Letters only Ukrainian writes: a name with one gets the second spelling.
_UKRAINIAN = re.compile("[іїєґІЇЄҐ]")


def translit(name: str) -> str:
    """`name` as the index holds it: lower-cased, word starts, digraphs, then
    letter by letter."""
    text = name.lower()
    text = _STARTS.sub(lambda m: STARTS[m.group(1)], text)
    text = _DIGRAPHS.sub(lambda m: DIGRAPHS[m.group(0)], text)
    return text.translate(_TRANSLATE)


def translit_alt(name: str) -> str:
    """`name` in the second Cyrillic spelling: lower-cased, `starts_uk` at the
    start of a word, then `letters_uk` letter by letter. Anything else goes
    through `translit`, so a Greek letter in the name still comes out Latin."""
    text = name.lower()
    text = _STARTS_UK.sub(lambda m: STARTS_UK[m.group(1)], text)
    return translit(text.translate(_TRANSLATE_UK))


def has_ukrainian_letter(text: str) -> bool:
    """Whether `text` holds і, ї, є or ґ, in either case."""
    return _UKRAINIAN.search(text) is not None


def index_text(name: str) -> str:
    """What the FTS index holds for `name`: `translit(name)`, and for a name
    with a Ukrainian-only letter (`has_ukrainian_letter`) the words of `translit_alt(name)` that it does not
    already hold, after a space. A word is what the tokenizer cuts: a run of
    letters and digits."""
    text = translit(name)
    if not has_ukrainian_letter(name):
        return text
    seen = set(_WORD.findall(text))
    extra = []
    for word in _WORD.findall(translit_alt(name)):
        if word not in seen:
            seen.add(word)
            extra.append(word)
    return " ".join([text] + extra) if extra else text
