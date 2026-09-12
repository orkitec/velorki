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

SegmentEntry _entry({int? bytes, String? sha256}) => SegmentEntry(
  tile: _tile,
  bytes: bytes ?? _body.length,
  updatedAt: DateTime.utc(2026, 9, 1),
  formatVersion: '11.2',
  sha256: sha256,
);

void main() {
  late Directory segments;

  TileDownloader downloader(FakeSegmentsAdapter adapter) {
    final d = TileDownloader(
      dio: segmentsDioWith(adapter),
      segmentsDir: segments,
      urlFor: (tile) => Uri.parse('https://mirror.test/${tile.fileName}'),
    );
    addTearDown(d.dispose);
    return d;
  }

  File partFile() => File('${segments.path}/${_tile.fileName}.part');

  setUp(() {
    segments = Directory('${tempDir('velorki-download').path}/segments');
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
}
