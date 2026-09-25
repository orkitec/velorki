import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/navigation/application/off_route_machine.dart';
import 'package:velorki/features/navigation/application/route_geometry.dart';
import 'package:velorki/features/navigation/data/navigation_settings.dart';
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
  RerouteMode mode = RerouteMode.guideBack,
  double? alongNowM,
  double? distanceFromDetourM,
  double? accuracyM,
}) => machine.update(
  position: position,
  distanceFromRouteM: distanceFromRouteM,
  alongM: alongM,
  speedMps: speedMps,
  headingDeg: headingDeg,
  now: _t0.add(at),
  mode: mode,
  alongNowM: alongNowM,
  distanceFromDetourM: distanceFromDetourM,
  accuracyM: accuracyM,
);

OffRouteMachine _machine() => OffRouteMachine(line: _line);

void main() {
  group('hysteresis', () {
    test('one stray fix is noise, not a detour', () {
      final machine = _machine();

      final decision = _fix(
        machine,
        _at(300, asideM: 120),
        distanceFromRouteM: 120,
        alongM: 300,
      );

      expect(decision.state, OffRouteState.onRoute);
      expect(decision.guidance, isNull);
    });

    test('two stray fixes in a row are', () {
      final machine = _machine();
      _fix(
        machine,
        _at(300, asideM: 120),
        distanceFromRouteM: 120,
        alongM: 300,
      );

      final decision = _fix(
        machine,
        _at(320, asideM: 130),
        distanceFromRouteM: 130,
        alongM: 300,
        at: const Duration(seconds: 1),
      );

      expect(decision.state, OffRouteState.guiding);
      expect(decision.guidance, isNotNull);
    });

    test(
      'a fix that comes back inside the threshold starts the count over',
      () {
        final machine = _machine();
        _fix(
          machine,
          _at(300, asideM: 120),
          distanceFromRouteM: 120,
          alongM: 300,
        );
        _fix(
          machine,
          _at(320, asideM: 10),
          distanceFromRouteM: 10,
          alongM: 320,
          at: const Duration(seconds: 1),
        );

        final decision = _fix(
          machine,
          _at(340, asideM: 120),
          distanceFromRouteM: 120,
          alongM: 320,
          at: const Duration(seconds: 2),
        );

        expect(decision.state, OffRouteState.onRoute);
      },
    );

    test('one stray fix held for eight seconds is a detour on its own', () {
      final machine = _machine();
      _fix(
        machine,
        _at(300, asideM: 120),
        distanceFromRouteM: 120,
        alongM: 300,
      );

      // The same fix again, from a receiver that reports rarely.
      final decision = machine.update(
        position: _at(300, asideM: 120),
        distanceFromRouteM: 120,
        alongM: 300,
        speedMps: 6,
        headingDeg: 0,
        now: _t0.add(const Duration(seconds: 9)),
        mode: RerouteMode.guideBack,
      );

      expect(decision.state, OffRouteState.guiding);
    });

    test('one fix within the snap distance puts the rider back on', () {
      final machine = _machine();
      _fix(
        machine,
        _at(300, asideM: 120),
        distanceFromRouteM: 120,
        alongM: 300,
      );
      _fix(
        machine,
        _at(320, asideM: 130),
        distanceFromRouteM: 130,
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

    test('forty metres out is off the route but not back on it', () {
      final machine = _machine();
      _fix(
        machine,
        _at(300, asideM: 120),
        distanceFromRouteM: 120,
        alongM: 300,
      );
      _fix(
        machine,
        _at(320, asideM: 130),
        distanceFromRouteM: 130,
        alongM: 300,
        at: const Duration(seconds: 1),
      );

      final decision = _fix(
        machine,
        _at(340, asideM: 40),
        distanceFromRouteM: 40,
        alongM: 300,
        at: const Duration(seconds: 2),
      );

      expect(decision.state, OffRouteState.guiding);
    });
  });

  group('the thresholds follow the accuracy', () {
    /// Two fixes the same distance out, which is what a detour takes.
    OffRouteDecision twoFixes(double distanceM, {double? accuracyM}) {
      final machine = _machine();
      _fix(
        machine,
        _at(300, asideM: distanceM),
        distanceFromRouteM: distanceM,
        alongM: 300,
        accuracyM: accuracyM,
      );
      return _fix(
        machine,
        _at(320, asideM: distanceM),
        distanceFromRouteM: distanceM,
        alongM: 300,
        at: const Duration(seconds: 1),
        accuracyM: accuracyM,
      );
    }

    test('seventy metres out is on the route, eighty is off it', () {
      expect(twoFixes(70).state, OffRouteState.onRoute);
      expect(twoFixes(80).state, OffRouteState.guiding);
    });

    test('ninety metres out with fifty metres of accuracy is on it', () {
      // 2 × 50 is a hundred: the fix could be on the road it left.
      expect(twoFixes(90, accuracyM: 50).state, OffRouteState.onRoute);
      expect(twoFixes(90, accuracyM: 5).state, OffRouteState.guiding);
    });

    test('an accuracy of kilometres cannot switch detection off', () {
      // Capped at a hundred metres, so 250 m out is still a detour.
      expect(twoFixes(250, accuracyM: 5000).state, OffRouteState.guiding);
    });

    test('coming back on widens by one error circle', () {
      final sure = _machine();
      _fix(sure, _at(300, asideM: 120), distanceFromRouteM: 120, alongM: 300);
      _fix(
        sure,
        _at(320, asideM: 120),
        distanceFromRouteM: 120,
        alongM: 300,
        at: const Duration(seconds: 1),
      );
      final near = _fix(
        sure,
        _at(340, asideM: 28),
        distanceFromRouteM: 28,
        alongM: 300,
        at: const Duration(seconds: 2),
        accuracyM: 5,
      );
      expect(near.state, OffRouteState.onRoute, reason: '28 m is inside 30');
      expect(near.restored, isTrue);

      final shaky = _machine();
      for (var i = 0; i < 2; i++) {
        _fix(
          shaky,
          _at(300, asideM: 200),
          distanceFromRouteM: 200,
          alongM: 300,
          at: Duration(seconds: i),
          accuracyM: 50,
        );
      }
      // 45 m would be too far for a good fix; with 50 m of accuracy the
      // rider is as likely as not on the plan.
      final back = _fix(
        shaky,
        _at(340, asideM: 45),
        distanceFromRouteM: 45,
        alongM: 300,
        at: const Duration(seconds: 2),
        accuracyM: 50,
      );
      expect(back.state, OffRouteState.onRoute);
      expect(back.restored, isTrue);
    });

    test('drifting off a rejoin follows the accuracy too', () {
      OffRouteMachine onDetour() {
        final machine = _machine();
        for (var i = 0; i < 2; i++) {
          _fix(
            machine,
            _at(300, asideM: 300),
            distanceFromRouteM: 300,
            alongM: 300,
            at: Duration(seconds: i),
          );
        }
        machine.detourStarted(_t0.add(const Duration(seconds: 2)));
        return machine;
      }

      // 60 m off the rejoin is past the 50 m base with a good fix...
      expect(
        _fix(
          onDetour(),
          _at(320, asideM: 300),
          distanceFromRouteM: 300,
          alongM: 300,
          at: const Duration(seconds: 30),
          distanceFromDetourM: 60,
          accuracyM: 5,
        ).planDetour,
        isTrue,
      );
      // ...and inside 2 × 40 m of accuracy with a shaky one.
      expect(
        _fix(
          onDetour(),
          _at(320, asideM: 300),
          distanceFromRouteM: 300,
          alongM: 300,
          at: const Duration(seconds: 30),
          distanceFromDetourM: 60,
          accuracyM: 40,
        ).planDetour,
        isFalse,
      );
    });
  });

  group('guiding', () {
    /// Puts [machine] into the guiding state 120 m east of 300 m along.
    OffRouteMachine guidingAt({double? headingDeg = 0}) {
      final machine = _machine();
      for (var i = 0; i < 2; i++) {
        _fix(
          machine,
          _at(300, asideM: 120),
          distanceFromRouteM: 120,
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
        _at(300, asideM: 120),
        distanceFromRouteM: 120,
        alongM: 300,
        at: const Duration(seconds: 2),
      );

      final guidance = decision.guidance!;
      expect(guidance.alongM, closeTo(300, 1));
      expect(guidance.distanceM, closeTo(120, 2));
    });

    test('a point already ridden is never the way back', () {
      final machine = guidingAt();

      // Stood beside the 100 m mark, but 500 m along the plan: the way back
      // is forwards, never to a corner already taken.
      final decision = _fix(
        machine,
        _at(100, asideM: 120),
        distanceFromRouteM: 120,
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
          _at(50, asideM: 120),
          distanceFromRouteM: 120,
          alongM: 1500,
          at: Duration(seconds: i),
        );
      }

      final decision = _fix(
        machine,
        _at(50, asideM: 120),
        distanceFromRouteM: 120,
        alongM: 1500,
        at: const Duration(seconds: 2),
      );

      // On a loop the start is ahead, so the nearest point wins outright.
      expect(decision.guidance!.alongM, lessThan(1500));
    });

    test('the direction is the bearing to it minus the rider\'s heading', () {
      // Riding north, 120 m east of the plan: the way back is to the left.
      final machine = guidingAt();
      final left = _fix(
        machine,
        _at(300, asideM: 120),
        distanceFromRouteM: 120,
        alongM: 300,
        at: const Duration(seconds: 2),
      );
      expect(left.guidance!.direction, RelativeDirection.left);

      // The same spot, riding south: now it is on the right.
      final other = guidingAt(headingDeg: 180);
      final right = _fix(
        other,
        _at(300, asideM: 120),
        distanceFromRouteM: 120,
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
        _at(300, asideM: 120),
        distanceFromRouteM: 120,
        alongM: 300,
        headingDeg: null,
        at: const Duration(seconds: 2),
      );

      expect(decision.guidance!.direction, isNull);
    });

    test('the way back is said once, and again only when the gap grows', () {
      final machine = _machine();
      final spokenAt = <int>[];
      // Drifting away at 2 m per fix: 120 m at first, 520 m by the end.
      for (var second = 0; second <= 400; second += 2) {
        final aside = 120.0 + second;
        final decision = _fix(
          machine,
          _at(300, asideM: aside),
          distanceFromRouteM: aside,
          alongM: 300,
          at: Duration(seconds: second),
          mode: RerouteMode.off,
        );
        if (decision.speakGuidance) spokenAt.add(second);
      }

      // Once on leaving the route — the second stray fix, 122 m out — and
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
          _at(300, asideM: 120),
          distanceFromRouteM: 120,
          alongM: 300,
          at: Duration(seconds: second),
          mode: RerouteMode.off,
        );
        if (decision.speakGuidance) spoken++;
      }
      expect(spoken, 1);
    });
  });

  group('the rejoin trigger', () {
    test('three quarters of a minute off the route asks for one', () {
      final machine = _machine();
      var asked = false;
      for (var second = 0; second <= 60; second += 10) {
        final decision = _fix(
          machine,
          _at(300, asideM: 120),
          distanceFromRouteM: 120,
          alongM: 300,
          at: Duration(seconds: second),
        );
        // Off the route from the second fix, at ten seconds.
        if (second < 10 + detourAfter.inSeconds) {
          expect(decision.planDetour, isFalse, reason: '$second');
        }
        asked |= decision.planDetour;
      }

      expect(asked, isTrue);
    });

    test('a hundred and fifty metres from where the rider left asks sooner, '
        'but not before fifteen seconds', () {
      final machine = _machine();
      // On the route at 300 m, then riding straight away from it, 20 m a
      // second.
      _fix(machine, _at(300), distanceFromRouteM: 0, alongM: 300);
      var askedAt = -1;
      for (var i = 1; i <= 20; i++) {
        final aside = 20.0 * i;
        final decision = _fix(
          machine,
          _at(300, asideM: aside),
          distanceFromRouteM: aside,
          alongM: 300,
          at: Duration(seconds: i),
        );
        if (decision.planDetour && askedAt < 0) askedAt = i;
      }

      expect(askedAt, greaterThan(0), reason: 'well past 150 m');
      expect(askedAt, lessThan(detourAfter.inSeconds));
      // Off route from the fifth fix on; the rule waits fifteen seconds.
      expect(askedAt, greaterThanOrEqualTo(4 + detourMinTime.inSeconds));
      expect(machine.offTravelM, greaterThan(detourAfterMeters));
    });

    test('fixes thrown about by a street canyon add up to no travel', () {
      final machine = _machine();
      _fix(machine, _at(300), distanceFromRouteM: 0, alongM: 300);
      var asked = false;
      // Ten wild fixes a second apart, 100 m either side of the route: a
      // kilometre of steps between them, and the rider nowhere else.
      for (var i = 1; i <= 10; i++) {
        final aside = i.isEven ? 100.0 : -100.0;
        final decision = _fix(
          machine,
          _at(300 + i * 5.0, asideM: aside),
          distanceFromRouteM: 100,
          alongM: 300,
          at: Duration(seconds: i),
        );
        asked |= decision.planDetour;
      }
      expect(asked, isFalse);
      expect(machine.offTravelM, lessThan(detourAfterMeters));
    });

    test('re-routing switched off never asks', () {
      final machine = _machine();
      _fix(
        machine,
        _at(300, asideM: 120),
        distanceFromRouteM: 120,
        alongM: 300,
      );

      for (var second = 10; second <= 600; second += 10) {
        final decision = _fix(
          machine,
          _at(300, asideM: 120.0 + second * 10),
          distanceFromRouteM: 120.0 + second * 10,
          alongM: 300,
          at: Duration(seconds: second),
          mode: RerouteMode.off,
        );
        expect(decision.planDetour, isFalse, reason: '$second s');
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
          _at(300, asideM: 120),
          distanceFromRouteM: 120,
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
        _at(320, asideM: 120),
        distanceFromRouteM: 120,
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

  group('what each mode asks for', () {
    /// Guided for [seconds], a kilometre out, in [mode].
    bool asksAfter(RerouteMode mode, int seconds) {
      final machine = _machine();
      var asked = false;
      for (var second = 0; second <= seconds; second += 5) {
        final decision = _fix(
          machine,
          _at(300, asideM: 1000),
          distanceFromRouteM: 1000,
          alongM: 300,
          at: Duration(seconds: second),
          mode: mode,
        );
        asked |= decision.planDetour;
        if (second == 0) continue; // One stray fix is noise.
        expect(decision.state, OffRouteState.guiding);
        expect(decision.guidance, isNotNull);
      }
      return asked;
    }

    test('guide me back and a new route both ask after the same wait', () {
      expect(asksAfter(RerouteMode.guideBack, 40), isFalse);
      expect(asksAfter(RerouteMode.guideBack, 50), isTrue);
      expect(asksAfter(RerouteMode.newRoute, 40), isFalse);
      expect(asksAfter(RerouteMode.newRoute, 50), isTrue);
    });

    test('don\'t re-route never asks, and still guides', () {
      expect(asksAfter(RerouteMode.off, 3600), isFalse);
    });

    test('a long time far out is still only a way back', () {
      // No three-kilometre, five-minute re-plan any more: a rider who asked
      // to be guided back is guided back, however long they are away.
      final machine = _machine();
      for (var second = 0; second <= 600; second += 5) {
        final decision = _fix(
          machine,
          _at(300, asideM: 4000),
          distanceFromRouteM: 4000,
          alongM: 300,
          at: Duration(seconds: second),
        );
        if (second > 0) expect(decision.state, OffRouteState.guiding);
      }
    });
  });

  group('ignoring a way back', () {
    /// A rider at 300 m along, 120 m out, handed a way back that meets the
    /// plan at 900 m.
    OffRouteMachine ignoring() {
      final machine = _machine();
      for (var i = 0; i < 2; i++) {
        _fix(
          machine,
          _at(300, asideM: 120),
          distanceFromRouteM: 120,
          alongM: 300,
          at: Duration(seconds: i),
        );
      }
      machine.detourStarted(
        _t0.add(const Duration(seconds: 2)),
        from: _at(300, asideM: 120),
        targetAlongM: 900,
      );
      return machine;
    }

    test('riding away from it asks again only three hundred metres on', () {
      final machine = ignoring();
      // Riding north beside the plan, 120 m out, 5 m/s, off the way back.
      double? askedAtM;
      for (var second = 5; second <= 120; second += 5) {
        final aheadM = 300.0 + second * 5;
        final decision = _fix(
          machine,
          _at(aheadM, asideM: 120),
          distanceFromRouteM: 120,
          alongM: 300,
          alongNowM: math.min(aheadM, 880),
          at: Duration(seconds: second),
          distanceFromDetourM: 100,
        );
        if (decision.planDetour) {
          askedAtM = aheadM - 300;
          break;
        }
      }
      expect(askedAtM, isNotNull);
      expect(askedAtM, greaterThanOrEqualTo(detourRecomputeMovedM));
      expect(askedAtM, lessThan(detourRecomputeMovedM + 30));
    });

    test('a target the rider has passed is replaced, once they have got '
        'three hundred metres on', () {
      final machine = ignoring();
      // Right beside the way back's end: not adrift of it, but past it.
      bool at(double alongM, int second) => _fix(
        machine,
        _at(alongM, asideM: 60),
        distanceFromRouteM: 60,
        alongM: 300,
        alongNowM: alongM,
        at: Duration(seconds: second),
        distanceFromDetourM: 5,
      ).planDetour;

      expect(at(560, 25), isFalse, reason: 'not past it yet');
      expect(at(900, 50), isTrue);
    });

    test('a target not yet reached and a rider on the way back ask for '
        'nothing, however far they ride', () {
      final machine = ignoring();
      final decision = _fix(
        machine,
        _at(800, asideM: 60),
        distanceFromRouteM: 60,
        alongM: 300,
        alongNowM: 800,
        at: const Duration(seconds: 90),
        distanceFromDetourM: 5,
      );
      expect(decision.planDetour, isFalse);
    });

    test('standing still off it never asks again', () {
      final machine = ignoring();
      for (var second = 20; second <= 600; second += 10) {
        final decision = _fix(
          machine,
          _at(310, asideM: 150),
          distanceFromRouteM: 150,
          alongM: 300,
          alongNowM: 310,
          at: Duration(seconds: second),
          distanceFromDetourM: 100,
          speedMps: 0,
        );
        expect(decision.planDetour, isFalse, reason: '$second s');
      }
    });

    test('only guide me back ever asks for another', () {
      for (final mode in [RerouteMode.newRoute, RerouteMode.off]) {
        final machine = ignoring();
        final decision = _fix(
          machine,
          _at(1200, asideM: 120),
          distanceFromRouteM: 120,
          alongM: 300,
          alongNowM: 1200,
          at: const Duration(seconds: 60),
          distanceFromDetourM: 200,
          mode: mode,
        );
        expect(decision.planDetour, isFalse, reason: mode.name);
      }
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

  group('where a way back is aimed from', () {
    final cumulative = cumulativeDistances(_line);

    test('where the rider left, while they have not got on beside it', () {
      expect(rejoinFromM(_line, cumulative, _at(250, asideM: 200), 300), 300);
    });

    test('their own place beside the plan, once it is ahead', () {
      expect(
        rejoinFromM(_line, cumulative, _at(1200, asideM: 200), 300),
        closeTo(1200, 1),
      );
    });

    test('where they left, for a rider far out and far on', () {
      expect(rejoinFromM(_line, cumulative, _at(5000, asideM: 1500), 300), 300);
    });

    test('their own place for a rider close to the plan far on: they '
        'skipped a stretch of it', () {
      expect(
        rejoinFromM(_line, cumulative, _at(5000, asideM: 200), 300),
        closeTo(5000, 1),
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
