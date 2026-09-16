import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/features/routing_tiles/application/tile_download_controller.dart';
import 'package:velorki/features/routing_tiles/data/brouter_storage.dart';
import 'package:velorki/features/routing_tiles/data/routing_tiles_repository.dart';
import 'package:velorki/features/routing_tiles/data/segments_manifest_service.dart';
import 'package:velorki/features/routing_tiles/domain/sha256.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

import 'support/fake_segments.dart';

const TileName _first = TileName(10, 45);
const TileName _second = TileName(5, 45);
final Uint8List _body = Uint8List.fromList(utf8.encode('rd5-body'));

final Uint8List _gaz = Uint8List.fromList(utf8.encode('gazetteer-body'));

SegmentEntry _entry(TileName tile, {int? bytes, bool gazetteer = false}) =>
    SegmentEntry(
      tile: tile,
      bytes: bytes ?? _body.length,
      updatedAt: DateTime.utc(2026, 9, 1),
      formatVersion: '11.2',
      gazetteer: gazetteer
          ? GazetteerEntry(
              tile: tile,
              bytes: _gaz.length,
              sha256: (Sha256()..add(_gaz)).hexDigest(),
              updatedAt: DateTime.utc(2026, 9, 16),
            )
          : null,
    );

/// A mirror that serves the tile and its gazetteer.
FakeSegmentsAdapter _servingBoth() => FakeSegmentsAdapter(
  (options) => options.uri.path.endsWith('.gaz')
      ? FakeSegmentsResponse.bytes(_gaz)
      : FakeSegmentsResponse.bytes(_body),
);

File _gazFile(BrouterStorage storage, TileName tile) =>
    File('${storage.gazetteer.path}/${tile.gazetteerFileName}');

