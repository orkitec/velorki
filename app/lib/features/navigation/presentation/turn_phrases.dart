import 'package:flutter/material.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

import '../../../core/units/units.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../application/turn_announcer.dart';
import '../domain/off_route_guidance.dart';
import '../../planner/domain/route_poi.dart';

/// The instruction that sends a rider who has left the route back onto it,
/// e.g. "Back to the route, on your left".
String backToRouteLabel(RelativeDirection? direction, AppLocalizations l10n) =>
    l10n.navBackToRoute(direction?.name ?? 'unknown');

/// The short banner text for [hint], e.g. "Turn left" or "Keep right" — or
/// what the route's author wrote for it, when the file had a cue sheet.
String turnLabel(TurnHint hint, AppLocalizations l10n) {
  final note = hint.note;
  if (note != null && note.isNotEmpty) return note;
  return turnKindLabel(hint, l10n);
}

/// The banner text for the manoeuvre alone, whatever the author wrote.
String turnKindLabel(
  TurnHint hint,
  AppLocalizations l10n,
) => switch (hint.kind) {
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

/// What the voice says for [cue], in [units].
///
/// [units] is named and optional so the controller that speaks the cues can
/// stay as it is until it has the rider's setting to hand.
String cuePhrase(
  TurnCue cue,
  AppLocalizations l10n, {
  UnitSystem units = UnitSystem.metric,
}) {
  switch (cue.kind) {
    case CueKind.backToRoute:
      // "Off route. In 200 metres, back to the route on your left": the same
      // advance-warning sentence a turn gets, because that is the sentence a
      // rider is already used to hearing.
      return l10n.navCueOffRoute(
        _aheadPhrase(
          cue.distanceM,
          _midSentence(backToRouteLabel(cue.direction, l10n)),
          l10n,
          units,
        ),
      );
    case CueKind.poi:
      final poi = cue.poi;
      if (poi == null) return '';
      // "In 100 metres, caution: start dismount zone": the same sentence
      // a turn gets, with the name where the instruction would be.
      return _aheadPhrase(
        cue.distanceM,
        _midSentence(poiLabel(poi, l10n)),
        l10n,
        units,
      );
    case CueKind.rerouted:
      return l10n.navRerouted;
    case CueKind.arrived:
      return l10n.navArrived;
    case CueKind.ahead:
      final turn = cue.turn;
      if (turn == null) return '';
      return _aheadPhrase(
        cue.distanceM,
        _midSentence(turnLabel(turn, l10n)),
        l10n,
        units,
      );
    case CueKind.now:
      final turn = cue.turn;
      if (turn == null) return '';
      final phrase = l10n.navCueNow(_midSentence(turnLabel(turn, l10n)));
      final then = cue.then;
      if (then == null) return phrase;
      return l10n.navCueThen(phrase, _midSentence(turnLabel(then, l10n)));
  }
}

/// What the banner and the voice call a point of interest: its name, with
/// "Caution:" in front of a hazard.
String poiLabel(RoutePoi poi, AppLocalizations l10n) => switch (poi.kind) {
  PoiKind.danger => l10n.navCautionLabel(poi.name),
  _ => poi.name,
};

/// The icon of a point of interest, by what it is about.
IconData poiIcon(PoiKind kind) => switch (kind) {
  PoiKind.danger => Icons.warning_amber_rounded,
  PoiKind.water => Icons.water_drop_outlined,
  PoiKind.food => Icons.restaurant_outlined,
  PoiKind.generic => Icons.place_outlined,
  PoiKind.summit => Icons.terrain_outlined,
  PoiKind.viewpoint => Icons.landscape_outlined,
  PoiKind.shelter => Icons.cabin_outlined,
  PoiKind.shop => Icons.storefront_outlined,
  PoiKind.repair => Icons.build_outlined,
  PoiKind.firstAid => Icons.medical_services_outlined,
  PoiKind.toilet => Icons.wc_outlined,
  PoiKind.campsite => Icons.festival_outlined,
  PoiKind.parking => Icons.local_parking_outlined,
  PoiKind.transport => Icons.directions_transit_outlined,
  PoiKind.turn => Icons.turn_right,
};

/// The spoken warning before a turn.
///
/// Metric counts the metres off. Imperial rounds to a hundred feet below a
/// thousand and then says the fractions a rider actually hears on the road —
/// a quarter, a half, a mile — rather than a number of miles with a decimal.
String _aheadPhrase(
  int metres,
  String instruction,
  AppLocalizations l10n,
  UnitSystem units,
) {
  if (units == UnitSystem.metric) {
    return l10n.navCueAhead(metres, instruction);
  }
  final feet = metres / metersPerFoot;
  if (feet < 1000) {
    return l10n.navCueAheadFeet(
      roundToHundredFeet(metres.toDouble()).round(),
      instruction,
    );
  }
  final miles = metres / metersPerMile;
  if (miles < 0.375) return l10n.navCueQuarterMile(instruction);
  if (miles < 0.75) return l10n.navCueHalfMile(instruction);
  if (miles < 1.5) return l10n.navCueOneMile(instruction);
  return l10n.navCueAheadMiles(miles.toStringAsFixed(1), instruction);
}

/// A distance for the banner, in [units].
///
/// Metric reads metres below a kilometre and kilometres with one decimal
/// above it; imperial reads feet below a tenth of a mile and miles with one
/// decimal above it. Both round the short end so the figure does not flicker
/// on every fix.
String distanceLabel(double metres, AppLocalizations l10n, UnitSystem units) {
  if (units == UnitSystem.metric) {
    if (metres < metersPerKilometer) {
      // Round to 10 m so the banner does not flicker on every fix.
      final rounded = (metres / 10).round() * 10;
      return l10n.navDistanceMetres(rounded);
    }
    return l10n.navDistanceKm((metres / metersPerKilometer).toStringAsFixed(1));
  }
  final miles = metres / metersPerMile;
  if (miles < 0.1) return l10n.navDistanceFeet(roundToTenFeet(metres).round());
  return l10n.navDistanceMiles(miles.toStringAsFixed(1));
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
/// The first letter is lower-cased ("In 200 metres, turn left"), so a turn
/// label has to be written to survive that: it may not start with a word that
/// is capitalised wherever it stands — a German noun, say. "Am Ziel ankommen"
/// rather than "Ziel erreichen".
String _midSentence(String label) {
  if (label.isEmpty) return label;
  return label[0].toLowerCase() + label.substring(1);
}

/// The banner's preview of the turn after the next one, e.g. "then keep right".
String thenLabel(TurnHint hint, AppLocalizations l10n) =>
    l10n.navThen(_midSentence(turnLabel(hint, l10n)));
