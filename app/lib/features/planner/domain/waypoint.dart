import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'route_poi.dart';

part 'waypoint.freezed.dart';

/// Where a waypoint sits in the ordered list.
enum WaypointKind { start, via, end }

/// One point the route has to pass through.
@freezed
abstract class Waypoint with _$Waypoint {
  const factory Waypoint({
    required LatLng pos,
    @Default(WaypointKind.via) WaypointKind kind,

    /// The point's name: from the place search when it came from there, or
    /// typed in by the rider.
    String? name,

    /// What the point is about, for the marker on export and the map.
    @Default(PoiKind.generic) PoiKind poiKind,

    /// A line or two the rider wrote about the point.
    String? note,

    /// The manoeuvre, for a point of the [PoiKind.turn] kind: what the cue
    /// sheet says there. `null` for any other kind.
    TurnKind? turn,

    /// The word the file this point came from called it, kept so an export
    /// can write it back. See [RoutePoi.sourceType].
    String? sourceType,
  }) = _Waypoint;

  /// Whether the point carries anything beyond its position: a name or a
  /// note, which make it worth a `<wpt>` of its own on export.
  bool get hasDetails =>
      (name?.isNotEmpty ?? false) || (note?.isNotEmpty ?? false);

  const Waypoint._();

  /// Parses one entry of the `waypoints_json` column.
  ///
  /// Deliberately not called `fromJson`: that name would make freezed
  /// generate json_serializable code, which cannot handle [LatLng].
  factory Waypoint.fromMap(Map<String, dynamic> json) => Waypoint(
    pos: LatLng(
      (json['lat'] as num? ?? 0).toDouble(),
      (json['lon'] as num? ?? 0).toDouble(),
    ),
    kind: WaypointKind.values.firstWhere(
      (k) => k.name == json['kind'],
      orElse: () => WaypointKind.via,
    ),
    name: json['name'] as String?,
    poiKind: PoiKind.values.firstWhere(
      (k) => k.name == json['poi'],
      orElse: () => PoiKind.generic,
    ),
    note: json['note'] as String?,
    turn: json['turn'] == null
        ? null
        : TurnKind.values.firstWhere(
            (k) => k.name == json['turn'],
            orElse: () => TurnKind.straight,
          ),
    sourceType: json['source'] as String?,
  );

  /// One entry of the `waypoints_json` column.
  Map<String, dynamic> toMap() => <String, dynamic>{
    'lat': pos.lat,
    'lon': pos.lon,
    'kind': kind.name,
    if (name != null) 'name': name,
    if (poiKind != PoiKind.generic) 'poi': poiKind.name,
    if (note != null) 'note': note,
    if (turn != null) 'turn': turn!.name,
    if (sourceType != null) 'source': sourceType,
  };
}

/// The waypoints of [waypoints] that carry a name or a note, as points of
/// interest: what a GPX export writes them as, beside the route's own.
List<RoutePoi> waypointPois(List<Waypoint> waypoints) => <RoutePoi>[
  for (final w in waypoints)
    if (w.hasDetails && w.poiKind != PoiKind.turn)
      RoutePoi(
        pos: w.pos,
        name: w.name ?? '',
        description: w.note,
        kind: w.poiKind,
        sourceType: w.sourceType,
      ),
];

/// Returns [waypoints] with start, via and end kinds set from the order.
///
/// A single waypoint is a start; the last of several is the end.
List<Waypoint> normalizeWaypointKinds(List<Waypoint> waypoints) {
  return List<Waypoint>.generate(waypoints.length, (i) {
    final kind = i == 0
        ? WaypointKind.start
        : (i == waypoints.length - 1 ? WaypointKind.end : WaypointKind.via);
    final w = waypoints[i];
    return w.kind == kind ? w : w.copyWith(kind: kind);
  }, growable: false);
}

/// The waypoints of the [PoiKind.turn] kind as the cue sheet's turns, each
/// at the point of [geometry] nearest to it, its name as the note. What a
/// save writes into the route's turns, beside the router's own.
List<TurnHint> waypointTurns(List<Waypoint> waypoints, List<LatLng> geometry) {
  if (geometry.isEmpty) return const <TurnHint>[];
  final turns = <TurnHint>[];
  for (final w in waypoints) {
    if (w.poiKind != PoiKind.turn) continue;
    var best = 0;
    var bestD = double.infinity;
    for (var i = 0; i < geometry.length; i++) {
      final d = haversineMeters(geometry[i], w.pos);
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    turns.add(
      TurnHint(
        pointIndex: best,
        kind: w.turn ?? TurnKind.straight,
        note: w.name ?? w.note,
      ),
    );
  }
  return turns;
}

/// [turns] with the turn waypoints of [waypoints] merged in: a waypoint's
/// turn replaces the router's at the same point of [geometry], the rest
/// stay, in point order.
List<TurnHint> mergeWaypointTurns(
  List<TurnHint> turns,
  List<Waypoint> waypoints,
  List<LatLng> geometry,
) {
  final own = waypointTurns(waypoints, geometry);
  if (own.isEmpty) return turns;
  final at = {for (final t in own) t.pointIndex};
  final merged = <TurnHint>[
    for (final t in turns)
      if (!at.contains(t.pointIndex)) t,
    ...own,
  ]..sort((a, b) => a.pointIndex.compareTo(b.pointIndex));
  return merged;
}
