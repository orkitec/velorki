import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/routing_tiles/data/tile_downloader.dart';
import 'package:velorki/features/routing_tiles/domain/sha256.dart';
import 'package:velorki_brouter/velorki_brouter.dart' hide CancelToken;

import 'support/fake_segments.dart';

const TileName _tile = TileName(10, 45);
final Uint8List _body = Uint8List.fromList(
  utf8.encode(List<String>.generate(64, (i) => 'rd5-block-$i;').join()),
);

final Uint8List _gaz = Uint8List.fromList(utf8.encode('SQLite format 3 ...'));

GazetteerEntry _gazEntry({int? bytes, String? sha256}) => GazetteerEntry(
  tile: _tile,
  bytes: bytes ?? _gaz.length,
  sha256: sha256 ?? (Sha256()..add(_gaz)).hexDigest(),
  updatedAt: DateTime.utc(2026, 9, 16),
);

SegmentEntry _entry({
  int? bytes,
  String? sha256,
  GazetteerEntry? gazetteer,
  String? baseUrl,
}) => SegmentEntry(
  tile: _tile,
  bytes: bytes ?? _body.length,
  updatedAt: DateTime.utc(2026, 9, 1),
  formatVersion: '11.2',
  sha256: sha256,
  gazetteer: gazetteer,
  baseUrl: baseUrl,
);

/// A tile whose mirror also offers the offline gazetteer.
SegmentEntry _withGaz({int? bytes, String? sha256, String? baseUrl}) => _entry(
  gazetteer: _gazEntry(bytes: bytes, sha256: sha256),
  baseUrl: baseUrl,
);

