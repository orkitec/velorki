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
import 'package:velorki_brouter/velorki_brouter.dart';

import 'support/fake_segments.dart';

const TileName _first = TileName(10, 45);
const TileName _second = TileName(5, 45);
final Uint8List _body = Uint8List.fromList(utf8.encode('rd5-body'));

SegmentEntry _entry(TileName tile, {int? bytes}) => SegmentEntry(
  tile: tile,
  bytes: bytes ?? _body.length,
  updatedAt: DateTime.utc(2026, 9, 1),
  formatVersion: '11.2',
);

void main() {
  late VelorkiDatabase db;
  late BrouterStorage storage;

  setUp(() {
    db = VelorkiDatabase.memory();
    storage = BrouterStorage(tempDir('velorki-queue'))
      ..segments.createSync(recursive: true)
      ..profiles.createSync(recursive: true);
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
}
