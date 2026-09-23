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
import 'package:velorki/features/recording/domain/ride_upload.dart';
import 'package:velorki_brouter/velorki_brouter.dart' show SurfaceStats;
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

    test('the sensor averages go into the row and come back', () async {
      final points = <TrackPoint>[
        for (final (i, point) in _track(4).indexed)
          point.copyWith(
            heartRateBpm: 140 + i * 10,
            cadenceRpm: 80,
            powerW: 200 + i,
          ),
      ];

      final ride = await repository.finalizeRide(
        rideId: 'ride-1',
        name: 'Morning loop',
        points: points,
        startedAt: DateTime.utc(2026, 9, 12, 10),
        endedAt: DateTime.utc(2026, 9, 12, 10, 0, 3),
      );

      expect(ride.stats.avgHeartRateBpm, 155);
      expect(ride.stats.maxHeartRateBpm, 170);

      final row = await db.ridesDao.rideById('ride-1');
      expect(row!.avgHeartRateBpm, 155);
      expect(row.maxHeartRateBpm, 170);
      expect(row.avgCadenceRpm, 80);
      expect(row.avgPowerW, 202);

      final read = await repository.rideById('ride-1');
      expect(read!.stats.avgHeartRateBpm, 155);
      expect(read.stats.maxHeartRateBpm, 170);
      expect(read.stats.avgCadenceRpm, 80);
      expect(read.stats.avgPowerW, 202);
      expect(read.points.last.powerW, 203);
    });

    test('a ride without sensors leaves the columns null', () async {
      await repository.finalizeRide(
        rideId: 'ride-1',
        name: 'Morning loop',
        points: _track(4),
        startedAt: DateTime.utc(2026, 9, 12, 10),
        endedAt: DateTime.utc(2026, 9, 12, 10, 0, 3),
      );

      final row = await db.ridesDao.rideById('ride-1');
      expect(row!.avgHeartRateBpm, isNull);
      expect(row.maxHeartRateBpm, isNull);
      expect(row.avgCadenceRpm, isNull);
      expect(row.avgPowerW, isNull);
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

    test('the matched surface goes into the row and comes back', () async {
      await repository.finalizeRide(
        rideId: 'ride-1',
        name: 'Morning loop',
        points: _track(5),
        startedAt: DateTime.utc(2026, 9, 12, 10),
        endedAt: DateTime.utc(2026, 9, 12, 10, 0, 4),
      );
      expect((await repository.rideById('ride-1'))!.surface, isNull);

      const stats = SurfaceStats(
        pavedShare: 0.7,
        unpavedShare: 0.2,
        unknownShare: 0.1,
        cyclewayShare: 0.3,
        busyShare: 0.05,
        coveredLengthM: 2950,
        totalLengthM: 3000,
      );
      await repository.setSurface('ride-1', stats);
      final matched = (await repository.rideById('ride-1'))!;
      expect(matched.surfaceStats, stats);
      expect(matched.surface!.unavailable, isFalse);

      // Saving the ride as it is, as an undo does, keeps the surface.
      await repository.save(matched);
      expect((await repository.rideById('ride-1'))!.surfaceStats, stats);

      await repository.markSurfaceUnavailable('ride-1');
      final marked = (await repository.rideById('ride-1'))!;
      expect(marked.surfaceStats, isNull);
      expect(marked.surface, RideSurfaceCache.unmatched);
      await repository.save(marked);
      expect(
        (await repository.rideById('ride-1'))!.surface,
        RideSurfaceCache.unmatched,
      );
    });

    test('the laps, the device totals and the temperatures go into the row '
        'and come back', () async {
      final ride = await repository.finalizeRide(
        rideId: 'ride-1',
        name: 'From a device',
        points: _track(5, ele: 500),
        startedAt: DateTime.utc(2026, 9, 12, 10),
        endedAt: DateTime.utc(2026, 9, 12, 10, 0, 4),
      );
      final laps = [
        RideLap(
          startedAt: DateTime.utc(2026, 9, 12, 10),
          endedAt: DateTime.utc(2026, 9, 12, 10, 0, 2),
          distanceM: 22.2,
          movingTime: const Duration(seconds: 2),
          calories: 3,
        ),
        RideLap(
          startedAt: DateTime.utc(2026, 9, 12, 10, 0, 2),
          endedAt: DateTime.utc(2026, 9, 12, 10, 0, 4),
        ),
      ];
      const totals = DeviceTotals(
        distanceM: 45.5,
        movingTime: Duration(seconds: 4),
        elapsedTime: Duration(seconds: 5),
        calories: 6,
        ascentM: 1,
        descentM: 0,
      );
      await repository.save(
        Ride(
          id: ride.id,
          name: ride.name,
          startedAt: ride.startedAt,
          endedAt: ride.endedAt,
          stats: ride.stats,
          geometry: ride.geometry,
          laps: laps,
          deviceTotals: totals,
          temperaturesC: const [14.5, null, -3.2, 20, 21.7],
        ),
      );
      final read = (await repository.rideById('ride-1'))!;
      expect(read.laps, hasLength(2));
      expect(read.laps.first.endedAt, DateTime.utc(2026, 9, 12, 10, 0, 2));
      expect(read.laps.first.distanceM, 22.2);
      expect(read.laps.first.movingTime, const Duration(seconds: 2));
      expect(read.laps.first.calories, 3);
      expect(read.laps.last.distanceM, isNull);
      expect(read.deviceTotals!.distanceM, 45.5);
      expect(read.deviceTotals!.elapsedTime, const Duration(seconds: 5));
      expect(read.deviceTotals!.calories, 6);
      expect(read.temperaturesC, [14.5, null, -3.2, 20, 21.7]);
      // A ride recorded here has none of it.
      expect(ride.laps, isEmpty);
      expect(ride.deviceTotals, isNull);
      expect(ride.temperaturesC, isEmpty);
    });

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

    /// A second recorder on a clock the test moves, because continuing a ride
    /// happens at a moment after the ride ended rather than at a pinned one.
    late MainIsolateRecordingService continuing;
    var now = DateTime.utc(2026, 9, 12, 10);

    setUp(() {
      now = DateTime.utc(2026, 9, 12, 10);
      continuing = MainIsolateRecordingService(
        store: Future<RecordingStore>.value(store),
        rides: repository,
        positions: positions,
        platform: TargetPlatform.iOS,
        clock: () => now,
      );
      addTearDown(continuing.dispose);
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

    test('continues a saved ride onto its own row', () async {
      // A ride of six fixes, already sent to Strava.
      final saved = await repository.finalizeRide(
        rideId: 'ride-1',
        name: 'Morning loop',
        points: _track(6, ele: 500),
        startedAt: DateTime.utc(2026, 9, 12, 10),
        endedAt: DateTime.utc(2026, 9, 12, 10, 0, 5),
      );
      await repository.recordUpload(
        'ride-1',
        serviceId: 'strava',
        upload: RideUpload(
          status: RideUploadStatus.done,
          uploadedAt: DateTime.utc(2026, 9, 12, 11),
          activityId: '99',
        ),
      );
      final before = (await repository.rideById('ride-1'))!;
      expect(before.uploads, isNotEmpty);
      expect(before.stats.distanceM, closeTo(55.6, 0.1));

      // Two seconds after it was stopped, the rider picks it up again.
      now = DateTime.utc(2026, 9, 12, 10, 0, 7);
      await continuing.continueRide(before, notificationTitle: 'Recording');

      final state = await store.readState();
      expect(state!.rideId, 'ride-1');
      expect(state.startedAt, saved.startedAt, reason: 'the start is kept');
      expect(state.isContinuation, isTrue);
      expect(state.pauses.last.seam, isTrue);
      expect(state.pauses.last.startedAt, saved.endedAt);
      expect(state.pauses.last.endedAt, now);
      expect(await store.readJournal('ride-1'), hasLength(6));
      expect(
        (await repository.rideById('ride-1'))!.uploads,
        isEmpty,
        reason: 'a continued ride has to be sent again',
      );

      // Three more fixes, the first of them across the seam.
      positions.emit(seconds: 8, meters: 66.7, ele: 510);
      positions.emit(seconds: 9, meters: 77.8, ele: 515);
      positions.emit(seconds: 10, meters: 88.9, ele: 520);
      await settle();

      final ride = await continuing.stop(rideName: 'Ride 12 Sept');
      expect(ride!.id, 'ride-1');
      expect(ride.name, 'Morning loop', reason: 'the name the rider gave it');
      expect(ride.startedAt, DateTime.utc(2026, 9, 12, 10));
      expect(ride.endedAt, DateTime.utc(2026, 9, 12, 10, 0, 10));
      expect(ride.points, hasLength(9), reason: 'the geometry is merged');
      expect(ride.points.first.time, DateTime.utc(2026, 9, 12, 10));
      // 55.6 m ridden before, 22.2 m after; the 11 m across the seam is not
      // a ridden distance and the two seconds are not moving time.
      expect(ride.stats.distanceM, closeTo(77.8, 0.2));
      expect(ride.stats.movingTime, const Duration(seconds: 7));
      expect(ride.stats.elapsedTime, const Duration(seconds: 10));
      // 3 m climbed before the seam and 10 m after it; the 5 m step across
      // the seam is not a climb, it is where the ride was picked up.
      expect(ride.stats.ascentM, closeTo(13, 0.001));
      expect(ride.uploads, isEmpty);
      expect(ride.pauses.where((p) => p.seam), hasLength(1));
      expect(await db.ridesDao.allRides(), hasLength(1));
      expect(store.journalFile('ride-1').existsSync(), isFalse);
      expect(await store.readState(), isNull);
    });

    test('a second continue keeps the first seam a break', () async {
      final saved = await repository.finalizeRide(
        rideId: 'ride-2',
        name: 'Evening loop',
        points: _track(3),
        startedAt: DateTime.utc(2026, 9, 12, 10),
        endedAt: DateTime.utc(2026, 9, 12, 10, 0, 2),
      );

      now = DateTime.utc(2026, 9, 12, 10, 0, 3);
      await continuing.continueRide(saved, notificationTitle: 'Recording');
      positions.emit(seconds: 4, meters: 44.5);
      positions.emit(seconds: 5, meters: 55.6);
      await settle();
      final once = await continuing.stop(rideName: 'unused');
      expect(once!.stats.distanceM, closeTo(33.4, 0.2));

      now = DateTime.utc(2026, 9, 12, 10, 0, 6);
      await continuing.continueRide(once, notificationTitle: 'Recording');
      positions.emit(seconds: 7, meters: 66.7);
      positions.emit(seconds: 8, meters: 77.8);
      await settle();
      final twice = await continuing.stop(rideName: 'unused');

      expect(twice!.id, 'ride-2');
      expect(twice.name, 'Evening loop');
      expect(twice.points, hasLength(7));
      expect(twice.pauses.where((p) => p.seam), hasLength(2));
      // Neither seam was ridden: 22.2 + 11.1 + 11.1 m.
      expect(twice.stats.distanceM, closeTo(44.5, 0.3));
      expect(twice.stats.movingTime, const Duration(seconds: 4));
      expect(await db.ridesDao.allRides(), hasLength(1));
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
