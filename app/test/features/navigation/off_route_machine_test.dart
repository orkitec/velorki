import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/navigation/application/off_route_machine.dart';
import 'package:velorki/features/navigation/application/route_geometry.dart';
import 'package:velorki/features/navigation/domain/off_route_guidance.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// Metres in one degree of latitude on the sphere the geo package uses.
const double _mPerDegLat = earthRadiusMeters * math.pi / 180;

/// Metres in one degree of longitude at 48°.
final double _mPerDegLon = _mPerDegLat * math.cos(48 * math.pi / 180);

/// A point [alongM] north of 48°/11°, [asideM] metres east of the line.
LatLng _at(double alongM, {double asideM = 0}) =>
    LatLng(48 + alongM / _mPerDegLat, 11 + asideM / _mPerDegLon);

/// Ten kilometres due north, a point every 100 m.
final List<LatLng> _line = <LatLng>[
  for (var i = 0; i <= 100; i++) _at(i * 100.0),
];

final DateTime _t0 = DateTime.utc(2026, 9, 12, 10);

/// Feeds one fix to [machine] with the everyday defaults.
OffRouteDecision _fix(
  OffRouteMachine machine,
  LatLng position, {
  required double distanceFromRouteM,
  double alongM = 0,
  double speedMps = 6,
  double? headingDeg = 0,
  Duration at = Duration.zero,
  bool rerouteAllowed = true,
  double? distanceFromDetourM,
}) => machine.update(
  position: position,
  distanceFromRouteM: distanceFromRouteM,
  alongM: alongM,
  speedMps: speedMps,
  headingDeg: headingDeg,
  now: _t0.add(at),
  rerouteAllowed: rerouteAllowed,
  distanceFromDetourM: distanceFromDetourM,
);

OffRouteMachine _machine() => OffRouteMachine(line: _line);

