/// Builds `<TILE>.gaz` files in the v1 format the app reads.
///
/// The real files come from `tools/gazetteer`, but a unit test must not depend
/// on that directory or on a committed binary, so the schema of the format
/// spec is written out here and filled with a handful of rows. Keep this in
/// step with `GazetteerStore` and the format spec: if the two drift apart, the
/// tests stop saying anything.
library;

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

/// A settlement row.
class GazPlace {
  /// Creates a place.
  const GazPlace(
    this.id,
    this.name,
    this.kind,
    this.lat,
    this.lon, {
    this.population,
    this.adminId,
  });

  /// The row id, unique across places, streets and POIs.
  final int id;

  /// The searchable name.
  final String name;

  /// `city`, `town`, `village`, …
  final String kind;

  /// Position in degrees.
  final double lat, lon;

  /// Inhabitants, when OSM has a number.
  final int? population;

  /// The place this one sits in.
  final int? adminId;
}

/// A street row.
class GazStreet {
  /// Creates a street.
  const GazStreet(this.id, this.name, this.lat, this.lon, {this.placeId});

  /// The row id, unique across all three tables.
  final int id;

  /// The searchable name.
  final String name;

  /// Position in degrees.
  final double lat, lon;

  /// The place it belongs to.
  final int? placeId;
}

/// A named point of interest.
class GazPoi {
  /// Creates a POI.
  const GazPoi(
    this.id,
    this.name,
    this.kind,
    this.lat,
    this.lon, {
    this.placeId,
  });

  /// The row id, unique across all three tables.
  final int id;

  /// The searchable name.
  final String name;

  /// `drinking_water`, `cafe`, `peak`, …
  final String kind;

  /// Position in degrees.
  final double lat, lon;

  /// The place it belongs to.
  final int? placeId;
}

/// An alternative name of a place, a street or a POI.
class GazAlias {
  /// Creates an alias.
  const GazAlias(this.id, this.refId, this.name);

  /// The row id, from the same counter as the three tables.
  final int id;

  /// The places/streets/pois row this name belongs to.
  final int refId;

  /// The alternative name, which is what the FTS index holds.
  final String name;
}

/// One house-number anchor on a street.
class GazHouseNumber {
  /// Creates an anchor.
  const GazHouseNumber(this.streetId, this.number, this.lat, this.lon);

  /// The street it sits on.
  final int streetId;

  /// The leading integer of `addr:housenumber`.
  final int number;

  /// Position in degrees.
  final double lat, lon;
}

