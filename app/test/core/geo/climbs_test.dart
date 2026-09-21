import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/geo/climbs.dart';
import 'package:velorki/core/geo/ride_analysis.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// 20 km/h: a kilometre in exactly three minutes, 5.56 m a second.
const double _twentyKmh = 1000 / 180;

const LatLng _start = LatLng(48.0, 11.0);
final DateTime _t0 = DateTime.utc(2026, 9, 12, 10);

/// A stretch of road: [meters] long at [gradePercent].
typedef _Stretch = ({double meters, double gradePercent});

/// A ride due north at 20 km/h over [road], one fix a second, the height
/// following the grades. [gapAfterM] opens a two minute hole in the
/// timestamps once the ride has come that far, which the analysis reads as a
/// pause.
List<TrackPoint> _ride(
  List<_Stretch> road, {
  double? gapAfterM,
  int? heartRateBpm,
  int? powerW,
}) {
  final points = <TrackPoint>[];
  var position = _start;
  var height = 500.0;
  var along = 0.0;
  var time = _t0;
  var stretch = 0;
  var intoStretch = 0.0;
  var gapOpened = false;
  points.add(
    TrackPoint(
      position,
      ele: height,
      time: time,
      heartRateBpm: heartRateBpm,
      powerW: powerW,
    ),
  );
  while (stretch < road.length) {
    position = destinationPoint(position, 0, _twentyKmh);
    height += _twentyKmh * road[stretch].gradePercent / 100;
    along += _twentyKmh;
    intoStretch += _twentyKmh;
    time = time.add(const Duration(seconds: 1));
    if (gapAfterM != null && !gapOpened && along >= gapAfterM) {
      time = time.add(const Duration(minutes: 2));
      gapOpened = true;
    }
    points.add(
      TrackPoint(
        position,
        ele: height,
        time: time,
        heartRateBpm: heartRateBpm,
        powerW: powerW,
      ),
    );
    if (intoStretch >= road[stretch].meters) {
      stretch++;
      intoStretch = 0;
    }
  }
  return points;
}

const _Stretch _flat500 = (meters: 500, gradePercent: 0);

double _seconds(Duration d) =>
    d.inMicroseconds / Duration.microsecondsPerSecond;

