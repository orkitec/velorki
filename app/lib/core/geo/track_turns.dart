import 'track_thinning.dart';

import 'dart:math' as math;

import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// Turn instructions for a track that came without any.
///
/// A route read from a plain track file has a line and nothing else: no cue
/// sheet, no spoken turns, no course points on the way out. The router knows
/// what happens at every junction, so the track is routed through its own
/// points on the device, as `TrackSurfaceService` does for the surface, and
/// the router's turn instructions are put on the *track's* points. The line
/// itself never changes.
///
/// How a turn of the router finds its place on the track:
///
/// * The router's way is trusted only where it lies on the track. Around
///   each turn, the router's way from [TrackTurnService.windowM] before it to
///   as far after is sampled, and every sample has to be within
///   [TrackTurnService.toleranceM] of the track. Where the router went round
///   something the track crosses (a field, a path the map does not have, a
///   ferry), its turns are dropped: no turns on that stretch.
/// * The turn goes to the track's point nearest to it, among the stretches of
///   the track within the tolerance, the one at about the same distance along
///   the chunk as the turn is along the router's way: a track that comes back
///   the way it went passes every junction twice.
/// * The track has to turn the way the router says: a left where the track
///   bends left, a right where it bends right, measured over 30 m either side
///   of the point. A router that took a side street and came back, to reach
///   a waypoint just off the road, says "right" where the track goes
///   straight on, and that is dropped too.
/// * The track is routed in chunks of waypoints that overlap; each chunk
///   owns the turns from the middle of its overlap with the one before to the
///   middle of its overlap with the next, so a turn where two chunks meet is
///   neither lost (a router names no turn at its first or last point) nor
///   counted twice.

/// Why a track got turns, or did not.
enum TrackTurnsState {
  /// The track was routed and [TrackTurns.turns] are the turns found.
  generated,

  /// There is no on-device routing at all.
  noRouting,

  /// The tiles for the track's area are not on the phone; see
  /// [TrackTurns.missingTiles].
  noTiles,

  /// The router could not follow any part of the track.
  unmatched,
}

/// The outcome of [TrackTurnService.generate].
class TrackTurns {
  const TrackTurns._(
    this.state, {
    this.turns = const <TurnHint>[],
    this.missingTiles = const <TileName>[],
  });

  /// What happened.
  final TrackTurnsState state;

  /// The turns, anchored to the track's own points, ending with the finish;
  /// only for [TrackTurnsState.generated]. Empty there only when the track
  /// was too short to say anything about.
  final List<TurnHint> turns;

  /// The tiles the track needs and the phone does not have, for
  /// [TrackTurnsState.noTiles].
  final List<TileName> missingTiles;
}

/// Finds turn instructions for a track by routing through its points on the
/// device. See the library comment above for how they are placed.
class TrackTurnService {
  /// Creates the service over [local], the on-device engine (or `null`
  /// without one), and [decide], the coverage rule.
  TrackTurnService({
    required this.local,
    required this.decide,
    this.maxPointsPerQuery = 50,
    this.overlap = 2,
    this.timeout = const Duration(seconds: 60),
    this.toleranceM = 40,
    this.windowM = 50,
    this.minTurnDeg = 20,
  }) : assert(
         maxPointsPerQuery > overlap + 2,
         'a chunk has to reach past its overlaps',
       );

  /// The on-device engine, or `null` when routing is server-only or off.
  final RoutingBackend? local;

  /// Whether the tiles for a query are on disk.
  final RoutingDecision Function(RouteQuery query) decide;

  /// The most waypoints in one routing request.
  final int maxPointsPerQuery;

  /// How many waypoint gaps two chunks in a row share.
  final int overlap;

  /// The deadline per request.
  final Duration timeout;

  /// How far the router's way may lie from the track and still count as
  /// the track, in metres: a GPS track drawn beside the road, or a road
  /// mapped a few metres off, is still that road.
  final double toleranceM;

  /// How far before and after a turn the router's way has to keep to the
  /// track, in metres.
  final double windowM;

  /// How much the track has to bend for a left or a right to count, in
  /// degrees.
  final double minTurnDeg;

  /// The profile: the way that follows the points most closely.
  static const String profile = 'shortest';

  /// The waypoints [points] would be routed through, as indices: the ones
  /// the surface is matched through, every corner and a point every 250 m,
  /// which keep the router on the track's own streets.
  static List<int> waypointsOf(List<TrackPoint> points) =>
      thinTrackIndices(points);

  /// The tiles [points] need that are not on the phone: empty when all are,
  /// `null` when there is no on-device routing at all.
  List<TileName>? missingTiles(List<TrackPoint> points) {
    if (local == null) return null;
    final waypoints = [for (final i in waypointsOf(points)) points[i].pos];
    if (waypoints.length < 2) return const <TileName>[];
    return decide(RouteQuery(points: waypoints, profile: profile)).missingTiles;
  }

