import 'dart:convert';

import 'tiles.dart';

/// One rd5 segment tile offered by a mirror.
class SegmentEntry {
  /// Creates an entry.
  const SegmentEntry({
    required this.tile,
    required this.bytes,
    this.updatedAt,
    this.formatVersion,
    this.sha256,
  });

  /// Which tile this is.
  final TileName tile;

  /// Size of the `.rd5` file in bytes; `0` when the source does not say.
  final int bytes;

  /// When the mirror last wrote the file, in UTC, or `null` when unknown.
  final DateTime? updatedAt;

  /// The rd5 format version (the `lookups.dat` version pair, e.g. `11.2`).
  ///
  /// The updater states it once for the whole manifest;
  /// [SegmentsManifest.parse] copies it onto every entry so a tile row is
  /// self-contained, which is how the app stores it in `routing_tiles`.
  final String? formatVersion;

  /// Hex SHA-256 of the file, when the mirror publishes one
  /// (`MANIFEST_SHA256=1` in the updater).
  final String? sha256;

  /// The `.rd5` file name.
  String get fileName => tile.fileName;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SegmentEntry &&
          other.tile == tile &&
          other.bytes == bytes &&
          other.updatedAt == updatedAt &&
          other.formatVersion == formatVersion &&
          other.sha256 == sha256;

  @override
  int get hashCode =>
      Object.hash(tile, bytes, updatedAt, formatVersion, sha256);

  @override
  String toString() => 'SegmentEntry($tile, $bytes B, $updatedAt)';
}

/// What a segment mirror offers: the tile list of `manifest.json`, or the same
/// information scraped from a directory listing.
///
/// The app reads `${VELORKI_SEGMENTS_URL}/manifest.json` from our own mirror
/// (written by `brouter/updater/sync.sh`) and falls back to the brouter.de
/// directory index, which is why both shapes parse into this one type.
class SegmentsManifest {
  /// Creates a manifest.
  const SegmentsManifest({
    required this.tiles,
    this.formatVersion,
    this.brouterVersion,
    this.source,
    this.generatedAt,
  });

  /// An empty manifest.
  static const SegmentsManifest empty = SegmentsManifest(
    tiles: <SegmentEntry>[],
  );

  /// The tiles, in the order the source listed them.
  final List<SegmentEntry> tiles;

  /// The rd5 format version the whole mirror is on, when it says.
  final String? formatVersion;

  /// The BRouter release the mirror tracks, e.g. `v1.7.10`.
  final String? brouterVersion;

  /// Where the mirror itself pulled the tiles from.
  final String? source;

  /// When the manifest was written, in UTC.
  final DateTime? generatedAt;

  /// The entries keyed by tile.
  Map<TileName, SegmentEntry> get byTile => <TileName, SegmentEntry>{
    for (final e in tiles) e.tile: e,
  };

  /// The tiles as a set, for the composite backend's coverage check.
  Set<TileName> get tileSet => tiles.map((e) => e.tile).toSet();

  /// Total download size of every tile, in bytes.
  int get totalBytes => tiles.fold(0, (sum, e) => sum + e.bytes);

  /// The entry for [tile], or `null`.
  SegmentEntry? operator [](TileName tile) {
    for (final e in tiles) {
      if (e.tile == tile) return e;
    }
    return null;
  }

  /// Sum of the sizes of [wanted], ignoring tiles the mirror does not have.
  int bytesFor(Iterable<TileName> wanted) {
    final index = byTile;
    var sum = 0;
    for (final t in wanted) {
      sum += index[t]?.bytes ?? 0;
    }
    return sum;
  }

  /// Parses the updater's `manifest.json`.
  ///
  /// [json] is either the raw text or an already decoded structure. Both
  /// shapes the mirrors write are accepted:
  ///
  /// * a bare array — `[{"tile": "E5_N45", "bytes": 1, "updatedAt": "..."}]`
  /// * the object `sync.sh` writes — `{"formatVersion": "11.2",
  ///   "brouterVersion": "v1.7.10", "source": "...", "generatedAt": "...",
  ///   "tiles": [...], "tileCount": N, "totalBytes": N}`
  ///
  /// A row may spell the tile as `tile`, `name` or `file` (with or without the
  /// `.rd5` suffix) and its size as `bytes` or `size`. Rows whose tile name is
  /// not a BRouter tile are rejected.
  ///
  /// Throws [FormatException] on anything else.
  factory SegmentsManifest.parse(Object? json) {
    final decoded = json is String ? jsonDecode(json) : json;
    if (decoded is List) {
      return SegmentsManifest(tiles: _entries(decoded, null));
    }
    if (decoded is! Map) {
      throw const FormatException(
        'a segments manifest is a JSON array or object',
      );
    }
    final rows = decoded['tiles'] ?? decoded['segments'];
    if (rows is! List) {
      throw const FormatException('manifest has no "tiles" array');
    }
    final formatVersion = _string(decoded['formatVersion']);
    return SegmentsManifest(
      tiles: _entries(rows, formatVersion),
      formatVersion: formatVersion,
      brouterVersion: _string(decoded['brouterVersion']),
      source: _string(decoded['source']),
      generatedAt: _dateTime(decoded['generatedAt']),
    );
  }

