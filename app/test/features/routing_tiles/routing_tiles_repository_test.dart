import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/features/routing_tiles/data/routing_tiles_repository.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

import 'support/fake_segments.dart';

const TileName _e10n45 = TileName(10, 45);
const TileName _e5n45 = TileName(5, 45);

SegmentEntry _entry(
  TileName tile, {
  int bytes = 12,
  DateTime? updatedAt,
  String formatVersion = '11.2',
  String? contentSha256,
  String? gazetteerContentSha256,
}) => SegmentEntry(
  tile: tile,
  bytes: bytes,
  updatedAt: updatedAt ?? DateTime.utc(2026, 9, 1),
  formatVersion: formatVersion,
  contentSha256: contentSha256,
  gazetteer: gazetteerContentSha256 == null
      ? null
      : GazetteerEntry(
          tile: tile,
          bytes: 3,
          sha256: 'file',
          contentSha256: gazetteerContentSha256,
        ),
);

void main() {
  late VelorkiDatabase db;
  late Directory segments;
  late Directory gazetteer;
  late RoutingTilesRepository repository;

  setUp(() async {
    db = VelorkiDatabase.memory();
    final root = tempDir('velorki-tiles');
    segments = Directory('${root.path}/segments')..createSync(recursive: true);
    gazetteer = Directory('${root.path}/gazetteer')
      ..createSync(recursive: true);
    repository = RoutingTilesRepository(
      dao: db.routingTilesDao,
      segmentsDir: segments,
      gazetteerDir: gazetteer,
    );
    await repository.load();
    addTearDown(() async {
      await repository.dispose();
      await db.close();
    });
  });

  void writeTile(TileName tile, {String content = 'rd5-bytes-here'}) =>
      File('${segments.path}/${tile.fileName}').writeAsStringSync(content);

  /// Up to six seconds of short waits that stop as soon as [holds] does.
  ///
  /// The cache behind `readyTiles()` follows the table through drift's watch
  /// stream, and on a loaded machine that event arrives later than the write
  /// returns; a fixed wait is either too long or, under load, too short.
  Future<void> waitFor(bool Function() holds) async {
    for (var i = 0; i < 300 && !holds(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  test('a downloaded tile becomes a ready tile the engine may use', () async {
    final entry = _entry(_e10n45, bytes: 14);
    await repository.markDownloading(entry);
    expect(repository.readyTiles(), isEmpty);

    writeTile(_e10n45);
    await repository.markReady(entry, bytes: 14);
    await waitFor(() => repository.readyTiles().contains(_e10n45));

    expect(repository.readyTiles(), {_e10n45});
    expect(repository.formatVersions(), {_e10n45: '11.2'});
    expect(repository.totalBytes, 14);
    expect(repository.fileFor(_e10n45).existsSync(), isTrue);
  });

  test('watch() reports the table as it changes', () async {
    final seen = <int>[];
    final sub = repository.watch().listen((tiles) => seen.add(tiles.length));
    addTearDown(sub.cancel);

    writeTile(_e10n45);
    await repository.markReady(_entry(_e10n45, bytes: 14), bytes: 14);
    await pumpEventQueue();

    expect(seen.last, 1);
  });

  test('reconcile drops rows whose file is gone', () async {
    writeTile(_e10n45);
    await repository.markReady(_entry(_e10n45, bytes: 14), bytes: 14);
    repository.fileFor(_e10n45).deleteSync();

    await repository.reconcile();

    expect(repository.readyTiles(), isEmpty);
    expect(await repository.tiles(), isEmpty);
  });

  test('reconcile adopts a tile that is on disk without a row', () async {
    writeTile(_e5n45);

    await repository.reconcile(
      manifest: SegmentsManifest(
        tiles: <SegmentEntry>[_entry(_e5n45)],
        formatVersion: '11.2',
      ),
    );

    expect(repository.readyTiles(), {_e5n45});
    expect(repository.formatVersions()[_e5n45], '11.2');
  });

  test('a tile the mirror rebuilt becomes stale and stays usable', () async {
    writeTile(_e10n45);
    await repository.markReady(
      _entry(_e10n45, bytes: 14, updatedAt: DateTime.utc(2026, 9, 1)),
      bytes: 14,
    );

    final stale = await repository.applyManifest(
      SegmentsManifest(
        tiles: <SegmentEntry>[
          _entry(_e10n45, updatedAt: DateTime.utc(2026, 9, 20)),
        ],
      ),
    );

    expect(stale, [_e10n45]);
    expect(repository.cached.single.isStale, isTrue);
    // Stale is only "there is a newer one": the file is complete and routing
    // on it is still correct.
    expect(repository.readyTiles(), {_e10n45});

    final again = await repository.applyManifest(
      SegmentsManifest(
        tiles: <SegmentEntry>[
          _entry(_e10n45, updatedAt: DateTime.utc(2026, 9, 1)),
        ],
      ),
    );
    expect(again, isEmpty);
    expect(repository.cached.single.isStale, isFalse);
  });

  group('content digests', () {
    // sha256 of the bytes writeTile writes, which no rd5 header is long
    // enough to change.
    const rd5Digest =
        'e9525fab781f564189a2a78ee93a8e6a7bbbcea54e07086ed50fc15a858c3168';
    const gazDigest =
        '77d62adfdcf821cad6d3b3d34e868d36a4e24cd8c3786295ba108f0b967d67f3';

    Future<RoutingTileRow> row() async =>
        (await db.routingTilesDao.tileByName('E10_N45'))!;

    test('a finished download records the manifest\'s digests', () async {
      writeTile(_e10n45);

      await repository.markReady(
        _entry(_e10n45, contentSha256: 'aa', gazetteerContentSha256: 'gg'),
        bytes: 14,
        gazetteerFetched: true,
      );

      expect((await row()).contentSha256, 'aa');
      expect((await row()).gazetteerContentSha256, 'gg');
      expect(repository.cached.single.contentSha256, 'aa');
    });

    test('a manifest without digests records none', () async {
      writeTile(_e10n45);
      await repository.markReady(
        _entry(_e10n45, contentSha256: 'aa'),
        bytes: 14,
      );

      await repository.markReady(_entry(_e10n45), bytes: 14);

      expect((await row()).contentSha256, isNull);
    });

    test(
      'a gazetteer that did not come keeps the digest of the old one',
      () async {
        writeTile(_e10n45);
        await repository.markReady(
          _entry(_e10n45, gazetteerContentSha256: 'g1'),
          bytes: 14,
          gazetteerFetched: true,
        );

        await repository.markReady(
          _entry(_e10n45, gazetteerContentSha256: 'g2'),
          bytes: 14,
        );

        expect((await row()).gazetteerContentSha256, 'g1');
      },
    );

    test('a gazetteer fetched alone records its digest and clears a stale '
        'mark that was only its', () async {
      writeTile(_e10n45);
      await repository.markReady(
        _entry(_e10n45, contentSha256: 'aa', gazetteerContentSha256: 'g1'),
        bytes: 14,
        gazetteerFetched: true,
      );
      final next = _entry(
        _e10n45,
        contentSha256: 'aa',
        gazetteerContentSha256: 'g2',
      );
      expect(await repository.applyManifest(SegmentsManifest(tiles: [next])), [
        _e10n45,
      ]);

      await repository.markGazetteerFetched(next);

      expect((await row()).gazetteerContentSha256, 'g2');
      expect((await row()).state, RoutingTileState.ready);
    });

    test('the same content under a newer date is not stale, other content '
        'is', () async {
      writeTile(_e10n45);
      await repository.markReady(
        _entry(_e10n45, contentSha256: 'aa'),
        bytes: 14,
      );
      final later = DateTime.utc(2026, 10, 1);

      expect(
        await repository.applyManifest(
          SegmentsManifest(
            tiles: [_entry(_e10n45, contentSha256: 'aa', updatedAt: later)],
          ),
        ),
        isEmpty,
      );
      expect(repository.cached.single.isStale, isFalse);

      expect(
        await repository.applyManifest(
          SegmentsManifest(
            tiles: [_entry(_e10n45, contentSha256: 'bb', updatedAt: later)],
          ),
        ),
        [_e10n45],
      );
      expect(repository.cached.single.isStale, isTrue);
    });

    test('the backfill works the digests out from the files, once, and '
        'then decides', () async {
      writeTile(_e10n45);
      File('../tools/gazetteer/fixtures/E5_N45.gaz')
          .copySync(repository.gazetteerFileFor(_e10n45).path);
      // Downloaded before the mirror had digests: none stored.
      await repository.markReady(_entry(_e10n45), bytes: 14);
      final manifest = SegmentsManifest(
        tiles: [
          _entry(
            _e10n45,
            updatedAt: DateTime.utc(2026, 10, 1),
            contentSha256: rd5Digest,
            gazetteerContentSha256: 'other',
          ),
        ],
      );

      // The date alone no longer marks it while the digest is unknown.
      expect(await repository.applyManifest(manifest), isEmpty);

      await repository.backfillDigests(manifest);

      expect((await row()).contentSha256, rd5Digest);
      expect((await row()).gazetteerContentSha256, gazDigest);
      // The rd5 matches the mirror's; the gazetteer does not.
      expect(repository.cached.single.isStale, isTrue);
      expect(
        repository.cached.single.isRd5OutdatedBy(manifest.tiles.single),
        isFalse,
      );
    });

    test('the backfill leaves a tile alone when the manifest has no digest '
        'or the file is gone', () async {
      await repository.markReady(_entry(_e10n45), bytes: 14);
      writeTile(_e10n45);
      await repository.backfillDigests(
        SegmentsManifest(tiles: [_entry(_e10n45)]),
      );
      expect((await row()).contentSha256, isNull);

      File('${segments.path}/${_e10n45.fileName}').deleteSync();
      await repository.backfillDigests(
        SegmentsManifest(tiles: [_entry(_e10n45, contentSha256: 'aa')]),
      );
      expect((await row()).contentSha256, isNull);
    });
  });

  test('delete removes the file, a leftover .part and the row', () async {
    writeTile(_e10n45);
    File('${segments.path}/${_e10n45.fileName}.part').writeAsStringSync('x');
    await repository.markReady(_entry(_e10n45, bytes: 14), bytes: 14);

    await repository.delete(_e10n45);

    expect(repository.readyTiles(), isEmpty);
    expect(repository.fileFor(_e10n45).existsSync(), isFalse);
    expect(
      File('${segments.path}/${_e10n45.fileName}.part').existsSync(),
      isFalse,
    );
  });

  test('delete takes the offline gazetteer with it', () async {
    writeTile(_e10n45);
    writeTile(_e5n45);
    await repository.markReady(_entry(_e10n45, bytes: 14), bytes: 14);
    repository.gazetteerFileFor(_e10n45).writeAsStringSync('gaz');
    File('${repository.gazetteerFileFor(_e10n45).path}.part')
        .writeAsStringSync('half');
    repository.gazetteerFileFor(_e5n45).writeAsStringSync('gaz');

    await repository.delete(_e10n45);

    expect(repository.gazetteerFileFor(_e10n45).path, endsWith('.gaz'));
    expect(
      repository.gazetteerFileFor(_e10n45).path,
      startsWith(gazetteer.path),
    );
    expect(repository.gazetteerFileFor(_e10n45).existsSync(), isFalse);
    expect(
      File('${repository.gazetteerFileFor(_e10n45).path}.part').existsSync(),
      isFalse,
    );
    expect(
      repository.gazetteerFileFor(_e5n45).existsSync(),
      isTrue,
      reason: 'the other tile keeps its search index',
    );
  });

  test('delete works when there never was a gazetteer', () async {
    writeTile(_e10n45);
    await repository.markReady(_entry(_e10n45, bytes: 14), bytes: 14);

    await repository.delete(_e10n45);

    expect(repository.readyTiles(), isEmpty);
  });

  test('an interrupted download is forgotten but keeps its .part', () async {
    await repository.markDownloading(_entry(_e10n45));
    File('${segments.path}/${_e10n45.fileName}.part').writeAsStringSync('x');

    await repository.forgetFailed(_e10n45);

    expect(await repository.tiles(), isEmpty);
    expect(
      File('${segments.path}/${_e10n45.fileName}.part').existsSync(),
      isTrue,
    );
  });
}
