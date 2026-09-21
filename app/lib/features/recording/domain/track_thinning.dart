import 'dart:math' as math;

import 'package:velorki_geo/velorki_geo.dart';

/// Picks the waypoints a router needs to retrace a recorded track.
///
/// Kept are the first and the last fix, a fix every [everyM] of track
/// distance, and every corner: a fix where the heading over the [turnSpanM]
/// leading into it differs from the heading over the [turnSpanM] leading out
/// of it by more than [turnDeg], so a router asked to pass through the points
/// does not cut the bend short. Pauses are nothing special here; a track that
/// stood still for an hour has a cluster of fixes that thins like any other.
///
/// When more than [maxPoints] would remain, the spacing is raised to the track
/// length over the gaps allowed, which is [everyM] scaled by how far the
/// spaced points overshoot, and the pass is run again over what was kept,
/// corners and all, a quarter wider each round until at most [maxPoints]
/// stay. The result always has both ends of a track with two or more fixes;
/// an empty track yields an empty list, a single fix itself.
List<LatLng> thinTrack(
  List<TrackPoint> points, {
  double everyM = 250,
  double turnDeg = 35,
  int maxPoints = 200,
  double turnSpanM = 30,
}) {
  if (points.isEmpty) return const <LatLng>[];
  final positions = points.map((p) => p.pos).toList(growable: false);
  if (positions.length <= 2) return positions;

  // Cumulative distance along the track.
  final along = List<double>.filled(positions.length, 0);
  for (var i = 1; i < positions.length; i++) {
    along[i] = along[i - 1] + haversineMeters(positions[i - 1], positions[i]);
  }

  var kept = _spaced(
    positions,
    along,
    List<int>.generate(positions.length, (i) => i),
    everyM,
    corners: _corners(positions, along, turnDeg, turnSpanM),
  );

  // Too many: raise the spacing and thin what was kept, the corners like the
  // rest. The track length over the gaps allowed is the whole story when the
  // first pass was mostly spacing; a track that is mostly corners needs
  // another round or two.
  final cap = math.max(2, maxPoints);
  var spacing = math.max(everyM, along.last / (cap - 1));
  while (kept.length > cap) {
    kept = _spaced(positions, along, kept, spacing);
    spacing *= 1.25;
  }
  return kept.map((i) => positions[i]).toList(growable: false);
}

/// Walks [candidates] in order and keeps the first, the last, every index in
/// [corners], and any index at least [spacing] of track distance after the
/// last one kept.
List<int> _spaced(
  List<LatLng> positions,
  List<double> along,
  List<int> candidates,
  double spacing, {
  Set<int> corners = const <int>{},
}) {
  final out = <int>[candidates.first];
  var lastKept = candidates.first;
  for (var c = 1; c < candidates.length - 1; c++) {
    final i = candidates[c];
    if (corners.contains(i) || along[i] - along[lastKept] >= spacing) {
      out.add(i);
      lastKept = i;
    }
  }
  out.add(candidates.last);
  return out;
}

/// The apex of every bend sharper than [turnDeg]: the heading of the [spanM]
/// into a fix against the heading of the [spanM] out of it.
///
/// Every fix within [spanM] of a sharp bend sees part of the turn, so one
/// bend is a run of fixes that pass the test; its apex is the one that turns
/// the most, and only a fix that turns at least as much as every fix within
/// [spanM] of it is kept.
Set<int> _corners(
  List<LatLng> positions,
  List<double> along,
  double turnDeg,
  double spanM,
) {
  final n = positions.length;
  final turns = List<double>.filled(n, 0);
  var back = 0; // the last index at least spanM behind i
  var ahead = 0; // the first index at least spanM ahead of i
  for (var i = 1; i < n - 1; i++) {
    while (back < i && along[i] - along[back + 1] >= spanM) {
      back++;
    }
    if (along[i] - along[back] < spanM) continue;
    if (ahead < i) ahead = i;
    while (ahead < n - 1 && along[ahead] - along[i] < spanM) {
      ahead++;
    }
    if (along[ahead] - along[i] < spanM) break;
    turns[i] = _turn(
      bearingDegrees(positions[back], positions[i]),
      bearingDegrees(positions[i], positions[ahead]),
    );
  }

  final corners = <int>{};
  for (var i = 1; i < n - 1; i++) {
    final turn = turns[i];
    if (turn <= turnDeg) continue;
    var apex = true;
    for (var j = i - 1; j >= 0 && along[i] - along[j] <= spanM; j--) {
      // An equal turn just before wins: one apex per bend, not two.
      if (turns[j] >= turn) {
        apex = false;
        break;
      }
    }
    for (var j = i + 1; apex && j < n && along[j] - along[i] <= spanM; j++) {
      if (turns[j] > turn) apex = false;
    }
    if (apex) corners.add(i);
  }
  return corners;
}

/// The smaller angle between two headings, 0..180.
double _turn(double a, double b) {
  final d = (a - b).abs() % 360;
  return d > 180 ? 360 - d : d;
}
