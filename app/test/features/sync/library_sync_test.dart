import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/features/planner/data/route_repository.dart';
import 'package:velorki/features/sync/application/library_sync.dart';
import 'package:velorki/features/sync/data/record_codec.dart';

import 'support/fake_cloud.dart';
import 'support/rows.dart';

/// One phone or tablet: its own database and engine over the shared cloud.
class _Device {
  _Device(FakeCloud cloud, Directory dir, String name)
    : db = VelorkiDatabase.memory(),
      bridge = FakeCloudSyncBridge(cloud),
      _outbox = Directory('${dir.path}/$name') {
    _attach();
  }

  final VelorkiDatabase db;
  final FakeCloudSyncBridge bridge;
  final Directory _outbox;
  late LibrarySync sync;

  void _attach() {
    sync = LibrarySync(db: db, bridge: bridge, codec: RecordCodec(_outbox));
    bridge.setHandler(
      LibraryHandler(
        toSave: sync.recordsToSave,
        apply: sync.applyRemote,
        onSent: sync.sent,
      ),
    );
  }

  /// The app killed and opened again: the database and the engine's state
  /// stay, the library sync is a new one that knows nothing of what the old
  /// one handed out, and it hands over what waits, as the controller's
  /// start does.
  Future<void> restart() async {
    await sync.stop();
    _attach();
    await sync.push();
  }

  /// Renames the route [id] as the library screen does.
  Future<void> renameRoute(String id, String name) =>
      RouteRepository(db.routesDao).rename(id, name);

  Future<String?> routeName(String id) async =>
      (await db.routesDao.routeById(id))?.name;

  /// Hands the waiting changes over, sends them and fetches.
  Future<void> syncNow() async {
    await sync.push();
    await bridge.sync();
  }

  Future<void> setChangedAt(String kind, String id, int ms) =>
      db.customStatement(
        'UPDATE sync_records SET changed_at_ms = ? WHERE kind = ? AND record_id = ?',
        [ms, kind, id],
      );

  Future<List<String>> routeNames() async =>
      [for (final r in await db.routesDao.allRoutes()) r.name]..sort();

  Future<List<String>> rideNames() async =>
      [for (final r in await db.ridesDao.allRides()) r.name]..sort();

  Future<void> close() => db.close();
}

