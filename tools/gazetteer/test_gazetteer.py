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
    charging_station picnic_site bicycle_parking
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
                (row[1], row[2], row[5])
                for row in db.execute("PRAGMA table_info(house_numbers)")
            ],
            [
                ("street_id", "INTEGER", 1),
                ("number", "INTEGER", 2),
                ("lat", "INTEGER", 0),
                ("lon", "INTEGER", 0),
            ],
        )
        self.assertIn(
            "WITHOUT ROWID",
            db.execute(
                "SELECT sql FROM sqlite_master WHERE name = 'house_numbers'"
            ).fetchone()[0],
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
            {"idx_places_pos", "idx_streets_pos", "idx_pois_pos", "idx_aliases_ref"},
            indexes,
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

    def test_streets_are_built_by_default(self) -> None:
        db = self.open()
        self.assertGreater(db.execute("SELECT count(*) FROM streets").fetchone()[0], 0)
        self.assertGreater(
            db.execute("SELECT count(*) FROM house_numbers").fetchone()[0], 0
        )

    def test_no_streets_leaves_out_streets_and_house_numbers(self) -> None:
        db = self.open(streets=False)
        self.assertEqual(db.execute("SELECT count(*) FROM streets").fetchone()[0], 0)
        self.assertEqual(
            db.execute("SELECT count(*) FROM house_numbers").fetchone()[0], 0
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

    # ----------------------------------------------------- house numbers ---

    def test_thin_anchors_keeps_the_ends(self) -> None:
        entries = [(number, number, 0) for number in range(1, 61)]
        thinned = build.thin_anchors(entries)
        self.assertEqual(thinned[0], entries[0])
        self.assertEqual(thinned[-1], entries[-1])
        self.assertLessEqual(len(thinned), build.MAX_ANCHORS)
        self.assertEqual([e[0] for e in thinned], sorted(e[0] for e in thinned))
        # Every tenth in between, so 1, 11, 21, ... plus the last.
        self.assertEqual([e[0] for e in thinned], [1, 11, 21, 31, 41, 51, 60])
        # Even 500 numbers stay under the cap.
        many = build.thin_anchors([(n, n, 0) for n in range(1, 501)])
        self.assertLessEqual(len(many), build.MAX_ANCHORS)
        self.assertEqual((many[0][0], many[-1][0]), (1, 500))

    def test_a_street_with_fifty_addresses_is_thinned(self) -> None:
        """The whole path: addresses in, anchors out, on one synthetic street."""
        street = build.StreetRow(7, "Teststrasse", 47.14, 9.52, None, ())
        book = build.AddressBook()
        for number in range(50, 0, -1):  # out of order on purpose
            book.add("teststrasse", number, 47.14 + number * 1e-5, 9.52)
        book.add("Teststrasse", 1, 47.145, 9.52)  # number 1 again, further off
        book.add("Teststrasse", 2, 48.90, 9.52)  # 200 km away: no street near
        anchors = build.house_numbers(book.of("E5_N45"), book.names, [street])
        numbers = [row[1] for row in anchors]
        self.assertTrue(all(row[0] == 7 for row in anchors))
        self.assertLessEqual(len(anchors), build.MAX_ANCHORS)
        self.assertEqual(numbers, sorted(numbers))
        self.assertEqual((numbers[0], numbers[-1]), (1, 50))
        # The first address of a repeated number wins, so number 1 keeps the
        # position it was first seen at, not the one added later.
        first = next(row for row in anchors if row[1] == 1)
        self.assertAlmostEqual(first[2] / 1e7, 47.14 + 1e-5, places=6)

    def test_house_numbers_in_the_built_file(self) -> None:
        db = self.open()
        street_ids = {row[0] for row in db.execute("SELECT id FROM streets")}
        rows = db.execute(
            "SELECT street_id, count(*), min(number), max(number) FROM house_numbers"
            " GROUP BY street_id"
        ).fetchall()
        self.assertGreater(len(rows), 100)
        for street_id, count, lowest, highest in rows:
            self.assertIn(street_id, street_ids)
            self.assertLessEqual(count, build.MAX_ANCHORS)
            self.assertLessEqual(lowest, highest)
        self.assertEqual(
            db.execute("SELECT count(*) FROM house_numbers WHERE number < 1").fetchone()[0],
            0,
        )

    def test_leading_number(self) -> None:
        self.assertEqual(build.leading_number("12a"), 12)
        self.assertEqual(build.leading_number(" 7 "), 7)
        self.assertEqual(build.leading_number("12-14"), 12)
        self.assertIsNone(build.leading_number("A3"))
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

    def busiest_street(self) -> tuple[int, str, list[int]]:
        db = self.open()
        street_id, name = db.execute(
            "SELECT s.id, s.name FROM streets s JOIN house_numbers h"
            " ON h.street_id = s.id GROUP BY s.id"
            " ORDER BY count(*) DESC, s.id LIMIT 1"
        ).fetchone()
        numbers = [
            row[0]
            for row in db.execute(
                "SELECT number FROM house_numbers WHERE street_id = ? ORDER BY number",
                (street_id,),
            )
        ]
        return street_id, name, numbers

    def test_query_finds_an_exact_anchor(self) -> None:
        db = self.open()
        street_id, name, numbers = self.busiest_street()
        hits = query.search(db, f"{numbers[0]} {name}", 30)
        hit = next(h for h in hits if h.id == street_id)
        self.assertEqual(hit.house_number, str(numbers[0]))
        self.assertFalse(hit.approximate)
        lat, lon = db.execute(
            "SELECT lat, lon FROM house_numbers WHERE street_id = ? AND number = ?",
            (street_id, numbers[0]),
        ).fetchone()
        self.assertAlmostEqual(hit.lat, lat / 1e7, places=6)
        self.assertAlmostEqual(hit.lon, lon / 1e7, places=6)

    def test_query_interpolates_between_two_anchors(self) -> None:
        db = self.open()
        street_id, name, numbers = self.busiest_street()
        low, high = next(
            (a, b) for a, b in zip(numbers, numbers[1:]) if b - a > 1
        )
        between = low + 1
        hits = query.search(db, f"{name} {between}", 30)
        hit = next(h for h in hits if h.id == street_id)
        self.assertEqual(hit.house_number, str(between))
        self.assertTrue(hit.approximate)
        ends = db.execute(
            "SELECT lat, lon FROM house_numbers WHERE street_id = ? AND number IN (?, ?)",
            (street_id, low, high),
        ).fetchall()
        self.assertEqual(len(ends), 2)
        self.assertGreaterEqual(hit.lat, min(e[0] for e in ends) / 1e7 - 1e-9)
        self.assertLessEqual(hit.lat, max(e[0] for e in ends) / 1e7 + 1e-9)

    def test_query_falls_back_past_the_ends_and_to_the_street(self) -> None:
        db = self.open()
        street_id, name, numbers = self.busiest_street()
        hit = next(
            h for h in query.search(db, f"{numbers[-1] + 5000} {name}", 30)
            if h.id == street_id
        )
        self.assertTrue(hit.approximate)
        last = db.execute(
            "SELECT lat, lon FROM house_numbers WHERE street_id = ? AND number = ?",
            (street_id, numbers[-1]),
        ).fetchone()
        self.assertAlmostEqual(hit.lat, last[0] / 1e7, places=6)

        # A street with no anchors at all answers with its own position.
        row = db.execute(
            "SELECT id, name, lat, lon FROM streets WHERE id NOT IN"
            " (SELECT street_id FROM house_numbers) LIMIT 1"
        ).fetchone()
        hit = next(
            (h for h in query.search(db, f"{row[1]} 9", 60) if h.id == row[0]), None
        )
        if hit is not None:
            self.assertTrue(hit.approximate)
            self.assertAlmostEqual(hit.lat, row[2] / 1e7, places=6)

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

    def test_merge_of_two_copies_keeps_the_anchors_and_the_aliases(self) -> None:
        merged = self.run_merge(*self.copies(self.path(), self.path()))
        before = sqlite3.connect(f"file:{self.path()}?mode=ro", uri=True)
        after = sqlite3.connect(f"file:{merged}?mode=ro", uri=True)
        self.addCleanup(before.close)
        self.addCleanup(after.close)

        def rows(db: sqlite3.Connection, sql: str) -> list:
            return db.execute(sql).fetchall()

        # Ids are handed out again, so the anchors and aliases are compared
        # through the names of the rows they hang off.
        anchors = (
            "SELECT s.name, h.number, h.lat, h.lon FROM house_numbers h "
            "JOIN streets s ON s.id = h.street_id ORDER BY s.name, h.number"
        )
        self.assertEqual(rows(after, anchors), rows(before, anchors))
        self.assertGreater(len(rows(after, anchors)), 100)

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
        db.executescript("DROP TABLE aliases; DROP TABLE house_numbers;")
        db.commit()
        db.close()
        merged = self.run_merge(*inputs)
        out = sqlite3.connect(f"file:{merged}?mode=ro", uri=True)
        self.addCleanup(out.close)
        self.assertGreater(
            out.execute("SELECT count(*) FROM house_numbers").fetchone()[0], 100
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

    def test_check_rejects_a_dangling_alias(self) -> None:
        broken = self.break_file(
            "INSERT INTO aliases (id, ref_id, name) VALUES (9999999, 9999998, 'x')"
        )
        with self.assertRaises(check.GazetteerError) as caught:
            check.check(broken)
        self.assertIn("ref_id", str(caught.exception))

    def test_check_rejects_a_dangling_anchor(self) -> None:
        broken = self.break_file(
            "INSERT INTO house_numbers (street_id, number, lat, lon)"
            " VALUES (9999998, 1, 471400000, 95200000)"
        )
        with self.assertRaises(check.GazetteerError) as caught:
            check.check(broken)
        self.assertIn("street_id", str(caught.exception))

    def test_check_rejects_a_street_over_the_anchor_cap(self) -> None:
        street_id = self.open().execute("SELECT id FROM streets LIMIT 1").fetchone()[0]
        broken = self.break_file(
            "INSERT OR REPLACE INTO house_numbers (street_id, number, lat, lon)"
            f" SELECT {street_id}, value, 471400000, 95200000"
            f" FROM (WITH RECURSIVE n(value) AS (SELECT 1 UNION ALL"
            f"   SELECT value + 1 FROM n WHERE value < {build.MAX_ANCHORS + 1})"
            " SELECT value FROM n)"
        )
        with self.assertRaises(check.GazetteerError) as caught:
            check.check(broken)
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