void main() {
  late Directory segments;
  late Directory gazetteer;

  TileDownloader downloader(FakeSegmentsAdapter adapter) {
    final d = TileDownloader(
      dio: segmentsDioWith(adapter),
      segmentsDir: segments,
      gazetteerDir: gazetteer,
      urlFor: (entry) => Uri.parse(
        '${entry.baseUrl ?? 'https://mirror.test'}/${entry.fileName}',
      ),
      gazetteerUrlFor: (entry) => Uri.parse(
        '${entry.baseUrl ?? 'https://mirror.test'}/'
        '${entry.tile.gazetteerFileName}',
      ),
    );
    addTearDown(d.dispose);
    return d;
  }

  File partFile() => File('${segments.path}/${_tile.fileName}.part');

  setUp(() {
    final root = tempDir('velorki-download');
    segments = Directory('${root.path}/segments');
    gazetteer = Directory('${root.path}/gazetteer');
  });

  test('downloads a tile and renames it into place', () async {
    final adapter = FakeSegmentsAdapter.serving(_body);
    final progress = <TileDownloadProgress>[];
    final d = downloader(adapter);
    final sub = d.progress.listen(progress.add);
    addTearDown(sub.cancel);

    final file = await d.download(_entry());

    expect(file.path, endsWith('E10_N45.rd5'));
    expect(file.readAsBytesSync(), _body);
    expect(partFile().existsSync(), isFalse);
    expect(adapter.ranges, <String?>[null]);
    expect(progress.last.received, _body.length);
    expect(progress.last.fraction, 1.0);
  });

  test('resumes from a .part with a range request', () async {
    segments.createSync(recursive: true);
    partFile().writeAsBytesSync(Uint8List.sublistView(_body, 0, 100));
    final adapter = FakeSegmentsAdapter.serving(_body);

    final file = await downloader(adapter).download(_entry());

    expect(adapter.ranges, <String?>['bytes=100-']);
    expect(file.readAsBytesSync(), _body);
  });

  test('starts over when the mirror ignores the range', () async {
    segments.createSync(recursive: true);
    partFile().writeAsBytesSync(Uint8List.sublistView(_body, 0, 100));
    final adapter = FakeSegmentsAdapter.serving(_body, supportsRange: false);

    final file = await downloader(adapter).download(_entry());

    expect(adapter.ranges, <String?>['bytes=100-']);
    expect(file.readAsBytesSync(), _body);
  });

  test('a .part longer than the tile is thrown away', () async {
    segments.createSync(recursive: true);
    partFile().writeAsBytesSync(Uint8List.fromList(<int>[..._body, 1, 2, 3]));
    final adapter = FakeSegmentsAdapter.serving(_body);

    final file = await downloader(adapter).download(_entry());

    expect(adapter.ranges, <String?>[null]);
    expect(file.readAsBytesSync(), _body);
  });

  test('a short answer is refused and the .part removed', () async {
    final adapter = FakeSegmentsAdapter.serving(
      Uint8List.sublistView(_body, 0, 40),
    );

    await expectLater(
      downloader(adapter).download(_entry()),
      throwsA(
        isA<TileDownloadException>().having(
          (e) => e.kind,
          'kind',
          TileDownloadFailure.sizeMismatch,
        ),
      ),
    );
    expect(partFile().existsSync(), isFalse);
    expect(File('${segments.path}/${_tile.fileName}').existsSync(), isFalse);
  });

  test('a wrong checksum is refused', () async {
    final adapter = FakeSegmentsAdapter.serving(_body);

    await expectLater(
      downloader(adapter).download(_entry(sha256: 'a' * 64)),
      throwsA(
        isA<TileDownloadException>().having(
          (e) => e.kind,
          'kind',
          TileDownloadFailure.checksumMismatch,
        ),
      ),
    );
    expect(partFile().existsSync(), isFalse);
  });

  test('the manifest checksum is accepted when it matches', () async {
    final adapter = FakeSegmentsAdapter.serving(_body);
    final expected = (Sha256()..add(_body)).hexDigest();

    final file = await downloader(adapter)
        .download(_entry(sha256: expected.toUpperCase()));

    expect(file.existsSync(), isTrue);
  });

  test('a cancelled download keeps what it has for the next attempt', () async {
    segments.createSync(recursive: true);
    partFile().writeAsBytesSync(Uint8List.sublistView(_body, 0, 100));
    final adapter = FakeSegmentsAdapter.serving(_body);
    final cancel = CancelToken()..cancel('by the rider');

    await expectLater(
      downloader(adapter).download(_entry(), cancelToken: cancel),
      throwsA(
        isA<TileDownloadException>().having(
          (e) => e.kind,
          'kind',
          TileDownloadFailure.cancelled,
        ),
      ),
    );
    expect(partFile().lengthSync(), 100);
  });

  test('a network failure keeps the .part too', () async {
    segments.createSync(recursive: true);
    partFile().writeAsBytesSync(Uint8List.sublistView(_body, 0, 100));
    final adapter = FakeSegmentsAdapter(
      (options) => FakeSegmentsResponse.failure(
        DioException.connectionError(
          requestOptions: options,
          reason: 'mirror down',
        ),
      ),
    );

    await expectLater(
      downloader(adapter).download(_entry()),
      throwsA(
        isA<TileDownloadException>().having(
          (e) => e.kind,
          'kind',
          TileDownloadFailure.network,
        ),
      ),
    );
    expect(partFile().lengthSync(), 100);
  });

  test('a .part that is already complete is only verified', () async {
    segments.createSync(recursive: true);
    partFile().writeAsBytesSync(_body);
    final adapter = FakeSegmentsAdapter.serving(_body);

    final file = await downloader(adapter).download(_entry());

    expect(adapter.requests, isEmpty);
    expect(file.readAsBytesSync(), _body);
  });

  group('the offline gazetteer next to a tile', () {
    /// A mirror that serves the `.gaz` and nothing else.
    FakeSegmentsAdapter servingGazetteer() => FakeSegmentsAdapter((options) {
      if (options.uri.path.endsWith('.gaz')) {
        return FakeSegmentsResponse.bytes(_gaz);
      }
      return FakeSegmentsResponse.bytes(_body);
    });

    File gazFile() => File('${gazetteer.path}/${_tile.gazetteerFileName}');

    test('lands in the gazetteer directory, not next to the tiles', () async {
      final adapter = servingGazetteer();

      final file = (await downloader(adapter).downloadGazetteer(_withGaz()))!;

      expect(file.path, gazFile().path);
      expect(file.readAsBytesSync(), _gaz);
      expect(adapter.requests.single.uri.path, endsWith('E10_N45.gaz'));
      expect(File('${gazFile().path}.part').existsSync(), isFalse);
      expect(
        File('${segments.path}/${_tile.gazetteerFileName}').existsSync(),
        isFalse,
      );
    });

    test('a wrong size is refused and nothing is left behind', () async {
      final adapter = servingGazetteer();

      await expectLater(
        downloader(adapter).downloadGazetteer(_withGaz(bytes: 99)),
        throwsA(
          isA<TileDownloadException>().having(
            (e) => e.kind,
            'kind',
            TileDownloadFailure.sizeMismatch,
          ),
        ),
      );
      expect(gazFile().existsSync(), isFalse);
      expect(File('${gazFile().path}.part').existsSync(), isFalse);
    });

    test('a wrong checksum is refused', () async {
      final adapter = servingGazetteer();

      await expectLater(
        downloader(adapter).downloadGazetteer(_withGaz(sha256: 'b' * 64)),
        throwsA(
          isA<TileDownloadException>().having(
            (e) => e.kind,
            'kind',
            TileDownloadFailure.checksumMismatch,
          ),
        ),
      );
      expect(gazFile().existsSync(), isFalse);
    });

    test('a mirror that does not have it fails the gazetteer only', () async {
      final adapter = FakeSegmentsAdapter((options) {
        if (options.uri.path.endsWith('.gaz')) {
          return FakeSegmentsResponse.text('not found', status: 404);
        }
        return FakeSegmentsResponse.bytes(_body);
      });
      final d = downloader(adapter);

      await expectLater(
        d.downloadGazetteer(_withGaz()),
        throwsA(
          isA<TileDownloadException>().having(
            (e) => e.kind,
            'kind',
            TileDownloadFailure.network,
          ),
        ),
      );
      expect((await d.download(_entry())).existsSync(), isTrue);
    });

    test('reports progress on the same stream as the tile', () async {
      final adapter = servingGazetteer();
      final d = downloader(adapter);
      final progress = <TileDownloadProgress>[];
      final sub = d.progress.listen(progress.add);
      addTearDown(sub.cancel);

      await d.downloadGazetteer(_withGaz());

      expect(progress, isNotEmpty);
      expect(
        progress.every((p) => p.tile == _tile),
        isTrue,
        reason: 'the gazetteer is the same tile, seen a second time',
      );
      expect(progress.first.received, 0);
      expect(progress.last.received, _gaz.length);
      expect(progress.last.total, _gaz.length);
      expect(progress.last.fraction, 1.0);
    });

    test('an interrupted gazetteer resumes from its .part', () async {
      gazetteer.createSync(recursive: true);
      File('${gazFile().path}.part')
          .writeAsBytesSync(Uint8List.sublistView(_gaz, 0, 5));
      final adapter = servingGazetteer();

      final file = (await downloader(adapter).downloadGazetteer(_withGaz()))!;

      expect(adapter.ranges, <String?>['bytes=5-']);
      expect(file.readAsBytesSync(), _gaz);
    });

    test('a tile the mirror has no gazetteer for downloads nothing', () async {
      final adapter = servingGazetteer();

      expect(await downloader(adapter).downloadGazetteer(_entry()), isNull);
      expect(adapter.requests, isEmpty);
    });
  });

  group('a tile that lives on another shard', () {
    const String shard = 'https://mirror.test/releases/tiles-20260913-s2';

    test('is fetched from its own shard, and so is its gazetteer', () async {
      final adapter = FakeSegmentsAdapter(
        (options) => options.uri.path.endsWith('.gaz')
            ? FakeSegmentsResponse.bytes(_gaz)
            : FakeSegmentsResponse.bytes(_body),
      );
      final d = downloader(adapter);

      final tile = await d.download(_entry(baseUrl: shard));
      final gaz = (await d.downloadGazetteer(_withGaz(baseUrl: shard)))!;

      expect(tile.readAsBytesSync(), _body);
      expect(gaz.readAsBytesSync(), _gaz);
      expect(adapter.requests.map((r) => r.uri.toString()), <String>[
        '$shard/E10_N45.rd5',
        '$shard/E10_N45.gaz',
      ]);
    });
  });
}
