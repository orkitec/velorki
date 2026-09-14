import 'dart:math' as math;

import 'package:velorki_brouter/velorki_brouter.dart';

import '../domain/navigation_progress.dart';

/// The farthest a turn is announced from.
const double _aheadM = 300;

/// A turn nearer than this when it first comes into view gets no advance
/// warning: there is no time to say it twice, so only the "now" cue follows.
const double _tooLateForAheadM = 120;

/// The shortest distance a "now" cue is given at, whatever the speed.
const double _nowFloorM = 40;

/// A second turn this close behind the first is tacked onto its cue as a
/// "then ..." so the rider hears both while there is still time.
const double _thenM = 80;

/// What a cue tells the rider.
enum CueKind {
  /// A turn is coming up in [TurnCue.distanceM] metres.
  ahead,

  /// Take the turn now.
  now,

  /// The rider has left the route.
  offRoute,

  /// The rider is back on the route.
  backOnRoute,

  /// A new way back onto the route has been computed and is now being
  /// followed. Given by the controller, not by [TurnAnnouncer].
  rerouted,

  /// The end of the route is reached.
  arrived,
}

/// One thing to say (or show) once.
class TurnCue {
  /// Creates a cue.
  const TurnCue({required this.kind, this.turn, this.distanceM = 0, this.then});

  /// What kind of cue this is.
  final CueKind kind;

  /// The turn the cue is about; `null` for the route-wide cues.
  final TurnHint? turn;

  /// The distance to announce, in metres. Rounded for [CueKind.ahead].
  final int distanceM;

  /// A second turn following straight after [turn], for "..., then keep right".
  final TurnHint? then;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TurnCue &&
          other.kind == kind &&
          other.turn == turn &&
          other.distanceM == distanceM &&
          other.then == then;

  @override
  int get hashCode => Object.hash(kind, turn, distanceM, then);

  @override
  String toString() =>
      'TurnCue(${kind.name}'
      '${turn != null ? ' ${turn!.kind.name}@${turn!.pointIndex}' : ''}'
      '${distanceM != 0 ? ' in $distanceM m' : ''}'
      '${then != null ? ' then ${then!.kind.name}' : ''})';
}

/// Turns a stream of [NavigationProgress] values into cues, each given once.
///
/// The navigator reports the same turn on every fix; this decides when there
/// is something new to say. Cues are remembered per turn (by its point index),
/// so a turn that is passed during a GPS gap is simply left behind rather than
/// announced late.
class TurnAnnouncer {
  final Set<int> _seen = <int>{};
  final Set<int> _aheadGiven = <int>{};
  final Set<int> _nowGiven = <int>{};
  bool _offRoute = false;
  bool _arrived = false;

  /// The cues [p] calls for, in the order they should be said.
  ///
  /// [speedMps] stretches the "now" cue: at 10 m/s it comes 40 m out, giving
  /// the same four seconds of warning as at walking pace.
  List<TurnCue> update(NavigationProgress p, {double speedMps = 0}) {
    final cues = <TurnCue>[];

    if (p.offRoute && !_offRoute) {
      _offRoute = true;
      cues.add(const TurnCue(kind: CueKind.offRoute));
    } else if (!p.offRoute && _offRoute) {
      _offRoute = false;
      cues.add(const TurnCue(kind: CueKind.backOnRoute));
    }

    final next = p.next;
    if (next != null) {
      final key = next.pointIndex;
      if (_seen.add(key) && p.distanceToNextM < _tooLateForAheadM) {
        // First sight and already close: skip the advance warning.
        _aheadGiven.add(key);
      }
      if (p.distanceToNextM <= _aheadM && _aheadGiven.add(key)) {
        cues.add(
          TurnCue(
            kind: CueKind.ahead,
            turn: next,
            distanceM: _roundedAhead(p.distanceToNextM),
          ),
        );
      }
      final nowAt = math.max(_nowFloorM, speedMps * 4);
      if (p.distanceToNextM <= nowAt && _nowGiven.add(key)) {
        cues.add(
          TurnCue(
            kind: CueKind.now,
            turn: next,
            distanceM: p.distanceToNextM.round(),
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

  /// Distances are announced in round numbers: the nearest 50 m, never less.
  static int _roundedAhead(double metres) =>
      math.max(50, (metres / 50).round() * 50);
}
