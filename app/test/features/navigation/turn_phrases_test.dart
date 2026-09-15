import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/units/units.dart';
import 'package:velorki/features/navigation/application/turn_announcer.dart';
import 'package:velorki/features/navigation/presentation/turn_phrases.dart';
import 'package:velorki/l10n/generated/app_localizations.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

const TurnHint _left = TurnHint(pointIndex: 4, kind: TurnKind.left);
const TurnHint _keepRight = TurnHint(pointIndex: 9, kind: TurnKind.keepRight);
const TurnHint _roundabout = TurnHint(
  pointIndex: 12,
  kind: TurnKind.roundabout,
  exitNumber: 2,
);

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  test('every turn kind has a banner label', () {
    for (final kind in TurnKind.values) {
      final label = turnLabel(TurnHint(pointIndex: 0, kind: kind), l10n);
      expect(label, isNotEmpty, reason: kind.name);
    }
  });

  test('the labels read like a road sign', () {
    expect(turnLabel(_left, l10n), 'Turn left');
    expect(
      turnLabel(
        const TurnHint(pointIndex: 0, kind: TurnKind.slightRight),
        l10n,
      ),
      'Bear right',
    );
    expect(
      turnLabel(const TurnHint(pointIndex: 0, kind: TurnKind.sharpLeft), l10n),
      'Turn sharp left',
    );
    expect(turnLabel(_keepRight, l10n), 'Keep right');
    expect(
      turnLabel(const TurnHint(pointIndex: 0, kind: TurnKind.uTurn), l10n),
      'Turn around',
    );
    expect(turnLabel(_roundabout, l10n), 'At the roundabout, take exit 2');
    expect(
      turnLabel(const TurnHint(pointIndex: 0, kind: TurnKind.end), l10n),
      'Arrive',
    );
  });

  test('an advance cue names the distance and lower-cases the instruction', () {
    const cue = TurnCue(kind: CueKind.ahead, turn: _left, distanceM: 200);

    expect(cuePhrase(cue, l10n), 'In 200 metres, turn left');
  });

  test('a now cue says it straight out', () {
    const cue = TurnCue(kind: CueKind.now, turn: _left, distanceM: 30);

    expect(cuePhrase(cue, l10n), 'Now turn left');
  });

  test('two turns in a row are said in one breath', () {
    const cue = TurnCue(
      kind: CueKind.now,
      turn: _left,
      distanceM: 30,
      then: _keepRight,
    );

    expect(cuePhrase(cue, l10n), 'Now turn left, then keep right');
  });

  test('the route-wide cues have their own phrases', () {
    expect(cuePhrase(const TurnCue(kind: CueKind.offRoute), l10n), 'Off route');
    expect(
      cuePhrase(const TurnCue(kind: CueKind.backOnRoute), l10n),
      'Back on the route',
    );
    expect(
      cuePhrase(const TurnCue(kind: CueKind.arrived), l10n),
      'You have arrived',
    );
    expect(
      cuePhrase(const TurnCue(kind: CueKind.rerouted), l10n),
      'Route recalculated',
    );
  });

  test('a roundabout is spoken with its exit number', () {
    const cue = TurnCue(kind: CueKind.ahead, turn: _roundabout, distanceM: 150);

    expect(
      cuePhrase(cue, l10n),
      'In 150 metres, at the roundabout, take exit 2',
    );
  });

  test('distances switch to kilometres above a thousand metres', () {
    const metric = UnitSystem.metric;
    expect(distanceLabel(248, l10n, metric), '250 m');
    expect(distanceLabel(999, l10n, metric), '1000 m');
    expect(distanceLabel(1400, l10n, metric), '1.4 km');
    expect(distanceLabel(12345, l10n, metric), '12.3 km');
  });

  test('imperial distances switch to miles above a tenth of one', () {
    const imperial = UnitSystem.imperial;
    expect(distanceLabel(100, l10n, imperial), '330 ft');
    expect(distanceLabel(160, l10n, imperial), '520 ft');
    expect(distanceLabel(161, l10n, imperial), '0.1 mi');
    expect(distanceLabel(12345, l10n, imperial), '7.7 mi');
  });

  test('an imperial advance cue counts feet to the hundred', () {
    String ahead(int metres) => cuePhrase(
      TurnCue(kind: CueKind.ahead, turn: _left, distanceM: metres),
      l10n,
      units: UnitSystem.imperial,
    );

    expect(ahead(152), 'In 500 feet, turn left');
    expect(ahead(200), 'In 700 feet, turn left');
    // 300 m is the threshold the announcer fires at.
    expect(ahead(300), 'In 1000 feet, turn left');
  });

  test('an imperial advance cue says the fractions of a mile', () {
    String ahead(int metres) => cuePhrase(
      TurnCue(kind: CueKind.ahead, turn: _left, distanceM: metres),
      l10n,
      units: UnitSystem.imperial,
    );

    expect(ahead(500), 'In a quarter mile, turn left');
    expect(ahead(800), 'In half a mile, turn left');
    expect(ahead(1500), 'In one mile, turn left');
    expect(ahead(4000), 'In 2.5 miles, turn left');
  });

  test('the cues that carry no distance are the same either way', () {
    for (final kind in [
      CueKind.offRoute,
      CueKind.backOnRoute,
      CueKind.rerouted,
      CueKind.arrived,
    ]) {
      expect(
        cuePhrase(TurnCue(kind: kind), l10n, units: UnitSystem.imperial),
        cuePhrase(TurnCue(kind: kind), l10n),
        reason: kind.name,
      );
    }
    const now = TurnCue(kind: CueKind.now, turn: _left, distanceM: 30);
    expect(cuePhrase(now, l10n, units: UnitSystem.imperial), 'Now turn left');
  });

  test('every turn kind has an icon and the sides differ', () {
    for (final kind in TurnKind.values) {
      expect(turnIcon(kind), isNotNull, reason: kind.name);
    }
    expect(turnIcon(TurnKind.left), Icons.turn_left);
    expect(turnIcon(TurnKind.right), Icons.turn_right);
    expect(turnIcon(TurnKind.keepLeft), Icons.fork_left);
    expect(turnIcon(TurnKind.keepRight), Icons.fork_right);
    expect(turnIcon(TurnKind.uTurn), Icons.u_turn_left);
    expect(turnIcon(TurnKind.roundaboutLeft), Icons.roundabout_left);
    expect(turnIcon(TurnKind.exitRight), Icons.ramp_right);
    expect(turnIcon(TurnKind.end), Icons.flag);
    expect(turnIcon(TurnKind.straight), Icons.straight);
  });
}
