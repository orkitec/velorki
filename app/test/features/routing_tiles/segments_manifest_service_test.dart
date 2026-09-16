import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/features/routing_tiles/data/routing_tiles_repository.dart';
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

  group('what a mirror failure says', () {
    test(
      'an unreachable mirror is named, and the cause kept for the log',
      () async {
        final service = SegmentsManifestService(
          dio: segmentsDioWith(
            FakeSegmentsAdapter(
              (options) => FakeSegmentsResponse.failure(
                DioException.connectionError(
                  requestOptions: options,
                  reason: 'no route to host',
                ),
              ),
            ),
          ),
          segmentsUrl: 'https://mirror.test/segments4',
        );

        await expectLater(
          service.fetch(),
          throwsA(
            isA<SegmentsManifestException>()
                .having(
                  (e) => e.message,
                  'message',
                  contains('https://mirror.test/segments4'),
                )
                .having((e) => e.cause, 'cause', isA<DioException>()),
          ),
        );
      },
    );

    test('an unreadable manifest names the file it could not read', () async {
      final service = SegmentsManifestService(
        dio: segmentsDioWith(
          FakeSegmentsAdapter((_) => FakeSegmentsResponse.json('nope')),
        ),
        segmentsUrl: 'https://mirror.test/segments4',
      );

      await expectLater(
        service.fetch(),
        throwsA(
          isA<SegmentsManifestException>()
              .having((e) => e.message, 'message', contains('manifest.json'))
              .having((e) => e.cause, 'cause', isNotNull),
        ),
      );
    });

    test('the failure reads as one sentence', () {
      const failure = SegmentsManifestException('The mirror is down.');

      expect(
        failure.toString(),
        'SegmentsManifestException: The mirror is down.',
      );
      expect(failure.cause, isNull);
    });
  });

  group('a manifest that is only half there', () {
    Future<SegmentsManifest> fetch(Object? body) => SegmentsManifestService(
      dio: segmentsDioWith(
        FakeSegmentsAdapter((_) => FakeSegmentsResponse.json(body)),
      ),
      segmentsUrl: 'https://mirror.test/segments4',
    ).fetch();

    test('a row with nothing but a name is a tile of unknown size', () async {
      final manifest = await fetch(<String, Object?>{
        'tiles': <Object?>[
          <String, Object?>{'tile': 'E10_N45'},
        ],
      });

      final entry = manifest[const TileName(10, 45)]!;
      expect(entry.bytes, 0);
      expect(entry.updatedAt, isNull);
      expect(entry.sha256, isNull);
      expect(entry.formatVersion, isNull);
    });

    test(
      'the format version of the mirror is copied onto every tile',
      () async {
        final manifest = await fetch(<String, Object?>{
          'formatVersion': '11.2',
          'brouterVersion': 'v1.7.10',
          'generatedAt': '2026-09-12T01:03:00Z',
          'tiles': <Object?>[
            <String, Object?>{'tile': 'E10_N45', 'bytes': 1},
            <String, Object?>{
              'tile': 'E5_N45',
              'bytes': 2,
              'formatVersion': '11.1',
            },
          ],
        });

        expect(manifest.formatVersion, '11.2');
        expect(manifest.brouterVersion, 'v1.7.10');
        expect(manifest.generatedAt, DateTime.utc(2026, 9, 12, 1, 3));
        expect(manifest[const TileName(10, 45)]!.formatVersion, '11.2');
        expect(manifest[const TileName(5, 45)]!.formatVersion, '11.1');
      },
    );

    test('a bare array of tiles is a manifest too', () async {
      final manifest = await fetch(<Object?>[
        <String, Object?>{'tile': 'E10_N45', 'bytes': 7},
      ]);

      expect(manifest.formatVersion, isNull);
      expect(manifest.tiles, hasLength(1));
      expect(manifest[const TileName(10, 45)]!.bytes, 7);
    });

    test('a row may name its file and its size the other way round', () async {
      final manifest = await fetch(<String, Object?>{
        'tiles': <Object?>[
          <String, Object?>{
            'file': 'E10_N45.rd5',
            'size': 131072000,
            'updated_at': '2026-09-12T01:03:00Z',
          },
        ],
      });

      final entry = manifest[const TileName(10, 45)]!;
      expect(entry.bytes, 131072000);
      expect(entry.updatedAt, DateTime.utc(2026, 9, 12, 1, 3));
    });

    test('a row that is not an object is refused', () async {
      await expectLater(
        fetch(<String, Object?>{
          'tiles': <Object?>['E10_N45'],
        }),
        throwsA(isA<SegmentsManifestException>()),
      );
    });

    test('a row naming something that is not a tile is refused', () async {
      await expectLater(
        fetch(<String, Object?>{
          'tiles': <Object?>[
            <String, Object?>{'tile': 'lookups.dat'},
          ],
        }),
        throwsA(isA<SegmentsManifestException>()),
      );
    });

    test('a row without any name at all is refused', () async {
      await expectLater(
        fetch(<String, Object?>{
          'tiles': <Object?>[
            <String, Object?>{'bytes': 12},
          ],
        }),
        throwsA(isA<SegmentsManifestException>()),
      );
    });

    test('a document with no tiles array is refused', () async {
      await expectLater(
        fetch(<String, Object?>{'formatVersion': '11.2'}),
        throwsA(isA<SegmentsManifestException>()),
      );
    });

    test('an empty tiles array is a mirror with nothing on it', () async {
      final manifest = await fetch(<String, Object?>{'tiles': <Object?>[]});

      expect(manifest.tiles, isEmpty);
      expect(manifest.totalBytes, 0);
      expect(manifest[const TileName(10, 45)], isNull);
    });
  });

  group('a directory listing that is not what it should be', () {
    Future<SegmentsManifest> fetch(FakeSegmentsResponse response) =>
        SegmentsManifestService(
          dio: segmentsDioWith(FakeSegmentsAdapter((_) => response)),
          segmentsUrl: '',
        ).fetch();

    test(
      'a listing that cannot be reached is reported, not swallowed',
      () async {
        final service = SegmentsManifestService(
          dio: segmentsDioWith(
            FakeSegmentsAdapter(
              (options) => FakeSegmentsResponse.failure(
                DioException.receiveTimeout(
                  timeout: const Duration(seconds: 1),
                  requestOptions: options,
                ),
              ),
            ),
          ),
          segmentsUrl: '',
        );

        await expectLater(
          service.fetch(),
          throwsA(
            isA<SegmentsManifestException>()
                .having(
                  (e) => e.message,
                  'message',
                  contains(brouterDeSegmentsUrl),
                )
                .having((e) => e.cause, 'cause', isA<DioException>()),
          ),
        );
      },
    );

    test('an empty page is no tiles rather than an error', () async {
      final manifest = await fetch(FakeSegmentsResponse.text(''));

      expect(manifest.tiles, isEmpty);
    });

    test(
      'a page without a single rd5 link offers nothing to download',
      () async {
        final manifest = await fetch(
          FakeSegmentsResponse.text(
            '<html><body><a href="lookups.dat">lookups.dat</a>'
            '<a href="../">../</a></body></html>',
          ),
        );

        expect(manifest.tiles, isEmpty);
      },
    );

    test('the same tile listed twice is downloaded once', () async {
      final manifest = await fetch(
        FakeSegmentsResponse.text(
          '<a href="E10_N45.rd5">E10_N45.rd5</a> 12-Sep-2026 01:03 11M\n'
          '<a href="E10_N45.rd5">E10_N45.rd5</a> 11-Sep-2026 01:03 11M\n',
        ),
      );

      expect(manifest.tiles, hasLength(1));
      expect(
        manifest[const TileName(10, 45)]!.updatedAt,
        DateTime.utc(2026, 9, 12, 1, 3),
      );
    });

    test('a row without a size is still a tile, of unknown size', () async {
      final manifest = await fetch(
        FakeSegmentsResponse.text(
          '<a href="E10_N45.rd5">E10_N45.rd5</a> 12-Sep-2026 01:03\n',
        ),
      );

      expect(manifest[const TileName(10, 45)]!.bytes, 0);
    });

    test('an answer that is not a listing at all offers no tiles', () async {
      final manifest = await fetch(
        FakeSegmentsResponse.json(<String, Object?>{'tiles': <Object?>[]}),
      );

      expect(manifest.tiles, isEmpty);
    });
  });

  group('where the tiles are fetched from', () {
    SegmentsManifestService serviceFor(String url) => SegmentsManifestService(
      dio: segmentsDioWith(
        FakeSegmentsAdapter((_) => FakeSegmentsResponse.text('')),
      ),
      segmentsUrl: url,
    );

    test('a mirror URL is used without its trailing slash', () {
      expect(
        serviceFor('https://mirror.test/segments4/').baseUrl,
        'https://mirror.test/segments4',
      );
      expect(
        serviceFor('https://mirror.test/segments4').baseUrl,
        'https://mirror.test/segments4',
      );
    });

    test('whitespace around a mirror URL is not part of it', () {
      expect(
        serviceFor('  https://mirror.test/segments4  ').baseUrl,
        'https://mirror.test/segments4',
      );
      expect(
        serviceFor('  https://mirror.test/segments4  ').isFallback,
        isFalse,
      );
    });

    test('no mirror at all is the brouter.de fallback', () {
      expect(serviceFor('').isFallback, isTrue);
      expect(serviceFor('\t\n ').isFallback, isTrue);
      expect(serviceFor('').baseUrl, brouterDeSegmentsUrl);
    });

    test('every tile has its own file under the mirror', () {
      final service = serviceFor('https://mirror.test/segments4/');

      expect(
        service.tileUrl(const TileName(-5, -10)).toString(),
        'https://mirror.test/segments4/W5_S10.rd5',
      );
      expect(
        service.tileUrl(const TileName(0, 0)).toString(),
        'https://mirror.test/segments4/E0_N0.rd5',
      );
    });
  });

  group('the mirror of a build', () {
    test('the configured segments URL is the one that is used', () {
      final container = ProviderContainer(
        overrides: [
          effectiveConfigProvider.overrideWithValue(
            const AppConfig(segmentsUrl: 'https://mirror.test/segments4/'),
          ),
        ],
      );
      addTearDown(container.dispose);

      final service = container.read(segmentsManifestServiceProvider);

      expect(service.isFallback, isFalse);
      expect(service.baseUrl, 'https://mirror.test/segments4');
    });

    test('a build without a segments URL falls back to brouter.de', () {
      final container = ProviderContainer(
        overrides: [
          effectiveConfigProvider.overrideWithValue(const AppConfig()),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(segmentsManifestServiceProvider).isFallback,
        isTrue,
      );
    });

    test('the tile download waits far longer than an API call would', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final dio = container.read(segmentsDioProvider);

      expect(dio.options.connectTimeout, const Duration(seconds: 20));
      expect(dio.options.receiveTimeout, const Duration(minutes: 2));
      expect(dio.options.responseType, ResponseType.json);
      expect(dio.options.headers['User-Agent'], contains('Velorki'));
    });
  });

  group('keeping the downloaded tiles in step with the mirror', () {
    late VelorkiDatabase db;
    late RoutingTilesRepository repository;
    late Directory segments;

    setUp(() async {
      db = VelorkiDatabase.memory();
      final root = tempDir('velorki-manifest');
      segments = Directory('${root.path}/segments')
        ..createSync(recursive: true);
      repository = RoutingTilesRepository(
        dao: db.routingTilesDao,
        segmentsDir: segments,
        gazetteerDir: Directory('${root.path}/gazetteer')
          ..createSync(recursive: true),
      );
      await repository.load();
      addTearDown(() async {
        await repository.dispose();
        await db.close();
      });
    });

    /// A ready tile on disk, built by the mirror on [updatedAt].
    Future<void> haveTile(TileName tile, DateTime updatedAt) async {
      File('${segments.path}/${tile.fileName}').writeAsStringSync('rd5');
      await repository.markReady(
        SegmentEntry(
          tile: tile,
          bytes: 3,
          updatedAt: updatedAt,
          formatVersion: '11.2',
        ),
        bytes: 3,
      );
    }

    ProviderContainer containerFor(SegmentsManifestService service) {
      final container = ProviderContainer(
        overrides: [
          segmentsManifestServiceProvider.overrideWithValue(service),
          routingTilesRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('a tile the mirror has rebuilt is marked stale when the manifest '
        'arrives', () async {
      await haveTile(const TileName(10, 45), DateTime.utc(2026, 9, 1));
      final container = containerFor(
        SegmentsManifestService(
          dio: segmentsDioWith(
            FakeSegmentsAdapter(
              (_) => FakeSegmentsResponse.json(<String, Object?>{
                'formatVersion': '11.2',
                'tiles': <Object?>[
                  <String, Object?>{
                    'tile': 'E10_N45',
                    'bytes': 4,
                    'updatedAt': '2026-09-12T01:03:00Z',
                  },
                ],
              }),
            ),
          ),
          segmentsUrl: 'https://mirror.test/segments4',
        ),
      );

      final manifest = await container.read(
        segmentsManifestSourceProvider.future,
      );

      expect(manifest.tiles, hasLength(1));
      expect(repository.cached.single.isStale, isTrue);
      expect(repository.cached.single.isUsable, isTrue);
    });

    test('a tile the mirror has not touched stays ready', () async {
      await haveTile(const TileName(10, 45), DateTime.utc(2026, 9, 12, 1, 3));
      final container = containerFor(
        SegmentsManifestService(
          dio: segmentsDioWith(
            FakeSegmentsAdapter(
              (_) => FakeSegmentsResponse.json(<String, Object?>{
                'tiles': <Object?>[
                  <String, Object?>{
                    'tile': 'E10_N45',
                    'bytes': 3,
                    'updatedAt': '2026-09-12T01:03:00Z',
                  },
                ],
              }),
            ),
          ),
          segmentsUrl: 'https://mirror.test/segments4',
        ),
      );

      await container.read(segmentsManifestSourceProvider.future);

      expect(repository.cached.single.isStale, isFalse);
      expect(repository.cached.single.isUsable, isTrue);
    });

    test('checking for updates asks the mirror again', () async {
      await haveTile(const TileName(10, 45), DateTime.utc(2026, 9, 1));
      var built = 0;
      final adapter = FakeSegmentsAdapter((_) {
        built++;
        return FakeSegmentsResponse.json(<String, Object?>{
          'tiles': <Object?>[
            <String, Object?>{
              'tile': 'E10_N45',
              'bytes': 3,
              'updatedAt': built == 1
                  ? '2026-09-01T00:00:00Z'
                  : '2026-09-12T01:03:00Z',
            },
          ],
        });
      });
      final container = containerFor(
        SegmentsManifestService(
          dio: segmentsDioWith(adapter),
          segmentsUrl: 'https://mirror.test/segments4',
        ),
      );

      await container.read(segmentsManifestSourceProvider.future);
      expect(repository.cached.single.isStale, isFalse);

      await container.read(segmentsManifestSourceProvider.notifier).refresh();

      expect(built, 2);
      expect(adapter.requests, hasLength(2));
      expect(repository.cached.single.isStale, isTrue);
    });

    test(
      'a mirror that is down leaves the source without a manifest',
      () async {
        final container = containerFor(
          SegmentsManifestService(
            dio: segmentsDioWith(
              FakeSegmentsAdapter(
                (options) => FakeSegmentsResponse.failure(
                  DioException.connectionError(
                    requestOptions: options,
                    reason: 'no route to host',
                  ),
                ),
              ),
            ),
            segmentsUrl: 'https://mirror.test/segments4',
          ),
        );

        final sub = container.listen(
          segmentsManifestSourceProvider,
          (_, _) {},
          onError: (_, _) {},
        );
        addTearDown(sub.close);
        await pumpEventQueue();

        final state = container.read(segmentsManifestSourceProvider);
        expect(state.hasValue, isFalse);
        expect(state.error, isA<SegmentsManifestException>());
        expect(repository.cached, isEmpty);
      },
    );
  });

  group('with a pointer configured', () {
    test('follows latest.json to the snapshot it names', () async {
      final adapter = FakeSegmentsAdapter((options) {
        if (options.uri.path.endsWith('latest.json')) {
          return FakeSegmentsResponse.json(<String, Object?>{
            'tag': 'tiles-20260913',
            'formatVersion': '11.2',
            'baseUrl': 'https://mirror.test/releases/tiles-20260913/',
            'shards': <Object?>[
              <String, Object?>{
                'tag': 'tiles-20260913',
                'baseUrl': 'https://mirror.test/releases/tiles-20260913/',
              },
            ],
          });
        }
        return FakeSegmentsResponse.json(_manifest);
      });
      final service = SegmentsManifestService(
        dio: segmentsDioWith(adapter),
        segmentsUrl: 'https://mirror.test/main/latest.json',
      );

      final manifest = await service.fetch();

      expect(service.isPointer, isTrue);
      expect(manifest.tiles, hasLength(2));
      expect(adapter.requests.map((r) => r.uri.toString()), <String>[
        'https://mirror.test/main/latest.json',
        'https://mirror.test/releases/tiles-20260913/manifest.json',
      ]);
      expect(
        service.tileUrl(const TileName(10, 45)).toString(),
        'https://mirror.test/releases/tiles-20260913/E10_N45.rd5',
      );
    });

    test('a pointer served as plain text is read all the same', () async {
      final adapter = FakeSegmentsAdapter((options) {
        if (options.uri.path.endsWith('latest.json')) {
          return FakeSegmentsResponse.text(
            '{"tag":"tiles-20260913",'
            '"baseUrl":"https://mirror.test/releases/tiles-20260913/"}',
          );
        }
        return FakeSegmentsResponse.json(_manifest);
      });
      final service = SegmentsManifestService(
        dio: segmentsDioWith(adapter),
        segmentsUrl: 'https://mirror.test/main/latest.json',
      );

      final manifest = await service.fetch();

      expect(manifest.tiles, hasLength(2));
      expect(
        service.tileUrl(const TileName(10, 45)).toString(),
        'https://mirror.test/releases/tiles-20260913/E10_N45.rd5',
      );
    });

    test('a pointer that names no snapshot is reported', () async {
      final adapter = FakeSegmentsAdapter(
        (_) => FakeSegmentsResponse.json(<String, Object?>{'tag': 'x'}),
      );
      final service = SegmentsManifestService(
        dio: segmentsDioWith(adapter),
        segmentsUrl: 'https://mirror.test/main/latest.json',
      );

      await expectLater(
        service.fetch(),
        throwsA(isA<SegmentsManifestException>()),
      );
    });
  });
}