  /// The turns along [points]. [onProgress] hears after each chunk how many
  /// of how many are done; [cancel] stops between and during requests.
  Future<TrackTurns> generate({
    required List<TrackPoint> points,
    void Function(int done, int total)? onProgress,
    CancelToken? cancel,
  }) async {
    final backend = local;
    if (backend == null) return const TrackTurns._(TrackTurnsState.noRouting);
    if (points.length < 2) {
      return const TrackTurns._(TrackTurnsState.unmatched);
    }
    final line = [for (final p in points) p.pos];
    final indices = waypointsOf(points);
    if (indices.length < 2) {
      return const TrackTurns._(TrackTurnsState.unmatched);
    }
    final waypoints = [for (final i in indices) line[i]];
    final coverage = decide(RouteQuery(points: waypoints, profile: profile));
    if (!coverage.hasLocalCoverage) {
      return TrackTurns._(
        TrackTurnsState.noTiles,
        missingTiles: coverage.missingTiles,
      );
    }

    final along = cumulativeDistancesMeters(line);
    final chunks = trackChunks(indices.length, maxPointsPerQuery, overlap);
    final found = <TurnHint>[];
    var routed = 0;
    onProgress?.call(0, chunks.length);
    for (var c = 0; c < chunks.length; c++) {
      if (cancel?.isCancelled ?? false) throw cancel!.toException();
      final (from, to) = chunks[c];
      final ownFrom = c == 0 ? 0 : indices[(chunks[c - 1].$2 + from) ~/ 2];
      final ownTo = c == chunks.length - 1
          ? line.length
          : indices[(to + chunks[c + 1].$1) ~/ 2];
      final RouteResult result;
      try {
        result = await backend.route(
          RouteQuery(
            points: waypoints.sublist(from, to + 1),
            profile: profile,
            alternativeIdx: 0,
            timeout: timeout,
            profileParams: turnInstructionParams,
          ),
          cancel: cancel,
        );
      } on RoutingException catch (e) {
        if (e.kind == RoutingErrorKind.cancelled) rethrow;
        // A chunk the router could not follow is a stretch without turns,
        // not a track without any.
        onProgress?.call(c + 1, chunks.length);
        continue;
      }
      routed++;
      found.addAll(
        mapRoutedTurns(
          track: line,
          trackAlong: along,
          matched: result.positions,
          turns: result.turns,
          from: indices[from],
          to: indices[to],
          ownFrom: ownFrom,
          ownTo: ownTo,
          toleranceM: toleranceM,
          windowM: windowM,
          minTurnDeg: minTurnDeg,
        ),
      );
      onProgress?.call(c + 1, chunks.length);
    }
    if (routed == 0) return const TrackTurns._(TrackTurnsState.unmatched);
    return TrackTurns._(
      TrackTurnsState.generated,
      turns: finishTurns(found, along),
    );
  }
}

/// Told to the `shortest` profile, which sets none of these, so its turn
/// instructions come out as a bike profile's do: turns within 40 m of each
/// other merged into one, and a roundabout said as a roundabout.
const Map<String, String> turnInstructionParams = <String, String>{
  'turnInstructionCatchingRange': '40',
  // A profile variable, so a number: the parser reads no `true`.
  'turnInstructionRoundabouts': '1',
};

/// Consecutive runs of at most [maxPoints] of [count] waypoints, as inclusive
/// `(first, last)` indices, each one starting [overlap] waypoints before the
/// one before it ended.
List<(int, int)> trackChunks(int count, int maxPoints, int overlap) {
  final out = <(int, int)>[];
  if (count < 2) return out;
  var start = 0;
  while (true) {
    final end = math.min(start + maxPoints - 1, count - 1);
    out.add((start, end));
    if (end == count - 1) break;
    start = end - overlap;
  }
  return out;
}

