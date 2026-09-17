import 'dart:math' as math;

import 'package:velorki_geo/velorki_geo.dart';

import '../domain/off_route_guidance.dart';
import 'off_route_thresholds.dart';
import 'route_geometry.dart';

/// How many stray fixes in a row it takes to call the rider off route.
///
/// Two, not one: a single fix thrown out by a bridge or a canyon is not a
/// detour, and the rider should not hear about it.
const int offRouteFixes = 2;

/// ...or, for a receiver that reports rarely, how long straying it takes.
const Duration offRouteAfter = Duration(seconds: 8);

/// How long guiding a rider back goes on before a rejoin is worked out.
const Duration detourAfter = Duration(seconds: 30);

/// ...or how far they travel while off the route, whichever comes first.
const double detourAfterMeters = 150;

/// How far ahead along the plan a rejoin is aimed for.
///
/// Three targets rather than one: near enough to turn round for, a few
/// minutes out, and far enough that a closed road or a one-way street is
/// left well behind. They are tried in that order and the first one that can
/// be reached without a detour of its own wins, because the point of a rejoin
/// is the shortest way back onto the plan, not the shortest way to the
/// finish — the end of the ride is only ever a candidate when it falls inside
/// the two-kilometre window anyway.
const List<double> rejoinTargetsM = <double>[300, 800, 2000];

/// How much longer than the straight line to it a way back onto the plan may
/// be before that candidate is skipped.
///
/// Three times the beeline is a road that bends; much more than that is a
/// river, a motorway or a one-way street between the rider and the target,
/// and the next candidate along is the better question to ask.
const double rejoinDetourFactor = 3;

/// How far ahead of the rider the via point of a rejoin is put.
///
/// BRouter has no heading parameter, so the only way to say "I am going this
/// way" is to ask for a route through a point that way. Short enough that it
/// never sends the rider round a block, long enough to rule out the road
/// behind them.
const double headingViaMeters = 40;

/// Below this speed a heading says nothing, so no via point is asked for.
const double headingViaSpeedMps = 1.5;

/// How often drifting off a rejoin — see [detourDriftMeters] — may ask for
/// another one, so a rider weaving around one is not re-routed on every fix.
const Duration detourRecomputeGap = Duration(seconds: 20);

/// Farther than this from the plan, for longer than [fullRerouteAfter], and
/// the ride is re-planned to its destination rather than back onto the plan.
const double fullRerouteMeters = 3000;

/// See [fullRerouteMeters].
const Duration fullRerouteAfter = Duration(minutes: 5);

/// How much further from the plan the rider has to get before the way back
/// is said again. Said once on leaving and once when the detour starts; a
/// rider who left on purpose is not nagged every minute, only told when the
/// gap keeps growing.
const double guidanceRepeatMeters = 300;

/// Ends this near each other and the plan is a loop, so a point near its
/// start is ahead of the rider rather than behind them.
const double _loopEndsMeters = 60;

/// How much short of the rider's own progress a point may sit and still count
/// as ahead of them. Only rounding: the two distances are added up over
/// different runs of the same line.
const double _aheadSlackM = 2;

/// Within this many degrees of the rider's heading a point counts as ahead.
const double _aheadDegrees = 30;

/// Beyond this many degrees it counts as behind them.
const double _behindDegrees = 150;

/// What one fix leaves the ride needing.
///
/// [state] is where the ride stands; the flags are the things the caller has
/// to go and do, each true for the one fix that asks for it.
class OffRouteDecision {
  /// Creates a decision.
  const OffRouteDecision({
    required this.state,
    this.guidance,
    this.speakGuidance = false,
    this.planDetour = false,
    this.fullReroute = false,
    this.restored = false,
  });

  /// Where the ride stands now.
  final OffRouteState state;

  /// The way back onto the plan, while [state] is [OffRouteState.guiding].
  final OffRouteGuidance? guidance;

  /// Whether [guidance] should be said out loud on this fix.
  final bool speakGuidance;

  /// Whether a way back onto the plan should be computed now.
  final bool planDetour;

  /// Whether a whole new route to the destination should be computed now.
  final bool fullReroute;

  /// Whether this fix is the one that put the rider back on the plan.
  final bool restored;

  @override
  String toString() =>
      'OffRouteDecision(${state.name}'
      '${guidance != null ? ', $guidance' : ''}'
      '${speakGuidance ? ', speak' : ''}'
      '${planDetour ? ', plan a detour' : ''}'
      '${fullReroute ? ', re-route' : ''}'
      '${restored ? ', restored' : ''})';
}

