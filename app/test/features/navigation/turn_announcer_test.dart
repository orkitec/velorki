import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/navigation/application/turn_announcer.dart';
import 'package:velorki/features/navigation/domain/navigation_progress.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

const TurnHint _left = TurnHint(
  pointIndex: 10,
  kind: TurnKind.left,
  distanceToNextM: 300,
);
const TurnHint _tightLeft = TurnHint(
  pointIndex: 10,
  kind: TurnKind.left,
  distanceToNextM: 60,
);
const TurnHint _keepRight = TurnHint(pointIndex: 14, kind: TurnKind.keepRight);

NavigationProgress _at(
  double distance, {
  TurnHint? next = _left,
  TurnHint? after,
  bool offRoute = false,
  bool arrived = false,
}) => NavigationProgress(
  next: next,
  distanceToNextM: distance,
  after: after,
  offRoute: offRoute,
  arrived: arrived,
);

List<CueKind> _kinds(List<TurnCue> cues) =>
    cues.map((cue) => cue.kind).toList();

void main() {
  // Standing still counts as 10 km/h: the warning comes at 50 m, the "now"
  // cue at 30 m, and the warning needs 8.4 m of room before the "now" cue.
  test('a turn coming into view at 50 m is announced in round numbers', () {
    final announcer = TurnAnnouncer();

    final cues = announcer.update(_at(48));

    expect(_kinds(cues), [CueKind.ahead]);
    expect(cues.single.turn, _left);
    expect(cues.single.distanceM, 50);
  });

  test('nothing is said while the turn is still far away', () {
    final announcer = TurnAnnouncer();

    expect(announcer.update(_at(800)), isEmpty);
    expect(announcer.update(_at(60)), isEmpty);
    expect(_kinds(announcer.update(_at(49))), [CueKind.ahead]);
  });

  test('the ahead cue is given once, however many fixes arrive', () {
    final announcer = TurnAnnouncer();

    announcer.update(_at(48));
    expect(announcer.update(_at(45)), isEmpty);
    expect(announcer.update(_at(35)), isEmpty);
  });

  test('a turn first seen at 35 m only gets a now cue', () {
    final announcer = TurnAnnouncer();

    final first = announcer.update(_at(35));
    final second = announcer.update(_at(25));

    expect(first, isEmpty);
    expect(_kinds(second), [CueKind.now]);
    expect(second.single.distanceM, 25);
  });

  test('the now cue comes at 30 m when standing still', () {
    final announcer = TurnAnnouncer();
    announcer.update(_at(48));

    expect(announcer.update(_at(32)), isEmpty);
    expect(_kinds(announcer.update(_at(28))), [CueKind.now]);
    expect(announcer.update(_at(10)), isEmpty);
  });

  test('speed moves both cues further out', () {
    // 15 m/s: the warning at 150 m, the now cue at 45 m.
    final announcer = TurnAnnouncer();

    expect(announcer.update(_at(160), speedMps: 15), isEmpty);
    final ahead = announcer.update(_at(140), speedMps: 15);
    expect(_kinds(ahead), [CueKind.ahead]);
    expect(ahead.single.distanceM, 150);
    expect(announcer.update(_at(55), speedMps: 15), isEmpty);
    expect(_kinds(announcer.update(_at(44), speedMps: 15)), [CueKind.now]);
  });

  test('the lead setting moves the warning out', () {
    // 5 m/s for 20 s: the warning at 100 m.
    final announcer = TurnAnnouncer();

    expect(announcer.update(_at(120), speedMps: 5, leadSeconds: 20), isEmpty);
    final cues = announcer.update(_at(95), speedMps: 5, leadSeconds: 20);
    expect(_kinds(cues), [CueKind.ahead]);
    expect(cues.single.distanceM, 100);
  });

  test('the warning never comes closer than 50 m, however short the lead', () {
    final announcer = TurnAnnouncer();

    expect(announcer.update(_at(60), leadSeconds: 5), isEmpty);
    expect(_kinds(announcer.update(_at(49), leadSeconds: 5)), [CueKind.ahead]);
  });

  test('a turn close behind the next one rides along on the now cue', () {
    final announcer = TurnAnnouncer();

    final cues = announcer.update(_at(30, next: _tightLeft, after: _keepRight));

    expect(_kinds(cues), [CueKind.now]);
    expect(cues.single.then, _keepRight);
  });

  test('a turn far behind the next one is left for its own cue', () {
    final announcer = TurnAnnouncer();

    final cues = announcer.update(_at(30, after: _keepRight));

    expect(cues.single.then, isNull);
  });

  test('leaving and rejoining the route is said once each', () {
    final announcer = TurnAnnouncer();

    expect(_kinds(announcer.update(_at(500, offRoute: true))), [
      CueKind.offRoute,
    ]);
    expect(announcer.update(_at(500, offRoute: true)), isEmpty);
    expect(_kinds(announcer.update(_at(500))), [CueKind.backOnRoute]);
    expect(announcer.update(_at(500)), isEmpty);
    expect(_kinds(announcer.update(_at(500, offRoute: true))), [
      CueKind.offRoute,
    ]);
  });

  test('arriving is said once', () {
    final announcer = TurnAnnouncer();

    expect(_kinds(announcer.update(_at(0, next: null, arrived: true))), [
      CueKind.arrived,
    ]);
    expect(announcer.update(_at(0, next: null, arrived: true)), isEmpty);
  });

  test('a turn passed during a GPS gap is simply left behind', () {
    final announcer = TurnAnnouncer();
    announcer.update(_at(800));

    // The next fix is already past the first turn and near the second.
    final cues = announcer.update(_at(25, next: _keepRight));

    expect(_kinds(cues), [CueKind.now]);
    expect(cues.single.turn, _keepRight);
  });

  test('the next turn gets its own cues after the first one is done', () {
    final announcer = TurnAnnouncer();
    announcer.update(_at(48));
    announcer.update(_at(20));

    final cues = announcer.update(_at(45, next: _keepRight));

    expect(_kinds(cues), [CueKind.ahead]);
    expect(cues.single.turn, _keepRight);
    expect(cues.single.distanceM, 50);
  });

  test('advance distances are rounded to 10 m below 100 m and 50 m above', () {
    // 4 m/s for 20 s: the warning at 80 m.
    expect(
      TurnAnnouncer()
          .update(_at(76), speedMps: 4, leadSeconds: 20)
          .first
          .distanceM,
      80,
    );
    expect(
      TurnAnnouncer()
          .update(_at(63), speedMps: 4, leadSeconds: 20)
          .first
          .distanceM,
      60,
    );
    expect(
      TurnAnnouncer()
          .update(_at(52), speedMps: 4, leadSeconds: 20)
          .first
          .distanceM,
      50,
    );
    // 15 m/s: the warning at 150 m.
    expect(TurnAnnouncer().update(_at(130), speedMps: 15).first.distanceM, 150);
    expect(TurnAnnouncer().update(_at(112), speedMps: 15).first.distanceM, 100);
  });
}