void main() {
  late VelorkiDatabase db;
  late BrouterStorage storage;

  setUp(() {
    db = VelorkiDatabase.memory();
    storage = BrouterStorage(tempDir('velorki-queue'))
      ..segments.createSync(recursive: true)
      ..profiles.createSync(recursive: true)
      ..gazetteer.createSync(recursive: true);
    addTearDown(db.close);
  });

  Future<ProviderContainer> containerFor(FakeSegmentsAdapter adapter) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
        appConfigProvider.overrideWithValue(
          const AppConfig(segmentsUrl: 'https://mirror.test/segments4'),
        ),
        velorkiDatabaseProvider.overrideWithValue(db),
        brouterStorageProvider.overrideWith((ref) async => storage),
        segmentsDioProvider.overrideWithValue(segmentsDioWith(adapter)),
      ],
    );
    addTearDown(container.dispose);
    container.listen(tileDownloadQueueProvider, (_, _) {});
    await container.read(routingTilesRepositoryProvider.future);
    return container;
  }

  test('downloads the queue one tile after another', () async {
    final container = await containerFor(FakeSegmentsAdapter.serving(_body));

    await container.read(tileDownloadQueueProvider.notifier).enqueue(
      <SegmentEntry>[_entry(_first), _entry(_second)],
    );

    final state = container.read(tileDownloadQueueProvider);
    expect(state.isRunning, isFalse);
    expect(state.finished, <TileName>[_first, _second]);
    expect(state.failure, isNull);

    final repository = await container.read(
      routingTilesRepositoryProvider.future,
    );
    expect(repository.readyTiles(), <TileName>{_first, _second});
    expect(
      File('${storage.segments.path}/${_first.fileName}').existsSync(),
      isTrue,
    );
  });

  test('one broken tile does not stop the rest', () async {
    final adapter = FakeSegmentsAdapter((options) {
      if (options.uri.path.endsWith(_first.fileName)) {
        return FakeSegmentsResponse.bytes(Uint8List.fromList(<int>[1, 2]));
      }
      return FakeSegmentsResponse.bytes(_body);
    });
    final container = await containerFor(adapter);

    await container.read(tileDownloadQueueProvider.notifier).enqueue(
      <SegmentEntry>[_entry(_first), _entry(_second)],
    );

    final state = container.read(tileDownloadQueueProvider);
    expect(state.finished, <TileName>[_second]);
    expect(state.failure, contains('E10_N45.rd5'));

    final repository = await container.read(
      routingTilesRepositoryProvider.future,
    );
    // The broken one leaves no row behind that the engine could route on.
    expect(repository.readyTiles(), <TileName>{_second});
  });

  test('a tile that is already queued is not queued twice', () async {
    final adapter = FakeSegmentsAdapter.serving(_body);
    final container = await containerFor(adapter);
    final queue = container.read(tileDownloadQueueProvider.notifier);

    // Two taps in a row, before the first download has finished.
    final running = queue.enqueue(<SegmentEntry>[_entry(_first)]);
    await queue.enqueue(<SegmentEntry>[_entry(_first)]);
    await running;

    expect(adapter.requests, hasLength(1));
    expect(container.read(tileDownloadQueueProvider).finished, <TileName>[
      _first,
    ]);
  });

  test('a tile with a gazetteer gets it after the rd5', () async {
    final adapter = _servingBoth();
    final container = await containerFor(adapter);

    await container.read(tileDownloadQueueProvider.notifier).enqueue(
      <SegmentEntry>[_entry(_first, gazetteer: true)],
    );

    expect(container.read(tileDownloadQueueProvider).finished, <TileName>[
      _first,
    ]);
    expect(adapter.requests.map((r) => r.uri.path.split('/').last), <String>[
      'E10_N45.rd5',
      'E10_N45.gaz',
    ], reason: 'the tile first, then its search index');
    expect(_gazFile(storage, _first).readAsBytesSync(), _gaz);

    final repository = await container.read(
      routingTilesRepositoryProvider.future,
    );
    expect(repository.readyTiles(), <TileName>{_first});
  });

  test('the gazetteer is a second phase of the same tile', () async {
    final container = await containerFor(_servingBoth());
    final seen = <({int received, int total, bool finished})>[];
    container.listen(tileDownloadQueueProvider, (_, next) {
      final progress = next.progress;
      if (progress == null) return;
      seen.add((
        received: progress.received,
        total: progress.total,
        finished: next.finished.contains(_first),
      ));
    });

    await container.read(tileDownloadQueueProvider.notifier).enqueue(
      <SegmentEntry>[_entry(_first, gazetteer: true)],
    );

    final gazetteer = seen.indexWhere((s) => s.total == _gaz.length);
    expect(gazetteer, greaterThan(0), reason: 'the .gaz is reported too');
    expect(
      seen.take(gazetteer).every((s) => s.total == _body.length),
      isTrue,
      reason: 'the rd5 first, in full',
    );
    expect(seen[gazetteer - 1].received, _body.length);
    expect(seen[gazetteer].received, 0, reason: 'the bar starts over');
    expect(seen.last.received, _gaz.length);
    expect(
      seen.take(gazetteer + 1).every((s) => !s.finished),
      isTrue,
      reason: 'the rd5 alone does not finish the tile',
    );
    expect(
      seen
          .where((s) => s.total == _gaz.length && s.received < s.total)
          .every((s) => !s.finished),
      isTrue,
      reason: 'nor does a gazetteer that is still coming down',
    );
    expect(container.read(tileDownloadQueueProvider).finished, <TileName>[
      _first,
    ]);
  });

  test('a tile without a gazetteer asks for none', () async {
    final adapter = _servingBoth();
    final container = await containerFor(adapter);

    await container.read(tileDownloadQueueProvider.notifier).enqueue(
      <SegmentEntry>[_entry(_first)],
    );

    expect(adapter.requests, hasLength(1));
    expect(_gazFile(storage, _first).existsSync(), isFalse);
  });

  test('a gazetteer that fails leaves the tile ready and moves on', () async {
    final adapter = FakeSegmentsAdapter((options) {
      if (options.uri.path.endsWith('.gaz')) {
        return FakeSegmentsResponse.text('gone', status: 404);
      }
      return FakeSegmentsResponse.bytes(_body);
    });
    final container = await containerFor(adapter);

    await container.read(tileDownloadQueueProvider.notifier).enqueue(
      <SegmentEntry>[_entry(_first, gazetteer: true), _entry(_second)],
    );

    final state = container.read(tileDownloadQueueProvider);
    expect(state.finished, <TileName>[_first, _second]);
    expect(state.failure, isNull, reason: 'the rider is not told off for it');

    final repository = await container.read(
      routingTilesRepositoryProvider.future,
    );
    expect(repository.readyTiles(), <TileName>{_first, _second});
    expect(_gazFile(storage, _first).existsSync(), isFalse);
  });

  test('downloading a tile again retries its gazetteer', () async {
    var serveGazetteer = false;
    final adapter = FakeSegmentsAdapter((options) {
      if (!options.uri.path.endsWith('.gaz')) {
        return FakeSegmentsResponse.bytes(_body);
      }
      return serveGazetteer
          ? FakeSegmentsResponse.bytes(_gaz)
          : FakeSegmentsResponse.text('gone', status: 404);
    });
    final container = await containerFor(adapter);
    final queue = container.read(tileDownloadQueueProvider.notifier);

    await queue.enqueue(<SegmentEntry>[_entry(_first, gazetteer: true)]);
    expect(_gazFile(storage, _first).existsSync(), isFalse);

    serveGazetteer = true;
    await queue.enqueue(<SegmentEntry>[_entry(_first, gazetteer: true)]);

    expect(_gazFile(storage, _first).readAsBytesSync(), _gaz);
  });
}
