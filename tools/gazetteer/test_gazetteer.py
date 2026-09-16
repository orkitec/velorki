#!/usr/bin/env python3
"""Tests for the gazetteer builder.

    venv/bin/python -m unittest tools/gazetteer/test_gazetteer.py

Builds the Liechtenstein extract once with and once without `--streets` into a
temporary directory, then asserts the file format, the query contract and the
mirror tooling against it. Needs pyosmium and the extract; set
`GAZ_EXTRACT` to point at another copy of `liechtenstein.osm.pbf`.
"""

from __future__ import annotations

import ast
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import build  # noqa: E402
import check  # noqa: E402
import manifest  # noqa: E402
import merge  # noqa: E402
import query  # noqa: E402

EXTRACT_NAME = "liechtenstein.osm.pbf"


def find_extract() -> str | None:
    """The 3.5 MB Geofabrik extract these tests build from.

    It is not committed (the .gaz fixture built from it is). Point GAZ_EXTRACT
    at a copy, or drop one next to this file or in the working directory.
    """
    candidates = [
        os.environ.get("GAZ_EXTRACT"),
        os.path.join(HERE, EXTRACT_NAME),
        os.path.join(os.getcwd(), EXTRACT_NAME),
        os.path.join(tempfile.gettempdir(), EXTRACT_NAME),
    ]
    for path in candidates:
        if path and os.path.isfile(path):
            return path
    return None


TILE = "E5_N45"

# Every kind `pois.kind` may hold: the rider's kit, then the landmarks.
POI_KINDS = frozenset(
    """
    drinking_water cafe bicycle_repair_station shelter bicycle_shop station
    viewpoint peak park
    attraction museum historic place_of_worship hospital university stadium
    mall airport ferry_terminal tower lighthouse water beach nature_reserve
    building
    """.split()
)


