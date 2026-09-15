import 'dart:math' as math;

import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../domain/navigation_progress.dart';

/// How far past a turn the rider has to be before it counts as taken.
const double _passedMarginM = 15;

/// Farther than this from the route counts as a stray fix.
const double _strayM = 50;

/// Nearer than this and the rider is back on the route.
const double _backOnM = 30;

/// How many stray fixes in a row it takes to call the rider off route. GPS in
/// a city throws the odd fix a long way out; three in a row is a real detour.
const int _strayFixes = 3;

/// Within this distance of the last point the route is done.
const double _arrivalM = 30;

/// Turn kinds that are never announced: they tell the rider to do nothing.
bool _announced(TurnHint hint) =>
    hint.kind != TurnKind.straight &&
    hint.kind != TurnKind.beeline &&
    hint.kind != TurnKind.offRoad;

/// Follows a rider along a planned route and says which turn comes next.
///
/// Pure logic: feed it position fixes with [update] and it returns a
/// [NavigationProgress] for each one. It keeps a little state between calls —
/// where the rider was last matched, and how many fixes in a row have been far
/// from the line — so a fix is matched near the last one rather than to some
/// other place where the route happens to come back on itself.
class TurnNavigator {
  /// Creates a navigator for [line] with [turns] on it.
  ///
  /// [turns] is expected sorted by `pointIndex`; hints pointing outside the
  /// line are dropped, because a route that was cut or stitched can carry
  /// them.
  TurnNavigator({required List<LatLng> line, required List<TurnHint> turns})
    : _line = List<LatLng>.unmodifiable(line),
      _turns = List<TurnHint>.unmodifiable(
        turns.where((h) => h.pointIndex >= 0 && h.pointIndex < line.length),
      ) {
    _cumulative = List<double>.filled(_line.length, 0);
    for (var i = 1; i < _line.length; i++) {
      _cumulative[i] =
          _cumulative[i - 1] + haversineMeters(_line[i - 1], _line[i]);
    }
    _announcedTurns = _turns.where(_announced).toList(growable: false);
  }

  final List<LatLng> _line;
  final List<TurnHint> _turns;

  /// Distance from the start of the route to each of its points.
  late final List<double> _cumulative;

  /// The subset of [_turns] the rider is told about.
  late final List<TurnHint> _announcedTurns;

  /// The segment the last fix was matched to, the middle of the next search.
  int _lastSegment = 0;

  /// Stray fixes in a row so far.
  int _strayCount = 0;

  bool _offRoute = false;

  /// The length of the whole route in metres.
  double get totalM => _cumulative.isEmpty ? 0 : _cumulative.last;

  /// The turns the rider is told about, in order.
  List<TurnHint> get announcedTurns => _announcedTurns;

  /// Matches [position] to the route and reports what comes next.
  NavigationProgress update(LatLng position) {
    if (_line.isEmpty) return const NavigationProgress();

    final match = _snap(position);
    final alongM = match.alongM;

    if (match.distanceM > _strayM) {
      _strayCount++;
      if (_strayCount >= _strayFixes) _offRoute = true;
    } else {
      _strayCount = 0;
      if (_offRoute && match.distanceM < _backOnM) _offRoute = false;
    }

    TurnHint? next;
    TurnHint? after;
    for (final hint in _announcedTurns) {
      if (alongM > _cumulative[hint.pointIndex] + _passedMarginM) continue;
      if (next == null) {
        next = hint;
      } else {
        after = hint;
        break;
      }
    }

    final distanceToNextM = next == null
        ? 0.0
        : math.max(0.0, _cumulative[next.pointIndex] - alongM);
    final remainingM = math.max(0.0, totalM - alongM);
    final toEndM = haversineMeters(position, _line.last);
    // Arrival is progress along the route, not nearness to its last point:
    // a loop starts where it ends, and the first fix of a ride would
    // otherwise be an arrival.
    final arrived = toEndM <= _arrivalM && remainingM <= _arrivalM;

    return NavigationProgress(
      next: next,
      distanceToNextM: distanceToNextM,
      after: after,
      offRoute: _offRoute,
      remainingM: remainingM,
      alongM: alongM,
      arrived: arrived,
      snapped: match.snapped,
      routeBearingDeg: _segmentBearing(match.segment),
      distanceFromRouteM: match.distanceM,
    );
  }