/// Decides what a ride that has left its route should do, fix by fix.
///
/// Pure logic over one plan: it is told where the rider is and how far that
/// is from the plan and from any rejoin in use, and it answers with the state
/// and with the things to do. It holds no router, no clock and no providers —
/// [NavigationController] owns those and acts on what this returns.
///
/// The order it works in is the point of it. A rider who is seventy-five
/// metres out is guided back by the plan they already chose, not sent down a route they
/// have never seen; only a rider who is still off it half a minute later gets
/// a rejoin computed, and only one who is kilometres away for minutes gets
/// the whole ride re-planned.
class OffRouteMachine {
  /// Creates a machine for [line], the plan the rider is being held to.
  OffRouteMachine({required List<LatLng> line})
    : _line = List<LatLng>.unmodifiable(line),
      _cumulative = cumulativeDistances(line),
      _loop =
          line.length > 1 &&
          haversineMeters(line.first, line.last) <= _loopEndsMeters;

  final List<LatLng> _line;
  final List<double> _cumulative;

  /// Whether the plan comes back to where it started, in which case a point
  /// near its start is ahead of the rider rather than behind them.
  final bool _loop;

  OffRouteState _state = OffRouteState.onRoute;

  /// Stray fixes in a row, and when the run of them started.
  int _strayCount = 0;
  DateTime? _strayingSince;

  /// When the rider left the route, and how far they have gone since.
  DateTime? _offSince;
  double _offTravelM = 0;
  LatLng? _lastPosition;

  /// When the way back was last said out loud.
  double? _spokenDistanceM;

  /// When the rejoin in use was computed.
  DateTime? _detourAt;

  /// Where the ride stands.
  OffRouteState get state => _state;

  /// How far the rider has travelled since leaving the route, in metres.
  double get offTravelM => _offTravelM;

  /// Takes one fix in and says what it calls for.
  ///
  /// [distanceFromRouteM] is the distance from the plan, [alongM] how far
  /// along it the rider last was while on it, and [distanceFromDetourM] the
  /// distance from the rejoin in use, or `null` while none is.
  /// [rerouteAllowed] is the rider's re-route setting: with it off the ride
  /// never gets past [OffRouteState.guiding] on its own.
  /// [accuracyM] is the horizontal accuracy the fix came with, in metres,
  /// which widens every distance threshold here — see [strayThresholdM] and
  /// [snapThresholdM]. Unknown accuracy leaves the base distances standing.
  OffRouteDecision update({
    required LatLng position,
    required double distanceFromRouteM,
    required double alongM,
    required double speedMps,
    required double? headingDeg,
    required DateTime now,
    required bool rerouteAllowed,
    double? distanceFromDetourM,
    double? accuracyM,
  }) {
    final previous = _lastPosition;
    _lastPosition = position;
    if (previous != null && _state != OffRouteState.onRoute) {
      _offTravelM += haversineMeters(previous, position);
    }

    if (_state == OffRouteState.onRoute) {
      if (distanceFromRouteM <= strayThresholdM(accuracyM)) {
        _strayCount = 0;
        _strayingSince = null;
        return const OffRouteDecision(state: OffRouteState.onRoute);
      }
      _strayCount++;
      _strayingSince ??= now;
      final longEnough = now.difference(_strayingSince!) >= offRouteAfter;
      if (_strayCount < offRouteFixes && !longEnough) {
        return const OffRouteDecision(state: OffRouteState.onRoute);
      }
      _state = OffRouteState.guiding;
      _offSince = now;
      _offTravelM = 0;
      _spokenDistanceM = null;
      _detourAt = null;
    }

    // Back on the plan, from either off-route state: the rider found it
    // again, and whatever was worked out for them is not needed.
    if (distanceFromRouteM <= snapThresholdM(accuracyM)) return _restore();

    if (rerouteAllowed && _wantsFullReroute(distanceFromRouteM, now)) {
      return OffRouteDecision(state: _state, fullReroute: true);
    }

    if (_state == OffRouteState.detour) {
      final drift = distanceFromDetourM;
      final planned = _detourAt;
      final stale =
          planned == null || now.difference(planned) >= detourRecomputeGap;
      final adrift =
          drift != null &&
          drift > strayThresholdM(accuracyM, baseM: detourDriftMeters);
      return OffRouteDecision(
        state: _state,
        planDetour: rerouteAllowed && adrift && stale,
      );
    }

    final guidance = _guidanceTo(position, headingDeg, alongM);
    final due =
        _spokenDistanceM == null ||
        (guidance != null &&
            guidance.distanceM >= _spokenDistanceM! + guidanceRepeatMeters);
    if (due && guidance != null) _spokenDistanceM = guidance.distanceM;
    return OffRouteDecision(
      state: _state,
      guidance: guidance,
      speakGuidance: due && guidance != null,
      planDetour: rerouteAllowed && _wantsDetour(now),
    );
  }

  /// Whether the rider has been guided long enough, or far enough, that a
  /// rejoin is worth computing.
  bool _wantsDetour(DateTime now) {
    final since = _offSince;
    if (since == null) return false;
    return now.difference(since) >= detourAfter ||
        _offTravelM >= detourAfterMeters;
  }

  /// Whether the ride has drifted so far, for so long, that heading back to
  /// the plan at all has stopped making sense.
  bool _wantsFullReroute(double distanceFromRouteM, DateTime now) {
    final since = _offSince;
    if (since == null) return false;
    return distanceFromRouteM > fullRerouteMeters &&
        now.difference(since) > fullRerouteAfter;
  }

