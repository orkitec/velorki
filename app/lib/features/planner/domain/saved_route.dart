import 'dart:typed_data';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../../core/db/database.dart' show RouteSource;
import 'route_profile.dart';
import 'routing_options.dart';
import 'waypoint.dart';

part 'saved_route.freezed.dart';

/// A row of the `routes` table as the app thinks of it.
///
/// The geometry stays packed in [geometryBlob] so a library list of a hundred
/// routes does not decode a million track points; [geometry] unpacks it on
/// demand.
@freezed
abstract class SavedRoute with _$SavedRoute {
  const factory SavedRoute({
    required String id,
    required String name,
    required RouteSource source,
    required RouteProfile profile,
    required DateTime createdAt,
    required DateTime updatedAt,
    required double distanceM,
    required double ascentM,
    required double descentM,
    required BoundingBox bounds,
    required Uint8List geometryBlob,
    required List<Waypoint> waypoints,
    required RoutingOptions options,
    String? description,
    SurfaceStats? surfaceStats,

    /// Whether [description] was written by the model rather than by the
    /// rider. Shown next to the text and re-set when it is written again.
    @Default(false) bool aiDescriptionGenerated,
  }) = _SavedRoute;

  const SavedRoute._();

  /// The track points, decoded from [geometryBlob] on every call.
  List<TrackPoint> get geometry => PackedTrack.decode(geometryBlob);

  /// Estimated riding time at the profile's typical speed.
  Duration get estimatedTime => profile.estimatedTime(distanceM);
}