void main() {
  // Two devices, two in-memory databases, on purpose.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dir;
  late FakeCloud cloud;
  late _Device phone;
  late _Device pad;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('library_sync');
    cloud = FakeCloud(Directory('${dir.path}/cloud')..createSync());
    phone = _Device(cloud, dir, 'phone');
    pad = _Device(cloud, dir, 'pad');
  });
  tearDown(() async {
    await phone.close();
    await pad.close();
    dir.deleteSync(recursive: true);
  });

  test('a change whose push was missed comes with the manual fetch, and '
      'the engine fetching it again later writes nothing', () async {
    await phone.db.routesDao.upsertRoute(fullRoute('r1'));
    await phone.db.routesDao.upsertRoute(fullRoute('r2'));
    await phone.syncNow();
    await pad.syncNow();
    expect(await pad.routeNames(), hasLength(2));

    await phone.renameRoute('r1', 'Renamed');
    await phone.db.routesDao.deleteRoute('r2');
    await phone.syncNow();

    // No push reached the pad: only the manual fetch asks the server.
    await pad.bridge.fetchNow();
    expect(await pad.routeName('r1'), 'Renamed');
    expect(await pad.db.routesDao.routeById('r2'), isNull);

    // The engine gets to the same changes later, from its own token.
    await pad.bridge.fetch();
    expect(await pad.routeNames(), ['Renamed']);
    expect(await pad.db.syncDao.dirtyRecords(), isEmpty);
    expect(await pad.db.syncDao.record('route', 'r2'), isNull);
    await pad.sync.push();
    expect(pad.bridge.pendingSaves, isEmpty);
    expect(pad.bridge.pendingDeletes, isEmpty);
  });

  test('the library there was is sent once, then nothing waits', () async {
    await phone.db.routesDao.upsertRoute(fullRoute('r1'));
    await phone.db.routesDao.upsertRoute(fullRoute('r2'));
    await phone.db.ridesDao.upsertRide(fullRide('ride1', routeId: 'r1'));

    await phone.syncNow();

    expect(cloud.names, {'route_r1', 'route_r2', 'ride_ride1'});
    expect(await phone.db.syncDao.dirtyRecords(), isEmpty);
    expect(cloud.fields('ride_ride1')!['routeId'], 'r1');

    // Nothing to send the second time round, and the own changes that came
    // back wrote nothing.
    await phone.syncNow();
    expect(phone.bridge.pendingSaves, isEmpty);
    expect(await phone.db.syncDao.dirtyRecords(), isEmpty);
  });

  test('a new device gets everything, rides linked to their routes', () async {
    await phone.db.routesDao.upsertRoute(fullRoute('r1', points: 5000));
    await phone.db.ridesDao.upsertRide(
      fullRide('ride1', points: 20000, routeId: 'r1'),
    );
    await phone.syncNow();

    await pad.syncNow();

    final route = await pad.db.routesDao.routeById('r1');
    final ride = await pad.db.ridesDao.rideById('ride1');
    expect(
      route!.copyWith(externalIdsJson: const Value(null)),
      (await phone.db.routesDao.routeById('r1'))!,
    );
    expect(ride, (await phone.db.ridesDao.rideById('ride1'))!);
    expect(ride!.routeId, 'r1');
    expect(
      await pad.db.syncDao.dirtyRecords(),
      isEmpty,
      reason: 'nothing echoed',
    );
  });

  test(
    'a ride that arrives before its route is linked when it comes',
    () async {
      await phone.db.routesDao.upsertRoute(fullRoute('r1'));
      await phone.db.ridesDao.upsertRide(fullRide('ride1', routeId: 'r1'));
      await phone.syncNow();
      final names = await pad.sync.recordsToSave(['route_r1']);
      expect(names, isEmpty, reason: 'the pad has no such route');

      // The ride alone first, as a batch boundary could deliver it.
      final ride = await phone.sync.recordsToSave(['ride_ride1']);
      await pad.sync.applyRemote(ride, const []);
      expect((await pad.db.ridesDao.rideById('ride1'))!.routeId, isNull);
      await pad.syncNow();

      expect((await pad.db.ridesDao.rideById('ride1'))!.routeId, 'r1');
      expect(await pad.db.syncDao.dirtyRecords(), isEmpty);
    },
  );

  test('an edit on one device reaches the other', () async {
    await phone.db.routesDao.upsertRoute(fullRoute('r1'));
    await phone.syncNow();
    await pad.syncNow();

    await pad.db.customStatement("UPDATE routes SET name = 'Renamed'");
    await pad.syncNow();
    await phone.syncNow();

    expect(await phone.routeNames(), ['Renamed']);
  });

  group('a conflict goes to the newer change', () {
    setUp(() async {
      await phone.db.ridesDao.upsertRide(fullRide('ride1'));
      await phone.syncNow();
      await pad.syncNow();
      await phone.db.ridesDao.renameRide('ride1', 'Phone');
      await pad.db.ridesDao.renameRide('ride1', 'Pad');
    });

    test('the newer one sent second wins on both', () async {
      await phone.setChangedAt('ride', 'ride1', 1000);
      await pad.setChangedAt('ride', 'ride1', 2000);

      await phone.syncNow();
      await pad.syncNow();
      await phone.syncNow();

      expect(await phone.rideNames(), ['Pad']);
      expect(await pad.rideNames(), ['Pad']);
      expect(cloud.fields('ride_ride1')!['name'], 'Pad');
    });

    test('the newer one sent first wins on both', () async {
      await phone.setChangedAt('ride', 'ride1', 3000);
      await pad.setChangedAt('ride', 'ride1', 2000);

      await phone.syncNow();
      await pad.syncNow();
      await phone.syncNow();

      expect(await phone.rideNames(), ['Phone']);
      expect(await pad.rideNames(), ['Phone']);
      expect(await pad.db.syncDao.dirtyRecords(), isEmpty);
    });

    test('a tie goes to the copy on the server, alike everywhere', () async {
      await phone.setChangedAt('ride', 'ride1', 2000);
      await pad.setChangedAt('ride', 'ride1', 2000);

      await phone.syncNow();
      await pad.syncNow();
      await phone.syncNow();

      expect(await phone.rideNames(), ['Phone']);
      expect(await pad.rideNames(), ['Phone']);
    });
  });

  test('a refused save whose server copy comes without its body is not '
      'sent over the same stale tag again, and the fetch settles it', () async {
    await phone.db.ridesDao.upsertRide(fullRide('ride1'));
    await phone.syncNow();
    await pad.syncNow();
    await phone.db.ridesDao.renameRide('ride1', 'Phone');
    await pad.db.ridesDao.renameRide('ride1', 'Pad');
    await phone.setChangedAt('ride', 'ride1', 3000);
    await pad.setChangedAt('ride', 'ride1', 2000);
    await phone.syncNow();
    cloud.conflictsWithoutBody = true;

    // The pad's older rename is refused; it cannot read the server's copy
    // it was refused with, so it fetches instead of sending again.
    await pad.sync.push();
    await pad.bridge.send();

    expect(pad.bridge.fetchRequests, 1);
    expect(await pad.rideNames(), ['Phone']);
    expect(await pad.db.syncDao.dirtyRecords(), isEmpty);
    expect(cloud.fields('ride_ride1')!['name'], 'Phone');
  });

  group('delete against edit', () {
    setUp(() async {
      await phone.db.routesDao.upsertRoute(fullRoute('r1'));
      await phone.syncNow();
      await pad.syncNow();
    });

    test('a delete elsewhere removes an unchanged route', () async {
      await pad.db.routesDao.deleteRoute('r1');
      await pad.syncNow();
      expect(cloud.names, isEmpty);

      await phone.syncNow();
      expect(await phone.routeNames(), isEmpty);
      expect(await phone.db.syncDao.dirtyRecords(), isEmpty);
      expect(await phone.db.syncDao.record('route', 'r1'), isNull);
    });

    test('an edit here not yet sent brings a deleted route back', () async {
      await pad.db.routesDao.deleteRoute('r1');
      await pad.syncNow();
      await phone.db.customStatement("UPDATE routes SET name = 'Kept'");

      await phone.bridge.fetch();
      expect(await phone.routeNames(), ['Kept']);
      await phone.syncNow();
      await pad.syncNow();

      expect(cloud.names, {'route_r1'});
      expect(await pad.routeNames(), ['Kept']);
    });

    test(
      'an edit sent before the delete is lost to the newer delete',
      () async {
        await phone.db.customStatement("UPDATE routes SET name = 'Edited'");
        await phone.setChangedAt('route', 'r1', 1000);
        await phone.syncNow();
        // The pad deletes after it has seen the edit... or not: its delete is
        // newer either way and goes through.
        await pad.db.routesDao.deleteRoute('r1');
        await pad.setChangedAt('route', 'r1', 5000);
        await pad.syncNow();
        await phone.syncNow();

        expect(await phone.routeNames(), isEmpty);
        expect(await pad.routeNames(), isEmpty);
        expect(cloud.names, isEmpty);
      },
    );
  });

  group('Strava data stays on the phone', () {
    test('Strava routes are never sent, their deletes neither', () async {
      await phone.db.routesDao.upsertRoute(
        fullRoute('s1', source: RouteSource.strava),
      );
      await phone.db.routesDao.upsertRoute(
        fullRoute('s2')
            .copyWith(externalIdsJson: const Value('{"strava_route_id":"9"}')),
      );
      await phone.db.routesDao.upsertRoute(fullRoute('own'));
      await phone.syncNow();
      expect(cloud.names, {'route_own'});
      expect(await phone.db.syncDao.dirtyRecords(), isEmpty);

      await phone.db.routesDao.deleteStravaRoutes();
      await phone.syncNow();
      expect(cloud.names, {'route_own'});
      expect(await phone.db.syncDao.dirtyRecords(), isEmpty);
      expect(await phone.db.syncDao.record('route', 's1'), isNull);
    });

    test('a route asked for that is Strava\'s is not handed out', () async {
      await phone.db.routesDao.upsertRoute(
        fullRoute('s1', source: RouteSource.strava),
      );
      expect(await phone.sync.recordsToSave(['route_s1']), isEmpty);
    });

    test('a synced route that becomes Strava\'s is taken off iCloud', () async {
      await phone.db.routesDao.upsertRoute(fullRoute('r1'));
      await phone.syncNow();
      expect(cloud.names, {'route_r1'});

      await phone.db.customStatement(
        'UPDATE routes SET external_ids_json = \'{"strava_route_id":"3"}\'',
      );
      await phone.syncNow();

      expect(cloud.names, isEmpty);
      expect(await phone.routeNames(), ['Route r1'], reason: 'kept here');
      expect(await phone.db.syncDao.dirtyRecords(), isEmpty);
    });

    test('a ride keeps a Strava route it followed to itself', () async {
      await phone.db.routesDao.upsertRoute(
        fullRoute('s1', source: RouteSource.strava),
      );
      await phone.db.ridesDao.upsertRide(fullRide('ride1', routeId: 's1'));
      await phone.syncNow();
      expect(cloud.names, {'ride_ride1'});
      expect(cloud.fields('ride_ride1')!.containsKey('routeId'), isFalse);
    });

    test('a ride\'s uploads stay, whatever comes from iCloud', () async {
      await phone.db.ridesDao.upsertRide(fullRide('ride1'));
      await phone.syncNow();
      await pad.syncNow();
      await phone.db.ridesDao.setRideUploads('ride1', '{"strava":{}}');
      await pad.db.ridesDao.renameRide('ride1', 'From the pad');
      await pad.syncNow();
      await phone.syncNow();

      final ride = (await phone.db.ridesDao.rideById('ride1'))!;
      expect(ride.name, 'From the pad');
      expect(ride.uploadsJson, '{"strava":{}}');
      expect((await pad.db.ridesDao.rideById('ride1'))!.uploadsJson, isNull);
    });
  });

  test('a surface matched here stays when the record has none', () async {
    await phone.db.ridesDao.upsertRide(
      fullRide('ride1').copyWith(surfaceStatsJson: const Value(null)),
    );
    await phone.syncNow();
    await pad.syncNow();
    await pad.db.ridesDao.setRideSurface('ride1', '{"paved":1}');
    await phone.db.ridesDao.renameRide('ride1', 'Renamed');
    await phone.syncNow();
    await pad.syncNow();

    final ride = (await pad.db.ridesDao.rideById('ride1'))!;
    expect(ride.name, 'Renamed');
    expect(ride.surfaceStatsJson, '{"paved":1}');
  });

  test(
    'a reset sends everything again as new, the library untouched',
    () async {
      await phone.db.routesDao.upsertRoute(fullRoute('r1'));
      await phone.db.ridesDao.upsertRide(fullRide('ride1'));
      await phone.db.ridesDao.upsertRide(fullRide('gone'));
      await phone.syncNow();
      await phone.db.ridesDao.deleteRide('gone');

      await phone.sync.reset();

      final dirty = await phone.db.syncDao.dirtyRecords();
      expect({for (final d in dirty) d.recordId}, {'r1', 'ride1'});
      expect(dirty.every((d) => d.systemFields == null && !d.deleted), isTrue);
      expect(await phone.routeNames(), ['Route r1']);
      expect(await phone.rideNames(), ['Ride ride1']);
    },
  );

  test('many records go in rounds without losing one', () async {
    for (var i = 0; i < 120; i++) {
      await phone.db.ridesDao.upsertRide(fullRide('ride$i', points: 200));
    }
    await phone.syncNow();
    await pad.syncNow();
    expect((await pad.db.ridesDao.allRides()).length, 120);
  });

  group('one route renamed back and forth between two devices', () {
    // The pad made the route, the phone renames it: what a rider did with
    // an iPad and an iPhone.
    setUp(() async {
      await pad.db.routesDao.upsertRoute(fullRoute('r1'));
      await pad.syncNow();
      await phone.syncNow();
      expect(await phone.routeName('r1'), 'Route r1');
    });

    Future<void> tick() =>
        Future<void>.delayed(const Duration(milliseconds: 5));

    test('a rename, a restart before it is sent, then a second rename: '
        'both reach the other device', () async {
      await tick();
      await phone.renameRoute('r1', 'Name 1');
      await phone.sync.push();
      await phone.restart();
      await phone.bridge.sync();
      await pad.syncNow();
      expect(await pad.routeName('r1'), 'Name 1');

      await tick();
      await phone.renameRoute('r1', 'Name 2');
      await phone.syncNow();
      await pad.syncNow();
      expect(await pad.routeName('r1'), 'Name 2');
      expect(cloud.fields('route_r1')!['name'], 'Name 2');
      expect(await phone.db.syncDao.dirtyRecords(), isEmpty);
      expect(await pad.db.syncDao.dirtyRecords(), isEmpty);
    });

    test('a restart after the first rename is sent', () async {
      await tick();
      await phone.renameRoute('r1', 'Name 1');
      await phone.syncNow();
      await phone.restart();
      await pad.syncNow();
      expect(await pad.routeName('r1'), 'Name 1');

      await tick();
      await phone.renameRoute('r1', 'Name 2');
      await phone.syncNow();
      await phone.restart();
      await phone.syncNow();
      await pad.restart();
      await pad.syncNow();
      expect(await pad.routeName('r1'), 'Name 2');
    });

    test('two renames in quick succession, the second while the first is '
        'on its way', () async {
      await tick();
      await phone.renameRoute('r1', 'Name 1');
      await phone.sync.push();
      final first = await phone.bridge.handOut();
      await tick();
      await phone.renameRoute('r1', 'Name 2');
      // What the dirty watch does: the name is pending still, so the
      // engine adds nothing.
      await phone.sync.push();
      await phone.bridge.complete(first);
      await phone.bridge.send();
      await pad.syncNow();

      expect(await pad.routeName('r1'), 'Name 2');
      expect(await phone.db.syncDao.dirtyRecords(), isEmpty);
    });

    test('a rename here while the other device edited too: the newer one '
        'wins on both', () async {
      await tick();
      await pad.renameRoute('r1', 'Pad');
      await tick();
      await phone.renameRoute('r1', 'Phone');
      await pad.syncNow();
      await phone.syncNow();
      await pad.syncNow();

      expect(await phone.routeName('r1'), 'Phone');
      expect(await pad.routeName('r1'), 'Phone');
      expect(await phone.db.syncDao.dirtyRecords(), isEmpty);
      expect(await pad.db.syncDao.dirtyRecords(), isEmpty);
    });

    test('made on one, renamed on the other, renamed back on the first, '
        'then again on the other', () async {
      await tick();
      await phone.renameRoute('r1', 'Phone 1');
      await phone.syncNow();
      await pad.syncNow();
      expect(await pad.routeName('r1'), 'Phone 1');

      await tick();
      await pad.renameRoute('r1', 'Pad 1');
      await pad.syncNow();
      await phone.syncNow();
      expect(await phone.routeName('r1'), 'Pad 1');

      await tick();
      await phone.renameRoute('r1', 'Phone 2');
      await phone.restart();
      await phone.syncNow();
      await pad.syncNow();
      expect(await pad.routeName('r1'), 'Phone 2');
      expect(await phone.routeName('r1'), 'Phone 2');
    });

    test(
      'a rename sent before the device fetched its own last save back',
      () async {
        await tick();
        await phone.renameRoute('r1', 'Name 1');
        await phone.sync.push();
        await phone.bridge.send();
        await tick();
        await phone.renameRoute('r1', 'Name 2');
        await phone.sync.push();
        await phone.bridge.send();
        await phone.bridge.fetch();
        await pad.syncNow();

        expect(await pad.routeName('r1'), 'Name 2');
        expect(await phone.routeName('r1'), 'Name 2');
      },
    );

    test('the other device fetches the first rename between the two', () async {
      await tick();
      await phone.renameRoute('r1', 'Name 1');
      await phone.syncNow();
      await pad.syncNow();
      await tick();
      await phone.renameRoute('r1', 'Name 2');
      await phone.sync.push();
      // The pad fetches while the phone's second save is on its way.
      final batch = await phone.bridge.handOut();
      await pad.syncNow();
      await phone.bridge.complete(batch);
      await phone.bridge.sync();
      await pad.syncNow();

      expect(await pad.routeName('r1'), 'Name 2');
    });
  });

  test(
    'a local edit after start is sent without a restart, and once',
    () async {
      await phone.db.routesDao.upsertRoute(fullRoute('r1'));
      await phone.syncNow();
      expect(phone.bridge.pendingSaves, isEmpty);

      phone.sync.start();
      addTearDown(phone.sync.stop);
      await pumpEventQueue();

      await RouteRepository(phone.db.routesDao).rename('r1', 'Renamed');
      // The push waits out a burst of writes (two seconds).
      await _until(() => phone.bridge.pendingSaves.contains('route_r1'));

      await phone.bridge.sync();
      expect(cloud.fields('route_r1')!['name'], 'Renamed');
      expect(await phone.db.syncDao.dirtyRecords(), isEmpty);

      // What the send wrote to sync_records does not send it again.
      await Future<void>.delayed(const Duration(milliseconds: 2500));
      expect(phone.bridge.pendingSaves, isEmpty);
    },
  );
}

/// Waits up to five seconds for [done].
Future<void> _until(bool Function() done) async {
  final until = DateTime.now().add(const Duration(seconds: 5));
  while (!done()) {
    if (DateTime.now().isAfter(until)) fail('timed out');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}
