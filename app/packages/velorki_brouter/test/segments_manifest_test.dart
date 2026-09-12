import 'dart:io';

import 'package:test/test.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

void main() {
  group('manifest.json as the updater writes it', () {
    late SegmentsManifest manifest;

    setUpAll(() {
      manifest = SegmentsManifest.parse(fixture('segments_manifest.json'));
    });

    test('reads the header', () {
      expect(manifest.formatVersion, '11.2');
      expect(manifest.brouterVersion, 'v1.7.10');
      expect(manifest.source, 'https://brouter.de/brouter/segments4/');
      expect(manifest.generatedAt, DateTime.utc(2026, 9, 12, 2, 17, 5));
    });

    test('reads the tiles in order', () {
      expect(manifest.tiles.map((e) => e.tile.name), [
        'E5_N45',
        'E10_N45',
        'W20_N30',
      ]);
      final madeira = manifest[const TileName(-20, 30)]!;
      expect(madeira.bytes, 1499136);
      expect(madeira.updatedAt, DateTime.utc(2026, 9, 5, 23, 48));
      expect(madeira.fileName, 'W20_N30.rd5');
    });

    test('the manifest format version lands on every entry', () {
      expect(
        manifest.tiles.every((e) => e.formatVersion == '11.2'),
        isTrue,
        reason: 'the app stores the version per tile in routing_tiles',
      );
    });

    test('totals and lookups', () {
      expect(manifest.totalBytes, 390068736);
      expect(manifest.tileSet, {
        const TileName(5, 45),
        const TileName(10, 45),
        const TileName(-20, 30),
      });
      expect(
        manifest.bytesFor([const TileName(5, 45), const TileName(-20, 30)]),
        212408832 + 1499136,
      );
      expect(
        manifest.bytesFor([const TileName(0, 0)]),
        0,
        reason: 'a tile the mirror does not have counts as zero',
      );
      expect(manifest[const TileName(0, 0)], isNull);
    });

    test('parses an already decoded structure too', () {
      expect(
        SegmentsManifest.parse(<String, Object?>{
          'tiles': [
            {'tile': 'E5_N45', 'bytes': 1},
          ],
        }).tiles.single.tile,
        const TileName(5, 45),
      );
    });
  });

  group('the bare array shape', () {
    test('parses without a header', () {
      final m = SegmentsManifest.parse(
        '[{"tile": "E5_N45", "bytes": 212408832, '
        '"updatedAt": "2026-09-12T01:03:00Z"}, '
        '{"tile": "W20_N30", "bytes": 1499136, '
        '"updatedAt": "2026-09-05T23:48:00Z"}]',
      );
      expect(m.formatVersion, isNull);
      expect(m.tiles, hasLength(2));
      expect(m.totalBytes, 213907968);
      expect(m.tiles.first.formatVersion, isNull);
    });

    test('accepts the alternative spellings and a sha256', () {
      final m = SegmentsManifest.parse(
        '[{"name": "E5_N45.rd5", "size": "17", "updated_at": '
        '"2026-09-12T01:03:00Z", "sha256": "abc", "formatVersion": "11.2"}]',
      );
      final e = m.tiles.single;
      expect(e.tile, const TileName(5, 45));
      expect(e.bytes, 17);
      expect(e.sha256, 'abc');
      expect(e.formatVersion, '11.2');
    });

    test('a missing size is zero, a missing date is null', () {
      final e = SegmentsManifest.parse('[{"tile": "E5_N45"}]').tiles.single;
      expect(e.bytes, 0);
      expect(e.updatedAt, isNull);
    });

    test('rejects garbage', () {
      expect(() => SegmentsManifest.parse('7'), throwsFormatException);
      expect(() => SegmentsManifest.parse('{}'), throwsFormatException);
      expect(() => SegmentsManifest.parse('[7]'), throwsFormatException);
      expect(() => SegmentsManifest.parse('[{}]'), throwsFormatException);
      expect(
        () => SegmentsManifest.parse('[{"tile": "Atlantis"}]'),
        throwsFormatException,
      );
    });

    test('entries compare by value', () {
      const a = SegmentEntry(tile: TileName(5, 45), bytes: 1);
      const b = SegmentEntry(tile: TileName(5, 45), bytes: 1);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(const SegmentEntry(tile: TileName(5, 45), bytes: 2)));
      expect(SegmentsManifest.empty.tiles, isEmpty);
      expect(SegmentsManifest.empty.totalBytes, 0);
    });
  });

  group('the brouter.de directory listing fallback', () {
    late SegmentsManifest manifest;

    setUpAll(() {
      manifest = SegmentsManifest.parseDirectoryListing(
        fixture('segments_index.html'),
      );
    });

    test('picks up every rd5 row and nothing else', () {
      expect(manifest.tiles.map((e) => e.tile.name), [
        'E5_N45',
        'E10_N45',
        'W20_N30',
        'W25_N60',
      ]);
    });

    test('reads the size and date columns', () {
      final e = manifest[const TileName(5, 45)]!;
      expect(e.bytes, 212408832);
      expect(e.updatedAt, DateTime.utc(2026, 9, 12, 1, 3));
      expect(manifest[const TileName(-25, 60)]!.bytes, 2764800);
      expect(manifest.totalBytes, 212408832 + 176160768 + 1499136 + 2764800);
    });

    test('the listing agrees with our own manifest', () {
      final mirror = SegmentsManifest.parse(fixture('segments_manifest.json'));
      for (final e in mirror.tiles) {
        expect(manifest[e.tile]!.bytes, e.bytes, reason: e.tile.name);
        expect(manifest[e.tile]!.updatedAt, e.updatedAt, reason: e.tile.name);
      }
    });

    test('human readable sizes are expanded', () {
      final m = SegmentsManifest.parseDirectoryListing(
        '<a href="E5_N45.rd5">E5_N45.rd5</a> 12-Sep-2026 01:03  203M\n'
        '<a href="E10_N45.rd5">E10_N45.rd5</a> 12-Sep-2026 01:03 1.5G\n',
      );
      expect(m.tiles[0].bytes, 203 * 1024 * 1024);
      expect(m.tiles[1].bytes, (1.5 * 1024 * 1024 * 1024).round());
    });

    test('a row without a size does not read the clock as bytes', () {
      final m = SegmentsManifest.parseDirectoryListing(
        '<a href="E5_N45.rd5">E5_N45.rd5</a>   12-Sep-2026 01:03    -\n',
      );
      expect(m.tiles.single.bytes, 0);
      expect(m.tiles.single.updatedAt, DateTime.utc(2026, 9, 12, 1, 3));
    });

    test('an ISO date column is understood as well', () {
      final m = SegmentsManifest.parseDirectoryListing(
        "<a href='W20_N30.rd5'>W20_N30.rd5</a> 2026-09-05 23:48:12 1499136\n",
      );
      expect(m.tiles.single.updatedAt, DateTime.utc(2026, 9, 5, 23, 48, 12));
      expect(m.tiles.single.bytes, 1499136);
    });

    test('a page with no tiles is an empty manifest, not an error', () {
      expect(
        SegmentsManifest.parseDirectoryListing('<html>nothing here</html>')
            .tiles,
        isEmpty,
      );
    });

    test('a tile listed twice is taken once', () {
      final m = SegmentsManifest.parseDirectoryListing(
        '<a href="E5_N45.rd5">E5_N45.rd5</a> 12-Sep-2026 01:03 10\n'
        '<a href="E5_N45.rd5">mirror</a> 12-Sep-2026 01:03 10\n',
      );
      expect(m.tiles, hasLength(1));
    });
  });
}