  /// Parses an nginx/Apache directory index of `.rd5` files.
  ///
  /// This is the brouter.de fallback for when our own mirror is unreachable.
  /// One row looks like
  ///
  /// ```html
  /// <a href="E5_N45.rd5">E5_N45.rd5</a>   12-Sep-2026 01:03   12134767
  /// ```
  ///
  /// The date is taken as written (brouter.de states CET, but nothing in the
  /// page says so, so it is parsed as UTC and only ever used for "is my copy
  /// older than the mirror's"); a human-readable size (`11M`) is expanded, and
  /// a missing or unparsable size becomes `0`. Links that are not tile names
  /// (`../`, checksum files) are skipped, so a listing with no tile at all
  /// yields an empty manifest rather than an error.
  factory SegmentsManifest.parseDirectoryListing(String html) {
    final out = <SegmentEntry>[];
    final seen = <TileName>{};
    for (final m in _linkPattern.allMatches(html)) {
      final tile = TileName.tryParse(m.group(1)!);
      if (tile == null || !seen.add(tile)) continue;
      final (date, bytes) = _listingMeta(m.group(2) ?? '');
      out.add(SegmentEntry(tile: tile, bytes: bytes, updatedAt: date));
    }
    return SegmentsManifest(tiles: out);
  }

  @override
  String toString() =>
      'SegmentsManifest(${tiles.length} tiles, $totalBytes B, '
      'format $formatVersion)';

  // `<a href="E5_N45.rd5">E5_N45.rd5</a>  12-Sep-2026 01:03  12134767`
  // group 1 is the file name, group 2 the rest of the line (date and size).
  static final RegExp _linkPattern = RegExp(
    r'''<a\s+[^>]*href\s*=\s*["']([^"'/?#]+\.rd5)["'][^>]*>.*?</a>([^<\r\n]*)''',
    caseSensitive: false,
    dotAll: false,
  );

  static final RegExp _listingDatePattern = RegExp(
    r'(\d{1,2})-([A-Za-z]{3})-(\d{4})\s+(\d{2}):(\d{2})(?::(\d{2}))?',
  );

  static final RegExp _isoDatePattern = RegExp(
    r'(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})(?::(\d{2}))?',
  );

  static final RegExp _sizePattern = RegExp(
    r'(\d+(?:\.\d+)?)\s*([KMGT])?(?:i?B)?\s*$',
    caseSensitive: false,
  );

  static const List<String> _months = <String>[
    'jan',
    'feb',
    'mar',
    'apr',
    'may',
    'jun',
    'jul',
    'aug',
    'sep',
    'oct',
    'nov',
    'dec',
  ];

  static List<SegmentEntry> _entries(List<Object?> rows, String? fallback) {
    final out = <SegmentEntry>[];
    for (final row in rows) {
      if (row is! Map) {
        throw FormatException('manifest row is not an object: $row');
      }
      final rawName =
          _string(row['tile']) ?? _string(row['name']) ?? _string(row['file']);
      if (rawName == null) {
        throw FormatException('manifest row has no tile name: $row');
      }
      final tile = TileName.tryParse(rawName);
      if (tile == null) {
        throw FormatException('not a BRouter tile name: $rawName');
      }
      out.add(
        SegmentEntry(
          tile: tile,
          bytes: _int(row['bytes'] ?? row['size']) ?? 0,
          updatedAt: _dateTime(row['updatedAt'] ?? row['updated_at']),
          formatVersion: _string(row['formatVersion']) ?? fallback,
          sha256: _string(row['sha256']),
        ),
      );
    }
    return out;
  }

  /// Pulls the date and the size out of the text behind an index link.
  ///
  /// The size is only looked for *after* the date, so that the minutes of
  /// `01:03` in a row without a size cannot be read as a byte count.
  static (DateTime?, int) _listingMeta(String tail) {
    final iso = _isoDatePattern.firstMatch(tail);
    final named = iso == null ? _listingDatePattern.firstMatch(tail) : null;
    final end = iso?.end ?? named?.end ?? 0;
    return (_listingDate(iso, named), _listingSize(tail.substring(end)));
  }

  static int _listingSize(String rest) {
    final m = _sizePattern.firstMatch(rest.trimRight());
    if (m == null) return 0;
    final value = double.parse(m.group(1)!);
    final unit = m.group(2)?.toUpperCase();
    final factor = switch (unit) {
      'K' => 1024,
      'M' => 1024 * 1024,
      'G' => 1024 * 1024 * 1024,
      'T' => 1024 * 1024 * 1024 * 1024,
      _ => 1,
    };
    return (value * factor).round();
  }

  static DateTime? _listingDate(RegExpMatch? iso, RegExpMatch? named) {
    if (iso != null) {
      return DateTime.utc(
        int.parse(iso.group(1)!),
        int.parse(iso.group(2)!),
        int.parse(iso.group(3)!),
        int.parse(iso.group(4)!),
        int.parse(iso.group(5)!),
        int.parse(iso.group(6) ?? '0'),
      );
    }
    final m = named;
    if (m == null) return null;
    final month = _months.indexOf(m.group(2)!.toLowerCase());
    if (month < 0) return null;
    return DateTime.utc(
      int.parse(m.group(3)!),
      month + 1,
      int.parse(m.group(1)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
      int.parse(m.group(6) ?? '0'),
    );
  }

  static String? _string(Object? v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static int? _int(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.round();
    return int.tryParse(v.toString().trim());
  }

  static DateTime? _dateTime(Object? v) {
    final s = _string(v);
    if (s == null) return null;
    return DateTime.tryParse(s)?.toUtc();
  }
}
