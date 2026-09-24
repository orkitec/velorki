import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../../core/geo/ride_stats.dart';

/// One stretch of a plan: the line between two consecutive waypoints.
///
/// A leg is either routed — drawn by the router with the plan's profile — or
/// kept: exactly as it came out of a file. An edit routes only the legs it
/// touches, so a route read from a file stays the file's course everywhere
/// the rider did not change it.
class RouteLeg {
  const RouteLeg._(this.result, {required this.kept, required this.fresh});

  /// A leg the router has just drawn, with everything it said about it.
  const RouteLeg.routed(RouteResult result)
    : this._(result, kept: false, fresh: true);

  /// A leg exactly as a file drew it: [geometry] as it is, its length and
  /// climb measured off the points, and the file's own [turns] (anchored to
  /// [geometry]).
  factory RouteLeg.kept(
    List<TrackPoint> geometry, {
    List<TurnHint> turns = const <TurnHint>[],
  }) => RouteLeg._(_measured(geometry, turns), kept: true, fresh: false);

  /// A leg the router drew once, read back from the library: the line it
  /// drew, but none of the router's figures, which were never stored per
  /// leg.
  factory RouteLeg.restored(
    List<TrackPoint> geometry, {
    List<TurnHint> turns = const <TurnHint>[],
  }) => RouteLeg._(_measured(geometry, turns), kept: false, fresh: false);

  /// The leg as a route of its own.
  final RouteResult result;

  /// Whether the leg is the file's own line rather than the router's.
  final bool kept;

  /// Whether [result] is the router's answer as it came, `messages` and
  /// all; what the surface figures of a plan can be read from.
  final bool fresh;

  /// The leg's line.
  List<TrackPoint> get geometry => result.geometry;

  /// This kept leg ridden the other way: the same line, back to front. Its
  /// turns are dropped, since a left one way is a right the other.
  RouteLeg reversedKept() {
    assert(kept, 'only a kept leg reverses; a routed one is routed again');
    return RouteLeg.kept(geometry.reversed.toList(growable: false));
  }

  /// Two kept legs that meet as one: [a] then [b], the shared point once.
  static RouteLeg joinKept(RouteLeg a, RouteLeg b) {
    assert(a.kept && b.kept, 'only kept legs join without routing');
    final offset = a.geometry.isEmpty ? 0 : a.geometry.length - 1;
    final skip = a.geometry.isNotEmpty && b.geometry.isNotEmpty ? 1 : 0;
    return RouteLeg.kept(
      <TrackPoint>[...a.geometry, ...b.geometry.skip(skip)],
      turns: <TurnHint>[
        ...a.result.turns.where((t) => t.kind != TurnKind.end),
        ...b.result.turns.map((t) => t.shifted(offset)),
      ],
    );
  }

  static RouteResult _measured(
    List<TrackPoint> geometry,
    List<TurnHint> turns,
  ) {
    final stats = computeRouteGeometryStats(geometry);
    return RouteResult(
      geometry: geometry,
      lengthM: stats.distanceM,
      ascentM: stats.ascentM,
      descentM: stats.descentM,
      messages: const <SegmentMessage>[],
      raw: const <String, dynamic>{},
      turns: turns,
    );
  }
}

/// Where a saved route's leg starts and what kind it is: what the library
/// stores per waypoint so a route opens with the legs it was saved with.
class SavedLeg {
  /// Creates the entry.
  const SavedLeg({required this.start, this.kept = false});

  /// The index into the route's geometry where the leg starts; it ends
  /// where the next one starts, or at the end of the line.
  final int start;

  /// Whether the leg is a file's own line.
  final bool kept;

  @override
  bool operator ==(Object other) =>
      other is SavedLeg && other.start == start && other.kept == kept;

  @override
  int get hashCode => Object.hash(start, kept);

  @override
  String toString() => 'SavedLeg($start${kept ? ', kept' : ''})';
}

/// A whole route joined from its legs: one line, one set of figures, and the
/// legs it was made of, so the next edit can replace only some of them.
///
/// The line runs leg after leg, the point two legs share once. Where two
/// legs do not meet — a routed leg starts where the router put the waypoint,
/// which is on a road, and the kept leg beside it where the file put it —
/// the gap is bridged by a straight line, which belongs to the routed leg:
/// a kept leg stays the file's line point for point.
class PlannedRoute extends RouteResult {
  PlannedRoute._({
    required this.legs,
    required this.legStarts,
    required super.geometry,
    required super.lengthM,
    required super.ascentM,
    required super.descentM,
    required super.messages,
    required super.turns,
    super.plainAscentM,
    super.totalTime,
    super.energyJ,
    super.name,
  }) : super(raw: const <String, dynamic>{});

