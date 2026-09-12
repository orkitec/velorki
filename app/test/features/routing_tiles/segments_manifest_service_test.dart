import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/routing_tiles/data/segments_manifest_service.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

import 'support/fake_segments.dart';

const String _listing = '''
<html><head><title>Index of /brouter/segments4</title></head><body>
<h1>Index of /brouter/segments4</h1><pre>
<a href="../">../</a>
<a href="E5_N45.rd5">E5_N45.rd5</a>                  12-Sep-2026 01:03   202.6M
<a href="E10_N45.rd5">E10_N45.rd5</a>                11-Sep-2026 23:47   198.1M
<a href="lookups.dat">lookups.dat</a>                11-Sep-2026 23:47    30.8K
</pre></body></html>
''';

final Map<String, Object?> _manifest = <String, Object?>{
  'formatVersion': '11.2',
  'brouterVersion': 'v1.7.10',
  'generatedAt': '2026-09-12T01:03:00Z',
  'tiles': <Object?>[
    <String, Object?>{
      'tile': 'E10_N45',
      'bytes': 131072000,
      'updatedAt': '2026-09-12T01:03:00Z',
      'sha256': 'ab' * 32,
    },
    <String, Object?>{
      'tile': 'E5_N45',
      'bytes': 212408832,
      'updatedAt': '2026-09-11T23:47:00Z',
    },
  ],
};

void main() {
  group('with a mirror configured', () {
    test('reads manifest.json', () async {
      final adapter = FakeSegmentsAdapter(
        (_) => FakeSegmentsResponse.json(_manifest),
      );
      final service = SegmentsManifestService(
        dio: segmentsDioWith(adapter),
        segmentsUrl: 'https://mirror.test/segments4/',
      );

      final manifest = await service.fetch();

      expect(service.isFallback, isFalse);
      expect(
        adapter.requests.single.uri.toString(),
        'https://mirror.test/segments4/manifest.json',
      );
      expect(manifest.formatVersion, '11.2');
      expect(manifest.tiles, hasLength(2));
      expect(manifest[const TileName(10, 45)]!.bytes, 131072000);
      expect(manifest[const TileName(10, 45)]!.formatVersion, '11.2');
      expect(manifest[const TileName(10, 45)]!.sha256, 'ab' * 32);
      expect(
        service.tileUrl(const TileName(10, 45)).toString(),
        'https://mirror.test/segments4/E10_N45.rd5',
      );
    });

    test(
      'a mirror that cannot be reached is reported, not swallowed',
      () async {
        final adapter = FakeSegmentsAdapter(
          (options) => FakeSegmentsResponse.failure(
            DioException.connectionError(
              requestOptions: options,
              reason: 'no route to host',
            ),
          ),
        );
        final service = SegmentsManifestService(
          dio: segmentsDioWith(adapter),
          segmentsUrl: 'https://mirror.test/segments4',
        );

        await expectLater(
          service.fetch(),
          throwsA(isA<SegmentsManifestException>()),
        );
      },
    );

    test('a manifest that is not a manifest is reported', () async {
      final adapter = FakeSegmentsAdapter(
        (_) => FakeSegmentsResponse.json(<String, Object?>{'tiles': 'nope'}),
      );
      final service = SegmentsManifestService(
        dio: segmentsDioWith(adapter),
        segmentsUrl: 'https://mirror.test/segments4',
      );

      await expectLater(
        service.fetch(),
        throwsA(isA<SegmentsManifestException>()),
      );
    });
  });

  group('without a mirror configured', () {
    test('falls back to the brouter.de directory listing', () async {
      final adapter = FakeSegmentsAdapter(
        (_) => FakeSegmentsResponse.text(_listing),
      );
      final service = SegmentsManifestService(
        dio: segmentsDioWith(adapter),
        segmentsUrl: '   ',
      );

      final manifest = await service.fetch();

      expect(service.isFallback, isTrue);
      expect(service.baseUrl, brouterDeSegmentsUrl);
      expect(adapter.requests.single.uri.toString(), '$brouterDeSegmentsUrl/');
      expect(manifest.tiles.map((e) => e.tile.name), <String>[
        'E5_N45',
        'E10_N45',
      ]);
      expect(
        manifest[const TileName(5, 45)]!.updatedAt,
        DateTime.utc(2026, 9, 12, 1, 3),
      );
      expect(manifest[const TileName(5, 45)]!.bytes, greaterThan(200000000));
      expect(
        service.tileUrl(const TileName(5, 45)).toString(),
        '$brouterDeSegmentsUrl/E5_N45.rd5',
      );
    });
  });
}