  /// Notes that a rejoin is now being followed, so the drift clock starts.
  void detourStarted(DateTime now) {
    _state = OffRouteState.detour;
    _detourAt = now;
  }

  /// Notes that the whole ride was re-planned: the machine's plan is gone, so
  /// the caller builds a new machine and this one only has to stop asking.
  void reset() {
    _state = OffRouteState.onRoute;
    _strayCount = 0;
    _strayingSince = null;
    _offSince = null;
    _offTravelM = 0;
    _spokenDistanceM = null;
    _detourAt = null;
  }

  OffRouteDecision _restore() {
    final was = _state;
    reset();
    return OffRouteDecision(
      state: OffRouteState.onRoute,
      restored: was != OffRouteState.onRoute,
    );
  }

  /// The nearest point of the plan that is still ahead of the rider.
  ///
  /// "Ahead" is along-track progress, not straight-line distance: sending a
  /// rider back to a corner they already rode is the one thing a guide back
  /// must never do. A plan that comes back to where it started is the
  /// exception — there its start is ahead of them — so a loop is searched
  /// whole.
  OffRouteGuidance? _guidanceTo(
    LatLng position,
    double? headingDeg,
    double alongM,
  ) {
    if (_line.isEmpty) return null;
    var bestIndex = -1;
    var bestDistance = double.infinity;
    for (var i = 0; i < _line.length; i++) {
      if (!_loop && _cumulative[i] < alongM - _aheadSlackM) continue;
      final distance = haversineMeters(position, _line[i]);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }
    // Past the end of the plan: the end itself is the only point left.
    if (bestIndex < 0) {
      bestIndex = _line.length - 1;
      bestDistance = haversineMeters(position, _line[bestIndex]);
    }
    return OffRouteGuidance(
      target: _line[bestIndex],
      distanceM: bestDistance,
      alongM: _cumulative[bestIndex],
      direction: relativeDirection(
        bearingDegrees(position, _line[bestIndex]),
        headingDeg,
      ),
    );
  }
}

/// Which way [bearingDeg] lies for a rider headed [headingDeg], or `null`
/// when the heading is unknown.
RelativeDirection? relativeDirection(double bearingDeg, double? headingDeg) {
  if (headingDeg == null) return null;
  var delta = (bearingDeg - headingDeg) % 360;
  if (delta >= 180) delta -= 360;
  if (delta < -180) delta += 360;
  final magnitude = delta.abs();
  if (magnitude <= _aheadDegrees) return RelativeDirection.ahead;
  if (magnitude >= _behindDegrees) return RelativeDirection.behind;
  return delta > 0 ? RelativeDirection.right : RelativeDirection.left;
}

/// The point [metres] ahead of [position] on bearing [headingDeg], for a
/// rejoin that has to respect which way the rider is going.
///
/// `null` when the rider is too slow for their heading to mean anything, in
/// which case the rejoin is asked for without a via point and BRouter is free
/// to send them back the way they came.
LatLng? headingViaPoint({
  required LatLng position,
  required double? headingDeg,
  required double speedMps,
}) {
  if (headingDeg == null || speedMps <= headingViaSpeedMps) return null;
  return destinationPoint(position, headingDeg, headingViaMeters);
}

/// The points of [line] a rejoin should aim for: [rejoinTargetsM] metres
/// further along than [alongM], each clamped to the end of the line.
///
/// Duplicates are dropped, so a plan with less than 300 m left is asked for
/// once rather than three times.
List<RejoinTarget> rejoinTargets(
  List<LatLng> line,
  List<double> cumulative,
  double alongM,
) {
  if (line.isEmpty) return const <RejoinTarget>[];
  final total = cumulative.isEmpty ? 0.0 : cumulative.last;
  final out = <RejoinTarget>[];
  final seen = <int>{};
  for (final offset in rejoinTargetsM) {
    final wanted = math.min(alongM + offset, total);
    final index = _indexAt(cumulative, wanted);
    if (!seen.add(index)) continue;
    out.add(
      RejoinTarget(index: index, point: line[index], alongM: cumulative[index]),
    );
  }
  return out;
}

/// The first point of the line at or past [metres] along it.
int _indexAt(List<double> cumulative, double metres) {
  for (var i = 0; i < cumulative.length; i++) {
    if (cumulative[i] >= metres) return i;
  }
  return cumulative.length - 1;
}

/// One place a rejoin could put the rider back on the plan.
class RejoinTarget {
  /// Creates the target.
  const RejoinTarget({
    required this.index,
    required this.point,
    required this.alongM,
  });

  /// Which point of the plan it is.
  final int index;

  /// Where that point is.
  final LatLng point;

  /// How far along the plan it sits, in metres.
  final double alongM;

  @override
  String toString() =>
      'RejoinTarget(#$index at ${alongM.toStringAsFixed(0)} m)';
}
