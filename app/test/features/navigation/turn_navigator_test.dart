import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/navigation/application/turn_navigator.dart';
import 'package:velorki/features/navigation/domain/navigation_progress.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// Metres in one degree of latitude on the sphere the geo package uses.
const double _mPerDegLat = earthRadiusMeters * math.pi / 180;

/// Metres in one degree of longitude at 47° N.
final double _mPerDegLon = _mPerDegLat * math.cos(47.0 * math.pi / 180);

const double _lat0 = 47.0;
const double _lon0 = 8.0;

/// An L: a kilometre east from (47, 8), then a kilometre north, in 100 m
/// steps. 21 points, the corner at index 10, the end at index 20.
final List<LatLng> _line = <LatLng>[
  for (var i = 0; i <= 10; i++) LatLng(_lat0, _lon0 + i * 100 / _mPerDegLon),
  for (var i = 1; i <= 10; i++)
    LatLng(_lat0 + i * 100 / _mPerDegLat, _lon0 + 1000 / _mPerDegLon),
];

/// The point [alongM] metres into the L, optionally [offsetM] metres to the
/// side of it (north of the east leg, east of the north leg).
LatLng _at(double alongM, {double offsetM = 0}) => alongM <= 1000
    ? LatLng(_lat0 + offsetM / _mPerDegLat, _lon0 + alongM / _mPerDegLon)
    : LatLng(
        _lat0 + (alongM - 1000) / _mPerDegLat,
        _lon0 + (1000 + offsetM) / _mPerDegLon,
      );

const TurnHint _left = TurnHint(
  pointIndex: 10,
  kind: TurnKind.left,
  distanceToNextM: 1000,
);
const TurnHint _end = TurnHint(pointIndex: 20, kind: TurnKind.end);

TurnNavigator _navigator({List<TurnHint>? turns}) =>
    TurnNavigator(line: _line, turns: turns ?? const [_left, _end]);