/// The turns of one routed chunk put on the track.
///
/// [matched] is the router's way and [turns] its turns, anchored to it;
/// [from] and [to] are the track's points the chunk was routed between, and
/// only turns that land in `[ownFrom, ownTo)` are kept. The rules are the
/// library comment's.
List<TurnHint> mapRoutedTurns({
  required List<LatLng> track,
  required List<double> trackAlong,
  required List<LatLng> matched,
  required List<TurnHint> turns,
  int from = 0,
  int? to,
  int ownFrom = 0,
  int? ownTo,
  double toleranceM = 40,
  double windowM = 50,
  double minTurnDeg = 20,
}) {
  final last = to ?? track.length - 1;
  final own = ownTo ?? track.length;
  if (matched.length < 2 || last <= from) return const <TurnHint>[];
  final matchedAlong = cumulativeDistancesMeters(matched);
  final matchedTotal = matchedAlong.last;
  final out = <TurnHint>[];
  for (final turn in turns) {
    if (turn.kind == TurnKind.end ||
        turn.kind == TurnKind.offRoad ||
        turn.kind == TurnKind.beeline) {
      continue;
    }
    final k = turn.pointIndex;
    if (k < 0 || k >= matched.length) continue;
    final at = matchedAlong[k];

    // The router's way around the turn has to be the track's.
    var onTrack = true;
    for (final offset in <double>[-1, -0.5, 0, 0.5, 1]) {
      final sample = _pointAt(
        matched,
        matchedAlong,
        (at + offset * windowM).clamp(0, matchedTotal),
      );
      if (_distanceToTrack(sample, track, from, last) > toleranceM) {
        onTrack = false;
        break;
      }
    }
    if (!onTrack) continue;

    final expected =
        trackAlong[from] +
        (matchedTotal <= 0 ? 0 : at / matchedTotal) *
            (trackAlong[last] - trackAlong[from]);
    final index = _nearestIndex(
      track,
      trackAlong,
      matched[k],
      from,
      last,
      expected,
      toleranceM,
    );
    if (index == null || index < ownFrom || index >= own) continue;
    final kind = _kindOnTrack(turn.kind, track, trackAlong, index, minTurnDeg);
    if (kind == null) continue;
    out.add(
      TurnHint(
        pointIndex: index,
        kind: kind,
        exitNumber: turn.exitNumber,
        // A U-turn made a sharp turn takes the track's angle with it.
        angleDeg: kind == turn.kind
            ? turn.angleDeg
            : trackBendAt(track, trackAlong, index) ?? turn.angleDeg,
        note: turn.note,
      ),
    );
  }
  return out;
}

/// The turns of every chunk as one list for the track whose cumulative
/// distances are [trackAlong]: in order, one per point, none on the first
/// or the last point, each with the distance to the next, and the finish.
List<TurnHint> finishTurns(List<TurnHint> found, List<double> trackAlong) {
  final lastIndex = trackAlong.length - 1;
  if (lastIndex < 1) return const <TurnHint>[];
  final sorted = [...found]
    ..sort((a, b) => a.pointIndex.compareTo(b.pointIndex));
  final kept = <TurnHint>[];
  for (final t in sorted) {
    if (t.pointIndex <= 0 || t.pointIndex >= lastIndex) continue;
    if (kept.isNotEmpty && kept.last.pointIndex == t.pointIndex) continue;
    kept.add(t);
  }
  kept.add(TurnHint(pointIndex: lastIndex, kind: TurnKind.end));
  return [
    for (var i = 0; i < kept.length; i++)
      TurnHint(
        pointIndex: kept[i].pointIndex,
        kind: kept[i].kind,
        exitNumber: kept[i].exitNumber,
        angleDeg: kept[i].angleDeg,
        note: kept[i].note,
        distanceToNextM: i + 1 < kept.length
            ? trackAlong[kept[i + 1].pointIndex] -
                  trackAlong[kept[i].pointIndex]
            : 0,
      ),
  ];
}

/// What the router's [kind] is on the track at [index]: itself where the
/// track bends that way, `null` where it does not.
///
/// A U-turn is the exception. The router says one wherever a waypoint sits
/// on a hairpin or just off the road, and goes back the way it came; unless
/// the track itself does that, it is the sharp turn the track makes there.
TurnKind? _kindOnTrack(
  TurnKind kind,
  List<LatLng> track,
  List<double> along,
  int index,
  double minDeg,
) {
  final bend = trackBendAt(track, along, index);
  // Too near an end to measure: the router's word stands, but for a U-turn,
  // which there is a waypoint's artefact.
  if (bend == null) return _isUTurn(kind) ? null : kind;
  final ok = switch (kind) {
    TurnKind.left || TurnKind.sharpLeft => bend <= -minDeg,
    TurnKind.right || TurnKind.sharpRight => bend >= minDeg,
    TurnKind.slightLeft ||
    TurnKind.keepLeft ||
    TurnKind.exitLeft => bend <= minDeg,
    TurnKind.slightRight ||
    TurnKind.keepRight ||
    TurnKind.exitRight => bend >= -minDeg,
    _ => true,
  };
  if (!ok) return null;
  if (!_isUTurn(kind)) return kind;
  if (_retraces(track, along, index)) return kind;
  if (bend.abs() < minDeg) return null;
  final sharp = bend.abs() >= 120;
  return bend < 0
      ? (sharp ? TurnKind.sharpLeft : TurnKind.left)
      : (sharp ? TurnKind.sharpRight : TurnKind.right);
}

bool _isUTurn(TurnKind kind) =>
    kind == TurnKind.uTurn ||
    kind == TurnKind.uTurnLeft ||
    kind == TurnKind.uTurnRight;

