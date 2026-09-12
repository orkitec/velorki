import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:velorki_geo/velorki_geo.dart';

part 'waypoint.freezed.dart';

/// Where a waypoint sits in the ordered list.
enum WaypointKind { start, via, end }

/// One point the route has to pass through.
@freezed
abstract class Waypoint with _$Waypoint {
  const factory Waypoint({
    required LatLng pos,
    @Default(WaypointKind.via) WaypointKind kind,

    /// Label from the place search, when the point came from there.
    String? name,
  }) = _Waypoint;

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
  );

  /// One entry of the `waypoints_json` column.
  Map<String, dynamic> toMap() => <String, dynamic>{
    'lat': pos.lat,
    'lon': pos.lon,
    'kind': kind.name,
    if (name != null) 'name': name,
  };
}

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