class GazetteerTest(unittest.TestCase):
    tmp: str
    plain: str
    with_streets: str

    @classmethod
    def setUpClass(cls) -> None:
        extract = find_extract()
        if extract is None:
            raise unittest.SkipTest(
                "liechtenstein.osm.pbf not found; set GAZ_EXTRACT to its path"
            )
        cls.tmp = tempfile.mkdtemp(prefix="gaz-test-")
        cls.plain = os.path.join(cls.tmp, "plain")
        cls.with_streets = os.path.join(cls.tmp, "streets")
        for out, streets in ((cls.plain, False), (cls.with_streets, True)):
            os.makedirs(out)
            subprocess.run(
                [sys.executable, os.path.join(HERE, "build.py"), extract, "--out", out]
                + (["--streets"] if streets else []),
                check=True,
                capture_output=True,
            )

    @classmethod
    def tearDownClass(cls) -> None:
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def path(self, streets: bool = True) -> str:
        root = self.with_streets if streets else self.plain
        return os.path.join(root, f"{TILE}.gaz")

    def open(self, streets: bool = True) -> sqlite3.Connection:
        db = sqlite3.connect(f"file:{self.path(streets)}?mode=ro", uri=True)
        self.addCleanup(db.close)
        return db

    # ------------------------------------------------------------ schema ---

    def test_schema_is_the_spec(self) -> None:
        db = self.open()
        columns = {
            table: [
                (row[1], row[2])
                for row in db.execute(f"PRAGMA table_info({table})")
            ]
            for table in ("meta", "places", "streets", "pois")
        }
        self.assertEqual(columns["meta"], [("key", "TEXT"), ("value", "TEXT")])
        self.assertEqual(
            columns["places"],
            [
                ("id", "INTEGER"),
                ("name", "TEXT"),
                ("kind", "TEXT"),
                ("lat", "INTEGER"),
                ("lon", "INTEGER"),
                ("population", "INTEGER"),
                ("admin_id", "INTEGER"),
                ("osm_type", "TEXT"),
                ("osm_id", "INTEGER"),
            ],
        )
        self.assertEqual(
            columns["streets"],
            [
                ("id", "INTEGER"),
                ("name", "TEXT"),
                ("lat", "INTEGER"),
                ("lon", "INTEGER"),
                ("place_id", "INTEGER"),
                ("osm_type", "TEXT"),
                ("osm_id", "INTEGER"),
            ],
        )
        self.assertEqual(
            columns["pois"],
            [
                ("id", "INTEGER"),
                ("name", "TEXT"),
                ("kind", "TEXT"),
                ("lat", "INTEGER"),
                ("lon", "INTEGER"),
                ("place_id", "INTEGER"),
                ("osm_type", "TEXT"),
                ("osm_id", "INTEGER"),
            ],
        )
        sql = db.execute(
            "SELECT sql FROM sqlite_master WHERE name = 'search'"
        ).fetchone()[0]
        self.assertIn("content=''", sql)
        self.assertIn("columnsize=0", sql)
        self.assertIn("remove_diacritics 2", sql)
        self.assertNotIn("prefix=", sql)
        indexes = {
            row[0]
            for row in db.execute(
                "SELECT name FROM sqlite_master WHERE type = 'index'"
            )
        }
        self.assertLessEqual(
            {"idx_places_pos", "idx_streets_pos", "idx_pois_pos"}, indexes
        )
        self.assertEqual(db.execute("PRAGMA page_size").fetchone()[0], 4096)
        self.assertEqual(
            db.execute("PRAGMA journal_mode").fetchone()[0].lower(), "delete"
        )

    def test_meta_rows(self) -> None:
        meta = dict(self.open().execute("SELECT key, value FROM meta"))
        self.assertEqual(meta["schema_version"], "1")
        self.assertEqual(meta["tile"], TILE)
        self.assertEqual(meta["has_streets"], "1")
        self.assertEqual(meta["has_pois"], "1")
        self.assertEqual(meta["source"], "liechtenstein.osm.pbf")
        self.assertRegex(meta["built_at"], r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$")

        plain = dict(self.open(streets=False).execute("SELECT key, value FROM meta"))
        self.assertEqual(plain["has_streets"], "0")
        self.assertEqual(plain["has_pois"], "1")

    def test_default_build_has_no_streets(self) -> None:
        db = self.open(streets=False)
        self.assertEqual(db.execute("SELECT count(*) FROM streets").fetchone()[0], 0)
        self.assertGreater(db.execute("SELECT count(*) FROM pois").fetchone()[0], 0)

    def test_ids_are_unique_across_the_three_tables(self) -> None:
        db = self.open()
        ids = [
            row[0]
            for table in ("places", "streets", "pois")
            for row in db.execute(f"SELECT id FROM {table}")
        ]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertEqual(sorted(ids), list(range(1, len(ids) + 1)))

    def test_foreign_keys_resolve(self) -> None:
        db = self.open()
        place_ids = {row[0] for row in db.execute("SELECT id FROM places")}
        for table, column in (
            ("places", "admin_id"),
            ("streets", "place_id"),
            ("pois", "place_id"),
        ):
            refs = {
                row[0]
                for row in db.execute(
                    f"SELECT {column} FROM {table} WHERE {column} IS NOT NULL"
                )
            }
            self.assertTrue(refs, f"{table}.{column} is never set")
            self.assertLessEqual(refs, place_ids, f"{table}.{column} dangles")

    def test_coordinates_are_scaled_integers(self) -> None:
        lat, lon = self.open().execute(
            "SELECT lat, lon FROM places WHERE name = 'Vaduz'"
        ).fetchone()
        self.assertIsInstance(lat, int)
        self.assertIsInstance(lon, int)
        self.assertAlmostEqual(lat / 1e7, 47.139, places=2)
        self.assertAlmostEqual(lon / 1e7, 9.522, places=2)

    def test_only_named_pois(self) -> None:
        db = self.open()
        self.assertEqual(
            db.execute(
                "SELECT count(*) FROM pois WHERE name IS NULL OR name = ''"
            ).fetchone()[0],
            0,
        )
        self.assertEqual(
            db.execute(
                "SELECT count(*) FROM pois WHERE name <> trim(name)"
            ).fetchone()[0],
            0,
        )
        kinds = {row[0] for row in db.execute("SELECT DISTINCT kind FROM pois")}
        self.assertIn("peak", kinds)
        self.assertTrue(kinds & {"drinking_water", "cafe"})
        self.assertLessEqual(kinds, POI_KINDS)

    def test_landmark_kinds_are_collected(self) -> None:
        """The kinds a rider searches for by name, not just the ones on the
        road. Liechtenstein has at least one of each of these."""
        kinds = {row[0] for row in self.open().execute("SELECT DISTINCT kind FROM pois")}
        self.assertLessEqual(
            {
                "building",
                "historic",
                "museum",
                "place_of_worship",
                "attraction",
                "stadium",
                "water",
                "nature_reserve",
                "tower",
                "university",
                "hospital",
            },
            kinds,
        )

    def test_a_named_building_is_a_poi(self) -> None:
        """Vaduz town hall: amenity=townhall is not a kind of its own, so the
        building tag is what puts it in the search box."""
        row = self.open().execute(
            "SELECT kind, osm_type FROM pois WHERE name = 'Rathaus Vaduz'"
        ).fetchone()
        self.assertEqual(row, ("building", "w"))

    def test_a_church_is_a_place_of_worship(self) -> None:
        """building=cathedral, but the amenity is the useful kind."""
        row = self.open().execute(
            "SELECT kind FROM pois WHERE name = 'Kathedrale St. Florin'"
        ).fetchone()
        self.assertEqual(row[0], "place_of_worship")

    def test_a_more_specific_kind_wins_over_building(self) -> None:
        """One object, one row: the art museum is a building=yes way too."""
        rows = self.open().execute(
            "SELECT kind FROM pois WHERE name = 'Kunstmuseum Liechtenstein'"
        ).fetchall()
        self.assertEqual(rows, [("museum",)])

    def test_kind_table(self) -> None:
        """The tag-to-kind rules, without needing an object in the extract."""
        cases = [
            ({"building": "yes", "tourism": "museum"}, "museum"),
            ({"building": "yes", "amenity": "place_of_worship"}, "place_of_worship"),
            ({"building": "yes", "historic": "castle"}, "historic"),
            ({"building": "yes", "historic": "yes"}, "historic"),
            ({"building": "yes", "amenity": "cafe"}, "cafe"),
            ({"building": "house"}, "building"),
            ({"building": "no", "name": "x"}, None),
            ({"natural": "water", "water": "lake"}, "water"),
            ({"landuse": "reservoir"}, "water"),
            ({"natural": "bay"}, "water"),
            ({"leisure": "swimming_pool"}, "stadium"),
            ({"leisure": "nature_reserve"}, "nature_reserve"),
            ({"boundary": "protected_area"}, "nature_reserve"),
            ({"man_made": "communications_tower"}, "tower"),
            ({"man_made": "lighthouse"}, "lighthouse"),
            ({"aeroway": "aerodrome"}, "airport"),
            ({"shop": "department_store"}, "mall"),
            ({"amenity": "ferry_terminal"}, "ferry_terminal"),
            ({"amenity": "clinic"}, "hospital"),
            ({"amenity": "college"}, "university"),
            ({"tourism": "zoo"}, "attraction"),
            ({"tourism": "gallery"}, "museum"),
            ({"natural": "beach"}, "beach"),
            ({"highway": "residential"}, None),
        ]
        for tags, expected in cases:
            with self.subTest(tags=tags):
                self.assertEqual(build.poi_kind(tags), expected)

    def test_a_bare_number_is_never_a_name(self) -> None:
        """House numbers in the name field and numbered boundary stones."""
        self.assertTrue(build.is_bare_number("12"))
        self.assertTrue(build.is_bare_number("12-14"))
        self.assertFalse(build.is_bare_number("12a"))
        names = [row[0] for row in self.open().execute("SELECT name FROM pois")]
        self.assertEqual(
            [name for name in names if not any(c.isalpha() for c in name)], []
        )

    def test_a_multipolygon_relation_becomes_one_row(self) -> None:
        """Vaduz castle is a multipolygon; without areas it is missing."""
        db = self.open()
        rows = db.execute(
            "SELECT kind, osm_type, osm_id, lat, lon FROM pois "
            "WHERE name = 'Schloss Vaduz'"
        ).fetchall()
        self.assertEqual(len(rows), 1, "one object, one row")
        kind, osm_type, osm_id, lat, lon = rows[0]
        self.assertEqual((kind, osm_type, osm_id), ("historic", "r", 1252853))
        self.assertAlmostEqual(lat / 1e7, 47.14, places=1)
        self.assertAlmostEqual(lon / 1e7, 9.52, places=1)

        # Lakes are the other thing only relations hold.
        relations = db.execute(
            "SELECT name, kind, lat, lon FROM pois WHERE osm_type = 'r'"
        ).fetchall()
        self.assertGreater(len(relations), 5)
        self.assertIn("water", {row[1] for row in relations})
        for name, _, lat, lon in relations:
            # Every centroid has to land inside the tile the file is named for.
            self.assertEqual(build.tile_name(lat / 1e7, lon / 1e7), TILE, name)

    def test_osm_identity_columns(self) -> None:
        db = self.open()
        for table in ("places", "pois"):
            total, typed = db.execute(
                f"SELECT count(*), count(osm_id) FROM {table}"
            ).fetchone()
            self.assertEqual(total, typed, f"{table} rows without an osm_id")
            kinds = {
                row[0] for row in db.execute(f"SELECT DISTINCT osm_type FROM {table}")
            }
            self.assertLessEqual(kinds, {"n", "w", "r"})
            self.assertEqual(
                db.execute(
                    f"SELECT count(*) FROM (SELECT osm_type, osm_id FROM {table}"
                    " GROUP BY osm_type, osm_id HAVING count(*) > 1)"
                ).fetchone()[0],
                0,
            )
        # A street is merged out of many ways and has no single OSM identity.
        self.assertEqual(
            db.execute(
                "SELECT count(*) FROM streets "
                "WHERE osm_type IS NOT NULL OR osm_id IS NOT NULL"
            ).fetchone()[0],
            0,
        )

    def test_check_accepts_a_file_without_the_osm_columns(self) -> None:
        legacy = os.path.join(HERE, "fixtures", "W20_N30.gaz")
        if not os.path.isfile(legacy):
            self.skipTest("fixture not present")
        db = sqlite3.connect(f"file:{legacy}?mode=ro", uri=True)
        self.addCleanup(db.close)
        columns = {row[1] for row in db.execute("PRAGMA table_info(places)")}
        self.assertNotIn("osm_type", columns, "fixture is no longer the legacy shape")
        self.assertEqual(check.check(legacy).tile, "W20_N30")

    # ------------------------------------------------------------- query ---

    def test_fts_query_quotes_and_stars_the_last_token(self) -> None:
        self.assertEqual(query.fts_query("west 125"), '"west" "125"*')
        self.assertEqual(query.fts_query('a"b'), '"a""b"*')

    def test_muhleholz_finds_the_village_and_the_street(self) -> None:
        hits = query.search(self.open(), "muhleholz", 10)
        found = {(h.name, h.kind) for h in hits}
        self.assertIn(("Mühleholz", "village"), found)
        self.assertIn(("Im Mühleholz", "street"), found)

    def test_vad_ranks_vaduz_first(self) -> None:
        hits = query.search(self.open(), "vad", 10)
        self.assertEqual(hits[0].name, "Vaduz")
        self.assertEqual(hits[0].kind, "town")
        self.assertGreater(hits[0].population or 0, 0)

    def test_near_breaks_ties_by_distance(self) -> None:
        hits = query.search(self.open(), "vaduz", 10, near=(47.1393, 9.5228))
        self.assertTrue(all(h.distance_m is not None for h in hits))
        self.assertLess(hits[0].distance_m, 1000)

    def test_reverse_lookup(self) -> None:
        db = self.open()
        row, distance = query.nearest(db, "places", 47.1410, 9.5215)
        self.assertEqual(row[0], "Vaduz")
        self.assertLess(distance, 1000)

    # ------------------------------------------------------------- check ---

    def test_check_reports_the_file(self) -> None:
        report = check.check(self.path())
        self.assertEqual(report.tile, TILE)
        self.assertTrue(report.has_streets)
        self.assertGreater(report.places, 0)
        self.assertGreater(report.streets, 0)
        self.assertGreater(report.pois, 0)
        self.assertIn(TILE, report.summary())

    def test_check_rejects_a_wrong_schema_version(self) -> None:
        broken = os.path.join(self.tmp, f"{TILE}.gaz")
        shutil.copy(self.path(), broken)
        db = sqlite3.connect(broken)
        db.execute("UPDATE meta SET value = '2' WHERE key = 'schema_version'")
        db.commit()
        db.close()
        with self.assertRaises(check.GazetteerError) as caught:
            check.check(broken)
        self.assertIn("schema_version", str(caught.exception))
        os.remove(broken)

    def test_check_rejects_a_renamed_file(self) -> None:
        wrong = os.path.join(self.tmp, "W20_N30.gaz")
        shutil.copy(self.path(), wrong)
        with self.assertRaises(check.GazetteerError) as caught:
            check.check(wrong)
        self.assertIn("meta.tile", str(caught.exception))
        os.remove(wrong)

    # ---------------------------------------------------------- manifest ---

    def make_mirror(self) -> str:
        mirror = tempfile.mkdtemp(prefix="gaz-mirror-", dir=self.tmp)
        self.addCleanup(shutil.rmtree, mirror, ignore_errors=True)
        with open(os.path.join(mirror, "manifest.json"), "w") as out:
            json.dump(
                {
                    "formatVersion": "11.2",
                    "generatedAt": "2026-09-16T00:00:00Z",
                    "tiles": [
                        {"tile": TILE, "bytes": 1, "updatedAt": "2026-09-16T00:00:00Z"},
                        {"tile": "W20_N30", "bytes": 2, "updatedAt": "x"},
                    ],
                },
                out,
                indent=1,
            )
        return mirror

    def read_manifest(self, mirror: str) -> dict:
        with open(os.path.join(mirror, "manifest.json")) as handle:
            return json.load(handle)

    def test_manifest_adds_and_removes_the_gazetteer_object(self) -> None:
        mirror = self.make_mirror()
        shutil.copy(self.path(), os.path.join(mirror, f"{TILE}.gaz"))

        manifest.update_manifest(mirror, verbose=False)
        tiles = {t["tile"]: t for t in self.read_manifest(mirror)["tiles"]}
        entry = tiles[TILE]["gazetteer"]
        self.assertEqual(entry["bytes"], os.path.getsize(self.path()))
        self.assertEqual(len(entry["sha256"]), 64)
        self.assertRegex(entry["updatedAt"], r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$")
        self.assertNotIn("gazetteer", tiles["W20_N30"])
        # Key order is preserved and the tile keys come first.
        self.assertEqual(
            list(tiles[TILE]), ["tile", "bytes", "updatedAt", "gazetteer"]
        )

        # Idempotent: a second pass over an unchanged mirror changes nothing.
        raw = os.path.join(mirror, "manifest.json")
        with open(raw, "rb") as handle:
            before = handle.read()
        manifest.update_manifest(mirror, verbose=False)
        with open(raw, "rb") as handle:
            self.assertEqual(handle.read(), before)

        os.remove(os.path.join(mirror, f"{TILE}.gaz"))
        manifest.update_manifest(mirror, verbose=False)
        tiles = {t["tile"]: t for t in self.read_manifest(mirror)["tiles"]}
        self.assertNotIn("gazetteer", tiles[TILE])

    def test_manifest_fails_on_a_broken_gazetteer(self) -> None:
        mirror = self.make_mirror()
        target = os.path.join(mirror, f"{TILE}.gaz")
        shutil.copy(self.path(), target)
        db = sqlite3.connect(target)
        db.execute("UPDATE meta SET value = '99' WHERE key = 'schema_version'")
        db.commit()
        db.close()
        with self.assertRaises(check.GazetteerError):
            manifest.update_manifest(mirror, verbose=False)

    # ------------------------------------------------------------- merge ---

    def run_merge(self, *inputs: str, expect: int = 0) -> str:
        """Run merge.py over the given inputs; returns the merged tile path."""
        out = tempfile.mkdtemp(prefix="gaz-merged-", dir=self.tmp)
        self.addCleanup(shutil.rmtree, out, ignore_errors=True)
        result = subprocess.run(
            [sys.executable, os.path.join(HERE, "merge.py"), out] + list(inputs),
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, expect, result.stderr)
        if expect == 0:
            self.assertIn(TILE, result.stdout)
        return os.path.join(out, f"{TILE}.gaz")

    def copies(self, *sources: str) -> list[str]:
        """One input directory per source file, so merge.py sees them apart."""
        root = tempfile.mkdtemp(prefix="gaz-inputs-", dir=self.tmp)
        self.addCleanup(shutil.rmtree, root, ignore_errors=True)
        made = []
        for index, source in enumerate(sources):
            directory = os.path.join(root, f"in{index}")
            os.makedirs(directory)
            shutil.copy(source, os.path.join(directory, f"{TILE}.gaz"))
            made.append(directory)
        return made

    @staticmethod
    def counts(path: str) -> dict[str, int]:
        db = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
        try:
            return {
                table: db.execute(f"SELECT count(*) FROM {table}").fetchone()[0]
                for table in ("places", "streets", "pois")
            }
        finally:
            db.close()

    @staticmethod
    def meta_of(path: str) -> dict:
        db = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
        try:
            return dict(db.execute("SELECT key, value FROM meta"))
        finally:
            db.close()

    @staticmethod
    def osm_keys(path: str, table: str) -> set:
        db = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
        try:
            return {
                tuple(row)
                for row in db.execute(f"SELECT osm_type, osm_id FROM {table}")
            }
        finally:
            db.close()

    def test_merge_of_two_builds_is_the_union_with_no_duplicates(self) -> None:
        merged = self.run_merge(*self.copies(self.path(), self.path(streets=False)))
        counts = self.counts(merged)
        for table in ("places", "pois"):
            union = self.osm_keys(self.path(), table) | self.osm_keys(
                self.path(streets=False), table
            )
            self.assertEqual(counts[table], len(union))
            self.assertEqual(self.osm_keys(merged, table), union)
        # The streets only exist in one of the two inputs and survive whole.
        self.assertEqual(counts["streets"], self.counts(self.path())["streets"])

    def test_merge_renumbers_ids_and_resolves_the_references(self) -> None:
        merged = self.run_merge(*self.copies(self.path(), self.path(streets=False)))
        db = sqlite3.connect(f"file:{merged}?mode=ro", uri=True)
        self.addCleanup(db.close)
        ids = [
            row[0]
            for table in ("places", "streets", "pois")
            for row in db.execute(f"SELECT id FROM {table}")
        ]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertEqual(sorted(ids), list(range(1, len(ids) + 1)))

        place_ids = {row[0] for row in db.execute("SELECT id FROM places")}
        for table, column in (
            ("places", "admin_id"),
            ("streets", "place_id"),
            ("pois", "place_id"),
        ):
            refs = {
                row[0]
                for row in db.execute(
                    f"SELECT {column} FROM {table} WHERE {column} IS NOT NULL"
                )
            }
            self.assertTrue(refs, f"{table}.{column} is never set")
            self.assertLessEqual(refs, place_ids, f"{table}.{column} dangles")

    def test_merge_rebuilds_the_search_index(self) -> None:
        merged = self.run_merge(*self.copies(self.path(), self.path(streets=False)))
        db = sqlite3.connect(f"file:{merged}?mode=ro", uri=True)
        self.addCleanup(db.close)
        found = {(h.name, h.kind) for h in query.search(db, "muhleholz", 10)}
        self.assertIn(("Mühleholz", "village"), found)
        self.assertIn(("Im Mühleholz", "street"), found)

    def test_merging_two_copies_of_one_file_changes_nothing(self) -> None:
        merged = self.run_merge(*self.copies(self.path(), self.path()))
        self.assertEqual(self.counts(merged), self.counts(self.path()))

    def test_merge_output_passes_check(self) -> None:
        merged = self.run_merge(*self.copies(self.path(), self.path(streets=False)))
        report = check.check(merged)
        self.assertEqual(report.tile, TILE)
        self.assertTrue(report.has_streets)
        self.assertTrue(report.has_pois)
        self.assertGreater(report.streets, 0)

    def test_merge_meta_joins_the_distinct_sources(self) -> None:
        inputs = self.copies(self.path(), self.path(streets=False))
        other = os.path.join(inputs[1], f"{TILE}.gaz")
        db = sqlite3.connect(other)
        db.execute("UPDATE meta SET value = 'austria.osm.pbf' WHERE key = 'source'")
        db.commit()
        db.close()

        merged = self.run_merge(*inputs)
        meta = self.meta_of(merged)
        self.assertEqual(meta["schema_version"], "1")
        self.assertEqual(meta["tile"], TILE)
        self.assertEqual(meta["source"], "liechtenstein.osm.pbf,austria.osm.pbf")
        self.assertEqual(meta["has_streets"], "1")
        self.assertEqual(meta["has_pois"], "1")
        self.assertRegex(meta["built_at"], r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$")

    def test_merge_finds_inputs_in_nested_directories(self) -> None:
        root = tempfile.mkdtemp(prefix="gaz-nested-", dir=self.tmp)
        self.addCleanup(shutil.rmtree, root, ignore_errors=True)
        for leg in ("liechtenstein/tiles", "austria"):
            os.makedirs(os.path.join(root, leg))
            shutil.copy(self.path(), os.path.join(root, leg, f"{TILE}.gaz"))
        merged = self.run_merge(root)
        self.assertEqual(self.counts(merged), self.counts(self.path()))

    def test_merge_of_a_single_input_is_canonical(self) -> None:
        merged = self.run_merge(*self.copies(self.path(streets=False)))
        self.assertEqual(self.counts(merged), self.counts(self.path(streets=False)))
        self.assertEqual(self.meta_of(merged)["has_streets"], "0")
        check.check(merged)

    def test_merge_fails_on_a_broken_input(self) -> None:
        inputs = self.copies(self.path(), self.path(streets=False))
        broken = os.path.join(inputs[1], f"{TILE}.gaz")
        db = sqlite3.connect(broken)
        db.execute("UPDATE meta SET value = '2' WHERE key = 'schema_version'")
        db.commit()
        db.close()
        merged = self.run_merge(*inputs, expect=1)
        self.assertFalse(os.path.exists(merged), "a failed merge wrote a tile anyway")

    def test_merge_writes_the_same_schema_as_build(self) -> None:
        merged = self.run_merge(*self.copies(self.path()))

        def schema(path: str) -> dict:
            db = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
            try:
                return dict(
                    db.execute(
                        "SELECT name, sql FROM sqlite_master "
                        "WHERE sql IS NOT NULL AND name NOT LIKE 'search_%'"
                    )
                )
            finally:
                db.close()

        self.assertEqual(schema(merged), schema(self.path()))

    def test_merge_needs_only_the_standard_library(self) -> None:
        """The CI merge job runs without pyosmium, so merge.py must not use it."""
        with open(os.path.join(HERE, "merge.py"), encoding="utf-8") as handle:
            tree = ast.parse(handle.read())
        imported = set()
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                imported |= {alias.name.split(".")[0] for alias in node.names}
            elif isinstance(node, ast.ImportFrom) and node.level == 0 and node.module:
                imported.add(node.module.split(".")[0])
        self.assertLessEqual(imported, sys.stdlib_module_names | {"check"})

    # ------------------------------------------------------------- misc ----

    def test_tile_names_match_the_app(self) -> None:
        self.assertEqual(build.tile_name(47.14, 9.52), "E5_N45")
        self.assertEqual(build.tile_name(32.65, -16.91), "W20_N30")
        self.assertEqual(build.tile_name(40.81, -73.96), "W75_N40")
        self.assertEqual(build.tile_name(-33.87, 151.21), "E150_S35")

    def test_the_committed_fixture_is_valid(self) -> None:
        fixture = os.path.join(HERE, "fixtures", f"{TILE}.gaz")
        if not os.path.isfile(fixture):
            self.skipTest("fixture not present")
        report = check.check(fixture)
        self.assertTrue(report.has_streets)
        self.assertTrue(report.has_pois)


if __name__ == "__main__":
    unittest.main()