/// Whether the track goes back the way it came at [index]: the point
/// [spanM] after it is within [withinM] of the point as far before it.
bool _retraces(
  List<LatLng> track,
  List<double> along,
  int index, {
  double spanM = 30,
  double withinM = 12,
}) {
  final before = _pointAt(
    track,
    along,
    (along[index] - spanM).clamp(0, along.last),
  );
  final after = _pointAt(
    track,
    along,
    (along[index] + spanM).clamp(0, along.last),
  );
  return haversineMeters(before, after) <= withinM;
}

/// How much the track bends at [index], in degrees, negative to the left:
/// the heading over the [spanM] into it against the heading over the
/// [spanM] out of it; `null` within [spanM] of either end.
double? trackBendAt(
  List<LatLng> track,
  List<double> along,
  int index, {
  double spanM = 30,
}) {
  var back = index;
  while (back > 0 && along[index] - along[back] < spanM) {
    back--;
  }
  var ahead = index;
  while (ahead < track.length - 1 && along[ahead] - along[index] < spanM) {
    ahead++;
  }
  if (along[index] - along[back] < spanM / 2 ||
      along[ahead] - along[index] < spanM / 2) {
    return null;
  }
  final into = bearingDegrees(track[back], track[index]);
  final out = bearingDegrees(track[index], track[ahead]);
  var d = (out - into) % 360;
  if (d > 180) d -= 360;
  return d;
}

/// The track's point in `[from, to]` a turn at [p] belongs to, or `null`
/// when the track is nowhere within [toleranceM] of it.
///
/// The segments within the tolerance come in runs, one per pass of the
/// track by the turn; the run nearest [expectedAlong] wins, and in it the
/// end of the nearest segment that is nearer the turn.
int? _nearestIndex(
  List<LatLng> track,
  List<double> along,
  LatLng p,
  int from,
  int to,
  double expectedAlong,
  double toleranceM,
) {
  int? best;
  double? bestGap;
  int? runBest;
  double runDistance = double.infinity;
  double runAlong = 0;
  void closeRun() {
    if (runBest == null) return;
    final gap = (runAlong - expectedAlong).abs();
    if (bestGap == null || gap < bestGap!) {
      best = runBest;
      bestGap = gap;
    }
    runBest = null;
    runDistance = double.infinity;
  }

  for (var i = from; i < to; i++) {
    final (distance, t) = _toSegment(p, track[i], track[i + 1]);
    if (distance > toleranceM) {
      closeRun();
      continue;
    }
    if (distance < runDistance) {
      runDistance = distance;
      runBest = t < 0.5 ? i : i + 1;
      runAlong = along[i] + t * (along[i + 1] - along[i]);
    }
  }
  closeRun();
  return best;
}

/// The distance from [p] to the track between [from] and [to].
double _distanceToTrack(LatLng p, List<LatLng> track, int from, int to) {
  var best = double.infinity;
  for (var i = from; i < to; i++) {
    final (d, _) = _toSegment(p, track[i], track[i + 1]);
    if (d < best) best = d;
  }
  return best;
}

const double _earthRadiusM = 6371008.8;

/// The distance from [p] to the segment [a]–[b] in metres, and where along
/// it the nearest point lies, 0 at [a] and 1 at [b]: flat-earth around [p],
/// which is plenty for tens of metres.
(double, double) _toSegment(LatLng p, LatLng a, LatLng b) {
  final k = math.pi / 180 * _earthRadiusM;
  final c = math.cos(p.lat * math.pi / 180);
  final ax = (a.lon - p.lon) * k * c;
  final ay = (a.lat - p.lat) * k;
  final bx = (b.lon - p.lon) * k * c;
  final by = (b.lat - p.lat) * k;
  final dx = bx - ax;
  final dy = by - ay;
  final len2 = dx * dx + dy * dy;
  final t = len2 <= 0 ? 0.0 : (-(ax * dx + ay * dy) / len2).clamp(0.0, 1.0);
  final x = ax + t * dx;
  final y = ay + t * dy;
  return (math.sqrt(x * x + y * y), t);
}

/// The point [alongM] metres along [line].
LatLng _pointAt(List<LatLng> line, List<double> cumulative, double alongM) {
  var i = 1;
  while (i < line.length - 1 && cumulative[i] < alongM) {
    i++;
  }
  final span = cumulative[i] - cumulative[i - 1];
  final t = span <= 0 ? 0.0 : ((alongM - cumulative[i - 1]) / span);
  final a = line[i - 1];
  final b = line[i];
  final f = t.clamp(0.0, 1.0);
  return LatLng(a.lat + (b.lat - a.lat) * f, a.lon + (b.lon - a.lon) * f);
}
