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
  test('a turn coming into view at 300 m is announced in round numbers', () {
    final announcer = TurnAnnouncer();

    final cues = announcer.update(_at(268));

    expect(_kinds(cues), [CueKind.ahead]);
    expect(cues.single.turn, _left);
    expect(cues.single.distanceM, 250);
  });

  test('nothing is said while the turn is still far away', () {
    final announcer = TurnAnnouncer();

    expect(announcer.update(_at(800)), isEmpty);
    expect(_kinds(announcer.update(_at(290))), [CueKind.ahead]);
  });

  test('the ahead cue is given once, however many fixes arrive', () {
    final announcer = TurnAnnouncer();

    announcer.update(_at(280));
    expect(announcer.update(_at(250)), isEmpty);
    expect(announcer.update(_at(120)), isEmpty);
  });

  test('a turn first seen at 90 m only gets a now cue', () {
    final announcer = TurnAnnouncer();

    final first = announcer.update(_at(90));
    final second = announcer.update(_at(60));
    final third = announcer.update(_at(30));

    expect(first, isEmpty);
    expect(second, isEmpty);
    expect(_kinds(third), [CueKind.now]);
    expect(third.single.distanceM, 30);
  });

  test('the now cue comes at 40 m when standing still', () {
    final announcer = TurnAnnouncer();
    announcer.update(_at(280));

    expect(announcer.update(_at(45)), isEmpty);
    expect(_kinds(announcer.update(_at(38))), [CueKind.now]);
    expect(announcer.update(_at(10)), isEmpty);
  });

  test('speed moves the now cue further out', () {
    final announcer = TurnAnnouncer();
    announcer.update(_at(280), speedMps: 15);

    expect(_kinds(announcer.update(_at(55), speedMps: 15)), [CueKind.now]);
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
    final cues = announcer.update(_at(35, next: _keepRight));

    expect(_kinds(cues), [CueKind.now]);
    expect(cues.single.turn, _keepRight);
  });

  test('the next turn gets its own cues after the first one is done', () {
    final announcer = TurnAnnouncer();
    announcer.update(_at(280));
    announcer.update(_at(20));

    final cues = announcer.update(_at(200, next: _keepRight));

    expect(_kinds(cues), [CueKind.ahead]);
    expect(cues.single.turn, _keepRight);
    expect(cues.single.distanceM, 200);
  });

  test('advance distances are rounded to the nearest 50 m', () {
    expect(TurnAnnouncer().update(_at(130)).first.distanceM, 150);
    expect(TurnAnnouncer().update(_at(120)).first.distanceM, 100);
    expect(TurnAnnouncer().update(_at(299)).first.distanceM, 300);
  });
}
