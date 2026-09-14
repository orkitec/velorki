import 'package:flutter/material.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../application/turn_announcer.dart';

/// The short banner text for [hint], e.g. "Turn left" or "Keep right".
String turnLabel(TurnHint hint, AppLocalizations l10n) => switch (hint.kind) {
  TurnKind.left => l10n.navTurnLeft,
  TurnKind.right => l10n.navTurnRight,
  TurnKind.slightLeft => l10n.navTurnSlightLeft,
  TurnKind.slightRight => l10n.navTurnSlightRight,
  TurnKind.sharpLeft => l10n.navTurnSharpLeft,
  TurnKind.sharpRight => l10n.navTurnSharpRight,
  TurnKind.keepLeft => l10n.navKeepLeft,
  TurnKind.keepRight => l10n.navKeepRight,
  TurnKind.uTurn || TurnKind.uTurnLeft || TurnKind.uTurnRight => l10n.navUTurn,
  TurnKind.roundabout ||
  TurnKind.roundaboutLeft => l10n.navRoundaboutExit(hint.exitNumber),
  TurnKind.exitLeft => l10n.navExitLeft,
  TurnKind.exitRight => l10n.navExitRight,
  TurnKind.end => l10n.navArrive,
  // Never announced, but the banner still has to say something.
  TurnKind.straight || TurnKind.beeline || TurnKind.offRoad => l10n.navContinue,
};

/// What the voice says for [cue].
String cuePhrase(TurnCue cue, AppLocalizations l10n) {
  switch (cue.kind) {
    case CueKind.offRoute:
      return l10n.navOffRoute;
    case CueKind.backOnRoute:
      return l10n.navBackOnRoute;
    case CueKind.rerouted:
      return l10n.navRerouted;
    case CueKind.arrived:
      return l10n.navArrived;
    case CueKind.ahead:
      final turn = cue.turn;
      if (turn == null) return '';
      return l10n.navCueAhead(
        cue.distanceM,
        _midSentence(turnLabel(turn, l10n), l10n),
      );
    case CueKind.now:
      final turn = cue.turn;
      if (turn == null) return '';
      final phrase = l10n.navCueNow(_midSentence(turnLabel(turn, l10n), l10n));
      final then = cue.then;
      if (then == null) return phrase;
      return l10n.navCueThen(phrase, _midSentence(turnLabel(then, l10n), l10n));
  }
}

/// A distance for the banner: metres below a kilometre, kilometres with one
/// decimal above it.
String distanceLabel(double metres, AppLocalizations l10n) {
  if (metres < 1000) {
    // Round to 10 m so the banner does not flicker on every fix.
    final rounded = (metres / 10).round() * 10;
    return l10n.navDistanceMetres(rounded);
  }
  return l10n.navDistanceKm((metres / 1000).toStringAsFixed(1));
}

/// The Material icon that stands for [kind].
IconData turnIcon(TurnKind kind) => switch (kind) {
  TurnKind.left => Icons.turn_left,
  TurnKind.right => Icons.turn_right,
  TurnKind.slightLeft => Icons.turn_slight_left,
  TurnKind.slightRight => Icons.turn_slight_right,
  TurnKind.sharpLeft => Icons.turn_sharp_left,
  TurnKind.sharpRight => Icons.turn_sharp_right,
  TurnKind.keepLeft => Icons.fork_left,
  TurnKind.keepRight => Icons.fork_right,
  TurnKind.uTurnLeft || TurnKind.uTurn => Icons.u_turn_left,
  TurnKind.uTurnRight => Icons.u_turn_right,
  TurnKind.roundabout => Icons.roundabout_right,
  TurnKind.roundaboutLeft => Icons.roundabout_left,
  TurnKind.exitLeft => Icons.ramp_left,
  TurnKind.exitRight => Icons.ramp_right,
  TurnKind.end => Icons.flag,
  TurnKind.straight || TurnKind.beeline || TurnKind.offRoad => Icons.straight,
};

/// An instruction dropped into the middle of a sentence.
///
/// English lower-cases it ("In 200 metres, turn left"); languages that capitalise
/// mid-sentence words keep the label as their translators wrote it.
String _midSentence(String label, AppLocalizations l10n) {
  if (!l10n.localeName.startsWith('en') || label.isEmpty) return label;
  return label[0].toLowerCase() + label.substring(1);
}

/// The banner's preview of the turn after the next one, e.g. "then keep right".
String thenLabel(TurnHint hint, AppLocalizations l10n) =>
    l10n.navThen(_midSentence(turnLabel(hint, l10n), l10n));