void main() {
  group('hysteresis', () {
    test('one stray fix is noise, not a detour', () {
      final machine = _machine();

      final decision = _fix(
        machine,
        _at(300, asideM: 80),
        distanceFromRouteM: 80,
        alongM: 300,
      );

      expect(decision.state, OffRouteState.onRoute);
      expect(decision.guidance, isNull);
    });

    test('two stray fixes in a row are', () {
      final machine = _machine();
      _fix(machine, _at(300, asideM: 80), distanceFromRouteM: 80, alongM: 300);

      final decision = _fix(
        machine,
        _at(320, asideM: 90),
        distanceFromRouteM: 90,
        alongM: 300,
        at: const Duration(seconds: 1),
      );

      expect(decision.state, OffRouteState.guiding);
      expect(decision.guidance, isNotNull);
    });

    test('a fix that comes back inside fifty metres starts the count over', () {
      final machine = _machine();
      _fix(machine, _at(300, asideM: 80), distanceFromRouteM: 80, alongM: 300);
      _fix(
        machine,
        _at(320, asideM: 10),
        distanceFromRouteM: 10,
        alongM: 320,
        at: const Duration(seconds: 1),
      );

      final decision = _fix(
        machine,
        _at(340, asideM: 80),
        distanceFromRouteM: 80,
        alongM: 320,
        at: const Duration(seconds: 2),
      );

      expect(decision.state, OffRouteState.onRoute);
    });

    test('one stray fix held for eight seconds is a detour on its own', () {
      final machine = _machine();
      _fix(machine, _at(300, asideM: 80), distanceFromRouteM: 80, alongM: 300);

      // The same fix again, from a receiver that reports rarely.
      final decision = machine.update(
        position: _at(300, asideM: 80),
        distanceFromRouteM: 80,
        alongM: 300,
        speedMps: 6,
        headingDeg: 0,
        now: _t0.add(const Duration(seconds: 9)),
        rerouteAllowed: true,
      );

      expect(decision.state, OffRouteState.guiding);
    });

    test('one fix within the snap distance puts the rider back on', () {
      final machine = _machine();
      _fix(machine, _at(300, asideM: 80), distanceFromRouteM: 80, alongM: 300);
      _fix(
        machine,
        _at(320, asideM: 90),
        distanceFromRouteM: 90,
        alongM: 300,
        at: const Duration(seconds: 1),
      );

      final decision = _fix(
        machine,
        _at(340, asideM: 20),
        distanceFromRouteM: 20,
        alongM: 300,
        at: const Duration(seconds: 2),
      );

      expect(decision.state, OffRouteState.onRoute);
      expect(decision.restored, isTrue);
    });

    test('thirty metres out is off the route but not back on it', () {
      final machine = _machine();
      _fix(machine, _at(300, asideM: 80), distanceFromRouteM: 80, alongM: 300);
      _fix(
        machine,
        _at(320, asideM: 90),
        distanceFromRouteM: 90,
        alongM: 300,
        at: const Duration(seconds: 1),
      );

      final decision = _fix(
        machine,
        _at(340, asideM: 30),
        distanceFromRouteM: 30,
        alongM: 300,
        at: const Duration(seconds: 2),
      );

      expect(decision.state, OffRouteState.guiding);
    });
  });

  group('guiding', () {
    /// Puts [machine] into the guiding state 80 m east of 300 m along.
    OffRouteMachine guidingAt({double? headingDeg = 0}) {
      final machine = _machine();
      for (var i = 0; i < 2; i++) {
        _fix(
          machine,
          _at(300, asideM: 80),
          distanceFromRouteM: 80,
          alongM: 300,
          headingDeg: headingDeg,
          at: Duration(seconds: i),
        );
      }
      return machine;
    }

    test('the way back points at the nearest point still ahead', () {
      final machine = guidingAt();

      final decision = _fix(
        machine,
        _at(300, asideM: 80),
        distanceFromRouteM: 80,
        alongM: 300,
        at: const Duration(seconds: 2),
      );

      final guidance = decision.guidance!;
      expect(guidance.alongM, closeTo(300, 1));
      expect(guidance.distanceM, closeTo(80, 2));
    });

    test('a point already ridden is never the way back', () {
      final machine = guidingAt();

      // Stood beside the 100 m mark, but 500 m along the plan: the way back
      // is forwards, never to a corner already taken.
      final decision = _fix(
        machine,
        _at(100, asideM: 60),
        distanceFromRouteM: 60,
        alongM: 500,
        at: const Duration(seconds: 2),
      );

      expect(decision.guidance!.alongM, greaterThanOrEqualTo(500));
    });

    test('a loop may send the rider back to where it started', () {
      // Out and back: the last point is the first one again.
      final line = <LatLng>[
        for (var i = 0; i <= 10; i++) _at(i * 100.0),
        for (var i = 9; i >= 0; i--) _at(i * 100.0),
      ];
      final machine = OffRouteMachine(line: line);
      for (var i = 0; i < 2; i++) {
        _fix(
          machine,
          _at(50, asideM: 80),
          distanceFromRouteM: 80,
          alongM: 1500,
          at: Duration(seconds: i),
        );
      }

      final decision = _fix(
        machine,
        _at(50, asideM: 80),
        distanceFromRouteM: 80,
        alongM: 1500,
        at: const Duration(seconds: 2),
      );

      // On a loop the start is ahead, so the nearest point wins outright.
      expect(decision.guidance!.alongM, lessThan(1500));
    });

    test('the direction is the bearing to it minus the rider\'s heading', () {
      // Riding north, 80 m east of the plan: the way back is to the left.
      final machine = guidingAt();
      final left = _fix(
        machine,
        _at(300, asideM: 80),
        distanceFromRouteM: 80,
        alongM: 300,
        at: const Duration(seconds: 2),
      );
      expect(left.guidance!.direction, RelativeDirection.left);

      // The same spot, riding south: now it is on the right.
      final other = guidingAt(headingDeg: 180);
      final right = _fix(
        other,
        _at(300, asideM: 80),
        distanceFromRouteM: 80,
        alongM: 300,
        headingDeg: 180,
        at: const Duration(seconds: 2),
      );
      expect(right.guidance!.direction, RelativeDirection.right);
    });

    test('no heading means no direction is claimed', () {
      final machine = guidingAt(headingDeg: null);

      final decision = _fix(
        machine,
        _at(300, asideM: 80),
        distanceFromRouteM: 80,
        alongM: 300,
        headingDeg: null,
        at: const Duration(seconds: 2),
      );

      expect(decision.guidance!.direction, isNull);
    });

    test('the way back is said once, and again only when the gap grows', () {
      final machine = _machine();
      final spokenAt = <int>[];
      // Drifting away at 2 m per fix: 80 m at first, 480 m by the end.
      for (var second = 0; second <= 400; second += 2) {
        final aside = 80.0 + second;
        final decision = _fix(
          machine,
          _at(300, asideM: aside),
          distanceFromRouteM: aside,
          alongM: 300,
          at: Duration(seconds: second),
          rerouteAllowed: false,
        );
        if (decision.speakGuidance) spokenAt.add(second);
      }

      // Once on leaving the route — the second stray fix, 82 m out — and
      // again 300 m further out; time alone never repeats it.
      expect(spokenAt, hasLength(2));
      expect(spokenAt.first, 2);
      expect(spokenAt.last, greaterThanOrEqualTo(2 + 300));
    });

    test('staying at the same distance never repeats it', () {
      final machine = _machine();
      var spoken = 0;
      for (var second = 0; second <= 300; second += 2) {
        final decision = _fix(
          machine,
          _at(300, asideM: 80),
          distanceFromRouteM: 80,
          alongM: 300,
          at: Duration(seconds: second),
          rerouteAllowed: false,
        );
        if (decision.speakGuidance) spoken++;
      }
      expect(spoken, 1);
    });
  });

  group('the rejoin trigger', () {
    test('half a minute off the route asks for one', () {
      final machine = _machine();
      var asked = false;
      for (var second = 0; second <= 40; second += 10) {
        final decision = _fix(
          machine,
          _at(300, asideM: 80),
          distanceFromRouteM: 80,
          alongM: 300,
          at: Duration(seconds: second),
        );
        if (second < 30) {
          expect(decision.planDetour, isFalse, reason: '$second');
        }
        asked |= decision.planDetour;
      }

      expect(asked, isTrue);
    });

    test('a hundred and fifty metres of travel asks sooner', () {
      final machine = _machine();
      var asked = false;
      // Walking away from the route, a fix every 40 m and every second.
      for (var i = 0; i <= 6; i++) {
        final aside = 60.0 + i * 40;
        final decision = _fix(
          machine,
          _at(300, asideM: aside),
          distanceFromRouteM: aside,
          alongM: 300,
          at: Duration(seconds: i),
        );
        asked |= decision.planDetour;
      }

      expect(asked, isTrue, reason: '240 m of travel is well past 150');
      expect(machine.offTravelM, greaterThan(detourAfterMeters));
    });

    test('re-routing switched off never asks', () {
      final machine = _machine();
      _fix(machine, _at(300, asideM: 80), distanceFromRouteM: 80, alongM: 300);

      for (var second = 10; second <= 600; second += 10) {
        final decision = _fix(
          machine,
          _at(300, asideM: 80.0 + second * 10),
          distanceFromRouteM: 80.0 + second * 10,
          alongM: 300,
          at: Duration(seconds: second),
          rerouteAllowed: false,
        );
        expect(decision.planDetour, isFalse, reason: '$second s');
        expect(decision.fullReroute, isFalse, reason: '$second s');
        expect(decision.state, OffRouteState.guiding, reason: '$second s');
        expect(decision.guidance, isNotNull, reason: '$second s');
      }
    });
  });

  group('following a rejoin', () {
    OffRouteMachine onDetour() {
      final machine = _machine();
      for (var i = 0; i < 2; i++) {
        _fix(
          machine,
          _at(300, asideM: 80),
          distanceFromRouteM: 80,
          alongM: 300,
          at: Duration(seconds: i),
        );
      }
      machine.detourStarted(_t0.add(const Duration(seconds: 2)));
      return machine;
    }

    test('staying on it asks for nothing', () {
      final machine = onDetour();

      final decision = _fix(
        machine,
        _at(320, asideM: 80),
        distanceFromRouteM: 80,
        alongM: 300,
        at: const Duration(seconds: 40),
        distanceFromDetourM: 10,
      );

      expect(decision.state, OffRouteState.detour);
      expect(decision.planDetour, isFalse);
      expect(decision.guidance, isNull);
    });

    test('drifting off it asks for another, but not twice in twenty '
        'seconds', () {
      final machine = onDetour();

      final tooSoon = _fix(
        machine,
        _at(320, asideM: 200),
        distanceFromRouteM: 200,
        alongM: 300,
        at: const Duration(seconds: 10),
        distanceFromDetourM: 80,
      );
      expect(tooSoon.planDetour, isFalse);

      final later = _fix(
        machine,
        _at(340, asideM: 200),
        distanceFromRouteM: 200,
        alongM: 300,
        at: const Duration(seconds: 30),
        distanceFromDetourM: 80,
      );
      expect(later.planDetour, isTrue);
    });

    test('reaching the plan again restores it', () {
      final machine = onDetour();

      final decision = _fix(
        machine,
        _at(600, asideM: 10),
        distanceFromRouteM: 10,
        alongM: 300,
        at: const Duration(seconds: 60),
        distanceFromDetourM: 5,
      );

      expect(decision.state, OffRouteState.onRoute);
      expect(decision.restored, isTrue);
      expect(machine.state, OffRouteState.onRoute);
    });
  });

  group('the whole ride re-planned', () {
    test('three kilometres out for five minutes', () {
      final machine = _machine();
      for (var i = 0; i < 2; i++) {
        _fix(
          machine,
          _at(300, asideM: 4000),
          distanceFromRouteM: 4000,
          alongM: 300,
          at: Duration(seconds: i),
        );
      }

      final early = _fix(
        machine,
        _at(300, asideM: 4000),
        distanceFromRouteM: 4000,
        alongM: 300,
        at: const Duration(minutes: 4),
      );
      expect(early.fullReroute, isFalse, reason: 'four minutes is not five');

      final late = _fix(
        machine,
        _at(300, asideM: 4000),
        distanceFromRouteM: 4000,
        alongM: 300,
        at: const Duration(minutes: 6),
      );
      expect(late.fullReroute, isTrue);
    });

    test('a long time close by is still only a rejoin', () {
      final machine = _machine();
      for (var i = 0; i < 2; i++) {
        _fix(
          machine,
          _at(300, asideM: 200),
          distanceFromRouteM: 200,
          alongM: 300,
          at: Duration(seconds: i),
        );
      }

      final decision = _fix(
        machine,
        _at(300, asideM: 200),
        distanceFromRouteM: 200,
        alongM: 300,
        at: const Duration(minutes: 10),
      );

      expect(decision.fullReroute, isFalse);
      expect(decision.planDetour, isTrue);
    });
  });

  group('the heading via point', () {
    test('a moving rider gets one forty metres ahead', () {
      final via = headingViaPoint(
        position: _at(300),
        headingDeg: 0,
        speedMps: 6,
      );

      expect(via, isNotNull);
      expect(haversineMeters(_at(300), via!), closeTo(headingViaMeters, 1));
      expect(bearingDegrees(_at(300), via), closeTo(0, 1));
    });

    test('a rider barely moving gets none', () {
      expect(
        headingViaPoint(position: _at(300), headingDeg: 0, speedMps: 1.4),
        isNull,
      );
      expect(
        headingViaPoint(position: _at(300), headingDeg: null, speedMps: 6),
        isNull,
      );
    });
  });

  group('the rejoin targets', () {
    test('three points ahead along the plan, and never its end', () {
      final cumulative = cumulativeDistances(_line);

      final targets = rejoinTargets(_line, cumulative, 1000);

      expect(targets, hasLength(3));
      expect(targets[0].alongM, closeTo(1300, 100));
      expect(targets[1].alongM, closeTo(1800, 100));
      expect(targets[2].alongM, closeTo(3000, 100));
      // Seven kilometres of plan are still to ride: heading for the finish
      // would not be a way back onto it, it would be a way round it.
      expect(
        targets.map((t) => t.point),
        isNot(contains(_line.last)),
        reason: 'the finish is eight kilometres past the last candidate',
      );
    });

    test('a plan that ends inside the window is asked for once', () {
      final cumulative = cumulativeDistances(_line);

      final targets = rejoinTargets(_line, cumulative, 9950);

      expect(targets, hasLength(1));
      expect(targets.single.point, _line.last);
    });
  });

  group('relative direction', () {
    test('within thirty degrees is ahead, beyond a hundred and fifty is '
        'behind', () {
      expect(relativeDirection(20, 0), RelativeDirection.ahead);
      expect(relativeDirection(340, 0), RelativeDirection.ahead);
      expect(relativeDirection(90, 0), RelativeDirection.right);
      expect(relativeDirection(270, 0), RelativeDirection.left);
      expect(relativeDirection(180, 0), RelativeDirection.behind);
      expect(relativeDirection(0, 180), RelativeDirection.behind);
      expect(relativeDirection(0, null), isNull);
    });
  });
}
