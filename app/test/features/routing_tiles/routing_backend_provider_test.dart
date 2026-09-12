import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/features/planner/data/routing_backend_provider.dart';
import 'package:velorki/features/routing_tiles/data/brouter_assets.dart';
import 'package:velorki/features/routing_tiles/data/brouter_storage.dart';
import 'package:velorki/features/routing_tiles/data/on_device_routing.dart';
import 'package:velorki/features/routing_tiles/data/routing_tiles_repository.dart';
import 'package:velorki/features/routing_tiles/domain/routing_preference.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'support/fake_segments.dart';

const TileName _tile = TileName(10, 45);
const RouteQuery _inTile = RouteQuery(
  points: <LatLng>[LatLng(47.0, 11.0), LatLng(47.1, 11.1)],
);

void main() {
  late VelorkiDatabase db;
  late BrouterStorage storage;

  setUp(() {
    db = VelorkiDatabase.memory();
    storage = BrouterStorage(tempDir('velorki-backend'));
    storage.segments.createSync(recursive: true);
    storage.profiles.createSync(recursive: true);
    addTearDown(db.close);
  });

  Future<ProviderContainer> containerFor({
    String brouterUrl = 'https://brouter.test',
    RoutingPreference preference = RoutingPreference.auto,
    bool withTile = false,
  }) async {
    if (withTile) {
      File('${storage.segments.path}/${_tile.fileName}')
        ..createSync(recursive: true)
        ..writeAsStringSync('rd5');
      await db.routingTilesDao.markReady(
        _tile.name,
        bytes: 3,
        updatedAt: DateTime.utc(2026, 9, 1),
        formatVersion: '11.2',
      );
    }
    SharedPreferences.setMockInitialValues(<String, Object>{
      if (preference != RoutingPreference.auto)
        'routing.preference': preference.name,
    });
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
        appConfigProvider.overrideWithValue(AppConfig(brouterUrl: brouterUrl)),
        velorkiDatabaseProvider.overrideWithValue(db),
        brouterStorageProvider.overrideWith((ref) async => storage),
        brouterProfilesProvider.overrideWith((ref) async => storage.profiles),
      ],
    );
    addTearDown(container.dispose);
    // Riverpod 3 pauses a provider nobody listens to, and a paused provider
    // does not follow the tile table's stream. The planner's `ref.watch` is
    // that listener in the app; here it has to be made explicit.
    container.listen(routingBackendProvider, (_, _) {});
    // The local half only exists once the profiles are copied and the tile
    // table has been read; both are futures the provider watches.
    await container.read(onDeviceRoutingProvider.future);
    return container;
  }

  test('with a server and no tiles it routes remotely', () async {
    final container = await containerFor();

    final backend = container.read(routingBackendProvider);

    expect(backend, isA<CompositeRoutingBackend>());
    final composite = backend! as CompositeRoutingBackend;
    expect(composite.local, isNull);
    expect(composite.remote, isNotNull);
    expect(composite.decide(_inTile).source, RoutingSource.remote);
    expect(composite.decide(_inTile).missingTiles, <TileName>[_tile]);
    expect(container.read(onDeviceRoutingActiveProvider), isFalse);
  });

  test('a downloaded tile moves the route onto the device', () async {
    final container = await containerFor(withTile: true);

    final composite =
        container.read(routingBackendProvider)! as CompositeRoutingBackend;

    expect(composite.local, isNotNull);
    expect(composite.remote, isNotNull);
    final decision = composite.decide(_inTile);
    expect(decision.source, RoutingSource.local);
    expect(decision.hasLocalCoverage, isTrue);
    expect(container.read(onDeviceRoutingActiveProvider), isTrue);
  });

  test(
    'a route outside the downloaded tiles still goes to the server',
    () async {
      final container = await containerFor(withTile: true);

      final composite =
          container.read(routingBackendProvider)! as CompositeRoutingBackend;

      const faraway = RouteQuery(
        points: <LatLng>[LatLng(52.5, 13.4), LatLng(52.6, 13.5)],
      );
      expect(composite.decide(faraway).source, RoutingSource.remote);
    },
  );

  test('server only ignores the tiles that are there', () async {
    final container = await containerFor(
      withTile: true,
      preference: RoutingPreference.serverOnly,
    );

    final composite =
        container.read(routingBackendProvider)! as CompositeRoutingBackend;

    expect(composite.local, isNull);
    expect(composite.decide(_inTile).source, RoutingSource.remote);
    expect(container.read(onDeviceRoutingActiveProvider), isFalse);
  });

  test('on device only never asks the server', () async {
    final container = await containerFor(
      withTile: true,
      preference: RoutingPreference.onDeviceOnly,
    );

    final composite =
        container.read(routingBackendProvider)! as CompositeRoutingBackend;

    expect(composite.remote, isNull);
    expect(composite.decide(_inTile).source, RoutingSource.local);
  });

  test('on device only offers the download instead of a dead end', () async {
    final container = await containerFor(
      preference: RoutingPreference.onDeviceOnly,
    );

    final composite =
        container.read(routingBackendProvider)! as CompositeRoutingBackend;

    expect(composite.local, isNotNull);
    final decision = composite.decide(_inTile);
    expect(decision.canRoute, isFalse);
    expect(decision.missingTiles, <TileName>[_tile]);
    expect(decision.failure!.kind, RoutingErrorKind.missingTiles);
  });

  test('without a server and without tiles there is no backend', () async {
    final container = await containerFor(brouterUrl: '');

    expect(container.read(routingBackendProvider), isNull);
    expect(container.read(onDeviceRoutingActiveProvider), isFalse);
  });

  test('a fork without a server routes on its downloaded tiles', () async {
    final container = await containerFor(brouterUrl: '', withTile: true);

    final composite =
        container.read(routingBackendProvider)! as CompositeRoutingBackend;

    expect(composite.remote, isNull);
    expect(composite.decide(_inTile).source, RoutingSource.local);
  });

  test('deleting the last tile hands routing back to the server', () async {
    final container = await containerFor(withTile: true);
    expect(container.read(onDeviceRoutingActiveProvider), isTrue);

    final repository = await container.read(
      routingTilesRepositoryProvider.future,
    );
    await repository.delete(_tile);
    // The table's stream tells the providers; give it a turn of the loop.
    await pumpEventQueue();

    expect(container.read(onDeviceRoutingActiveProvider), isFalse);
  });
}