  /// Which way the route runs on segment [index], or `null` for a route of a
  /// single point.
  ///
  /// The direction of the road the rider is on beats a GNSS course by a wide
  /// margin, so this is what turns the map and points the cone while they are
  /// on the route. A segment of zero length carries no direction; the search
  /// walks back to the last one that does.
  double? _segmentBearing(int index) {
    if (_line.length < 2) return null;
    for (var i = math.min(index, _line.length - 2); i >= 0; i--) {
      final a = _line[i];
      final b = _line[i + 1];
      if (a != b) return bearingDegrees(a, b);
    }
    return null;
  }

  /// Finds the point of the route nearest to [position].
  ///
  /// Looks in a window around the last match first, which is both faster and
  /// right where a route crosses itself. Only when that match is far from the
  /// line does it fall back to the whole route, so a rider who jumped ahead
  /// (or restarted mid-route) is found again.
  _Match _snap(LatLng position) {
    if (_line.length == 1) {
      return _Match(0, haversineMeters(position, _line.first), 0, _line.first);
    }
    final segments = _line.length - 1;
    final from = math.max(0, _lastSegment - 5);
    final to = math.min(segments - 1, _lastSegment + 60);
    var best = _search(position, from, to);
    if (best.distanceM > _strayM) {
      final whole = _search(position, 0, segments - 1);
      if (whole.distanceM < best.distanceM) best = whole;
    }
    _lastSegment = best.segment;
    return best;
  }

  /// How much of a jump along the route, in metres, weighs like one metre
  /// of distance from it when two segments fit a fix about equally well.
  /// Keeps a loop's start from being matched to its end, and a route that
  /// doubles back from flipping between its two passes.
  static const double _jumpWeight = 0.05;

  _Match _search(LatLng position, int from, int to) {
    var bestSegment = from;
    var bestDistance = double.infinity;
    var bestScore = double.infinity;
    var bestAlong = _cumulative[from];
    var bestSnapped = _line[from];
    final lastAlong = _cumulative[_lastSegment];
    for (var i = from; i <= to; i++) {
      final a = _line[i];
      final b = _line[i + 1];
      // A local flat-earth frame around the segment start: longitude shrinks
      // with the cosine of the latitude, latitude is left as it is. Good to a
      // fraction of a metre over the few hundred metres of one segment.
      final kx = math.cos(a.lat * math.pi / 180);
      final abx = (b.lon - a.lon) * kx;
      final aby = b.lat - a.lat;
      final apx = (position.lon - a.lon) * kx;
      final apy = position.lat - a.lat;
      final lengthSquared = abx * abx + aby * aby;
      final t = lengthSquared == 0
          ? 0.0
          : ((apx * abx + apy * aby) / lengthSquared).clamp(0.0, 1.0);
      final snapped = LatLng(
        a.lat + (b.lat - a.lat) * t,
        a.lon + (b.lon - a.lon) * t,
      );
      final distance = haversineMeters(position, snapped);
      final along = _cumulative[i] + (_cumulative[i + 1] - _cumulative[i]) * t;
      final score = distance + _jumpWeight * (along - lastAlong).abs();
      if (score < bestScore) {
        bestScore = score;
        bestDistance = distance;
        bestSegment = i;
        bestAlong = along;
        bestSnapped = snapped;
      }
    }
    return _Match(bestSegment, bestDistance, bestAlong, bestSnapped);
  }
}

/// One position matched to the route.
class _Match {
  const _Match(this.segment, this.distanceM, this.alongM, this.snapped);

  /// Index of the segment the position sits on.
  final int segment;

  /// How far the position is from the route, in metres.
  final double distanceM;

  /// How far along the route the matched point is, in metres.
  final double alongM;

  /// The point on the route itself.
  final LatLng snapped;
}
