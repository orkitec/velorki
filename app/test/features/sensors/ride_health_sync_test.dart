import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/features/recording/data/ride_repository.dart';
import 'package:velorki/features/recording/domain/ride.dart';
import 'package:velorki/features/sensors/application/ride_health_sync.dart';
import 'package:velorki/features/sensors/data/health_gateway.dart';
import 'package:velorki/features/sensors/data/sensor_settings.dart';
import 'package:velorki/features/sensors/testing/fake_health_gateway.dart';
import 'package:velorki_geo/velorki_geo.dart';

final DateTime _start = DateTime.utc(2026, 9, 18, 9);

/// A minute of riding, one fix a second, [live] of them already carrying a
/// heart rate a strap reported live.
List<TrackPoint> _track({Set<int> live = const <int>{}}) => <TrackPoint>[
  for (var i = 0; i < 60; i++)
    TrackPoint(
      LatLng(48 + i * 0.0002, 11),
      ele: 500,
      time: _start.add(Duration(seconds: i)),
      heartRateBpm: live.contains(i) ? 99 : null,
    ),
];

HeartRateSample _sample(int bpm, int second) => HeartRateSample(
  bpm: bpm,
  at: _start.add(Duration(seconds: second)),
  sourceName: 'Watch',
);

void main() {
  late VelorkiDatabase db;
  late RideRepository rides;
  late FakeHealthGateway gateway;
  late SharedPreferences prefs;

  setUp(() async {
    db = VelorkiDatabase.memory();
    rides = RideRepository(db.ridesDao);
    gateway = FakeHealthGateway();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
  });

  tearDown(() => db.close());

  Future<Ride> seed({Set<int> live = const <int>{}}) => rides.finalizeRide(
    rideId: 'ride-1',
    name: 'Evening loop',
    points: _track(live: live),
    startedAt: _start,
    endedAt: _start.add(const Duration(seconds: 59)),
  );

  RideHealthSync sync({
    bool health = true,
    bool write = true,
    bool hasStore = true,
  }) => RideHealthSync(
    rides: rides,
    prefs: prefs,
    settings: SensorSettings(health: health, healthWrite: write),
    gateway: hasStore ? gateway : null,
  );

  Future<Ride> reload() async => (await rides.rideById('ride-1'))!;

  test('with Health off nothing is read and nothing is written', () async {
    final ride = await seed();
    gateway.samples.add(_sample(140, 10));

    await sync(health: false).afterRide(ride);

    expect(gateway.queries, isEmpty);
    expect(gateway.workouts, isEmpty);
    expect((await reload()).stats.avgHeartRateBpm, isNull);
  });

  test('every fix takes the nearest sample', () async {
    final ride = await seed();
    gateway.samples.addAll([_sample(120, 0), _sample(160, 59)]);

    await sync().afterRide(ride);

    final beats = (await reload()).points.map((p) => p.heartRateBpm).toList();
    expect(beats.first, 120);
    expect(beats[20], 120, reason: 'still closer to the first sample');
    expect(beats[40], 160, reason: 'closer to the second');
    expect(beats.last, 160);
  });

  test('a fix more than half a minute from any sample keeps none', () async {
    final ride = await seed();
    gateway.samples.add(_sample(120, 0));

    await sync().afterRide(ride);

    final beats = (await reload()).points.map((p) => p.heartRateBpm).toList();
    expect(beats[30], 120, reason: 'exactly at the window');
    expect(beats[31], isNull);
    expect(beats.last, isNull);
  });

  test('a fix that already has a live reading is left alone', () async {
    final ride = await seed(live: <int>{0, 1, 2});
    gateway.samples.addAll([_sample(120, 0), _sample(121, 1), _sample(122, 2)]);

    await sync().afterRide(ride);

    final saved = await reload();
    expect(saved.points.take(3).map((p) => p.heartRateBpm), <int>[
      99,
      99,
      99,
    ], reason: 'the strap won');
  });

  test('the statistics are recomputed from the filled track', () async {
    final ride = await seed();
    expect(ride.stats.avgHeartRateBpm, isNull);
    gateway.samples.addAll([
      for (var i = 0; i < 60; i += 5) _sample(140 + i, i),
    ]);

    await sync().afterRide(ride);

    final saved = await reload();
    expect(saved.stats.avgHeartRateBpm, isNotNull);
    expect(saved.stats.maxHeartRateBpm, 195);
    expect(
      saved.stats.distanceM,
      closeTo(ride.stats.distanceM, 0.001),
      reason: 'only the heart rate changed',
    );
    expect(saved.stats.pointCount, ride.stats.pointCount);
    expect(saved.name, ride.name);
  });

  test('nothing is rewritten when there is nothing to attach', () async {
    final ride = await seed();

    await sync().afterRide(ride);

    expect(gateway.queries, hasLength(1));
    expect((await reload()).stats.avgHeartRateBpm, isNull);
  });

  test('the ride is written as a workout, once', () async {
    final ride = await seed();
    gateway.samples.add(_sample(150, 30));

    await sync().afterRide(ride);
    await sync().afterRide(await reload());

    expect(gateway.workouts, hasLength(1));
    final workout = gateway.workouts.single;
    expect(workout.start, ride.startedAt);
    expect(workout.end, ride.endedAt);
    expect(workout.distanceM, closeTo(ride.stats.distanceM, 0.001));
    expect(workout.avgHeartRateBpm, 150);
    expect(prefs.getStringList(prefsHealthWorkoutsWritten), <String>['ride-1']);
  });

  test('a refused write is not remembered as written', () async {
    final ride = await seed();
    gateway.writeSucceeds = false;

    await sync().afterRide(ride);

    expect(gateway.workouts, hasLength(1));
    expect(prefs.getStringList(prefsHealthWorkoutsWritten), isNull);
  });

  test('with the writing switched off only the attach runs', () async {
    final ride = await seed();
    gateway.samples.add(_sample(150, 30));

    await sync(write: false).afterRide(ride);

    expect(gateway.workouts, isEmpty);
    expect((await reload()).stats.avgHeartRateBpm, 150);
  });

  test('a platform without a health store does nothing', () async {
    final ride = await seed();
    gateway.samples.add(_sample(150, 30));

    await sync(hasStore: false).afterRide(ride);

    expect(gateway.queries, isEmpty);
    expect(gateway.workouts, isEmpty);
  });
}
