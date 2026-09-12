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
}) => SegmentEntry(
  tile: tile,
  bytes: bytes,
  updatedAt: updatedAt ?? DateTime.utc(2026, 9, 1),
  formatVersion: formatVersion,
);

void main() {
  late VelorkiDatabase db;
  late Directory segments;
  late RoutingTilesRepository repository;

  setUp(() async {
    db = VelorkiDatabase.memory();
    segments = Directory('${tempDir('velorki-tiles').path}/segments')
      ..createSync(recursive: true);
    repository = RoutingTilesRepository(
      dao: db.routingTilesDao,
      segmentsDir: segments,
    );
    await repository.load();
    addTearDown(() async {
      await repository.dispose();
      await db.close();
    });
  });

  void writeTile(TileName tile, {String content = 'rd5-bytes-here'}) =>
      File('${segments.path}/${tile.fileName}').writeAsStringSync(content);

  test('a downloaded tile becomes a ready tile the engine may use', () async {
    final entry = _entry(_e10n45, bytes: 14);
    await repository.markDownloading(entry);
    expect(repository.readyTiles(), isEmpty);

    writeTile(_e10n45);
    await repository.markReady(entry, bytes: 14);

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