  /// Joins [legs], at least one.
  ///
  /// Figures are summed over the legs. The `messages` the surface figures
  /// are read from are only carried when every leg is fresh from the
  /// router: figures for part of a route must not stand for all of it.
  ///
  /// A route read back from the library passes its stored [lengthM],
  /// [ascentM], [descentM] and [turns], so it shows what it was saved with
  /// until it is changed.
  factory PlannedRoute.join(
    List<RouteLeg> legs, {
    String? name,
    double? lengthM,
    double? ascentM,
    double? descentM,
    List<TurnHint>? turns,
  }) {
    assert(legs.isNotEmpty, 'a route has at least one leg');
    final geometry = <TrackPoint>[];
    final starts = <int>[];
    final joinedTurns = <TurnHint>[];
    var length = 0.0;
    var ascent = 0.0;
    var descent = 0.0;
    var plainAscent = 0.0;
    Duration? time = Duration.zero;
    double? energy = 0;
    for (var k = 0; k < legs.length; k++) {
      final leg = legs[k];
      final line = leg.geometry;
      int offset;
      if (geometry.isEmpty) {
        starts.add(0);
        offset = 0;
        geometry.addAll(line);
      } else if (line.isEmpty || line.first == geometry.last) {
        offset = geometry.length - 1;
        starts.add(offset);
        geometry.addAll(line.skip(1));
      } else {
        final previousEnd = geometry.length - 1;
        offset = geometry.length;
        starts.add(leg.kept ? offset : previousEnd);
        geometry.addAll(line);
      }
      final r = leg.result;
      length += r.lengthM;
      ascent += r.ascentM;
      descent += r.descentM;
      plainAscent += r.plainAscentM;
      time = time == null || r.totalTime == null ? null : time + r.totalTime!;
      energy = energy == null || r.energyJ == null ? null : energy + r.energyJ!;
      for (final t in r.turns) {
        // Only the last leg arrives anywhere.
        if (t.kind == TurnKind.end && k < legs.length - 1) continue;
        joinedTurns.add(t.shifted(offset));
      }
    }
    final complete = legs.every((l) => l.fresh);
    return PlannedRoute._(
      legs: List<RouteLeg>.unmodifiable(legs),
      legStarts: List<int>.unmodifiable(starts),
      geometry: geometry,
      lengthM: lengthM ?? length,
      ascentM: ascentM ?? ascent,
      descentM: descentM ?? descent,
      plainAscentM: plainAscent,
      messages: complete
          ? <SegmentMessage>[for (final l in legs) ...l.result.messages]
          : const <SegmentMessage>[],
      turns: turns ?? joinedTurns,
      totalTime: complete ? time : null,
      energyJ: complete ? energy : null,
      name: name,
    );
  }

  /// The legs, one per pair of consecutive waypoints.
  final List<RouteLeg> legs;

  /// Where each leg starts in [geometry].
  final List<int> legStarts;

  /// Whether any leg is a file's own line.
  bool get hasKeptLegs => legs.any((l) => l.kept);

  /// What the library stores of the legs.
  List<SavedLeg> get savedLegs => <SavedLeg>[
    for (var i = 0; i < legs.length; i++)
      SavedLeg(start: legStarts[i], kept: legs[i].kept),
  ];
}

/// The legs of a saved route, cut out of its [geometry] where [saved] says
/// they start, or `null` when [saved] does not describe [geometry] — a
/// damaged row is opened as a route of unknown legs rather than a wrong one.
///
/// [turns] go with the leg they fall on.
List<RouteLeg>? legsFromSaved(
  List<TrackPoint> geometry,
  List<SavedLeg> saved, {
  List<TurnHint> turns = const <TurnHint>[],
}) {
  if (saved.isEmpty || geometry.isEmpty || saved.first.start != 0) return null;
  for (var i = 1; i < saved.length; i++) {
    if (saved[i].start < saved[i - 1].start) return null;
  }
  if (saved.last.start >= geometry.length) return null;
  return <RouteLeg>[
    for (var i = 0; i < saved.length; i++)
      _slice(
        geometry,
        saved[i].start,
        i + 1 < saved.length ? saved[i + 1].start : geometry.length - 1,
        kept: saved[i].kept,
        turns: turns,
        last: i == saved.length - 1,
      ),
  ];
}

/// The legs of a line read from a file, split at [starts] (the geometry
/// index of each leg's first point, `0` first), every one of them kept.
List<RouteLeg> keptLegs(
  List<TrackPoint> geometry,
  List<int> starts, {
  List<TurnHint> turns = const <TurnHint>[],
}) => <RouteLeg>[
  for (var i = 0; i < starts.length; i++)
    _slice(
      geometry,
      starts[i],
      i + 1 < starts.length ? starts[i + 1] : geometry.length - 1,
      kept: true,
      turns: turns,
      last: i == starts.length - 1,
    ),
];

RouteLeg _slice(
  List<TrackPoint> geometry,
  int from,
  int to, {
  required bool kept,
  required List<TurnHint> turns,
  required bool last,
}) {
  final line = geometry.sublist(from, to + 1);
  final own = <TurnHint>[
    for (final t in turns)
      if (t.pointIndex >= from &&
          (last ? t.pointIndex <= to : t.pointIndex < to))
        t.shifted(-from),
  ];
  return kept
      ? RouteLeg.kept(line, turns: own)
      : RouteLeg.restored(line, turns: own);
}
