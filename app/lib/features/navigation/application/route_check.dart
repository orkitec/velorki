/// What a computed way back asks of the rider that it should not: a one-way
/// street ridden the wrong way, a stretch of pavement, a turn back on
/// itself.
///
/// Read off BRouter's `messages`, which carry every tag of a way once the
/// query sets `processUnusedTags`; `reversedirection=yes` marks a way ridden
/// against the direction it was drawn in.
library;

import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// Whether a way with these [tags] is ridden against a direction a bicycle
/// has to keep to.
///
/// Against `oneway=yes` (or `-1` ridden forwards, or a roundabout), unless
/// bicycles are let through: `oneway:bicycle=no`, a contraflow cycleway
/// (`cycleway=opposite*`, on either side), or a lane or track on a side
/// whose own `:oneway` is `no` or `-1`. `oneway:bicycle=yes` makes a way a
/// one-way for bicycles whatever `oneway` says.
bool againstOneway(Map<String, String> tags) {
  final reversed = tags['reversedirection'] == 'yes';
  final oneway = tags['oneway'];
  final bicycle = tags['oneway:bicycle'];
  final against = reversed
      ? bicycle == 'yes' ||
            (oneway == null
                ? tags['junction'] == 'roundabout'
                : oneway == 'yes' || oneway == 'true' || oneway == '1')
      : oneway == '-1';
  if (!against || bicycle == 'no') return false;
  for (final key in const ['cycleway', 'cycleway:left', 'cycleway:right']) {
    if (tags[key]?.startsWith('opposite') ?? false) return false;
  }
  for (final side in const ['left', 'right', 'both']) {
    final own = tags['cycleway:$side:oneway'];
    if (tags['cycleway:$side'] != null && (own == 'no' || own == '-1')) {
      return false;
    }
  }
  return true;
}

/// Whether a way with these [tags] is a pavement a bicycle is not let onto:
/// a separately drawn `footway=sidewalk` without `bicycle=yes|designated`.
bool sidewalk(Map<String, String> tags) =>
    tags['highway'] == 'footway' &&
    tags['footway'] == 'sidewalk' &&
    tags['bicycle'] != 'yes' &&
    tags['bicycle'] != 'designated';

/// How much of a route runs against a one-way, in metres.
double againstOnewayM(RouteResult route) {
  var metres = 0.0;
  for (final m in route.messages) {
    if (againstOneway(m.wayTags)) metres += m.distanceM;
  }
  return metres;
}

/// How much of a route is pavement, in metres, not counting the first and
/// the last [endsM] metres: a start or a finish tapped beside a road is
/// matched to the pavement in a city that draws its pavements, and getting
/// off it is not the route's doing.
double sidewalkM(RouteResult route, {double endsM = 30}) {
  final total = route.messages.fold<double>(0, (sum, m) => sum + m.distanceM);
  var along = 0.0;
  var metres = 0.0;
  for (final m in route.messages) {
    final from = along;
    along += m.distanceM;
    if (!sidewalk(m.wayTags)) continue;
    final start = from < endsM ? endsM : from;
    final end = along > total - endsM ? total - endsM : along;
    if (end > start) metres += end - start;
  }
  return metres;
}

/// Whether the first [metres] of [route] head more than [maxTurnDeg] away
/// from [headingDeg]: a way back that starts by turning the rider round.
bool turnsBack(
  RouteResult route,
  double headingDeg, {
  double metres = 50,
  double maxTurnDeg = 120,
}) {
  final line = route.positions;
  if (line.length < 2) return false;
  var along = 0.0;
  var end = line.last;
  for (var i = 1; i < line.length; i++) {
    along += haversineMeters(line[i - 1], line[i]);
    if (along >= metres) {
      end = line[i];
      break;
    }
  }
  if (haversineMeters(line.first, end) < 5) return false;
  var delta = (bearingDegrees(line.first, end) - headingDeg) % 360;
  if (delta > 180) delta = 360 - delta;
  return delta > maxTurnDeg;
}
