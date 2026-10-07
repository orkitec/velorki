#!/usr/bin/env python3
"""Tests for the gazetteer builder.

    venv/bin/python -m unittest tools/gazetteer/test_gazetteer.py

Builds the Liechtenstein extract once as it comes and once with `--no-streets`
into a temporary directory, then asserts the file format, the query contract and
the mirror tooling against it. Needs pyosmium and the extract; set
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
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import build  # noqa: E402
import check  # noqa: E402
import manifest  # noqa: E402
import merge  # noqa: E402
import query  # noqa: E402
import street_numbers  # noqa: E402
import testset  # noqa: E402
import translit  # noqa: E402

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
    drinking_water cafe restaurant fast_food ice_cream fuel compressed_air
    bicycle_repair_station shelter bicycle_shop station
    viewpoint peak park
    toilets bicycle_rental charging_station pharmacy picnic_site
    bicycle_parking
    mountain_pass camp_site hotel hostel alpine_hut supermarket bakery
    attraction museum historic place_of_worship hospital university stadium
    mall airport ferry_terminal tower lighthouse water beach nature_reserve
    building
    """.split()
)

# Addendum 3: the only kinds a row may carry with no name at all.
UNNAMED_KINDS = frozenset(
    """
    drinking_water toilets bicycle_repair_station shelter bicycle_rental
    charging_station picnic_site bicycle_parking compressed_air fuel
    """.split()
)