void main() {
  test('a flat ride has no climbs', () {
    final climbs = analyseRide(_ride(const <_Stretch>[_flat500, _flat500]));

    expect(climbs.climbs, isEmpty);
  });

  test('two kilometres at 5 % are one climb of a hundred metres', () {
    final points = _ride(const <_Stretch>[
      _flat500,
      (meters: 2000, gradePercent: 5),
      _flat500,
    ]);

    final climbs = analyseRide(points).climbs;

    expect(climbs, hasLength(1));
    final climb = climbs.single;
    // The heights are smoothed over 20 m either way, so the foot and the top
    // are found a few metres off the exact ones.
    expect(climb.startM, closeTo(500, 40));
    expect(climb.lengthM, closeTo(2000, 60));
    expect(climb.ascentM, closeTo(100, 2));
    expect(climb.avgGradePercent, closeTo(5, 0.2));
    expect(climb.maxGradePercent, closeTo(5, 0.2));
    // Two kilometres at 20 km/h is six minutes.
    expect(_seconds(climb.movingTime), closeTo(360, 12));
    expect(
      climb.vamMPerHour,
      closeTo(climb.ascentM / (_seconds(climb.movingTime) / 3600), 1e-6),
    );
    expect(climb.avgHeartRateBpm, isNull);
    expect(climb.avgPowerW, isNull);
  });

  test('a bump gaining under twenty metres is not a climb, nor is a steep '
      'one shorter than three hundred', () {
    final points = _ride(const <_Stretch>[
      _flat500,
      // 300 m at 5 % is 15 m.
      (meters: 300, gradePercent: 5),
      // Down again, so the next bump stands on its own.
      (meters: 500, gradePercent: -5),
      // 200 m at 12 % is 24 m, but too short a stretch of road.
      (meters: 200, gradePercent: 12),
      (meters: 500, gradePercent: -5),
      _flat500,
    ]);

    expect(analyseRide(points).climbs, isEmpty);
  });

  test('two bumps with a flat between them are one climb only if the whole '
      'averages three percent', () {
    // 400 m at 5 % is 20 m; with a kilometre of flat between two of them
    // the pair gains 40 m over 1.8 km, 2.2 %: not a climb. With a hundred
    // metres of flat it is 40 m over 900 m, 4.4 %: one climb.
    const bump = (meters: 400.0, gradePercent: 5.0);
    final apart = _ride(const <_Stretch>[
      _flat500,
      bump,
      (meters: 1000, gradePercent: 0),
      bump,
      _flat500,
    ]);
    final close = _ride(const <_Stretch>[
      _flat500,
      bump,
      (meters: 100, gradePercent: 0),
      bump,
      _flat500,
    ]);

    expect(analyseRide(apart).climbs, isEmpty);
    expect(analyseRide(close).climbs, hasLength(1));
    expect(analyseRide(close).climbs.single.ascentM, closeTo(40, 2));
  });

  test('a descent between two climbs separates them', () {
    final points = _ride(const <_Stretch>[
      _flat500,
      (meters: 1000, gradePercent: 5),
      (meters: 500, gradePercent: -5),
      (meters: 1000, gradePercent: 5),
      _flat500,
    ]);

    final climbs = analyseRide(points).climbs;

    expect(climbs, hasLength(2));
    expect(climbs.first.ascentM, closeTo(50, 2));
    expect(climbs.last.ascentM, closeTo(50, 2));
    expect(climbs.last.startM, greaterThan(climbs.first.startM + 1000));
  });

  test('a dip of under ten metres does not cut a climb in two', () {
    final points = _ride(const <_Stretch>[
      _flat500,
      (meters: 1000, gradePercent: 5),
      (meters: 100, gradePercent: -5),
      (meters: 1000, gradePercent: 5),
      _flat500,
    ]);

    final climbs = analyseRide(points).climbs;

    expect(climbs, hasLength(1));
    expect(climbs.single.ascentM, closeTo(95, 2));
  });

  test('a pause inside a climb counts towards neither its time nor its '
      'speed', () {
    final points = _ride(const <_Stretch>[
      _flat500,
      (meters: 2000, gradePercent: 5),
      _flat500,
    ], gapAfterM: 1500);

    final climb = analyseRide(points).climbs.single;

    expect(_seconds(climb.movingTime), closeTo(360, 12));
    expect(climb.ascentM, closeTo(100, 2));
    expect(climb.vamMPerHour, closeTo(1000, 40));
  });

  test('the heart rate and the power over the climb are the readings', () {
    final points = _ride(
      const <_Stretch>[_flat500, (meters: 2000, gradePercent: 5), _flat500],
      heartRateBpm: 155,
      powerW: 240,
    );

    final climb = analyseRide(points).climbs.single;

    expect(climb.avgHeartRateBpm, 155);
    expect(climb.avgPowerW, 240);
  });

  test('the steepest window is the steepest hundred metres', () {
    final points = _ride(const <_Stretch>[
      _flat500,
      (meters: 800, gradePercent: 4),
      (meters: 200, gradePercent: 10),
      (meters: 800, gradePercent: 4),
      _flat500,
    ]);

    final climb = analyseRide(points).climbs.single;

    expect(climb.avgGradePercent, closeTo(4.7, 0.2));
    expect(climb.maxGradePercent, closeTo(10, 0.5));
  });

  test('detectClimbs reads legs without heights as flat', () {
    final legs = <ClimbLeg>[
      for (var i = 0; i < 100; i++)
        ClimbLeg(
          fromM: i * 10,
          toM: (i + 1) * 10,
          fromEle: null,
          toEle: null,
          duration: const Duration(seconds: 2),
          moving: true,
          isBreak: false,
        ),
    ];

    expect(detectClimbs(legs), isEmpty);
    expect(detectClimbs(const <ClimbLeg>[]), isEmpty);
  });

  test('a climb reads back in a line', () {
    const climb = RideClimb(
      startM: 1200,
      lengthM: 2000,
      ascentM: 100,
      maxGradePercent: 8,
      movingTime: Duration(minutes: 6),
    );

    expect(
      climb.toString(),
      'RideClimb(at 1200 m, 2000 m, +100 m, 5.0 %, '
      '0:06:00.000000)',
    );
    expect(climb.vamMPerHour, closeTo(1000, 1e-9));
  });
}
