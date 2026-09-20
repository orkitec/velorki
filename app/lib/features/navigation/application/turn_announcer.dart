import 'dart:math' as math;

import 'package:velorki_brouter/velorki_brouter.dart';

import '../domain/navigation_progress.dart';
import '../domain/off_route_guidance.dart';
import '../../planner/domain/route_poi.dart';

/// How many seconds before a turn it is announced unless the rider says
/// otherwise. Ten seconds at 20 km/h is 55 m: time to hear it, look up and
/// find the turning. OsmAnd's cycling profile says 22 s, Garmin a fixed
/// 160 m; both are commonly found early.
const int defaultLeadSeconds = 10;

/// The slowest speed the lead is worked out at, 10 km/h. Standing at a
/// light or coasting, the announcement still comes a sensible way out
/// rather than at the kerb.
const double _minSpeedMps = 2.8;

/// The closest the advance warning is ever given, whatever the speed.
const double _aheadFloorM = 50;

/// How many seconds before the turn the "now" cue comes.
const double _nowSeconds = 3;

/// The closest the "now" cue is ever given, whatever the speed.
const double _nowFloorM = 30;

/// How much travel the advance warning needs before the "now" cue: the
/// seconds it takes to say. A turn that comes into view closer than that
/// gets the "now" cue alone, so the two are never heard on top of each
/// other.
const double _sayingSeconds = 3;

/// A second turn this close behind the first is tacked onto its cue as a
/// "then ..." so the rider hears both while there is still time.
const double _thenM = 80;

/// What a cue tells the rider.
enum CueKind {
  /// A turn is coming up in [TurnCue.distanceM] metres.
  ahead,

  /// Take the turn now.
  now,

  /// The rider has left the route and is being pointed back at it, from
  /// [TurnCue.distanceM] metres away and [TurnCue.direction] of where they
  /// are headed. Given by the controller, not by [TurnAnnouncer].
  backToRoute,

  /// A new way back onto the route has been computed and is now being
  /// followed. Given by the controller, not by [TurnAnnouncer].
  rerouted,

  /// The end of the route is reached.
  arrived,

  /// A point of interest on the route is [TurnCue.distanceM] metres ahead.
  /// Given by the controller, not by [TurnAnnouncer].
  poi,
}

/// One thing to say (or show) once.
class TurnCue {
  /// Creates a cue.
  const TurnCue({
    required this.kind,
    this.turn,
    this.distanceM = 0,
    this.then,
    this.direction,
    this.poi,
  });

  /// What kind of cue this is.
  final CueKind kind;

  /// The turn the cue is about; `null` for the route-wide cues.
  final TurnHint? turn;

  /// The distance to announce, in metres. Rounded for [CueKind.ahead].
  final int distanceM;

  /// A second turn following straight after [turn], for "..., then keep right".
  final TurnHint? then;

  /// Which way the rider has to go, for [CueKind.backToRoute]; `null`
  /// elsewhere, and when the rider's heading is unknown.
  final RelativeDirection? direction;

  /// The point of interest, for [CueKind.poi]; `null` elsewhere.
  final RoutePoi? poi;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TurnCue &&
          other.kind == kind &&
          other.turn == turn &&
          other.distanceM == distanceM &&
          other.then == then &&
          other.direction == direction &&
          other.poi == poi;

  @override
  int get hashCode => Object.hash(kind, turn, distanceM, then, direction, poi);

  @override
  String toString() =>
      'TurnCue(${kind.name}'
      '${turn != null ? ' ${turn!.kind.name}@${turn!.pointIndex}' : ''}'
      '${distanceM != 0 ? ' in $distanceM m' : ''}'
      '${then != null ? ' then ${then!.kind.name}' : ''}'
      '${direction != null ? ' ${direction!.name}' : ''})';
}

/// Turns a stream of [NavigationProgress] values into cues, each given once.
///
/// Turns only: leaving the route is [OffRouteMachine]'s business, because
/// what a rider needs to hear there is which way to go, not that something
/// is wrong. The navigator reports the same turn on every fix; this decides
/// when there is something new to say. Cues are remembered per turn (by its point index),
/// so a turn that is passed during a GPS gap is simply left behind rather than
/// announced late.
class TurnAnnouncer {
  final Set<int> _aheadGiven = <int>{};
  final Set<int> _nowGiven = <int>{};
  bool _arrived = false;

  /// The cues [p] calls for, in the order they should be said.
  ///
  /// Everything is timed in seconds of travel at [speedMps], never slower
  /// than 10 km/h: the advance warning [leadSeconds] out, the "now" cue a
  /// few seconds out. A turn that comes into view too late for the warning
  /// to be said before the "now" cue is due only gets the "now" cue.
  List<TurnCue> update(
    NavigationProgress p, {
    double speedMps = 0,
    int leadSeconds = defaultLeadSeconds,
  }) {
    final cues = <TurnCue>[];

    final next = p.next;
    if (next != null) {
      final key = next.pointIndex;
      final speed = math.max(_minSpeedMps, speedMps);
      final aheadAt = math.max(_aheadFloorM, speed * leadSeconds);
      final nowAt = math.max(_nowFloorM, speed * _nowSeconds);
      final sayingM = speed * _sayingSeconds;
      final d = p.distanceToNextM;
      if (d <= aheadAt && d > nowAt + sayingM && _aheadGiven.add(key)) {
        cues.add(
          TurnCue(
            kind: CueKind.ahead,
            turn: next,
            distanceM: roundedAheadMeters(d),
          ),
        );
      }
      if (d <= nowAt && _nowGiven.add(key)) {
        cues.add(
          TurnCue(
            kind: CueKind.now,
            turn: next,
            distanceM: d.round(),
            then: _thenTurn(next, p.after),
          ),
        );
      }
    }

    if (p.arrived && !_arrived) {
      _arrived = true;
      cues.add(const TurnCue(kind: CueKind.arrived));
    }
    return cues;
  }

  /// [after] when it follows close enough behind [next] to be said in the same
  /// breath. The route model carries how far the next hint is, which is what
  /// the gap is measured with.
  TurnHint? _thenTurn(TurnHint next, TurnHint? after) {
    if (after == null) return null;
    return next.distanceToNextM > 0 && next.distanceToNextM <= _thenM
        ? after
        : null;
  }
}

/// Distances are announced in round numbers: the nearest 10 m up to 100 m,
/// the nearest 50 m beyond, never less than 50.
int roundedAheadMeters(double metres) => metres < 100
    ? math.max(50, (metres / 10).round() * 10)
    : (metres / 50).round() * 50;
