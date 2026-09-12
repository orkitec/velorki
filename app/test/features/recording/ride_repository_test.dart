import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/features/recording/data/recording_journal.dart';
import 'package:velorki/features/recording/data/recording_service.dart';
import 'package:velorki/features/recording/data/ride_repository.dart';
import 'package:velorki/features/recording/domain/recording_snapshot.dart';
import 'package:velorki/features/recording/domain/recording_state.dart';
import 'package:velorki/features/recording/domain/ride.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'support/fakes.dart';

List<TrackPoint> _track(int count, {double? ele}) => <TrackPoint>[
  for (var i = 0; i < count; i++)
    TrackPoint(
      LatLng(48 + i * 0.0001, 11),
      ele: ele == null ? null : ele + i,
      time: DateTime.utc(2026, 9, 12, 10, 0, i),
    ),
];

void main() {
  late VelorkiDatabase db;
  late RideRepository repository;
  late Directory directory;
  late RecordingStore store;

  setUp(() async {
    db = VelorkiDatabase.memory();
    repository = RideRepository(db.ridesDao);
    directory = await Directory.systemTemp.createTemp('velorki_rides');
    store = RecordingStore(directory);
  });

  tearDown(() async {
    await db.close();
    if (directory.existsSync()) await directory.delete(recursive: true);
  });

  group('RideRepository', () {
    test('finalizeRide writes a row with the packed geometry', () async {
      final ride = await repository.finalizeRide(
        rideId: 'ride-1',
        name: 'Morning loop',
        points: _track(5, ele: 500),
        startedAt: DateTime.utc(2026, 9, 12, 10),
        endedAt: DateTime.utc(2026, 9, 12, 10, 0, 4),
      );

      expect(ride.stats.pointCount, 5);
      final row = await db.ridesDao.rideById('ride-1');
      expect(row, isNotNull);
      expect(row!.name, 'Morning loop');
      expect(row.geometry.first, PackedTrack.version);
      expect(
        row.geometry.length,
        PackedTrack.headerLength + 5 * PackedTrack.bytesPerPoint,
      );
      expect(row.movingTimeS, 4);
      expect(row.elapsedTimeS, 4);
      expect(row.distanceM, closeTo(44.48, 0.1));
      expect(row.avgSpeedMps, closeTo(11.12, 0.05));

      final read = await repository.rideById('ride-1');
      expect(read!.points, hasLength(5));
      expect(read.points.first.pos, const LatLng(48, 11));
      expect(read.bounds!.north, closeTo(48.0004, 1e-9));
      expect(read.stats.distanceM, row.distanceM);
    });

    test('keeps the pauses and the followed route', () async {
      await db.routesDao.upsertRoute(
        RoutesCompanion.insert(
          id: 'route-1',
          name: 'Route',
          source: RouteSource.planned,
          profile: 'trekking',
          createdAt: DateTime.utc(2026, 9, 12),
          updatedAt: DateTime.utc(2026, 9, 12),
          distanceM: 1000,
          ascentM: 10,
          descentM: 10,
          bboxMinLat: 48,
          bboxMinLon: 11,
          bboxMaxLat: 48.1,
          bboxMaxLon: 11.1,
          geometry: PackedTrack.encode(_track(2)),
          waypointsJson: '[]',
          routingOptionsJson: '{}',
        ),
      );

      final ride = await repository.finalizeRide(
        rideId: 'ride-1',
        name: 'Ride',
        points: _track(3),
        startedAt: DateTime.utc(2026, 9, 12, 10),
        endedAt: DateTime.utc(2026, 9, 12, 10, 0, 2),
        routeId: 'route-1',
        pauses: <RidePause>[
          RidePause(
            startedAt: DateTime.utc(2026, 9, 12, 10, 1),
            endedAt: DateTime.utc(2026, 9, 12, 10, 2),
          ),
        ],
      );

      expect(ride.routeId, 'route-1');
      final read = await repository.rideById('ride-1');
      expect(read!.routeId, 'route-1');
      expect(read.pauses, hasLength(1));
      expect(read.pauses.single.duration, const Duration(minutes: 1));
    });

    test(
      'drops the link when the followed route was deleted meanwhile',
      () async {
        final ride = await repository.finalizeRide(
          rideId: 'ride-1',
          name: 'Ride',
          points: _track(3),
          startedAt: DateTime.utc(2026, 9, 12, 10),
          endedAt: DateTime.utc(2026, 9, 12, 10, 0, 2),
          routeId: 'gone',
        );

        expect(ride.routeId, 'gone');
        expect((await repository.rideById('ride-1'))!.routeId, isNull);
      },
    );

    test('renames, deletes and restores', () async {
      final ride = await repository.finalizeRide(
        rideId: 'ride-1',
        name: 'Ride',
        points: _track(3),
        startedAt: DateTime.utc(2026, 9, 12, 10),
        endedAt: DateTime.utc(2026, 9, 12, 10, 0, 2),
      );

      await repository.rename('ride-1', 'Sunday');
      expect((await repository.rideById('ride-1'))!.name, 'Sunday');

      await repository.delete('ride-1');
      expect(await repository.rideById('ride-1'), isNull);

      await repository.save(ride);
      expect((await repository.rideById('ride-1'))!.name, 'Ride');
    });

    test('watchRecentRides keeps only the newest rides', () async {
      for (var i = 0; i < 7; i++) {
        await repository.finalizeRide(
          rideId: 'ride-$i',
          name: 'Ride $i',
          points: <TrackPoint>[
            TrackPoint(
              const LatLng(48, 11),
              time: DateTime.utc(2026, 9, 12 - i, 10),
            ),
            TrackPoint(
              const LatLng(48.0001, 11),
              time: DateTime.utc(2026, 9, 12 - i, 10, 0, 1),
            ),
          ],
          startedAt: DateTime.utc(2026, 9, 12 - i, 10),
          endedAt: DateTime.utc(2026, 9, 12 - i, 10, 0, 1),
        );
      }

      final recent = await repository.watchRecentRides().first;
      expect(recent, hasLength(5));
      expect(recent.first.name, 'Ride 0');
    });
  });

  group('MainIsolateRecordingService', () {
    late FakePositionSource positions;
    late MainIsolateRecordingService service;

    setUp(() {
      positions = FakePositionSource();
      service = MainIsolateRecordingService(
        store: Future<RecordingStore>.value(store),
        rides: repository,
        positions: positions,
        platform: TargetPlatform.iOS,
        clock: () => DateTime.utc(2026, 9, 12, 10),
      );
    });

    tearDown(() async {
      await service.dispose();
      await positions.close();
    });

    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
    }

    test('records a ride from start to the rides row', () async {
      await service.start(notificationTitle: 'Recording');
      expect(await service.isRunning, isTrue);

      final state = await service.pendingState();
      expect(state, isNotNull);
      expect(state!.status, RecordingStatus.active);

      for (var i = 0; i < 4; i++) {
        positions.emit(seconds: i, meters: 10.0 * i);
      }
      await settle();

      final ride = await service.stop(rideName: 'Ride 12 Sept');
      expect(ride, isNotNull);
      expect(ride!.stats.pointCount, 4);
      expect(ride.stats.distanceM, closeTo(30, 0.2));

      expect(await repository.rideById(ride.id), isNotNull);
      expect(await store.readState(), isNull, reason: 'the journal is closed');
      expect(store.journalFile(ride.id).existsSync(), isFalse);
      expect(await service.isRunning, isFalse);
    });

    test('asks for the platform location settings', () async {
      await service.start(notificationTitle: 'Recording');
      await settle();
      expect(positions.settings.single.distanceFilter, 5);
      await service.stop(rideName: 'Ride');
    });

    test('a ride with too little in it is thrown away, not saved', () async {
      await service.start(notificationTitle: 'Recording');
      positions.emit(seconds: 0, meters: 0);
      await settle();

      final ride = await service.stop(rideName: 'Ride');
      expect(ride, isNull);
      expect(await db.ridesDao.allRides(), isEmpty);
      expect(await store.readState(), isNull);
    });

    test('finishes an interrupted recording from its journal alone', () async {
      final state = RecordingState(
        rideId: 'ride-x',
        startedAt: DateTime.utc(2026, 9, 12, 10),
        status: RecordingStatus.active,
      );
      await store.writeState(state);
      final journal = store.openJournal('ride-x');
      await journal.open();
      for (final point in _track(6, ele: 400)) {
        await journal.append(point);
      }
      await journal.close();

      final ride = await service.finishInterrupted(
        state,
        rideName: 'Recovered ride',
      );
      expect(ride, isNotNull);
      expect(ride!.id, 'ride-x');
      expect(ride.stats.pointCount, 6);
      expect(await repository.rideById('ride-x'), isNotNull);
      expect(store.journalFile('ride-x').existsSync(), isFalse);
      expect(await store.readState(), isNull);
    });

    test('resumes an interrupted recording where it left off', () async {
      final state = RecordingState(
        rideId: 'ride-y',
        startedAt: DateTime.utc(2026, 9, 12, 10),
        status: RecordingStatus.paused,
      );
      await store.writeState(state);
      final journal = store.openJournal('ride-y');
      await journal.open();
      for (final point in _track(3)) {
        await journal.append(point);
      }
      await journal.close();

      await service.resumeInterrupted(state, notificationTitle: 'Recording');
      positions.emit(seconds: 3, meters: 40);
      await settle();

      final ride = await service.stop(rideName: 'Resumed');
      expect(ride!.id, 'ride-y');
      expect(ride.stats.pointCount, 4);
    });

    test('discarding an interrupted recording leaves nothing behind', () async {
      final state = RecordingState(
        rideId: 'ride-z',
        startedAt: DateTime.utc(2026, 9, 12, 10),
        status: RecordingStatus.active,
      );
      await store.writeState(state);
      final journal = store.openJournal('ride-z');
      await journal.open();
      for (final point in _track(3)) {
        await journal.append(point);
      }
      await journal.close();

      await service.discardInterrupted(state);
      expect(await store.readState(), isNull);
      expect(store.journalFile('ride-z').existsSync(), isFalse);
      expect(await db.ridesDao.allRides(), isEmpty);
    });
  });
}