# Addendum 2's seven: where a tour sleeps, eats and crosses. Liechtenstein has
# at least one of each.
CYCLING_KINDS = frozenset(
    "mountain_pass camp_site hotel hostel alpine_hut supermarket bakery".split()
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
                + ([] if streets else ["--no-streets"]),
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
                ("importance", "INTEGER"),
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
                ("importance", "INTEGER"),
            ],
        )
        # `pois.name` is the one nullable name; places and streets are not.
        self.assertEqual(
            {
                table: {row[1]: row[3] for row in db.execute(f"PRAGMA table_info({table})")}["name"]
                for table in ("places", "streets", "pois")
            },
            {"places": 1, "streets": 1, "pois": 0},
        )
        self.assertEqual(
            [(row[1], row[2]) for row in db.execute("PRAGMA table_info(aliases)")],
            [("id", "INTEGER"), ("ref_id", "INTEGER"), ("name", "TEXT")],
        )
        self.assertEqual(
            [
                (row[1], row[2], row[3], row[5])
                for row in db.execute("PRAGMA table_info(street_numbers)")
            ],
            [("street_id", "INTEGER", 0, 1), ("data", "BLOB", 1, 0)],
        )
        self.assertEqual(
            [
                (row[1], row[2], row[3], row[5])
                for row in db.execute("PRAGMA table_info(vocab)")
            ],
            [("term", "TEXT", 1, 1), ("docs", "INTEGER", 1, 0)],
        )
        self.assertIn(
            "WITHOUT ROWID",
            db.execute("SELECT sql FROM sqlite_master WHERE name = 'vocab'").fetchone()[0],
        )
        # The anchors of older files are gone from a file built today.
        self.assertIsNone(
            db.execute(
                "SELECT 1 FROM sqlite_master WHERE name = 'house_numbers'"
            ).fetchone()
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
            {"idx_places_pos", "idx_pois_pos", "idx_aliases_ref"},
            indexes,
        )
        self.assertEqual(db.execute("PRAGMA page_size").fetchone()[0], 4096)
        self.assertEqual(
            db.execute("PRAGMA journal_mode").fetchone()[0].lower(), "delete"
        )

    def test_a_built_file_has_no_street_position_index(self) -> None:
        """Nothing on the phone looks a street up by position; the index is dropped."""
        for streets in (True, False):
            indexes = {
                row[0]
                for row in self.open(streets).execute(
                    "SELECT name FROM sqlite_master WHERE type = 'index'"
                )
            }
            self.assertNotIn("idx_streets_pos", indexes)

    def test_meta_rows(self) -> None:
        meta = dict(self.open().execute("SELECT key, value FROM meta"))
        self.assertEqual(meta["schema_version"], "1")
        self.assertEqual(meta["tile"], TILE)
        self.assertEqual(meta["has_streets"], "1")
        self.assertEqual(meta["has_pois"], "1")
        self.assertEqual(meta["source"], "liechtenstein.osm.pbf")
        self.assertEqual(meta["search_script"], "latin")
        self.assertRegex(meta["built_at"], r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$")

        plain = dict(self.open(streets=False).execute("SELECT key, value FROM meta"))
        self.assertEqual(plain["has_streets"], "0")
        self.assertEqual(plain["has_pois"], "1")

    def test_streets_are_built_by_default(self) -> None:
        db = self.open()
        self.assertGreater(db.execute("SELECT count(*) FROM streets").fetchone()[0], 0)
        self.assertGreater(
            db.execute("SELECT count(*) FROM street_numbers").fetchone()[0], 0
        )

    def test_no_streets_leaves_out_streets_and_house_numbers(self) -> None:
        db = self.open(streets=False)
        self.assertEqual(db.execute("SELECT count(*) FROM streets").fetchone()[0], 0)
        self.assertEqual(
            db.execute("SELECT count(*) FROM street_numbers").fetchone()[0], 0
        )
        self.assertGreater(db.execute("SELECT count(*) FROM pois").fetchone()[0], 0)
        self.assertGreater(db.execute("SELECT count(*) FROM aliases").fetchone()[0], 0)

    def test_ids_are_unique_across_the_three_tables(self) -> None:
        db = self.open()
        ids = [
            row[0]
            for table in ("places", "streets", "pois", "aliases")
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

    def test_only_utility_kinds_go_unnamed(self) -> None:
        db = self.open()
        unnamed = {
            row[0]: row[1]
            for row in db.execute(
                "SELECT kind, count(*) FROM pois WHERE name IS NULL OR name = ''"
                " GROUP BY kind"
            )
        }
        self.assertTrue(unnamed, "no unnamed rows at all")
        self.assertLessEqual(set(unnamed), UNNAMED_KINDS, "a named-only kind is NULL")
        # Every other kind is named, and no kind is ever the empty string.
        self.assertEqual(
            db.execute(
                "SELECT count(*) FROM pois WHERE name = '' OR name <> trim(name)"
            ).fetchone()[0],
            0,
        )
        kinds = {row[0] for row in db.execute("SELECT DISTINCT kind FROM pois")}
        self.assertIn("peak", kinds)
        self.assertTrue(kinds & {"drinking_water", "cafe"})
        self.assertLessEqual(kinds, POI_KINDS)

    def test_a_named_kind_is_never_null(self) -> None:
        """cafe, peak, hotel and the rest keep the named-only rule."""
        rows = self.open().execute(
            "SELECT kind, count(*) FROM pois WHERE name IS NULL"
            " AND kind NOT IN ({}) GROUP BY kind".format(
                ",".join("?" * len(UNNAMED_KINDS))
            ),
            tuple(sorted(UNNAMED_KINDS)),
        ).fetchall()
        self.assertEqual(rows, [])

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

    def test_cycling_stop_kinds_are_collected(self) -> None:
        """Addendum 2's seven. Liechtenstein is alpine and touristy enough to
        hold every one of them, so none of these needs a synthetic extract."""
        kinds = {
            row[0]: row[1]
            for row in self.open().execute(
                "SELECT kind, count(*) FROM pois GROUP BY kind"
            )
        }
        self.assertLessEqual(CYCLING_KINDS, set(kinds), f"got {sorted(kinds)}")
        for kind in sorted(CYCLING_KINDS):
            self.assertGreater(kinds[kind], 0, kind)

    def test_a_hotel_is_not_a_building(self) -> None:
        """The seven sit with the rider's kit, ahead of every landmark kind, so
        a hotel in a named historic building is still a hotel."""
        self.assertEqual(build.poi_kind({"building": "yes", "tourism": "hotel"}), "hotel")
        self.assertEqual(
            build.poi_kind({"historic": "castle", "tourism": "alpine_hut"}), "alpine_hut"
        )
        self.assertEqual(
            build.poi_kind({"shop": "supermarket", "building": "retail"}), "supermarket"
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
            ({"mountain_pass": "yes"}, "mountain_pass"),
            ({"natural": "saddle"}, "mountain_pass"),
            ({"tourism": "caravan_site"}, "camp_site"),
            ({"tourism": "motel"}, "hotel"),
            ({"tourism": "guest_house"}, "hostel"),
            ({"tourism": "chalet"}, "hostel"),
            ({"tourism": "wilderness_hut"}, "alpine_hut"),
            ({"shop": "convenience"}, "supermarket"),
            ({"shop": "bakery"}, "bakery"),
            ({"amenity": "restaurant"}, "restaurant"),
            ({"amenity": "ice_cream"}, "ice_cream"),
            ({"shop": "ice_cream"}, "ice_cream"),
            ({"amenity": "fuel"}, "fuel"),
            ({"amenity": "compressed_air"}, "compressed_air"),
            ({"amenity": "fast_food"}, "fast_food"),
            # A bar or a pub is no riding stop; one serving food is tagged
            # a restaurant.
            ({"amenity": "bar"}, None),
            ({"amenity": "pub"}, None),
            ({"amenity": "restaurant", "historic": "building"}, "restaurant"),
            # The rider's own kit still wins over the seven.
            ({"amenity": "cafe", "shop": "bakery"}, "cafe"),
            ({"shop": "bicycle", "shop:name": "x"}, "bicycle_shop"),
            # Addendum 3.
            ({"amenity": "toilets"}, "toilets"),
            ({"amenity": "bicycle_rental"}, "bicycle_rental"),
            ({"amenity": "bicycle_parking"}, "bicycle_parking"),
            ({"amenity": "pharmacy"}, "pharmacy"),
            ({"tourism": "picnic_site"}, "picnic_site"),
            ({"amenity": "water_point"}, "drinking_water"),
            ({"man_made": "water_tap"}, "drinking_water"),
            ({"natural": "spring", "drinking_water": "yes"}, "drinking_water"),
            ({"amenity": "fountain", "drinking_water": "yes"}, "drinking_water"),
            # Never when the water is off.
            ({"natural": "spring", "drinking_water": "no"}, None),
            ({"amenity": "drinking_water", "drinking_water": "no"}, None),
            ({"man_made": "water_tap", "drinking_water": "no"}, None),
            ({"amenity": "water_point", "drinking_water": "no"}, None),
            # A charging station only counts when it charges a bike.
            ({"amenity": "charging_station"}, None),
            ({"amenity": "charging_station", "bicycle": "yes"}, "charging_station"),
            (
                {"amenity": "charging_station", "bicycle:charging": "yes"},
                "charging_station",
            ),
            (
                {"amenity": "charging_station", "socket:bicycle": "2"},
                "charging_station",
            ),
            ({"amenity": "charging_station", "socket:type2": "4"}, None),
            # The primary kind wins; the water is a second row, not this one.
            ({"amenity": "toilets", "drinking_water": "yes"}, "toilets"),
            ({"tourism": "camp_site", "drinking_water": "yes"}, "camp_site"),
            ({"building": "yes", "drinking_water": "yes"}, "building"),
        ]
        for tags, expected in cases:
            with self.subTest(tags=tags):
                self.assertEqual(build.poi_kind(tags), expected)

    def test_a_bare_number_is_never_a_name(self) -> None:
        """House numbers in the name field and numbered boundary stones."""
        self.assertTrue(build.is_bare_number("12"))
        self.assertTrue(build.is_bare_number("12-14"))
        self.assertFalse(build.is_bare_number("12a"))
        names = [
            row[0]
            for row in self.open().execute(
                "SELECT name FROM pois WHERE name IS NOT NULL"
            )
        ]
        self.assertEqual(
            [name for name in names if not any(c.isalpha() for c in name)], []
        )

    def test_poi_kinds_adds_a_water_row_to_another_kind(self) -> None:
        """One object, one row — except that `drinking_water=yes` on something
        that is not water earns a second row of kind `drinking_water` for the
        same OSM object. That is why everything deduplicates on
        (osm_type, osm_id, kind)."""
        self.assertEqual(build.poi_kinds({"amenity": "toilets"}), ("toilets",))
        self.assertEqual(
            build.poi_kinds({"amenity": "toilets", "drinking_water": "yes"}),
            ("toilets", "drinking_water"),
        )
        self.assertEqual(
            build.poi_kinds({"amenity": "drinking_water"}), ("drinking_water",)
        )
        self.assertEqual(build.poi_kinds({"highway": "residential"}), ())
        self.assertEqual(
            build.poi_kinds({"natural": "spring", "drinking_water": "no"}), ()
        )

    def test_utility_kinds_are_collected(self) -> None:
        """Addendum 3's kinds, in the extract. Liechtenstein has no
        `bicycle_rental`, so that one is proven by the tag rules above."""
        kinds = {
            row[0]: row[1]
            for row in self.open().execute(
                "SELECT kind, count(*) FROM pois GROUP BY kind"
            )
        }
        for kind in (
            "toilets",
            "bicycle_parking",
            "picnic_site",
            "charging_station",
            "pharmacy",
            "drinking_water",
        ):
            self.assertGreater(kinds.get(kind, 0), 0, f"no {kind} rows: {sorted(kinds)}")

    def test_unnamed_drinking_water_rows_exist(self) -> None:
        """Liechtenstein's fountains and taps: rows with a position and no name."""
        rows = self.open().execute(
            "SELECT count(*) FROM pois WHERE kind = 'drinking_water'"
            " AND name IS NULL"
        ).fetchone()[0]
        self.assertGreater(rows, 10, "no unnamed water stops")

    def indexed_ids(self, streets: bool = True) -> set[int]:
        """Every rowid the contentless FTS index actually holds."""
        db = self.open(streets)
        db.execute(
            "CREATE VIRTUAL TABLE temp.docs USING fts5vocab(main,'search','instance')"
        )
        try:
            return {row[0] for row in db.execute("SELECT DISTINCT doc FROM temp.docs")}
        finally:
            db.execute("DROP TABLE temp.docs")

    def test_unnamed_rows_are_not_in_the_search_index(self) -> None:
        db = self.open()
        indexed = self.indexed_ids()
        unnamed = {row[0] for row in db.execute("SELECT id FROM pois WHERE name IS NULL")}
        self.assertTrue(unnamed)
        self.assertEqual(indexed & unnamed, set(), "an unnamed row is in the index")

        # And the index is exactly the named rows plus the aliases.
        expected = sum(
            db.execute(sql).fetchone()[0]
            for sql in (
                "SELECT count(*) FROM places",
                "SELECT count(*) FROM streets",
                "SELECT count(*) FROM pois WHERE name IS NOT NULL",
                "SELECT count(*) FROM aliases",
            )
        )
        self.assertEqual(len(indexed), expected)
        self.assertEqual(check.check(self.path()).search, expected)

    def test_a_dry_spring_is_not_a_water_stop(self) -> None:
        """Node 12899110144 is a `natural=spring` with `drinking_water=no`; its
        neighbour 3565164920 says yes and is in the file."""
        db = self.open()
        self.assertEqual(
            db.execute(
                "SELECT count(*) FROM pois WHERE osm_type = 'n' AND osm_id = 12899110144"
            ).fetchone()[0],
            0,
        )
        self.assertEqual(
            db.execute(
                "SELECT kind, name FROM pois WHERE osm_type = 'n' AND osm_id = 3565164920"
            ).fetchall(),
            [("drinking_water", None)],
        )

    def test_a_toilet_with_a_tap_is_two_rows(self) -> None:
        """Node 4759689350 is `amenity=toilets` + `drinking_water=yes`: the
        primary kind stays `toilets` and the water is a second row."""
        rows = self.open().execute(
            "SELECT kind FROM pois WHERE osm_type = 'n' AND osm_id = 4759689350"
            " ORDER BY kind"
        ).fetchall()
        self.assertEqual(rows, [("drinking_water",), ("toilets",)])

    def test_nearest_of_kind_lists_unnamed_rows_by_distance(self) -> None:
        db = self.open()
        rows = query.nearest_of_kind(db, "drinking_water", 47.1410, 9.5215, 5)
        self.assertEqual(len(rows), 5)
        distances = [row[5] for row in rows]
        self.assertEqual(distances, sorted(distances))
        self.assertLess(distances[0], 2000)
        self.assertTrue(
            any(row[1] is None for row in rows), "only named rows came back"
        )
        for row_id, _, lat, lon, _, _ in rows:
            kind = db.execute(
                "SELECT kind FROM pois WHERE id = ?", (row_id,)
            ).fetchone()[0]
            self.assertEqual(kind, "drinking_water")
            self.assertEqual(build.tile_name(lat, lon), TILE)
        # A kind nothing in the tile carries comes back empty, not wrong.
        self.assertEqual(query.nearest_of_kind(db, "lighthouse", 47.141, 9.52, 5), [])

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
        """The dedupe key is (osm_type, osm_id) for a place and
        (osm_type, osm_id, kind) for a POI: one object can be a toilet row and
        a drinking water row, but never two rows of the same kind."""
        db = self.open()
        for table, key in (("places", "osm_type, osm_id"), ("pois", "osm_type, osm_id, kind")):
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
                    f"SELECT count(*) FROM (SELECT {key} FROM {table}"
                    f" GROUP BY {key} HAVING count(*) > 1)"
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
        # A file from before the osm columns existed: make one by dropping
        # them from a copy of the fixture.
        legacy = os.path.join(self.tmp, f"{TILE}.gaz")
        shutil.copy(self.path(), legacy)
        db = sqlite3.connect(legacy)
        for table in ("places", "streets", "pois"):
            db.execute(f"ALTER TABLE {table} DROP COLUMN osm_type")
            db.execute(f"ALTER TABLE {table} DROP COLUMN osm_id")
        db.commit()
        columns = {row[1] for row in db.execute("PRAGMA table_info(places)")}
        db.close()
        self.assertNotIn("osm_type", columns)
        self.assertEqual(check.check(legacy).tile, TILE)
        os.remove(legacy)

    # ----------------------------------------------------------- aliases ---

    def test_alias_names_are_split_and_deduplicated(self) -> None:
        tags = {
            "name:en": "Old Bridge; Old Bridge",
            "alt_name": "Alte Brücke",
            "short_name": "Alte Rheinbrücke",  # equals the primary name
            "old_name": "",
        }
        self.assertEqual(
            build.alias_names(tags, "Alte Rheinbrücke"),
            ("Old Bridge", "Alte Brücke"),
        )
        self.assertEqual(build.alias_names({}, "x"), ())

    def test_aliases_of_a_known_object(self) -> None:
        """Vaduz itself carries no `name:en`; the national museum does, and the
        old Rhine bridge is a street whose alias comes off its ways."""
        db = self.open()
        self.assertEqual(
            db.execute(
                "SELECT a.name FROM aliases a JOIN pois p ON p.id = a.ref_id "
                "WHERE p.name = 'Liechtensteinisches Landesmuseum Vaduz'"
            ).fetchall(),
            [("Liechtenstein National Museum",)],
        )
        self.assertEqual(
            db.execute(
                "SELECT a.name FROM aliases a JOIN streets s ON s.id = a.ref_id "
                "WHERE s.name = 'Alte Rheinbrücke Vaduz'"
            ).fetchall(),
            [("Old Rhine Bridge Vaduz",)],
        )
        # No alias ever repeats the primary name of the row it belongs to.
        self.assertEqual(
            db.execute(
                "SELECT count(*) FROM aliases a WHERE a.name IN "
                "(SELECT name FROM places WHERE id = a.ref_id UNION ALL "
                " SELECT name FROM streets WHERE id = a.ref_id UNION ALL "
                " SELECT name FROM pois WHERE id = a.ref_id)"
            ).fetchone()[0],
            0,
        )

    def test_language_names_of_a_well_known_object(self) -> None:
        tags = {
            "name": "Wien",
            "name:de": "Wien",
            "name:en": "Vienna",
            "name:fr": "Vienne",
            "name:it": "VIENNA",
            "name:ru": "Вена",
            "name:uk": "Відень",
            "name:etymology": "x",
            "name:sr-Latn": "Beč;Vena",
            "name:hr": "Beč",
        }
        alts = build.alias_names(tags, "Wien")
        self.assertEqual(alts, ("Vienna",))
        self.assertEqual(
            build.language_names(tags, "Wien", alts),
            ("Vienna", "Vienne", "Вена", "Відень", "Beč", "Vena"),
        )
        many = {f"name:{a}{b}": f"Name {a}{b}" for a in "abcdefghij" for b in "abcdefghij"}
        names = build.language_names(many, "x", ())
        self.assertEqual(len(names), build.LANGUAGE_ALIAS_LIMIT)
        self.assertEqual(names, tuple(list(many.values())[: build.LANGUAGE_ALIAS_LIMIT]))

    def language_alias_extract(self) -> build.Extract:
        """A tiny OSM file: what earns `name:<lang>` aliases and what does not."""
        many = "".join(
            f'<tag k="name:{a}{b}" v="Bigtown {a}{b}"/>'
            for a in "abcdefghij" for b in "abcdefghij"
        )
        xml = f"""<?xml version="1.0" encoding="UTF-8"?>
<osm version="0.6" generator="test">
 <node id="1" lat="47.10" lon="9.50" version="1">
  <tag k="place" v="town"/><tag k="name" v="Wien"/><tag k="name:de" v="Wien"/>
  <tag k="name:en" v="Vienna"/><tag k="name:ru" v="Вена"/><tag k="name:fr" v="Vienne"/>
  <tag k="alt_name" v="vienne"/><tag k="name:uk" v="Відень"/>
 </node>
 <node id="2" lat="47.11" lon="9.51" version="1">
  <tag k="place" v="hamlet"/><tag k="name" v="Weiler"/><tag k="name_1" v="Hof"/>
 </node>
 <node id="3" lat="47.12" lon="9.52" version="1">
  <tag k="place" v="city"/><tag k="name" v="Bigtown"/>{many}
 </node>
 <node id="4" lat="47.13" lon="9.53" version="1">
  <tag k="tourism" v="museum"/><tag k="name" v="Kleinmuseum"/><tag k="wikidata" v="Q1"/>
  <tag k="name:en" v="Small Museum"/><tag k="name:fr" v="Petit musée"/>
  <tag k="name:it" v="Piccolo museo"/><tag k="name:es" v="Museo pequeño"/>
 </node>
 <node id="5" lat="47.14" lon="9.54" version="1">
  <tag k="tourism" v="museum"/><tag k="name" v="Grossmuseum"/><tag k="wikidata" v="Q2"/>
  <tag k="name:en" v="Big Museum"/><tag k="name:fr" v="Grand musée"/>
  <tag k="name:it" v="Grande museo"/><tag k="name:es" v="Gran museo"/>
  <tag k="name:ru" v="Большой музей"/>
 </node>
 <node id="11" lat="47.150" lon="9.550" version="1"/>
 <node id="12" lat="47.151" lon="9.551" version="1"/>
 <way id="20" version="1">
  <nd ref="11"/><nd ref="12"/>
  <tag k="highway" v="residential"/><tag k="name" v="Hauptstrasse"/>
  <tag k="wikidata" v="Q3"/><tag k="name:en" v="Main Street"/>
  <tag k="name:fr" v="Rue principale"/><tag k="name:it" v="Via principale"/>
  <tag k="name:es" v="Calle mayor"/><tag k="name:ru" v="Главная улица"/>
 </way>
</osm>
"""
        out = tempfile.mkdtemp(prefix="gaz-lang-", dir=self.tmp)
        self.addCleanup(shutil.rmtree, out, ignore_errors=True)
        path = os.path.join(out, "lang.osm")
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(xml)
        return build.read_pbf(path, True, "flex_mem")

    def test_a_platform_or_a_planned_road_is_no_street(self) -> None:
        ways = "".join(
            f""" <way id="{30 + i}" version="1">
  <nd ref="11"/><nd ref="12"/>
  <tag k="highway" v="{highway}"/><tag k="name" v="{name}"/>
 </way>
"""
            for i, (highway, name) in enumerate(
                [
                    ("residential", "Hauptstrasse"),
                    ("platform", "S Suedkreuz"),
                    ("proposed", "Neue Strasse"),
                    ("corridor", "Ladenpassage"),
                    ("construction", "Baustrasse"),
                ]
            )
        )
        xml = f"""<?xml version="1.0" encoding="UTF-8"?>
<osm version="0.6" generator="test">
 <node id="11" lat="47.150" lon="9.550" version="1"/>
 <node id="12" lat="47.151" lon="9.551" version="1"/>
{ways}</osm>
"""
        out = tempfile.mkdtemp(prefix="gaz-streets-", dir=self.tmp)
        self.addCleanup(shutil.rmtree, out, ignore_errors=True)
        path = os.path.join(out, "streets.osm")
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(xml)
        extract = build.read_pbf(path, True, "flex_mem")
        self.assertEqual(
            sorted(w.name for w in extract.street_ways),
            ["Baustrasse", "Hauptstrasse"],
            "a platform, a planned road and a corridor are no street; "
            "a road being built is",
        )

    def language_alias_file(self) -> str:
        extract = self.language_alias_extract()
        out = tempfile.mkdtemp(prefix="gaz-lang-out-", dir=self.tmp)
        self.addCleanup(shutil.rmtree, out, ignore_errors=True)
        build.build_tile(
            out, TILE, extract.places, extract.street_ways, extract.pois,
            extract.addresses, "lang.osm", True, "2026-10-06T00:00:00Z",
        )
        path = os.path.join(out, f"{TILE}.gaz")
        check.check(path)
        return path

    @staticmethod
    def aliases_by_row(path: str) -> dict[str, list[str]]:
        db = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
        try:
            found: dict[str, list[str]] = {}
            for owner, alias in db.execute(
                "SELECT coalesce(p.name, s.name, o.name), a.name FROM aliases a"
                " LEFT JOIN places p ON p.id = a.ref_id"
                " LEFT JOIN streets s ON s.id = a.ref_id"
                " LEFT JOIN pois o ON o.id = a.ref_id ORDER BY a.id"
            ):
                found.setdefault(owner, []).append(alias)
            return found
        finally:
            db.close()

    def test_a_well_known_place_or_poi_gets_every_language_name(self) -> None:
        path = self.language_alias_file()
        found = self.aliases_by_row(path)
        # The six tags first; then name:<lang> in tag order, without the
        # primary name or a name already there, compared lower-cased.
        self.assertEqual(found["Wien"], ["Vienna", "vienne", "Вена", "Відень"])
        self.assertNotIn("Weiler", found, "no importance, no language aliases")
        self.assertEqual(
            found["Bigtown"],
            [f"Bigtown {a}{b}" for a in "abcdefghij" for b in "abcdefghij"][
                : build.LANGUAGE_ALIAS_LIMIT
            ],
        )
        # importance 9: name:en only; importance 10: every language.
        self.assertEqual(found["Kleinmuseum"], ["Small Museum"])
        self.assertEqual(
            found["Grossmuseum"],
            ["Big Museum", "Grand musée", "Grande museo", "Gran museo", "Большой музей"],
        )
        # A street keeps the six tags only, whatever it carries.
        self.assertEqual(found["Hauptstrasse"], ["Main Street"])
        db = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
        self.addCleanup(db.close)
        wien = db.execute("SELECT id FROM places WHERE name = 'Wien'").fetchone()[0]
        for text in ('"viden"', '"vena"'):
            rowid = db.execute(
                "SELECT rowid FROM search WHERE search MATCH ?", (text,)
            ).fetchone()
            self.assertIsNotNone(rowid, text)
            self.assertEqual(
                db.execute("SELECT ref_id FROM aliases WHERE id = ?", rowid).fetchone()[0],
                wien,
            )
        self.assertEqual([h.name for h in query.search(db, "Відень", 5)][:1], ["Wien"])

    def test_merge_keeps_the_language_aliases(self) -> None:
        path = self.language_alias_file()
        merged = self.run_merge(*self.copies(path, path))
        self.assertEqual(self.aliases_by_row(merged), self.aliases_by_row(path))

    def test_aliases_are_in_the_search_index(self) -> None:
        db = self.open()
        alias_id, ref_id = db.execute(
            "SELECT id, ref_id FROM aliases WHERE name = 'Liechtenstein National Museum'"
        ).fetchone()
        hits = {
            row[0]
            for row in db.execute(
                "SELECT rowid FROM search WHERE search MATCH ? LIMIT 100",
                ('"Liechtenstein" "National" "Museum"*',),
            )
        }
        self.assertIn(alias_id, hits)
        self.assertNotIn(ref_id, hits, "the primary name does not hold these words")

    def test_alias_search_returns_the_primary_row_once(self) -> None:
        hits = query.search(self.open(), "liechtenstein national museum", 10)
        names = [(h.name, h.kind) for h in hits]
        self.assertEqual(
            names.count(("Liechtensteinisches Landesmuseum Vaduz", "museum")), 1
        )
        self.assertEqual(len({h.id for h in hits}), len(hits), "a row hit twice")

    # -------------------------------------------------------- importance ---

    def test_importance_counts_language_names_and_wiki(self) -> None:
        score = build.importance
        self.assertIsNone(score({"name": "Vaduz"}))
        self.assertIsNone(
            score(
                {
                    "name": "x",
                    "name:etymology": "x",
                    "name:left": "x",
                    "name:prefix": "x",
                    "name_1": "x",
                    "old_name:en": "x",
                    "name:e": "x",
                    "name:engl": "x",
                    "name:EN": "x",
                    "name:zh-Hans-CN": "x",
                    "name:de-": "x",
                    "wikimedia_commons": "x",
                }
            )
        )
        self.assertEqual(score({"name:en": "x"}), 1)
        self.assertEqual(
            score({"name:en": "x", "name:zh-Hans": "x", "name:sr-Latn": "x", "name:ast": "x"}),
            4,
        )
        self.assertEqual(score({"wikidata": "Q1"}), 5)
        self.assertEqual(score({"wikipedia": "de:Vaduz"}), 5)
        self.assertEqual(score({"wikipedia:de": "Vaduz"}), 5)
        self.assertEqual(
            score({"wikidata": "Q1", "wikipedia": "de:Vaduz", "name:de": "x"}), 6
        )
        many = {
            f"name:{a}{b}{c}": "x"
            for a in "abcdefgh"
            for b in "abcdefgh"
            for c in "abcdefgh"
        }
        self.assertEqual(len(many), 512)
        self.assertEqual(score(many), 255)
        self.assertEqual(build.more_important(None, None), None)
        self.assertEqual(build.more_important(None, 3), 3)
        self.assertEqual(build.more_important(7, 3), 7)

    def test_importance_in_the_built_file(self) -> None:
        db = self.open()
        vaduz = db.execute(
            "SELECT importance FROM places WHERE name = 'Vaduz' AND kind = 'town'"
        ).fetchone()[0]
        self.assertGreater(vaduz, build.WIKI_BONUS)
        for table in ("places", "pois"):
            ranked, unranked, low, high = db.execute(
                f"SELECT count(importance), count(*) - count(importance),"
                f" min(importance), max(importance) FROM {table}"
            ).fetchone()
            self.assertGreater(ranked, 0, table)
            self.assertGreater(unranked, 0, f"{table}: an ordinary row is NULL")
            self.assertGreaterEqual(low, 1)
            self.assertLessEqual(high, build.MAX_IMPORTANCE)
        # The most famous building of the country outranks a bus shelter.
        castle = db.execute(
            "SELECT importance FROM pois WHERE name = 'Schloss Vaduz'"
        ).fetchone()[0]
        self.assertGreaterEqual(castle, build.WIKI_BONUS)
        columns = {row[1] for row in db.execute("PRAGMA table_info(streets)")}
        self.assertNotIn("importance", columns)

    def test_merge_keeps_the_higher_importance(self) -> None:
        low = self.break_file(
            "UPDATE places SET importance = NULL WHERE name = 'Vaduz'",
            "UPDATE pois SET importance = 3 WHERE name = 'Schloss Vaduz'",
        )
        high = self.break_file(
            "UPDATE places SET importance = 200 WHERE name = 'Vaduz'",
            "UPDATE pois SET importance = NULL WHERE name = 'Schloss Vaduz'",
        )
        castle = self.open().execute(
            "SELECT importance FROM pois WHERE name = 'Schloss Vaduz'"
        ).fetchone()[0]
        self.assertGreater(castle, 3)
        for order in ((low, high), (high, low)):
            merged = self.run_merge(*self.copies(*order))
            db = sqlite3.connect(f"file:{merged}?mode=ro", uri=True)
            self.addCleanup(db.close)
            self.assertEqual(
                db.execute(
                    "SELECT importance FROM places WHERE name = 'Vaduz' AND kind = 'town'"
                ).fetchone()[0],
                200,
            )
            self.assertEqual(
                db.execute(
                    "SELECT importance FROM pois WHERE name = 'Schloss Vaduz'"
                ).fetchone()[0],
                3,
            )

    def test_merge_reads_no_importance_from_an_older_file(self) -> None:
        older = self.break_file(
            "ALTER TABLE places DROP COLUMN importance",
            "ALTER TABLE pois DROP COLUMN importance",
        )
        check.check(older)
        alone = self.run_merge(*self.copies(older))
        db = sqlite3.connect(f"file:{alone}?mode=ro", uri=True)
        self.addCleanup(db.close)
        for table in ("places", "pois"):
            self.assertEqual(
                db.execute(f"SELECT count(importance) FROM {table}").fetchone()[0], 0
            )
        # Next to a new file, the new file's importance survives the dedup.
        merged = self.run_merge(*self.copies(older, self.path()))
        built = self.open()
        out = sqlite3.connect(f"file:{merged}?mode=ro", uri=True)
        self.addCleanup(out.close)
        sql = (
            "SELECT osm_type, osm_id, kind, importance FROM {} ORDER BY 1, 2, 3"
        )
        for table in ("places", "pois"):
            self.assertEqual(
                out.execute(sql.format(table)).fetchall(),
                built.execute(sql.format(table)).fetchall(),
            )

    def test_check_rejects_an_importance_out_of_range(self) -> None:
        for value in (0, 256, -1, "'x'"):
            with self.assertRaises(check.GazetteerError, msg=value) as caught:
                check.check(
                    self.break_file(f"UPDATE pois SET importance = {value} WHERE id = "
                                    "(SELECT min(id) FROM pois)")
                )
            self.assertIn("importance", str(caught.exception))

    # ----------------------------------------------------- transliteration ---

    def build_without_language_aliases(self) -> str:
        """Liechtenstein built in-process as before `name:<lang>` aliases."""
        with mock.patch.object(
            build, "language_names", lambda tags, primary, alts: alts
        ):
            extract = build.read_pbf(find_extract(), True, "flex_mem")

        def here(item) -> bool:
            return build.tile_name(item.lat, item.lon) == TILE

        out = tempfile.mkdtemp(prefix="gaz-nolang-", dir=self.tmp)
        self.addCleanup(shutil.rmtree, out, ignore_errors=True)
        build.build_tile(
            out,
            TILE,
            [p for p in extract.places if here(p)],
            [s for s in extract.street_ways if here(s)],
            [p for p in extract.pois if here(p)],
            extract.addresses,
            EXTRACT_NAME,
            True,
            "2026-01-01T00:00:00Z",
        )
        return os.path.join(out, f"{TILE}.gaz")

    def test_a_latin_file_indexes_what_it_did_before(self) -> None:
        """Transliteration, the second Cyrillic spelling included, changes
        nothing for a file with only Latin names.

        Liechtenstein has a Cyrillic or Greek name only among its `name:<lang>`
        aliases, so it is built here without them; the index is rebuilt from
        the untouched names, as the builder did before transliterating, and
        must give the very same vocab.
        """
        db = sqlite3.connect(f"file:{self.build_without_language_aliases()}?mode=ro", uri=True)
        self.addCleanup(db.close)
        names = [
            (rowid, name)
            for table, column in (
                ("places", "name"),
                ("streets", "name"),
                ("pois", "name"),
                ("aliases", "name"),
            )
            for rowid, name in db.execute(
                f"SELECT id, {column} FROM {table} WHERE {column} IS NOT NULL"
            )
        ]
        letters = frozenset(translit.LETTERS) | frozenset(translit.LETTERS_UK)
        self.assertTrue(all(letters.isdisjoint(name.lower()) for _, name in names))
        self.assertTrue(
            all(translit.index_text(name) == name.lower() for _, name in names)
        )
        plain = sqlite3.connect(":memory:")
        self.addCleanup(plain.close)
        plain.execute(
            "CREATE VIRTUAL TABLE search USING fts5(name, content='', columnsize=0,"
            " tokenize='unicode61 remove_diacritics 2')"
        )
        plain.executemany("INSERT INTO search(rowid, name) VALUES (?,?)", names)
        plain.execute("CREATE VIRTUAL TABLE temp.v USING fts5vocab(main, 'search', 'row')")
        self.assertEqual(
            db.execute("SELECT term, docs FROM vocab ORDER BY term").fetchall(),
            plain.execute("SELECT term, doc FROM temp.v ORDER BY term").fetchall(),
        )

    def cyrillic_file(self) -> str:
        """A small tile of Bulgarian, Serbian, Russian and Greek names."""
        out = tempfile.mkdtemp(prefix="gaz-cyrillic-", dir=self.tmp)
        self.addCleanup(shutil.rmtree, out, ignore_errors=True)
        places = [
            build.PlaceRow(1, "София", "city", 42.69, 23.32, 1_200_000, None, "n", 1, 40),
            build.PlaceRow(2, "Θεσσαλονίκη", "city", 40.64, 22.94, None, None, "n", 2, None),
        ]
        streets = [
            build.StreetRow(3, "Александър Невски", 42.69, 23.33, 1, ()),
            build.StreetRow(4, "Ђурђевданска", 42.70, 23.30, 1, ()),
        ]
        pois = [
            (5, "Храм-паметник Св. Александър Невски", "place_of_worship",
             42.696, 23.333, 1, "w", 5, 30),
            (6, "Щастливеца", "cafe", 42.69, 23.32, 1, "n", 6, None),
        ]
        aliases = [(7, 6, "Счастливец")]
        build.write_tile(
            os.path.join(out, f"{TILE}.gaz"), TILE, places, streets, pois, aliases,
            [], "test", True, "2026-10-06T00:00:00Z",
        )
        return os.path.join(out, f"{TILE}.gaz")

    def test_translit_of_cyrillic_and_greek(self) -> None:
        for name, latin in (
            ("Александър Невски", "aleksandar nevski"),
            ("София", "sofiya"),
            ("Щастливеца", "shtastlivetsa"),
            ("Ђурђевдан", "djurdjevdan"),
            ("Љубљана", "ljubljana"),
            ("Москва", "moskva"),
            ("Пётр Ильич", "petr ilich"),
            ("Θεσσαλονίκη", "thessaloniki"),
            ("ΑΘΗΝΑ", "athina"),
            ("Ψυχικό", "psychiko"),
            ("Ναύπλιο", "navplio"),
            ("Λευκωσία", "levkosia"),
            ("Λουτράκι", "loutraki"),
            ("Μπάρι Ντόρα", "bari dora"),
            ("Λάμπρος", "lampros"),
            ("Mühleholz St. Florin", "mühleholz st. florin"),
        ):
            self.assertEqual(translit.translit(name), latin, name)
        self.assertTrue(all(len(letter) == 1 for letter in translit.LETTERS))
        self.assertTrue(all(letter == letter.lower() for letter in translit.LETTERS))

    def test_translit_alt_is_the_ukrainian_spelling(self) -> None:
        for name, latin in (
            ("Хмельницький", "khmelnytskyi"),
            ("Кривий Ріг", "kryvyi rih"),
            ("Київ", "kyiv"),
            ("Єнакієве", "yenakiieve"),
            ("Юрій", "yurii"),
            # The Ukrainian rule over a Bulgarian name: и is y, я is ia.
            ("София", "sofyia"),
            ("Ђурђевдан", "djurdjevdan"),
            ("Μπάρι", "bari"),
            ("Vaduz", "vaduz"),
        ):
            self.assertEqual(translit.translit_alt(name), latin, name)
        # Both tables map the same Cyrillic letters.
        cyrillic = {letter for letter in translit.LETTERS if "Ѐ" <= letter <= "ӿ"}
        self.assertEqual(set(translit.LETTERS_UK), cyrillic)
        self.assertTrue(set(translit.STARTS_UK) <= cyrillic)

    def test_index_text_holds_both_spellings_once(self) -> None:
        """Only a name with і, ї, є or ґ gets the second spelling."""
        self.assertEqual(translit.index_text("Кривий Ріг"), "kriviy rig kryvyi rih")
        self.assertEqual(translit.index_text("Київ"), "kiyiv kyiv")
        self.assertEqual(translit.index_text("Єнакієве"), "yenakiyeve yenakiieve")
        self.assertEqual(translit.index_text("Юрій"), "yuriy yurii")
        self.assertEqual(translit.index_text("ҐАНОК"), "ganok")
        # A word both tables spell alike is not repeated.
        self.assertEqual(
            translit.index_text("Вулиця Шевченка Київ"), "vulitsya shevchenka kiyiv vulytsia kyiv"
        )
        for letter in "іїєґІЇЄҐ":
            self.assertTrue(translit.has_ukrainian_letter(letter), letter)
        # Хмельницький has none of those letters, so it gets the first
        # spelling alone, like every Bulgarian, Russian or Serbian name.
        for name in ("Хмельницький", "Иван Вазов", "Москва", "Ђурђевдан", "връх Мусала"):
            self.assertFalse(translit.has_ukrainian_letter(name), name)
            self.assertEqual(translit.index_text(name), translit.translit(name), name)
        # Latin and Greek names are what translit gives.
        for name in ("Mühleholz St. Florin", "Θεσσαλονίκη", "Vaduz"):
            self.assertEqual(translit.index_text(name), translit.translit(name), name)

    def test_a_cyrillic_name_is_found_by_its_ukrainian_spelling(self) -> None:
        out = tempfile.mkdtemp(prefix="gaz-uk-", dir=self.tmp)
        self.addCleanup(shutil.rmtree, out, ignore_errors=True)
        path = os.path.join(out, f"{TILE}.gaz")
        build.write_tile(
            path, TILE,
            [
                build.PlaceRow(1, "Хмельницький", "city", 49.42, 26.98, None, None, "n", 1, 30),
                build.PlaceRow(2, "Кривий Ріг", "city", 47.91, 33.39, None, None, "n", 2, None),
                build.PlaceRow(3, "Kyiv", "city", 50.45, 30.52, None, None, "n", 3, None),
            ],
            [], [], [(4, 3, "Київ")], [], "test", False, "2026-10-06T00:00:00Z",
        )
        check.check(path)
        db = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
        self.addCleanup(db.close)

        def match(text: str) -> set[int]:
            return {row[0] for row in db.execute(
                "SELECT rowid FROM search WHERE search MATCH ?", (text,)
            )}

        # Хмельницький has no і, ї, є or ґ: the first spelling only.
        self.assertEqual(match('"khmelnytskyi"'), set())
        self.assertEqual(match('"hmelnitskiy"'), {1})
        self.assertEqual(match('"kryvyi" "rih"'), {2})
        self.assertEqual(match('"kriviy" "rig"'), {2})
        self.assertEqual(match('"kyiv"'), {3, 4})
        self.assertEqual(match('"kiyiv"'), {4})
        self.assertEqual(
            dict(db.execute("SELECT term, docs FROM vocab")),
            {"hmelnitskiy": 1, "kriviy": 1, "rig": 1,
             "kryvyi": 1, "rih": 1, "kyiv": 2, "kiyiv": 1},
        )

    def test_a_cyrillic_name_is_found_by_its_latin_form(self) -> None:
        path = self.cyrillic_file()
        report = check.check(path)
        self.assertEqual(report.search, 7)
        db = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
        self.addCleanup(db.close)
        self.assertEqual(
            dict(db.execute("SELECT key, value FROM meta"))["search_script"], "latin"
        )

        def match(text: str) -> set[int]:
            return {row[0] for row in db.execute(
                "SELECT rowid FROM search WHERE search MATCH ?", (text,)
            )}

        self.assertEqual(match('"aleksandar" "nevski"'), {3, 5})
        self.assertEqual(match('"thessaloniki"'), {2})
        self.assertEqual(match('"djurdjevdanska"'), {4})
        self.assertEqual(match('"schastlivets"'), {7})
        self.assertEqual(match('"софия"'), set())
        # The tables keep the names as they are written.
        self.assertEqual(
            db.execute("SELECT name FROM places WHERE id = 1").fetchone()[0], "София"
        )
        terms = {row[0] for row in db.execute("SELECT term FROM vocab")}
        self.assertIn("sofiya", terms)
        self.assertTrue(all(term.isascii() for term in terms), terms)
        # query.py reads a query in either script the way the app does.
        self.assertEqual([h.name for h in query.search(db, "sofi", 5)][:1], ["София"])
        self.assertEqual([h.name for h in query.search(db, "Софи", 5)][:1], ["София"])
        self.assertEqual(
            db.execute("SELECT importance FROM places WHERE id = 1").fetchone()[0], 40
        )

    def test_merge_transliterates_an_older_index(self) -> None:
        """An input indexed as written, without search_script, comes out Latin."""
        path = self.cyrillic_file()
        db = sqlite3.connect(path)
        db.executescript(
            "DROP TABLE search; DELETE FROM vocab;"
            " DELETE FROM meta WHERE key = 'search_script';"
            "CREATE VIRTUAL TABLE search USING fts5(name, content='', columnsize=0,"
            " tokenize='unicode61 remove_diacritics 2');"
            "INSERT INTO search(rowid, name)"
            " SELECT id, name FROM places UNION ALL SELECT id, name FROM streets"
            " UNION ALL SELECT id, name FROM pois UNION ALL SELECT id, name FROM aliases;"
            "CREATE VIRTUAL TABLE temp.v USING fts5vocab(main, 'search', 'row');"
            "INSERT INTO vocab SELECT term, doc FROM temp.v;"
        )
        db.commit()
        db.close()
        check.check(path)
        merged = self.run_merge(*self.copies(path))
        check.check(merged)
        out = sqlite3.connect(f"file:{merged}?mode=ro", uri=True)
        self.addCleanup(out.close)
        self.assertEqual(self.meta_of(merged)["search_script"], "latin")
        terms = {row[0] for row in out.execute("SELECT term FROM vocab")}
        self.assertIn("aleksandar", terms)
        self.assertTrue(all(term.isascii() for term in terms), terms)
        self.assertEqual(
            out.execute("SELECT importance FROM pois WHERE name LIKE 'Храм%'").fetchone()[0],
            30,
        )

    def test_check_rejects_an_untransliterated_term_in_a_latin_file(self) -> None:
        path = self.cyrillic_file()
        db = sqlite3.connect(path)
        db.executescript(
            "INSERT INTO search(rowid, name) VALUES (99, 'Щастливеца');"
            "DELETE FROM vocab;"
            "CREATE VIRTUAL TABLE temp.v USING fts5vocab(main, 'search', 'row');"
            "INSERT INTO vocab SELECT term, doc FROM temp.v;"
        )
        db.commit()
        db.close()
        with self.assertRaises(check.GazetteerError) as caught:
            check.check(path)
        self.assertIn("search_script", str(caught.exception))
        self.assertIn("щастливеца", str(caught.exception))

    # ----------------------------------------------------- house numbers ---

    def test_varints_and_zigzag_round_trip(self) -> None:
        self.assertEqual(
            [street_numbers.zigzag(n) for n in (0, -1, 1, -2, 2)], [0, 1, 2, 3, 4]
        )
        for value in (0, 1, -1, 63, -64, 64, 1000, -1000, 2**31, -(2**31), 2**62, -(2**63)):
            self.assertEqual(street_numbers.unzigzag(street_numbers.zigzag(value)), value)
        for value in (0, 1, 127, 128, 300, 16383, 16384, 2**32, 2**63 - 1, 2**64 - 1):
            out = bytearray()
            street_numbers.write_varint(out, value)
            self.assertEqual(street_numbers.read_varint(bytes(out), 0), (value, len(out)))
        out = bytearray()
        street_numbers.write_varint(out, 300)
        self.assertEqual(bytes(out), b"\xac\x02")
        with self.assertRaises(ValueError):
            street_numbers.read_varint(b"\x80", 0)

    def test_a_street_blob_round_trips(self) -> None:
        odd = [(1, 4714000, 952000), (7, 4713990, 952010), (101, 4700000, 950000)]
        even = [(0, 4714005, 951990), (2, -100, -200), (40, 9000000, -18000000)]
        blob = street_numbers.encode(odd, even)
        self.assertEqual(blob[0], 1)
        self.assertEqual(street_numbers.decode(blob), (odd, even))
        # The cursor runs on from the odd run into the even one: the first even
        # point is coded against the last odd point, not against (0, 0).
        self.assertEqual(street_numbers.decode(street_numbers.encode([], [])), ([], []))
        self.assertEqual(street_numbers.encode([], []), b"\x01\x00\x00")
        self.assertEqual(
            street_numbers.encode([(1, 10, 20)], [(2, 9, 21)]),
            # version, 1 odd: +1, zz(10), zz(20); 1 even: +2, zz(-1), zz(1)
            bytes([1, 1, 1, 20, 40, 1, 2, 1, 2]),
        )
        for bad, why in (
            (b"", "version"),
            (b"\x02\x00\x00", "version"),
            (blob + b"\x00", "trailing"),
            (blob[:-1], "ends inside"),
            (street_numbers.encode([], [(2, 0, 0)]).replace(b"\x02", b"\x03", 1), "run"),
            (bytes([1, 2, 1, 0, 0, 0, 0, 0, 0]), "repeated"),
        ):
            with self.assertRaises(ValueError, msg=repr(bad)) as caught:
                street_numbers.decode(bad)
            self.assertIn(why, str(caught.exception))

    def test_parity_split(self) -> None:
        odd, even = street_numbers.split([(4, 0, 0), (1, 0, 0), (3, 0, 0), (0, 0, 0), (2, 0, 0)])
        self.assertEqual([p[0] for p in odd], [1, 3])
        self.assertEqual([p[0] for p in even], [0, 2, 4])

    def test_a_straight_evenly_numbered_side_keeps_its_ends(self) -> None:
        side = [(n, 4714000 + n * 10, 952000) for n in range(1, 200, 2)]
        self.assertEqual(street_numbers.thin(side), [side[0], side[-1]])
        self.assertEqual(street_numbers.thin(side[:2]), side[:2])
        self.assertEqual(street_numbers.thin(side[:1]), side[:1])

    def test_a_bent_street_keeps_the_corner(self) -> None:
        # North for 50 numbers, then east: 2.5 m between neighbours.
        side = [(n, 4714000 + n * 2, 952000) for n in range(0, 101, 2)]
        corner = side[-1]
        side += [(n, corner[1], corner[2] + (n - 100) * 3) for n in range(102, 201, 2)]
        thinned = street_numbers.thin(side)
        self.assertEqual(thinned, [side[0], corner, side[-1]])
        # Thinning what was already thinned keeps it as it is.
        self.assertEqual(street_numbers.thin(thinned), thinned)

    def test_thinning_keeps_every_number_within_the_tolerance(self) -> None:
        import random

        rng = random.Random(5)
        for _ in range(50):
            side, lat, lon, number = [], 4714000, 952000, 1
            for _ in range(rng.randint(3, 300)):
                number += 2 * rng.randint(1, 3)
                lat += rng.randint(-3, 6)
                lon += rng.randint(-6, 3)
                side.append((number, lat, lon))
            thinned = street_numbers.thin(side)
            self.assertEqual((thinned[0], thinned[-1]), (side[0], side[-1]))
            for n, la, lo in side:
                got = street_numbers.locate(thinned, [], n)
                self.assertTrue(got[2])
                self.assertLessEqual(
                    street_numbers.meters_between(la / 1e5, lo / 1e5, got[0], got[1]),
                    street_numbers.HOUSE_TOLERANCE_M,
                )

    def test_locate_follows_the_side_of_the_number(self) -> None:
        odd = [(1, 100, 100), (9, 180, 100)]
        even = [(2, 100, 200), (6, 140, 200)]
        self.assertEqual(street_numbers.locate(odd, even, 5), (140 / 1e5, 100 / 1e5, True))
        self.assertEqual(street_numbers.locate(odd, even, 4), (120 / 1e5, 200 / 1e5, True))
        self.assertEqual(street_numbers.locate(odd, even, 9), (180 / 1e5, 100 / 1e5, True))
        # Past an end of its own side: that end, approximate.
        self.assertEqual(street_numbers.locate(odd, even, 8), (140 / 1e5, 200 / 1e5, False))
        self.assertEqual(street_numbers.locate(odd, even, 0), (100 / 1e5, 200 / 1e5, False))
        # An empty side: the nearest end of the other one.
        self.assertEqual(street_numbers.locate(odd, [], 8), (180 / 1e5, 100 / 1e5, False))
        self.assertIsNone(street_numbers.locate([], [], 8))

    def test_a_street_with_sixty_addresses_is_thinned(self) -> None:
        """The whole path: addresses in, one blob out, on one synthetic street."""
        street = build.StreetRow(7, "Teststrasse", 47.14, 9.52, None, ())
        book = build.AddressBook()
        for number in range(60, 0, -1):  # out of order on purpose
            book.add("teststrasse", number, 47.14 + number * 1e-5, 9.52)
        book.add("Teststrasse", 1, 47.145, 9.52)  # number 1 again, further off
        book.add("Teststrasse", 2, 48.90, 9.52)  # 200 km away: no street near
        rows = build.street_numbers(book.of("E5_N45"), book.names, [street])
        self.assertEqual([row[0] for row in rows], [7])
        odd, even = street_numbers.decode(rows[0][1])
        # A straight, evenly numbered street: each side is its two ends. The
        # first address of a repeated number wins, so number 1 keeps the
        # position it was first seen at, not the one added later.
        self.assertEqual(odd, [(1, 4714001, 952000), (59, 4714059, 952000)])
        self.assertEqual(even, [(2, 4714002, 952000), (60, 4714060, 952000)])

    def test_street_numbers_in_the_built_file(self) -> None:
        db = self.open()
        street_ids = {row[0] for row in db.execute("SELECT id FROM streets")}
        rows = db.execute("SELECT street_id, data FROM street_numbers").fetchall()
        self.assertGreater(len(rows), 100)
        for street_id, data in rows:
            self.assertIn(street_id, street_ids)
            odd, even = street_numbers.decode(data)
            self.assertTrue(odd or even)
            for side in (odd, even):
                self.assertEqual(side, sorted(side))

    def test_every_address_lands_within_the_tolerance(self) -> None:
        """Rebuilt in-process to see the addresses each street was given."""
        extract = build.read_pbf(find_extract(), True, "flex_mem")
        seen: dict[int, list[tuple[int, int, int]]] = {}
        real = build.addresses_by_street

        def recording(columns, names, streets):
            by_street = real(columns, names, streets)
            _, numbers, lats, lons = columns
            for street_id, rows in by_street.items():
                seen[street_id] = [(numbers[r], lats[r], lons[r]) for r in rows]
            return by_street

        def here(item) -> bool:
            return build.tile_name(item.lat, item.lon) == TILE

        out = tempfile.mkdtemp(prefix="gaz-every-", dir=self.tmp)
        self.addCleanup(shutil.rmtree, out, ignore_errors=True)
        with mock.patch.object(build, "addresses_by_street", recording):
            build.build_tile(
                out,
                TILE,
                [p for p in extract.places if here(p)],
                [s for s in extract.street_ways if here(s)],
                [p for p in extract.pois if here(p)],
                extract.addresses,
                EXTRACT_NAME,
                True,
                "2026-01-01T00:00:00Z",
            )
        db = sqlite3.connect(os.path.join(out, f"{TILE}.gaz"))
        self.addCleanup(db.close)
        blobs = dict(db.execute("SELECT street_id, data FROM street_numbers"))
        self.assertEqual(set(blobs), set(seen))
        checked = 0
        for street_id, addresses in seen.items():
            odd, even = street_numbers.decode(blobs[street_id])
            first: dict[int, tuple[int, int]] = {}
            for number, lat, lon in addresses:  # file order: the first one wins
                first.setdefault(number, (lat, lon))
            for number, (lat, lon) in first.items():
                found = street_numbers.locate(odd, even, number)
                self.assertTrue(found[2], (street_id, number))
                distance = street_numbers.meters_between(lat / 1e7, lon / 1e7, found[0], found[1])
                self.assertLessEqual(
                    distance, street_numbers.HOUSE_TOLERANCE_M, (street_id, number)
                )
                checked += 1
        self.assertGreater(checked, 5000)

    def test_leading_number(self) -> None:
        self.assertEqual(build.leading_number("12a"), 12)
        self.assertEqual(build.leading_number(" 7 "), 7)
        self.assertEqual(build.leading_number("12-14"), 12)
        self.assertIsNone(build.leading_number("A3"))
        # Unicode digits that str.isdigit() accepts and int() does not.
        self.assertEqual(build.leading_number("218⁰"), 218)
        self.assertEqual(build.leading_number("6²"), 6)
        self.assertIsNone(build.leading_number("⁴20"))
        self.assertIsNone(build.leading_number("⑦"))
        self.assertIsNone(build.leading_number("٣"))
        self.assertIsNone(build.leading_number(""))
        self.assertIsNone(build.leading_number(None))

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

    def test_a_digits_only_token_at_either_end_is_the_house_number(self) -> None:
        self.assertEqual(query.split_house_number("400 w 42nd"), ("w 42nd", "400"))
        self.assertEqual(query.split_house_number("hauptstr 12"), ("hauptstr", "12"))
        self.assertEqual(query.split_house_number("w 42nd st"), ("w 42nd st", None))
        self.assertEqual(query.split_house_number("400"), ("400", None))
        self.assertEqual(query.split_house_number("w 12 st"), ("w 12 st", None))

    def busiest_street(self) -> tuple[int, str, list[street_numbers.Point]]:
        """The street with the most odd-side points, and those points."""
        db = self.open()
        best = None
        for street_id, data in db.execute(
            "SELECT street_id, data FROM street_numbers ORDER BY street_id"
        ):
            odd, _ = street_numbers.decode(data)
            if best is None or len(odd) > len(best[1]):
                best = (street_id, odd)
        street_id, odd = best
        name = db.execute("SELECT name FROM streets WHERE id = ?", (street_id,)).fetchone()[0]
        return street_id, name, odd

    def test_query_finds_a_stored_number(self) -> None:
        db = self.open()
        street_id, name, points = self.busiest_street()
        number, lat, lon = points[0]
        hits = query.search(db, f"{number} {name}", 30)
        hit = next(h for h in hits if h.id == street_id)
        self.assertEqual(hit.house_number, str(number))
        self.assertFalse(hit.approximate)
        self.assertAlmostEqual(hit.lat, lat / 1e5, places=6)
        self.assertAlmostEqual(hit.lon, lon / 1e5, places=6)

    def test_query_interpolates_within_a_side_as_exact(self) -> None:
        db = self.open()
        street_id, name, points = self.busiest_street()
        low, high = next((a, b) for a, b in zip(points, points[1:]) if b[0] - a[0] > 2)
        between = low[0] + 2
        hits = query.search(db, f"{name} {between}", 30)
        hit = next(h for h in hits if h.id == street_id)
        self.assertEqual(hit.house_number, str(between))
        # Between two points of its own side a number is within 20 m: exact.
        self.assertFalse(hit.approximate)
        self.assertGreaterEqual(hit.lat, min(low[1], high[1]) / 1e5 - 1e-9)
        self.assertLessEqual(hit.lat, max(low[1], high[1]) / 1e5 + 1e-9)

    def test_query_falls_back_past_the_ends_and_to_the_street(self) -> None:
        db = self.open()
        street_id, name, points = self.busiest_street()
        hit = next(
            h for h in query.search(db, f"{points[-1][0] + 5000} {name}", 30)
            if h.id == street_id
        )
        self.assertTrue(hit.approximate)
        self.assertAlmostEqual(hit.lat, points[-1][1] / 1e5, places=6)

        # A street with no house numbers at all answers with its own position.
        row = db.execute(
            "SELECT id, name, lat, lon FROM streets WHERE id NOT IN"
            " (SELECT street_id FROM street_numbers) LIMIT 1"
        ).fetchone()
        hit = next(
            (h for h in query.search(db, f"{row[1]} 9", 60) if h.id == row[0]), None
        )
        if hit is not None:
            self.assertTrue(hit.approximate)
            self.assertAlmostEqual(hit.lat, row[2] / 1e7, places=6)

    def test_query_reads_the_anchors_of_an_older_file(self) -> None:
        db = sqlite3.connect(f"file:{self.legacy()}?mode=ro", uri=True)
        self.addCleanup(db.close)
        street_id, name, number, lat = db.execute(
            "SELECT s.id, s.name, h.number, h.lat FROM house_numbers h"
            " JOIN streets s ON s.id = h.street_id ORDER BY h.street_id, h.number LIMIT 1"
        ).fetchone()
        hit = next(h for h in query.search(db, f"{number} {name}", 30) if h.id == street_id)
        self.assertFalse(hit.approximate)
        self.assertAlmostEqual(hit.lat, lat / 1e7, places=6)
        hit = next(h for h in query.search(db, f"{number + 1} {name}", 30) if h.id == street_id)
        self.assertTrue(hit.approximate)

    def test_reverse_lookup(self) -> None:
        db = self.open()
        row, distance = query.nearest(db, "places", 47.1410, 9.5215)
        self.assertEqual(row[0], "Vaduz")
        self.assertLess(distance, 1000)

    def test_reverse_lookup_of_a_street_without_the_index(self) -> None:
        """A built file has no idx_streets_pos, so the street answer is a scan."""
        db = self.open()
        self.assertFalse(query.has_position_index(db, "streets"))
        scanned, distance = query.nearest(db, "streets", 47.1410, 9.5215)
        self.assertIsNotNone(scanned)
        self.assertLess(distance, 1000)

        # The same file with the old index gives the same street, by bounding box.
        with_index = self.break_file("CREATE INDEX idx_streets_pos ON streets(lat, lon)")
        indexed_db = sqlite3.connect(f"file:{with_index}?mode=ro", uri=True)
        self.addCleanup(indexed_db.close)
        self.assertTrue(query.has_position_index(indexed_db, "streets"))
        row, indexed_distance = query.nearest(indexed_db, "streets", 47.1410, 9.5215)
        self.assertEqual(row, scanned)
        self.assertAlmostEqual(indexed_distance, distance, places=6)

    # ------------------------------------------------------------- check ---

    def test_check_reports_the_file(self) -> None:
        report = check.check(self.path())
        self.assertEqual(report.tile, TILE)
        self.assertTrue(report.has_streets)
        self.assertGreater(report.places, 0)
        self.assertGreater(report.streets, 0)
        self.assertGreater(report.pois, 0)
        self.assertIn(TILE, report.summary())

    def test_check_finds_a_name_among_thousands_sharing_its_first_word(
        self,
    ) -> None:
        # A tile the size of Mexico has thousands of names starting with the
        # same letter; the self-test must search the whole name, not a prefix
        # of its first word.
        crowded = os.path.join(self.tmp, f"{TILE}.gaz")
        shutil.copy(self.path(), crowded)
        db = sqlite3.connect(crowded)
        first_id, first_name = db.execute(
            "SELECT id, name FROM places WHERE name IS NOT NULL "
            "ORDER BY id LIMIT 1"
        ).fetchone()
        word = first_name.split()[0]
        # Ids come from one counter across all tables; start above them all.
        next_id = 1 + max(
            db.execute(f"SELECT max(id) FROM {table}").fetchone()[0] or 0
            for table in ("places", "streets", "pois", "aliases")
        )
        rows = [
            (next_id + i, f"{word} filler {i}", "locality", 471000000, 95000000)
            for i in range(6000)
        ]
        db.executemany(
            "INSERT INTO places(id, name, kind, lat, lon) VALUES (?, ?, ?, ?, ?)",
            rows,
        )
        db.executemany(
            "INSERT INTO search(rowid, name) VALUES (?, ?)",
            [(r[0], r[1]) for r in rows],
        )
        db.executescript(
            "CREATE VIRTUAL TABLE temp.v USING fts5vocab(main, 'search', 'row');"
            "DELETE FROM vocab; INSERT INTO vocab SELECT term, doc FROM temp.v;"
        )
        db.commit()
        db.close()
        report = check.check(crowded)
        self.assertGreater(report.places, 6000)
        os.remove(crowded)

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
        """The dedupe key of every row of a table: a POI's carries its kind."""
        columns = "osm_type, osm_id" + (", kind" if table == "pois" else "")
        db = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
        try:
            return {
                tuple(row) for row in db.execute(f"SELECT {columns} FROM {table}")
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

    def test_merge_of_two_copies_keeps_the_house_numbers_and_the_aliases(self) -> None:
        merged = self.run_merge(*self.copies(self.path(), self.path()))
        before = sqlite3.connect(f"file:{self.path()}?mode=ro", uri=True)
        after = sqlite3.connect(f"file:{merged}?mode=ro", uri=True)
        self.addCleanup(before.close)
        self.addCleanup(after.close)

        def rows(db: sqlite3.Connection, sql: str) -> list:
            return db.execute(sql).fetchall()

        # Ids are handed out again, so the house numbers and aliases are
        # compared through the names of the rows they hang off. Merging a file
        # with itself leaves every blob as it was, byte for byte.
        numbers = (
            "SELECT s.name, s.lat, s.lon, n.data FROM street_numbers n "
            "JOIN streets s ON s.id = n.street_id ORDER BY 1, 2, 3"
        )
        self.assertEqual(rows(after, numbers), rows(before, numbers))
        self.assertGreater(len(rows(after, numbers)), 100)

        vocab = "SELECT term, docs FROM vocab ORDER BY term"
        self.assertEqual(rows(after, vocab), rows(before, vocab))
        self.assertGreater(len(rows(after, vocab)), 1000)

        aliases = (
            "SELECT a.name, (SELECT name FROM places WHERE id = a.ref_id),"
            " (SELECT name FROM streets WHERE id = a.ref_id),"
            " (SELECT name FROM pois WHERE id = a.ref_id)"
            " FROM aliases a ORDER BY 1, 2, 3, 4"
        )
        self.assertEqual(rows(after, aliases), rows(before, aliases))
        self.assertGreater(len(rows(after, aliases)), 10)

    def test_merge_of_a_file_without_the_new_tables(self) -> None:
        """A `.gaz` built before Addendum 2 merges fine and gains the tables."""
        inputs = self.copies(self.path(), self.path(streets=False))
        legacy = os.path.join(inputs[1], f"{TILE}.gaz")
        db = sqlite3.connect(legacy)
        db.executescript(
            "DROP TABLE aliases; DROP TABLE street_numbers; DROP TABLE vocab;"
        )
        db.commit()
        db.close()
        merged = self.run_merge(*inputs)
        out = sqlite3.connect(f"file:{merged}?mode=ro", uri=True)
        self.addCleanup(out.close)
        self.assertGreater(
            out.execute("SELECT count(*) FROM street_numbers").fetchone()[0], 100
        )
        self.assertGreater(out.execute("SELECT count(*) FROM aliases").fetchone()[0], 10)
        check.check(merged)

    def break_file(self, *statements: str) -> str:
        broken = os.path.join(
            tempfile.mkdtemp(prefix="gaz-broken-", dir=self.tmp), f"{TILE}.gaz"
        )
        self.addCleanup(shutil.rmtree, os.path.dirname(broken), ignore_errors=True)
        shutil.copy(self.path(), broken)
        db = sqlite3.connect(broken)
        for statement in statements:
            db.execute(statement)
        db.commit()
        db.close()
        return broken

    def legacy(self) -> str:
        """A copy of the built file as an older builder wrote it: the
        street_numbers points as house_numbers anchors, and no vocab. A street
        with more points than an older file may hold anchors is left out."""
        path = self.break_file(
            "CREATE TABLE house_numbers (street_id INTEGER NOT NULL,"
            " number INTEGER NOT NULL, lat INTEGER NOT NULL, lon INTEGER NOT NULL,"
            " PRIMARY KEY (street_id, number)) WITHOUT ROWID"
        )
        db = sqlite3.connect(path)
        anchors = []
        for street_id, data in db.execute("SELECT street_id, data FROM street_numbers"):
            points = sum(street_numbers.decode(data), [])
            if len(points) <= check.MAX_ANCHORS:
                anchors += [(street_id, n, lat * 100, lon * 100) for n, lat, lon in points]
        db.executemany("INSERT INTO house_numbers VALUES (?,?,?,?)", anchors)
        db.executescript("DROP TABLE street_numbers; DROP TABLE vocab;")
        db.commit()
        db.close()
        return path

    def test_merge_of_an_older_file_with_a_new_one(self) -> None:
        """house_numbers anchors are read as points and come out as blobs."""
        inputs = self.copies(self.legacy(), self.path(streets=False))
        report = check.check(os.path.join(inputs[0], f"{TILE}.gaz"))
        self.assertGreater(report.house_numbers, 1000)
        self.assertEqual(report.street_numbers, 0)
        merged = self.run_merge(*inputs)
        merged_report = check.check(merged)
        self.assertEqual(merged_report.house_numbers, 0)
        self.assertEqual(merged_report.number_points, report.house_numbers)
        self.assertGreater(merged_report.vocab, 1000)

        def numbers(path: str) -> list:
            db = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
            try:
                return db.execute(
                    "SELECT s.name, s.lat, s.lon, n.data FROM street_numbers n "
                    "JOIN streets s ON s.id = n.street_id ORDER BY 1, 2, 3"
                ).fetchall()
            finally:
                db.close()

        # The anchors were this build's points, so the blobs come back unchanged.
        self.assertEqual(
            numbers(merged),
            [
                row
                for row in numbers(self.path())
                if sum(map(len, street_numbers.decode(row[3]))) <= check.MAX_ANCHORS
            ],
        )

        # Two different stretches of a street are joined and thinned again.
        inputs = self.copies(self.legacy(), self.path())
        first = os.path.join(inputs[0], f"{TILE}.gaz")
        db = sqlite3.connect(first)
        street_id = db.execute(
            "SELECT street_id FROM house_numbers GROUP BY street_id"
            " ORDER BY count(*) DESC LIMIT 1"
        ).fetchone()[0]
        db.execute(
            "DELETE FROM house_numbers WHERE street_id = ? AND number % 2 = 1", (street_id,)
        )
        db.execute(
            "INSERT INTO house_numbers VALUES (?, 100001, 471400000, 95200000)", (street_id,)
        )
        db.commit()
        db.close()
        merged = self.run_merge(*inputs)
        check.check(merged)
        joined = numbers(merged)
        self.assertEqual(len(joined), len(numbers(self.path())))
        self.assertTrue(
            any(100001 in [p[0] for p in street_numbers.decode(row[3])[0]] for row in joined)
        )

    def test_check_accepts_a_file_that_still_has_the_street_index(self) -> None:
        """Files built before the trim keep idx_streets_pos and stay valid."""
        older = self.break_file("CREATE INDEX idx_streets_pos ON streets(lat, lon)")
        report = check.check(older)
        self.assertTrue(report.has_streets)
        self.assertGreater(report.streets, 0)

    def test_check_rejects_a_dangling_alias(self) -> None:
        broken = self.break_file(
            "INSERT INTO aliases (id, ref_id, name) VALUES (9999999, 9999998, 'x')"
        )
        with self.assertRaises(check.GazetteerError) as caught:
            check.check(broken)
        self.assertIn("ref_id", str(caught.exception))

    def test_check_accepts_new_and_older_files(self) -> None:
        report = check.check(self.path())
        self.assertGreater(report.street_numbers, 100)
        self.assertGreater(report.number_points, report.street_numbers)
        self.assertGreater(report.vocab, 1000)
        self.assertEqual(report.house_numbers, 0)
        self.assertIn("numbered streets", report.summary())
        older = check.check(self.legacy())
        self.assertEqual((older.street_numbers, older.vocab), (0, 0))
        self.assertGreater(older.house_numbers, 1000)
        neither = self.break_file("DROP TABLE street_numbers", "DROP TABLE vocab")
        self.assertEqual(check.check(neither).street_numbers, 0)

    def test_check_rejects_a_corrupt_street_numbers_blob(self) -> None:
        street_id, data = self.open().execute(
            "SELECT street_id, data FROM street_numbers LIMIT 1"
        ).fetchone()
        for bad, why in (
            (data + b"\x00", "trailing"),
            (data[:-1], "ends inside"),
            (b"\x02" + data[1:], "version"),
            (b"\x01\x01\x02\x00\x00\x00", "odd run"),
        ):
            broken = self.break_file(
                f"UPDATE street_numbers SET data = x'{bad.hex()}' WHERE street_id = {street_id}"
            )
            with self.assertRaises(check.GazetteerError, msg=why) as caught:
                check.check(broken)
            self.assertIn(why, str(caught.exception))
            self.assertIn(f"street {street_id}", str(caught.exception))

    def test_check_rejects_dangling_house_numbers(self) -> None:
        broken = self.break_file(
            "INSERT INTO street_numbers (street_id, data) VALUES (9999998, x'010000')"
        )
        with self.assertRaises(check.GazetteerError) as caught:
            check.check(broken)
        self.assertIn("street_numbers.street_id", str(caught.exception))

        older = self.legacy()
        db = sqlite3.connect(older)
        db.execute(
            "INSERT INTO house_numbers (street_id, number, lat, lon)"
            " VALUES (9999998, 1, 471400000, 95200000)"
        )
        db.commit()
        db.close()
        with self.assertRaises(check.GazetteerError) as caught:
            check.check(older)
        self.assertIn("house_numbers.street_id", str(caught.exception))

    def test_vocab_is_the_fts_vocabulary(self) -> None:
        db = self.open()
        db.execute("CREATE VIRTUAL TABLE temp.v USING fts5vocab(main, 'search', 'row')")
        self.assertEqual(
            db.execute("SELECT term, docs FROM vocab ORDER BY term").fetchall(),
            db.execute("SELECT term, doc FROM temp.v ORDER BY term").fetchall(),
        )
        self.assertEqual(
            db.execute("SELECT docs FROM vocab WHERE term = 'vaduz'").fetchone()[0],
            db.execute("SELECT count(*) FROM search WHERE search MATCH 'vaduz'").fetchone()[0],
        )
        for statement, why in (
            ("UPDATE vocab SET docs = docs + 1 WHERE term = 'vaduz'", "'vaduz'"),
            ("DELETE FROM vocab WHERE term = 'vaduz'", "'vaduz'"),
            ("INSERT INTO vocab VALUES ('zzzznotaterm', 1)", "'zzzznotaterm'"),
        ):
            with self.assertRaises(check.GazetteerError, msg=statement) as caught:
                check.check(self.break_file(statement))
            self.assertIn("vocab", str(caught.exception))
            self.assertIn(why, str(caught.exception))

    def test_check_rejects_a_street_over_the_anchor_cap(self) -> None:
        """An older file's anchors: at most 40 a street."""
        self.assertEqual(check.MAX_ANCHORS, 40)
        street_id = self.open().execute("SELECT id FROM streets LIMIT 1").fetchone()[0]

        def crowd(anchors: int) -> str:
            path = self.legacy()
            db = sqlite3.connect(path)
            db.executescript(
                f"DELETE FROM house_numbers WHERE street_id = {street_id};"
                "INSERT INTO house_numbers (street_id, number, lat, lon)"
                f" SELECT {street_id}, value, 471400000, 95200000"
                f" FROM (WITH RECURSIVE n(value) AS (SELECT 1 UNION ALL"
                f"   SELECT value + 1 FROM n WHERE value < {anchors})"
                " SELECT value FROM n);"
            )
            db.close()
            return path

        # A file built before today carries up to 40 and is still valid.
        report = check.check(crowd(check.MAX_ANCHORS))
        self.assertEqual(report.max_anchors, check.MAX_ANCHORS)
        self.assertIn(f"max {check.MAX_ANCHORS}/street", report.summary())

        with self.assertRaises(check.GazetteerError) as caught:
            check.check(crowd(check.MAX_ANCHORS + 1))
        self.assertIn("anchors", str(caught.exception))

    def test_check_rejects_an_unnamed_cafe(self) -> None:
        """A NULL name is only ever allowed on the utility kinds."""
        broken = self.break_file(
            "UPDATE pois SET name = NULL WHERE id ="
            " (SELECT id FROM pois WHERE kind = 'cafe' LIMIT 1)"
        )
        with self.assertRaises(check.GazetteerError) as caught:
            check.check(broken)
        self.assertIn("cafe", str(caught.exception))

    def test_check_rejects_an_unnamed_row_in_the_index(self) -> None:
        """An unnamed row has nothing to match and must stay out of the FTS."""
        broken = self.break_file(
            "INSERT INTO search(rowid, name) SELECT id, 'brunnen' FROM pois"
            " WHERE name IS NULL LIMIT 1"
        )
        with self.assertRaises(check.GazetteerError) as caught:
            check.check(broken)
        self.assertIn("FTS index", str(caught.exception))
        self.assertIn("unnamed", str(caught.exception))

    def test_check_rejects_a_duplicated_poi(self) -> None:
        """(osm_type, osm_id, kind) is the identity of a POI row."""
        broken = self.break_file(
            "INSERT INTO pois (id, name, kind, lat, lon, place_id, osm_type, osm_id)"
            " SELECT 9999999, name, kind, lat, lon, place_id, osm_type, osm_id"
            " FROM pois WHERE name IS NULL LIMIT 1"
        )
        with self.assertRaises(check.GazetteerError) as caught:
            check.check(broken)
        self.assertIn("more than once", str(caught.exception))

    def test_merge_of_two_copies_keeps_the_unnamed_rows(self) -> None:
        """Unnamed rows merge like any other: deduplicated on
        (osm_type, osm_id, kind), and still out of the FTS index."""
        merged = self.run_merge(*self.copies(self.path(), self.path()))
        before = sqlite3.connect(f"file:{self.path()}?mode=ro", uri=True)
        after = sqlite3.connect(f"file:{merged}?mode=ro", uri=True)
        self.addCleanup(before.close)
        self.addCleanup(after.close)

        counted = "SELECT kind, count(*) FROM pois WHERE name IS NULL GROUP BY kind"
        rows = before.execute(counted).fetchall()
        self.assertTrue(rows)
        self.assertEqual(after.execute(counted).fetchall(), rows)
        self.assertEqual(
            after.execute(
                "SELECT count(*) FROM (SELECT osm_type, osm_id, kind FROM pois"
                " GROUP BY osm_type, osm_id, kind HAVING count(*) > 1)"
            ).fetchone()[0],
            0,
        )
        # A toilet with a tap survives as its two rows, not as one.
        self.assertEqual(
            after.execute(
                "SELECT kind FROM pois WHERE osm_type = 'n' AND osm_id = 4759689350"
                " ORDER BY kind"
            ).fetchall(),
            [("drinking_water",), ("toilets",)],
        )
        check.check(merged)

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
        self.assertEqual(meta["search_script"], "latin")
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
        self.assertLessEqual(
            imported, sys.stdlib_module_names | {"check", "street_numbers", "translit"}
        )
        for module in ("street_numbers.py", "translit.py"):
            with open(os.path.join(HERE, module), encoding="utf-8") as handle:
                tree = ast.parse(handle.read())
            imported = {
                alias.name.split(".")[0]
                for node in ast.walk(tree)
                if isinstance(node, ast.Import)
                for alias in node.names
            } | {
                node.module.split(".")[0]
                for node in ast.walk(tree)
                if isinstance(node, ast.ImportFrom) and node.module
            }
            self.assertLessEqual(imported, sys.stdlib_module_names, module)

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


def haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    import math

    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    d_phi = phi2 - phi1
    d_lambda = math.radians(lon2 - lon1)
    a = math.sin(d_phi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(d_lambda / 2) ** 2
    return 2 * 6371000 * math.asin(math.sqrt(a))


class TestsetTest(unittest.TestCase):
    """testset.py against the committed E5_N45 fixture: no extract needed."""

    fixture = os.path.join(HERE, "fixtures", f"{TILE}.gaz")
    generated: dict

    @classmethod
    def setUpClass(cls) -> None:
        if not os.path.isfile(cls.fixture):
            raise unittest.SkipTest("fixture not present")
        cls.generated = testset.generate(cls.fixture, seed=1, per_kind=15)
        db = sqlite3.connect(f"file:{cls.fixture}?mode=ro", uri=True)
        try:
            cls.rows = {
                table: {
                    row[0]: row[1:]
                    for row in db.execute(f"SELECT id, name, lat, lon FROM {table}")
                }
                for table in ("places", "streets", "pois")
            }
            cls.anchors = {}
            for street_id, data in db.execute(
                "SELECT street_id, data FROM street_numbers"
            ):
                odd, even = street_numbers.decode(data)
                cls.anchors[street_id] = {n: (lat, lon) for n, lat, lon in odd + even}
            cls.aliases = {
                (name, ref_id)
                for name, ref_id in db.execute("SELECT name, ref_id FROM aliases")
            }
        finally:
            db.close()

    def cases(self, kind: str) -> list[dict]:
        found = [c for c in self.generated["cases"] if c["kind"] == kind]
        self.assertTrue(found, f"no {kind} cases")
        return found

    # ---------------------------------------------------------- the file ---

    def test_is_deterministic(self) -> None:
        again = testset.generate(self.fixture, seed=1, per_kind=15)
        self.assertEqual(json.dumps(again, sort_keys=True), json.dumps(self.generated, sort_keys=True))
        other = testset.generate(self.fixture, seed=2, per_kind=15)
        self.assertNotEqual(
            [c["query"] for c in other["cases"]],
            [c["query"] for c in self.generated["cases"]],
        )

    def test_every_kind_is_present_and_tagged(self) -> None:
        kinds = {c["kind"] for c in self.generated["cases"]}
        self.assertEqual(kinds, set(testset.ALL_KINDS))
        self.assertEqual(self.generated["tile"], TILE)
        self.assertGreater(len(self.generated["cases"]), 300)
        for c in self.generated["cases"]:
            self.assertEqual(c["tile"], TILE)
            self.assertEqual(set(c), {"query", "kind", "expected", "tile", "near"})
            self.assertEqual(set(c["expected"]), {"table", "id", "name", "lat", "lon", "place"})

    def test_expected_rows_exist(self) -> None:
        for c in self.generated["cases"]:
            e = c["expected"]
            row = self.rows[e["table"]].get(e["id"])
            self.assertIsNotNone(row, f"{e} is not in the file")
            self.assertEqual(row[0], e["name"])
            if not c["kind"].startswith("address_"):
                self.assertAlmostEqual(row[1] / 1e7, e["lat"], places=6)
                self.assertAlmostEqual(row[2] / 1e7, e["lon"], places=6)

    def test_near_is_a_few_km_away(self) -> None:
        for c in self.generated["cases"]:
            e, near = c["expected"], c["near"]
            km = haversine_m(e["lat"], e["lon"], near["lat"], near["lon"]) / 1000
            self.assertTrue(0.4 < km < 3.2, f"{c['query']}: near is {km:.1f} km away")

    def test_no_case_is_repeated_within_a_kind(self) -> None:
        seen = set()
        for c in self.generated["cases"]:
            key = (c["kind"], c["query"].lower())
            self.assertNotIn(key, seen)
            seen.add(key)

    def test_writes_one_case_per_line(self) -> None:
        tmp = tempfile.mkdtemp(prefix="gaz-testset-")
        self.addCleanup(shutil.rmtree, tmp, ignore_errors=True)
        subprocess.run(
            [sys.executable, os.path.join(HERE, "testset.py"), self.fixture, "--out", tmp, "--per-kind", "3"],
            check=True,
            capture_output=True,
        )
        path = os.path.join(tmp, f"{TILE}.json")
        with open(path, encoding="utf-8") as f:
            text = f.read()
        parsed = json.loads(text)
        self.assertEqual(parsed["per_kind"], 3)
        self.assertEqual(len([l for l in text.splitlines() if l.startswith("  {")]), len(parsed["cases"]))

    # ------------------------------------------------ what each kind claims ---

    def test_exact_is_the_name(self) -> None:
        for c in self.cases("exact"):
            self.assertEqual(c["query"], c["expected"]["name"])

    def test_typos_are_one_edit_away(self) -> None:
        for kind in ("typo_swap", "typo_missing", "typo_double", "typo_neighbour", "typo_wrong"):
            for c in self.cases(kind):
                name, q = c["expected"]["name"], c["query"]
                self.assertNotEqual(q, name)
                self.assertEqual(testset.edit_distance(q, name), 1, f"{kind}: {q!r} vs {name!r}")
                self.assertEqual(q[0], name[0], f"{kind} touched the first letter: {q!r}")

    def test_typo_kinds_do_what_they_say(self) -> None:
        for c in self.cases("typo_swap"):
            name, q = c["expected"]["name"], c["query"]
            self.assertEqual(sorted(q), sorted(name))
            self.assertEqual(len(q), len(name))
        for c in self.cases("typo_missing"):
            self.assertEqual(len(c["query"]), len(c["expected"]["name"]) - 1)
        for c in self.cases("typo_double"):
            self.assertEqual(len(c["query"]), len(c["expected"]["name"]) + 1)
        for c in self.cases("typo_neighbour"):
            name, q = c["expected"]["name"], c["query"]
            self.assertEqual(len(q), len(name))
            (i,) = [i for i in range(len(q)) if q[i] != name[i]]
            self.assertIn(q[i].lower(), testset.KEY_NEIGHBOURS[name[i].lower()])
        for c in self.cases("typo_wrong"):
            name, q = c["expected"]["name"], c["query"]
            self.assertEqual(len(q), len(name))
            self.assertEqual(sum(1 for a, b in zip(q, name) if a != b), 1)

    def test_accents_sz_and_case(self) -> None:
        for c in self.cases("accent_drop"):
            name, q = c["expected"]["name"], c["query"]
            self.assertNotEqual(q, name)
            self.assertEqual(q, testset.strip_accents(name))
            self.assertTrue(q.isascii() or any(ord(ch) > 127 for ch in q))
        for c in self.cases("sz_to_ss"):
            self.assertNotIn("ß", c["query"])
            self.assertEqual(c["query"], c["expected"]["name"].replace("ß", "ss"))
        for c in self.cases("ss_to_sz"):
            self.assertIn("ß", c["query"])
            self.assertEqual(c["query"].replace("ß", "ss"), c["expected"]["name"])
        for c in self.cases("case"):
            name, q = c["expected"]["name"], c["query"]
            self.assertNotEqual(q, name)
            self.assertEqual(q.lower(), name.lower())

    def test_abbreviations_come_from_the_table(self) -> None:
        shorts = {s.lower() for _, options in testset.ABBREVIATIONS for s in options}
        for c in self.cases("abbrev"):
            name, q = c["expected"]["name"], c["query"]
            self.assertNotEqual(q, name)
            self.assertLess(len(q), len(name))
            self.assertTrue(
                any(s in q.lower() for s in shorts), f"{q!r} holds no abbreviation"
            )
        self.assertIn(testset.abbreviate("Hauptstraße", testset.random.Random(0)), ("Hauptstr.", "Hauptstr"))
        self.assertEqual(testset.abbreviate("Rua da Carreira", testset.random.Random(0)), "R. da Carreira")
        self.assertEqual(testset.abbreviation_sites("Via Roma"), [(0, 3, "via")])
        self.assertEqual(testset.abbreviation_sites("Viale Roma"), [(0, 5, "viale")])

    def test_compounds(self) -> None:
        for c in self.cases("compound_split"):
            name, q = c["expected"]["name"], c["query"]
            self.assertEqual(len(q.split()), len(name.split()) + 1)
            self.assertEqual(q.replace(" ", ""), name.replace(" ", ""))
        for c in self.cases("compound_join"):
            name, q = c["expected"]["name"], c["query"]
            self.assertEqual(len(q.split()), len(name.split()) - 1)
            self.assertEqual(q.replace(" ", "").lower(), name.replace(" ", "").lower())
        self.assertEqual(testset.split_point("Bahnhofstraße"), len("Bahnhof"))
        self.assertEqual(testset.split_point("Lockwood"), len("Lock"))
        self.assertIsNone(testset.split_point("aaaaaaaaaa"))

    def test_partials(self) -> None:
        for c in self.cases("partial_first"):
            name, q = c["expected"]["name"], c["query"]
            self.assertEqual(q, name.split()[0])
            self.assertNotIn(q.lower(), testset.GENERIC_WORDS)
        for c in self.cases("partial_last"):
            name, q = c["expected"]["name"], c["query"]
            self.assertEqual(q, name.split()[-1])
            self.assertNotIn(q.lower(), testset.GENERIC_WORDS)
        for c in self.cases("partial_prefix"):
            name, q = c["expected"]["name"], c["query"]
            self.assertTrue(name.startswith(q))
            self.assertTrue(4 <= len(q) < len(name))
            self.assertFalse(q.endswith(" "))

    def test_addresses_use_a_real_anchor(self) -> None:
        import re

        patterns = {
            "address_after": r"^(.+) (\d+)$",
            "address_before": r"^(\d+) (.+)$",
            "address_suffix": r"^(.+) (\d+)[abc]$",
            "address_range": r"^(.+) (\d+)-\d+$",
            "address_abbrev": r"^(.+) (\d+)$",
        }
        shorts = {s.lower() for _, options in testset.ABBREVIATIONS for s in options}
        for kind, pattern in patterns.items():
            for c in self.cases(kind):
                e = c["expected"]
                self.assertEqual(e["table"], "streets")
                m = re.match(pattern, c["query"])
                self.assertIsNotNone(m, f"{kind}: {c['query']!r}")
                if kind == "address_before":
                    street, number = m.group(2), int(m.group(1))
                else:
                    street, number = m.group(1), int(m.group(2))
                if kind == "address_abbrev":
                    self.assertNotEqual(street, e["name"])
                    self.assertTrue(any(s in street.lower() for s in shorts))
                else:
                    self.assertEqual(street, e["name"])
                anchor = self.anchors[e["id"]].get(number)
                self.assertIsNotNone(anchor, f"{number} is not a point of {e['name']}")
                self.assertAlmostEqual(anchor[0] / 1e5, e["lat"], places=6)
                self.assertAlmostEqual(anchor[1] / 1e5, e["lon"], places=6)
        for c in self.cases("address_place"):
            e = c["expected"]
            self.assertIsNotNone(e["place"])
            self.assertIn(e["name"], c["query"])
            self.assertIn(e["place"], c["query"])
            self.assertTrue(re.search(r"\d+", c["query"]))

    def test_aliases_point_at_their_row(self) -> None:
        for c in self.cases("alias"):
            e = c["expected"]
            self.assertIn((c["query"], e["id"]), self.aliases)
            self.assertNotEqual(c["query"], e["name"])

    # ------------------------------------------------------- the helpers ---

    def test_helpers(self) -> None:
        rng = testset.random.Random(3)
        self.assertEqual(testset.edit_distance("ab", "ba"), 1)
        self.assertEqual(testset.edit_distance("Vaduz", "Vadus"), 1)
        self.assertEqual(testset.edit_distance("Vaduz", "Vaduz"), 0)
        self.assertEqual(testset.strip_accents("São João Ødegård Łódź"), "Sao Joao Odegard Lodz")
        swapped = testset.swap_adjacent("Schaan", rng)
        self.assertEqual(swapped[0], "S")
        self.assertEqual(sorted(swapped), sorted("Schaan"))
        self.assertEqual(testset.drop_letter("Vaduz", rng)[0], "V")
        self.assertEqual(len(testset.double_letter("Vaduz", rng)), 6)
        self.assertEqual(testset.to_ss("Straße", rng), "Strasse")
        self.assertEqual(testset.to_sz("Strasse", rng), "Straße")
        self.assertEqual(testset.join_compound("Vorder Prufatscheng", rng), "Vorderprufatscheng")
        self.assertEqual(testset.first_word("Äussere Wiesen", rng), "Äussere")
        self.assertIsNone(testset.partial_word("Rua da Carreira", 0))
        self.assertEqual(testset.partial_word("Rua da Carreira", -1), "Carreira")
        self.assertTrue(testset.words_of("  a  b ") == ["a", "b"])


if __name__ == "__main__":
    unittest.main()
