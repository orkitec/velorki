#!/usr/bin/env python3
"""Generate search-quality test cases from a `<TILE>.gaz`.

    testset.py fixtures/E5_N45.gaz --out testset/generated
    testset.py ~/.cache/velorki-tiles/gaz/W75_N40.gaz --out testset/generated --per-kind 15

Samples real rows of the file — places, streets, named POIs and aliases — and
writes query/expected pairs the way a rider would mistype them, one JSON file
per tile. Every case carries the `kind` of corruption it was made with, so the
scorer (`app/test/search_quality/`) can say which kinds the search handles and
which it does not. The rules are letter-based and know no language: the only
word knowledge is `ABBREVIATIONS`, a table applied where one of its words
occurs, and `COMPOUND_SUFFIXES`, the places a long word is likely to be split.

Deterministic: the same file and `--seed` produce byte-identical output, so a
regenerated file diffs cleanly. A case looks like

    {"query": "Hauptstr. 12", "kind": "address_abbrev",
     "expected": {"table": "streets", "id": 4711, "name": "Hauptstraße",
                  "lat": 47.14, "lon": 9.52, "place": "Vaduz"},
     "tile": "E5_N45", "near": {"lat": 47.15, "lon": 9.53}}

`near` is a plausible rider position — the row's own point moved a few
kilometres — so distance ranking is scored too. `expected.id` is the row id in
the file the case was made from; a later build renumbers, which is why the
scorer matches by name and position, not by id.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import random
import re
import sqlite3
import sys
import unicodedata
from typing import Callable, Iterator, NamedTuple

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from street_numbers import POINT_SCALE, decode  # noqa: E402

COORD_SCALE = 1e7

# How far `near` is from the row: a rider who has just set off, or is looking
# at the town on the map.
NEAR_MIN_KM = 0.5
NEAR_MAX_KM = 3.0

# A name shorter than this is not mistyped: one wrong letter in "Rom" leaves
# nothing to find.
MIN_TYPO_LETTERS = 5

# A single word of at least this many letters is a compound worth splitting.
MIN_COMPOUND_LETTERS = 8

# POI kinds left out of the sample: `building` is the fallback kind and most of
# its rows are not what anybody types.
SKIPPED_POI_KINDS = frozenset({"building"})

# Keys next to each other on a QWERTY or a QWERTZ keyboard, the union of both,
# so a slip of the thumb looks the same whatever the phone's layout. Only Latin
# letters; a word in another script gets a wrong letter out of its own name.
KEY_NEIGHBOURS = {
    "q": "wasz", "w": "qeasd", "e": "wrsdf", "r": "etdfg", "t": "ryzufgh",
    "y": "tughjz", "u": "yzihj", "i": "uojk", "o": "ipkl", "p": "ol",
    "a": "qwszy", "s": "adwezxy", "d": "sferxc", "f": "dgrtcv", "g": "fhtyzvb",
    "h": "gjyzubn", "j": "hkuinm", "k": "jliom", "l": "kop",
    "z": "tughasx", "x": "zcsdy", "c": "xvdf", "v": "cbfg", "b": "vngh",
    "n": "bmhj", "m": "njk",
}

# Words riders shorten, and how. Matched as whole words, case-insensitively;
# the `straße` family also as the tail of a compound ("Hauptstraße" →
# "Hauptstr."). This is data, not language logic: a rule only ever fires on a
# name that contains its word.
ABBREVIATIONS: list[tuple[str, list[str]]] = [
    # German
    ("straße", ["str.", "str"]),
    ("strasse", ["str.", "str"]),
    ("platz", ["pl."]),
    ("sankt", ["st."]),
    # English
    ("street", ["st", "st."]),
    ("avenue", ["ave", "av."]),
    ("road", ["rd"]),
    ("boulevard", ["blvd", "bd"]),
    ("drive", ["dr"]),
    ("place", ["pl", "pl."]),
    ("lane", ["ln"]),
    ("court", ["ct"]),
    ("square", ["sq"]),
    ("parkway", ["pkwy"]),
    ("highway", ["hwy"]),
    ("saint", ["st", "st."]),
    ("north", ["n"]),
    ("south", ["s"]),
    ("east", ["e"]),
    ("west", ["w"]),
    # Portuguese
    ("rua", ["r."]),
    ("avenida", ["av.", "avda."]),
    ("travessa", ["tv."]),
    ("estrada", ["estr."]),
    ("largo", ["lg."]),
    ("praça", ["pç."]),
    # Spanish
    ("calle", ["c/", "c."]),
    ("paseo", ["pº", "p.º"]),
    ("plaza", ["pza."]),
    # Italian
    ("via", ["v."]),
    ("viale", ["v.le"]),
    ("piazza", ["p.za"]),
    ("corso", ["c.so"]),
    # French
    ("rue", ["r."]),
    ("chemin", ["ch."]),
    ("impasse", ["imp."]),
    ("sainte", ["ste"]),
    # Dutch
    ("straat", ["str."]),
    # Bulgarian / Russian
    ("улица", ["ул."]),
    ("булевард", ["бул."]),
    ("бульвар", ["бул."]),
    ("площад", ["пл."]),
]

# The generic words a partial query must not consist of: "Rua" alone finds
# every street in Lisbon. Every full word of the table above, plus articles.
GENERIC_WORDS = frozenset(word for word, _ in ABBREVIATIONS) | frozenset(
    "de da do das dos del della delle di du des la le les el los las van der "
    "den the of and y e und am im an in zum zur".split()
)

# Where a long word is likely to be split: before one of these when it ends
# the word ("Bahnhofstraße" → "Bahnhof straße"), otherwise at a vowel-consonant
# boundary near the middle.
COMPOUND_SUFFIXES = (
    "straße", "strasse", "gasse", "platz", "allee", "weg", "ring", "damm",
    "brücke", "mühle", "markt", "straat", "laan", "plein", "berg", "burg",
    "dorf", "hof", "feld", "bach", "tal", "wald", "see", "stadt", "hausen",
    "heim", "kirchen", "park", "wood", "field", "ford", "bridge", "town",
    "ville", "mont",
)

# A few letters NFD does not decompose and the index folds anyway.
PLAIN_LETTERS = str.maketrans(
    {"ø": "o", "Ø": "O", "ł": "l", "Ł": "L", "đ": "d", "Đ": "D", "æ": "ae",
     "Æ": "Ae", "œ": "oe", "Œ": "Oe", "ı": "i"}
)

VOWELS = set("aeiouyäöüáéíóúàèìòùâêîôûãõåø")


class Row(NamedTuple):
    table: str
    id: int
    name: str
    lat: float
    lon: float
    place: str | None


class Anchor(NamedTuple):
    number: int
    lat: float
    lon: float


class Corruption(NamedTuple):
    """One way to mistype a name."""

    kind: str
    applies: Callable[[str], bool]
    apply: Callable[[str, random.Random], str]


# ------------------------------------------------------------ text helpers ---


def words_of(name: str) -> list[str]:
    return [w for w in name.split() if w]


def letters(word: str) -> int:
    return sum(1 for c in word if c.isalpha())


def is_letter_run(word: str) -> bool:
    return len(word) >= 2 and all(c.isalpha() for c in word)


def edit_distance(a: str, b: str) -> int:
    """Damerau-Levenshtein (optimal string alignment), the metric the app's
    spelling pass uses, so the tests can assert a typo is one edit away."""
    if a == b:
        return 0
    d = [[0] * (len(b) + 1) for _ in range(len(a) + 1)]
    for i in range(len(a) + 1):
        d[i][0] = i
    for j in range(len(b) + 1):
        d[0][j] = j
    for i in range(1, len(a) + 1):
        for j in range(1, len(b) + 1):
            cost = 0 if a[i - 1] == b[j - 1] else 1
            d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
            if i > 1 and j > 1 and a[i - 1] == b[j - 2] and a[i - 2] == b[j - 1]:
                d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
    return d[len(a)][len(b)]


def strip_accents(text: str) -> str:
    decomposed = unicodedata.normalize("NFD", text.translate(PLAIN_LETTERS))
    return unicodedata.normalize(
        "NFC", "".join(c for c in decomposed if not unicodedata.combining(c))
    )


def pick_word(name: str, rng: random.Random, min_letters: int = 4) -> int | None:
    """The index of a word worth mistyping: a run of letters, long enough,
    chosen at random so one name does not always break in the same place."""
    candidates = [
        i for i, w in enumerate(words_of(name))
        if is_letter_run(w) and letters(w) >= min_letters
    ]
    return rng.choice(candidates) if candidates else None


def replace_word(name: str, index: int, word: str) -> str:
    parts = words_of(name)
    parts[index] = word
    return " ".join(parts)


def mistype_word(name: str, rng: random.Random, change: Callable[[str, random.Random], str]) -> str:
    index = pick_word(name, rng)
    if index is None:
        return name
    word = words_of(name)[index]
    return replace_word(name, index, change(word, rng))


# -------------------------------------------------------------- the typos ---


def swap_adjacent(word: str, rng: random.Random) -> str:
    # Never the first letter, like `drop_letter`.
    positions = [i for i in range(1, len(word) - 1) if word[i] != word[i + 1]]
    i = rng.choice(positions)
    return word[:i] + word[i + 1] + word[i] + word[i + 2:]


def drop_letter(word: str, rng: random.Random) -> str:
    # Never the first letter: the app's spelling pass keeps it, and so do
    # most thumbs.
    i = rng.randrange(1, len(word))
    return word[:i] + word[i + 1:]


def double_letter(word: str, rng: random.Random) -> str:
    i = rng.randrange(len(word))
    return word[:i] + word[i] + word[i:]


def neighbour_key(word: str, rng: random.Random) -> str:
    # Never the first letter, like `drop_letter`.
    positions = [i for i, c in enumerate(word) if i > 0 and c.lower() in KEY_NEIGHBOURS]
    if not positions:
        return word
    i = rng.choice(positions)
    c = word[i]
    other = rng.choice(KEY_NEIGHBOURS[c.lower()])
    return word[:i] + (other.upper() if c.isupper() else other) + word[i + 1:]


def wrong_letter(word: str, rng: random.Random) -> str:
    """A letter replaced by another letter of the same word's script, so a
    Cyrillic name gets a Cyrillic typo."""
    i = rng.randrange(1, len(word))
    c = word[i]
    pool = sorted({x.lower() for x in word if x.isalpha() and x.lower() != c.lower()})
    if c.lower() in KEY_NEIGHBOURS:
        pool = sorted(set("abcdefghijklmnopqrstuvwxyz") - {c.lower()})
    other = rng.choice(pool)
    return word[:i] + (other.upper() if c.isupper() else other) + word[i + 1:]


def has_latin_letter(name: str) -> bool:
    """Whether some word worth mistyping has a Latin letter after its first."""
    return any(
        is_letter_run(w) and letters(w) >= 4 and any(c.lower() in KEY_NEIGHBOURS for c in w[1:])
        for w in words_of(name)
    )


def typo_applies(name: str) -> bool:
    return letters(name) >= MIN_TYPO_LETTERS and any(
        is_letter_run(w) and letters(w) >= 4 for w in words_of(name)
    )


def wrong_letter_applies(name: str) -> bool:
    # Needs two different letters in some word to draw a replacement from.
    return typo_applies(name) and any(
        len({c.lower() for c in w if c.isalpha()}) >= 2 for w in words_of(name)
    )


# ------------------------------------------------------------- the others ---


def to_ss(name: str, _: random.Random) -> str:
    return name.replace("ß", "ss")


def to_sz(name: str, rng: random.Random) -> str:
    positions = [m.start() for m in re.finditer("ss", name)]
    i = rng.choice(positions)
    return name[:i] + "ß" + name[i + 2:]


def change_case(name: str, rng: random.Random) -> str:
    lowered = name.lower()
    if lowered != name and rng.random() < 0.7:
        return lowered
    upper = name.upper()
    return upper if upper != name else lowered


def abbreviation_sites(name: str) -> list[tuple[int, int, str]]:
    """Every (start, end, full word) in `name` an abbreviation rule covers."""
    sites: list[tuple[int, int, str]] = []
    lowered = name.lower()
    for word, _ in ABBREVIATIONS:
        for m in re.finditer(r"(?<![^\W\d_])" + re.escape(word) + r"(?![^\W\d_])", lowered):
            sites.append((m.start(), m.end(), word))
        if word in ("straße", "strasse", "straat"):
            # The tail of a compound: "Hauptstraße", "Kerkstraat".
            for m in re.finditer(r"[^\W\d_]{3,}" + re.escape(word) + r"(?![^\W\d_])", lowered):
                sites.append((m.end() - len(word), m.end(), word))
    return sorted(set(sites))


def abbreviate(name: str, rng: random.Random) -> str:
    start, end, word = rng.choice(abbreviation_sites(name))
    short = rng.choice(dict(ABBREVIATIONS)[word])
    if name[start].isupper():
        short = short[0].upper() + short[1:]
    return name[:start] + short + name[end:]


def split_point(word: str) -> int | None:
    lowered = word.lower()
    for suffix in COMPOUND_SUFFIXES:
        if lowered.endswith(suffix) and len(word) - len(suffix) >= 3:
            return len(word) - len(suffix)
    # Otherwise where a word is likely to begin: a consonant followed by a
    # consonant and a vowel ("Lock|wood"), as close to the middle as possible,
    # or failing that a consonant followed by a vowel ("Ober|al").
    middle = len(word) // 2
    best = None
    for want_consonant in (True, False):
        for i in range(3, len(word) - 2):
            before, here, after = lowered[i - 1], lowered[i], lowered[i + 1]
            if before in VOWELS or not here.isalpha():
                continue
            if want_consonant and (here in VOWELS or after not in VOWELS):
                continue
            if not want_consonant and here not in VOWELS:
                continue
            if best is None or abs(i - middle) < abs(best - middle):
                best = i
        if best is not None:
            return best
    return None


def compound_candidates(name: str) -> list[int]:
    return [
        i for i, w in enumerate(words_of(name))
        if is_letter_run(w) and letters(w) >= MIN_COMPOUND_LETTERS and split_point(w) is not None
    ]


def split_compound(name: str, rng: random.Random) -> str:
    index = rng.choice(compound_candidates(name))
    word = words_of(name)[index]
    at = split_point(word)
    assert at is not None
    return replace_word(name, index, word[:at] + " " + word[at:])


def join_candidates(name: str) -> list[int]:
    parts = words_of(name)
    return [
        i for i in range(len(parts) - 1)
        if is_letter_run(parts[i]) and is_letter_run(parts[i + 1])
        and letters(parts[i]) >= 3 and letters(parts[i + 1]) >= 3
    ]


def join_compound(name: str, rng: random.Random) -> str:
    parts = words_of(name)
    i = rng.choice(join_candidates(name))
    second = parts[i + 1]
    if parts[i][0].isupper() and second[0].isupper():
        second = second[0].lower() + second[1:]
    parts[i:i + 2] = [parts[i] + second]
    return " ".join(parts)


def partial_word(name: str, which: int) -> str | None:
    parts = words_of(name)
    if len(parts) < 2:
        return None
    word = parts[which]
    if not is_letter_run(word) or letters(word) < 4 or word.lower() in GENERIC_WORDS:
        return None
    return word


def first_word_applies(name: str) -> bool:
    return partial_word(name, 0) is not None


def last_word_applies(name: str) -> bool:
    return partial_word(name, -1) is not None


def first_word(name: str, _: random.Random) -> str:
    return partial_word(name, 0) or name


def last_word(name: str, _: random.Random) -> str:
    return partial_word(name, -1) or name


def prefix_applies(name: str) -> bool:
    return letters(name) >= 6 and name[:4].strip() == name[:4]


def prefix(name: str, rng: random.Random) -> str:
    # Between four letters and all but one, never ending in a space.
    n = rng.randrange(4, max(5, len(name) - 1))
    while n < len(name) - 1 and name[n - 1] == " ":
        n += 1
    return name[:n].rstrip()


CORRUPTIONS: list[Corruption] = [
    Corruption("exact", lambda n: True, lambda n, r: n),
    Corruption("typo_swap", typo_applies, lambda n, r: mistype_word(n, r, swap_adjacent)),
    Corruption("typo_missing", typo_applies, lambda n, r: mistype_word(n, r, drop_letter)),
    Corruption("typo_double", typo_applies, lambda n, r: mistype_word(n, r, double_letter)),
    Corruption(
        "typo_neighbour",
        lambda n: typo_applies(n) and has_latin_letter(n),
        lambda n, r: mistype_word(n, r, neighbour_key),
    ),
    Corruption("typo_wrong", wrong_letter_applies, lambda n, r: mistype_word(n, r, wrong_letter)),
    Corruption("accent_drop", lambda n: strip_accents(n) != n, lambda n, r: strip_accents(n)),
    Corruption("sz_to_ss", lambda n: "ß" in n, to_ss),
    Corruption("ss_to_sz", lambda n: "ss" in n and "ß" not in n, to_sz),
    Corruption("case", lambda n: n.lower() != n or n.upper() != n, change_case),
    Corruption("abbrev", lambda n: bool(abbreviation_sites(n)), abbreviate),
    Corruption("compound_split", lambda n: bool(compound_candidates(n)), split_compound),
    Corruption("compound_join", lambda n: bool(join_candidates(n)), join_compound),
    Corruption("partial_first", first_word_applies, first_word),
    Corruption("partial_last", last_word_applies, last_word),
    Corruption("partial_prefix", prefix_applies, prefix),
]

# Address cases are built from a street and one of its house-number points
# (or an older file's anchors), not from the name alone, so they are a second
# list with their own shape.
ADDRESS_KINDS = (
    "address_after",
    "address_before",
    "address_suffix",
    "address_range",
    "address_place",
    "address_abbrev",
)

ALL_KINDS = tuple(c.kind for c in CORRUPTIONS) + ADDRESS_KINDS + ("alias",)


def address_query(kind: str, street: Row, number: int, rng: random.Random) -> str | None:
    name = street.name
    if kind == "address_after":
        return f"{name} {number}"
    if kind == "address_before":
        return f"{number} {name}"
    if kind == "address_suffix":
        return f"{name} {number}{rng.choice('abc')}"
    if kind == "address_range":
        return f"{name} {number}-{number + 2}"
    if kind == "address_place":
        if not street.place:
            return None
        return (
            f"{name} {number} {street.place}"
            if rng.random() < 0.5
            else f"{number} {name}, {street.place}"
        )
    if kind == "address_abbrev":
        if not abbreviation_sites(name):
            return None
        return f"{abbreviate(name, rng)} {number}"
    raise ValueError(kind)


# ------------------------------------------------------------------ sampling ---


def load_rows(db: sqlite3.Connection) -> dict[str, list[Row]]:
    places = {
        row[0]: row[1] for row in db.execute("SELECT id, name FROM places")
    }

    def rows(sql: str, table: str) -> list[Row]:
        out = []
        for id_, name, lat, lon, place_id in db.execute(sql):
            if not name or not name.strip():
                continue
            out.append(Row(table, id_, name.strip(), lat / COORD_SCALE, lon / COORD_SCALE, places.get(place_id)))
        return out

    skipped = ", ".join(f"'{k}'" for k in sorted(SKIPPED_POI_KINDS))
    return {
        "places": rows("SELECT id, name, lat, lon, admin_id FROM places ORDER BY id", "places"),
        "streets": rows("SELECT id, name, lat, lon, place_id FROM streets ORDER BY id", "streets"),
        "pois": rows(
            f"SELECT id, name, lat, lon, place_id FROM pois WHERE name IS NOT NULL "
            f"AND kind NOT IN ({skipped}) ORDER BY id",
            "pois",
        ),
    }


def load_anchors(db: sqlite3.Connection) -> dict[int, list[Anchor]]:
    """Every stored house number and its position, per street.

    `street_numbers` points (odd side, then even) where the file has them,
    else an older file's `house_numbers` anchors, else nothing.
    """
    anchors: dict[int, list[Anchor]] = {}
    try:
        blobs = db.execute("SELECT street_id, data FROM street_numbers ORDER BY street_id").fetchall()
    except sqlite3.OperationalError:
        blobs = None
    if blobs is not None:
        for street_id, data in blobs:
            odd, even = decode(data)
            anchors[street_id] = [
                Anchor(number, lat / POINT_SCALE, lon / POINT_SCALE) for number, lat, lon in odd + even
            ]
        return anchors
    try:
        rows = db.execute("SELECT street_id, number, lat, lon FROM house_numbers ORDER BY street_id, number")
    except sqlite3.OperationalError:
        return anchors
    for street_id, number, lat, lon in rows:
        anchors.setdefault(street_id, []).append(Anchor(number, lat / COORD_SCALE, lon / COORD_SCALE))
    return anchors


def load_aliases(db: sqlite3.Connection, rows: dict[str, list[Row]]) -> list[tuple[str, Row]]:
    by_id = {row.id: row for table in rows.values() for row in table}
    try:
        found = db.execute("SELECT name, ref_id FROM aliases ORDER BY id")
    except sqlite3.OperationalError:
        return []
    out = []
    for name, ref_id in found:
        target = by_id.get(ref_id)
        if target is not None and name and name.strip() and name.strip() != target.name:
            out.append((name.strip(), target))
    return out


def jitter(lat: float, lon: float, rng: random.Random) -> tuple[float, float]:
    km = rng.uniform(NEAR_MIN_KM, NEAR_MAX_KM)
    bearing = rng.uniform(0, 2 * math.pi)
    d_lat = km * math.cos(bearing) / 111.32
    d_lon = km * math.sin(bearing) / (111.32 * max(math.cos(math.radians(lat)), 0.01))
    return round(lat + d_lat, 6), round(lon + d_lon, 6)


def draw(
    pools: list[list[Row]],
    count: int,
    applies: Callable[[Row], bool],
    rng: random.Random,
) -> list[Row]:
    """`count` rows that pass `applies`, drawn across the pools in turn, so a
    kind is scored on places, streets and POIs alike where all three apply.

    Each pool is walked in a shuffled order and only as far as needed: a tile
    has a million streets and testing every one against every rule is what
    made the first version take minutes."""
    walks: list[tuple[list[Row], Iterator[int]]] = []
    for pool in pools:
        if not pool:
            continue
        order = list(range(len(pool)))
        rng.shuffle(order)
        walks.append((pool, iter(order)))
    picked: list[Row] = []
    while walks and len(picked) < count:
        for walk in list(walks):
            pool, order = walk
            for index in order:
                row = pool[index]
                if applies(row):
                    picked.append(row)
                    break
            else:
                walks.remove(walk)
            if len(picked) >= count:
                break
    return picked


def make_case(
    query: str, row: Row, kind: str, tile: str, rng: random.Random,
    at: tuple[float, float] | None = None,
) -> dict:
    lat, lon = at or (row.lat, row.lon)
    near_lat, near_lon = jitter(lat, lon, rng)
    return {
        "query": query,
        "kind": kind,
        "expected": {
            "table": row.table,
            "id": row.id,
            "name": row.name,
            "lat": round(lat, 7),
            "lon": round(lon, 7),
            "place": row.place,
        },
        "tile": tile,
        "near": {"lat": near_lat, "lon": near_lon},
    }


def generate(path: str, seed: int = 1, per_kind: int = 15) -> dict:
    db = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    try:
        meta = dict(db.execute("SELECT key, value FROM meta"))
        rows = load_rows(db)
        anchors = load_anchors(db)
        aliases = load_aliases(db, rows)
    finally:
        db.close()
    tile = meta.get("tile") or os.path.splitext(os.path.basename(path))[0]
    rng = random.Random(seed)
    cases: list[dict] = []
    used: set[tuple[str, str]] = set()

    def add(case: dict) -> None:
        key = (case["kind"], case["query"].lower())
        if key in used or not case["query"].strip():
            return
        used.add(key)
        cases.append(case)

    tables = [rows["places"], rows["streets"], rows["pois"]]
    for corruption in CORRUPTIONS:
        for row in draw(tables, per_kind, lambda r: corruption.applies(r.name), rng):
            query = corruption.apply(row.name, rng)
            if corruption.kind != "exact" and query == row.name:
                continue
            add(make_case(query, row, corruption.kind, tile, rng))

    for kind in ADDRESS_KINDS:

        def addressed(r: Row, kind: str = kind) -> bool:
            if not anchors.get(r.id):
                return False
            if kind == "address_place":
                return bool(r.place)
            if kind == "address_abbrev":
                return bool(abbreviation_sites(r.name))
            return True

        for street in draw([rows["streets"]], per_kind, addressed, rng):
            anchor = rng.choice(anchors[street.id])
            query = address_query(kind, street, anchor.number, rng)
            if query is None:
                continue
            add(make_case(query, street, kind, tile, rng, at=(anchor.lat, anchor.lon)))

    shuffled = list(aliases)
    rng.shuffle(shuffled)
    for alias, target in shuffled[:per_kind]:
        add(make_case(alias, target, "alias", tile, rng))

    return {
        "tile": tile,
        "source": os.path.basename(path),
        "gaz_built_at": meta.get("built_at"),
        "seed": seed,
        "per_kind": per_kind,
        "cases": cases,
    }


def write(testset: dict, out: str) -> str:
    if os.path.isdir(out) or not out.endswith(".json"):
        os.makedirs(out, exist_ok=True)
        out = os.path.join(out, f"{testset['tile']}.json")
    # One case per line: compact, and a regenerated file diffs by case.
    head = {k: v for k, v in testset.items() if k != "cases"}
    with open(out, "w", encoding="utf-8") as f:
        f.write("{\n")
        for key, value in head.items():
            f.write(f" {json.dumps(key)}: {json.dumps(value, ensure_ascii=False)},\n")
        f.write(' "cases": [\n')
        lines = [json.dumps(case, ensure_ascii=False) for case in testset["cases"]]
        f.write(",\n".join("  " + line for line in lines))
        f.write("\n ]\n}\n")
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("gaz", nargs="+", help="one or more <TILE>.gaz files")
    parser.add_argument("--out", default="testset/generated", help="directory (or one .json for one file)")
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--per-kind", type=int, default=15, help="cases per corruption kind")
    args = parser.parse_args()
    for path in args.gaz:
        testset = generate(path, seed=args.seed, per_kind=args.per_kind)
        written = write(testset, args.out)
        kinds = sorted({c["kind"] for c in testset["cases"]})
        print(f"{testset['tile']}: {len(testset['cases'])} cases, {len(kinds)} kinds -> {written}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