void main() {
  test('the line is the length it was built to be', () {
    expect(_navigator().totalM, closeTo(2000, 2));
  });

  test('riding towards the corner shortens the way to the turn', () {
    final navigator = _navigator();

    final start = navigator.update(_at(0));
    final quarter = navigator.update(_at(300));
    final nearly = navigator.update(_at(900));

    expect(start.next, _left);
    expect(start.after, _end);
    expect(start.distanceToNextM, closeTo(1000, 3));
    expect(start.alongM, closeTo(0, 3));
    expect(start.remainingM, closeTo(2000, 3));
    expect(quarter.distanceToNextM, closeTo(700, 3));
    expect(nearly.distanceToNextM, closeTo(100, 3));
    expect(nearly.offRoute, isFalse);
    expect(nearly.arrived, isFalse);
  });

  test('a fix 20 m beside the line still lands on it', () {
    final navigator = _navigator();

    final progress = navigator.update(_at(500, offsetM: 20));

    expect(progress.alongM, closeTo(500, 3));
    expect(progress.distanceToNextM, closeTo(500, 3));
    expect(progress.offRoute, isFalse);
    // And the matched point is on the line itself, 20 m south of the fix:
    // that is where the puck is drawn while the rider is on the route.
    expect(progress.distanceFromRouteM, closeTo(20, 1));
    expect(progress.snapped!.lat, closeTo(_lat0, 1e-9));
    expect(progress.snapped!.lon, closeTo(_lon0 + 500 / _mPerDegLon, 1e-7));
  });

  test('the bearing comes from the leg the rider is on', () {
    final navigator = _navigator();

    // Due east on the first leg of the L, due north on the second.
    expect(navigator.update(_at(500)).routeBearingDeg, closeTo(90, 0.5));
    expect(navigator.update(_at(1500)).routeBearingDeg, closeTo(0, 0.5));
  });

  test('a route of a single point has no bearing and no distance off it', () {
    final navigator = TurnNavigator(
      line: <LatLng>[_at(0)],
      turns: const <TurnHint>[],
    );

    final progress = navigator.update(_at(0, offsetM: 10));

    expect(progress.routeBearingDeg, isNull);
    expect(progress.snapped, _at(0));
    expect(progress.distanceFromRouteM, closeTo(10, 1));
  });

  test('past the corner the end becomes the next turn', () {
    final navigator = _navigator();
    navigator.update(_at(500));

    final past = navigator.update(_at(1100));

    expect(past.next, _end);
    expect(past.after, isNull);
    expect(past.distanceToNextM, closeTo(900, 3));
    expect(past.remainingM, closeTo(900, 3));
  });

  test('the corner itself has not been passed yet', () {
    final navigator = _navigator();

    final atCorner = navigator.update(_at(1000));

    expect(atCorner.next, _left);
    expect(atCorner.distanceToNextM, closeTo(0, 1));
  });

  test(
    'two fixes 80 m out call the rider off route, one back on clears it',
    () {
      final navigator = _navigator();
      navigator.update(_at(400));

      // One fix thrown out by a bridge is not a detour.
      expect(navigator.update(_at(500, offsetM: 80)).offRoute, isFalse);
      expect(navigator.update(_at(520, offsetM: 80)).offRoute, isTrue);
      expect(navigator.update(_at(540, offsetM: 80)).offRoute, isTrue);

      expect(navigator.update(_at(560)).offRoute, isFalse);
    },
  );

  test('one stray fix for eight seconds is off route on its own', () {
    final navigator = _navigator();
    final start = DateTime.utc(2026, 9, 12, 10);
    navigator.update(_at(400), now: start);

    final first = navigator.update(_at(500, offsetM: 80), now: start);
    expect(first.offRoute, isFalse);

    // The next fix is the same one, a receiver that reports rarely; it is the
    // clock, not the count, that calls the rider off route here.
    expect(
      navigator
          .update(
            _at(500, offsetM: 80),
            now: start.add(const Duration(seconds: 9)),
          )
          .offRoute,
      isTrue,
    );
  });

  test('a fix 40 m out stays on route but does not clear an old stray', () {
    final navigator = _navigator();
    for (var i = 0; i < 3; i++) {
      navigator.update(_at(500 + i * 20, offsetM: 80));
    }
    expect(navigator.update(_at(560, offsetM: 80)).offRoute, isTrue);

    // Inside the stray limit but outside the snap limit: still off.
    expect(navigator.update(_at(580, offsetM: 40)).offRoute, isTrue);
    expect(navigator.update(_at(600, offsetM: 10)).offRoute, isFalse);
  });

  test('a navigator resumed part-way matches there, not at the start', () {
    final navigator = TurnNavigator(
      line: _line,
      turns: const [_left, _end],
      resumeAlongM: 1500,
    );

    final progress = navigator.update(_at(1500));

    expect(progress.alongM, closeTo(1500, 3));
    expect(progress.next, _end);
  });

  test('the last point is an arrival', () {
    final navigator = _navigator();
    navigator.update(_at(1500));

    final arrived = navigator.update(_at(2000));

    expect(arrived.arrived, isTrue);
    expect(arrived.remainingM, closeTo(0, 3));
    expect(arrived.next, _end);

    expect(navigator.update(_at(1800)).arrived, isFalse);
  });

  test('a hint pointing past the end of the line is dropped', () {
    final navigator = _navigator(
      turns: const [
        _left,
        _end,
        TurnHint(pointIndex: 99, kind: TurnKind.right),
      ],
    );

    final past = navigator.update(_at(1100));

    expect(navigator.announcedTurns, const [_left, _end]);
    expect(past.next, _end);
    expect(past.after, isNull);
  });

  test('straight, beeline and off-road hints are never announced', () {
    final navigator = _navigator(
      turns: const [
        TurnHint(pointIndex: 3, kind: TurnKind.straight),
        TurnHint(pointIndex: 5, kind: TurnKind.beeline),
        TurnHint(pointIndex: 7, kind: TurnKind.offRoad),
        _left,
        _end,
      ],
    );

    final start = navigator.update(_at(0));

    expect(navigator.announcedTurns, const [_left, _end]);
    expect(start.next, _left);
    expect(start.after, _end);
    expect(start.distanceToNextM, closeTo(1000, 3));
  });

  test('a route without turns still reports progress and arrival', () {
    final navigator = TurnNavigator(line: _line, turns: const []);

    final halfway = navigator.update(_at(1000));
    final done = navigator.update(_at(2000));

    expect(halfway.next, isNull);
    expect(halfway.distanceToNextM, 0);
    expect(halfway.remainingM, closeTo(1000, 3));
    expect(done.arrived, isTrue);
  });

  test('a loop is not an arrival at its own start', () {
    // A square: east, north, west, south, 500 m a side, back to the start.
    // Saved before turn hints existed, so it carries none, which used to
    // make "near the end" enough for an arrival.
    final square = <LatLng>[
      for (var i = 0; i <= 5; i++) LatLng(_lat0, _lon0 + i * 100 / _mPerDegLon),
      for (var i = 1; i <= 5; i++)
        LatLng(_lat0 + i * 100 / _mPerDegLat, _lon0 + 500 / _mPerDegLon),
      for (var i = 1; i <= 5; i++)
        LatLng(
          _lat0 + 500 / _mPerDegLat,
          _lon0 + (500 - i * 100) / _mPerDegLon,
        ),
      for (var i = 1; i <= 5; i++)
        LatLng(_lat0 + (500 - i * 100) / _mPerDegLat, _lon0),
    ];
    final navigator = TurnNavigator(line: square, turns: const []);

    // The first fix sits a few metres from the start, which is also the
    // end. It must count as the start.
    final first = navigator.update(
      LatLng(_lat0 + 3 / _mPerDegLat, _lon0 + 5 / _mPerDegLon),
    );
    expect(first.arrived, isFalse);
    expect(first.alongM, lessThan(50));
    expect(first.remainingM, greaterThan(1900));

    // Round the square, then home: now it is an arrival.
    for (final along in <double>[300, 600, 900, 1200, 1500, 1800, 1950]) {
      final leg = along ~/ 500;
      final into = along - leg * 500;
      final point = switch (leg) {
        0 => LatLng(_lat0, _lon0 + into / _mPerDegLon),
        1 => LatLng(_lat0 + into / _mPerDegLat, _lon0 + 500 / _mPerDegLon),
        2 => LatLng(
          _lat0 + 500 / _mPerDegLat,
          _lon0 + (500 - into) / _mPerDegLon,
        ),
        _ => LatLng(_lat0 + (500 - into) / _mPerDegLat, _lon0),
      };
      expect(navigator.update(point).arrived, isFalse, reason: 'at $along m');
    }
    final home = navigator.update(
      LatLng(_lat0 + 3 / _mPerDegLat, _lon0 + 2 / _mPerDegLon),
    );
    expect(home.arrived, isTrue);
  });

  test('an empty line reports nothing at all', () {
    final navigator = TurnNavigator(line: const [], turns: const [_left]);

    expect(navigator.update(_at(0)), const NavigationProgress());
    expect(navigator.totalM, 0);
  });
}