/// Writes `<tile>.gaz` into [dir] and returns it.
///
/// [schemaVersion] is written into `meta` as given, so a test can produce a
/// file from a future builder that this app must refuse. [legacy] leaves out
/// `aliases` and `house_numbers` altogether, the way the first builder wrote
/// its files; the app has to answer from those too.
File buildGazetteer(
  Directory dir,
  String tile, {
  String schemaVersion = '1',
  bool legacy = false,
  List<GazPlace> places = const <GazPlace>[],
  List<GazStreet> streets = const <GazStreet>[],
  List<GazPoi> pois = const <GazPoi>[],
  List<GazAlias> aliases = const <GazAlias>[],
  List<GazHouseNumber> houseNumbers = const <GazHouseNumber>[],
}) {
  dir.createSync(recursive: true);
  final file = File('${dir.path}/$tile.gaz');
  if (file.existsSync()) file.deleteSync();

  final db = sqlite3.open(file.path);
  try {
    db
      ..execute('PRAGMA page_size = 4096;')
      ..execute('PRAGMA journal_mode = DELETE;')
      ..execute(
        'CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);',
      )
      ..execute('''
CREATE TABLE places (
    id         INTEGER PRIMARY KEY,
    name       TEXT NOT NULL,
    kind       TEXT NOT NULL,
    lat        INTEGER NOT NULL,
    lon        INTEGER NOT NULL,
    population INTEGER,
    admin_id   INTEGER
);''')
      ..execute('''
CREATE TABLE streets (
    id       INTEGER PRIMARY KEY,
    name     TEXT NOT NULL,
    lat      INTEGER NOT NULL,
    lon      INTEGER NOT NULL,
    place_id INTEGER
);''')
      ..execute('''
CREATE TABLE pois (
    id       INTEGER PRIMARY KEY,
    name     TEXT NOT NULL,
    kind     TEXT NOT NULL,
    lat      INTEGER NOT NULL,
    lon      INTEGER NOT NULL,
    place_id INTEGER
);''')
      ..execute('''
CREATE VIRTUAL TABLE search USING fts5(
    name,
    content='',
    columnsize=0,
    tokenize='unicode61 remove_diacritics 2'
);''')
      ..execute('CREATE INDEX idx_places_pos  ON places(lat, lon);')
      ..execute('CREATE INDEX idx_streets_pos ON streets(lat, lon);')
      ..execute('CREATE INDEX idx_pois_pos    ON pois(lat, lon);');

    if (!legacy) {
      db
        ..execute('''
CREATE TABLE aliases (
    id     INTEGER PRIMARY KEY,
    ref_id INTEGER NOT NULL,
    name   TEXT NOT NULL
);''')
        ..execute('CREATE INDEX idx_aliases_ref ON aliases(ref_id);')
        ..execute('''
CREATE TABLE house_numbers (
    street_id INTEGER NOT NULL,
    number    INTEGER NOT NULL,
    lat       INTEGER NOT NULL,
    lon       INTEGER NOT NULL,
    PRIMARY KEY (street_id, number)
) WITHOUT ROWID;''');
    }

    for (final row in <List<Object?>>[
      <Object?>['schema_version', schemaVersion],
      <Object?>['tile', tile],
      <Object?>['built_at', '2026-09-16T01:00:00Z'],
      <Object?>['source', 'test-fixture.osm.pbf'],
      <Object?>['has_streets', streets.isEmpty ? '0' : '1'],
      <Object?>['has_pois', pois.isEmpty ? '0' : '1'],
    ]) {
      db.execute('INSERT INTO meta (key, value) VALUES (?, ?);', row);
    }

    final index = db.prepare('INSERT INTO search(rowid, name) VALUES (?, ?);');
    for (final place in places) {
      db.execute(
        'INSERT INTO places (id, name, kind, lat, lon, population, admin_id) '
        'VALUES (?, ?, ?, ?, ?, ?, ?);',
        <Object?>[
          place.id,
          place.name,
          place.kind,
          _e7(place.lat),
          _e7(place.lon),
          place.population,
          place.adminId,
        ],
      );
      index.execute(<Object?>[place.id, place.name]);
    }
    for (final street in streets) {
      db.execute(
        'INSERT INTO streets (id, name, lat, lon, place_id) '
        'VALUES (?, ?, ?, ?, ?);',
        <Object?>[
          street.id,
          street.name,
          _e7(street.lat),
          _e7(street.lon),
          street.placeId,
        ],
      );
      index.execute(<Object?>[street.id, street.name]);
    }
    for (final poi in pois) {
      db.execute(
        'INSERT INTO pois (id, name, kind, lat, lon, place_id) '
        'VALUES (?, ?, ?, ?, ?, ?);',
        <Object?>[
          poi.id,
          poi.name,
          poi.kind,
          _e7(poi.lat),
          _e7(poi.lon),
          poi.placeId,
        ],
      );
      index.execute(<Object?>[poi.id, poi.name]);
    }
    for (final alias in aliases) {
      db.execute(
        'INSERT INTO aliases (id, ref_id, name) VALUES (?, ?, ?);',
        <Object?>[alias.id, alias.refId, alias.name],
      );
      index.execute(<Object?>[alias.id, alias.name]);
    }
    for (final anchor in houseNumbers) {
      db.execute(
        'INSERT INTO house_numbers (street_id, number, lat, lon) '
        'VALUES (?, ?, ?, ?);',
        <Object?>[
          anchor.streetId,
          anchor.number,
          _e7(anchor.lat),
          _e7(anchor.lon),
        ],
      );
    }
    index.close();
    db.execute('VACUUM;');
  } finally {
    db.close();
  }
  return file;
}

/// The Liechtenstein-shaped fixture the store tests search in.
List<GazPlace> get fixturePlaces => const <GazPlace>[
  GazPlace(1, 'Vaduz', 'town', 47.1410, 9.5209, population: 5450),
  GazPlace(2, 'Mühleholz', 'village', 47.1465, 9.5150, adminId: 1),
  GazPlace(3, 'Schaan', 'town', 47.1650, 9.5090, population: 6039),
  GazPlace(4, 'Triesenberg', 'village', 47.1170, 9.5420, population: 2600),
];

/// Streets of the same fixture.
List<GazStreet> get fixtureStreets => const <GazStreet>[
  GazStreet(10, 'Im Mühleholz', 47.1460, 9.5140, placeId: 1),
  GazStreet(11, 'Städtle', 47.1400, 9.5215, placeId: 1),
];

/// POIs of the same fixture.
List<GazPoi> get fixturePois => const <GazPoi>[
  GazPoi(
    20,
    'Brunnen Mühleholz',
    'drinking_water',
    47.1466,
    9.5152,
    placeId: 2,
  ),
  GazPoi(21, 'Café Wolf', 'cafe', 47.1405, 9.5220, placeId: 1),
  GazPoi(22, 'Falknis', 'peak', 47.0900, 9.5800),
];

int _e7(double degrees) => (degrees * 1e7).round();
