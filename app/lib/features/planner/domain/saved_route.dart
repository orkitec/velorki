import 'dart:typed_data';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../../core/db/database.dart' show RouteSource;
import 'route_profile.dart';
import 'routing_options.dart';
import 'route_poi.dart';
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

    /// Set once the track was matched against the routing tiles and could
    /// not be followed, so the card says so instead of trying again on
    /// every open. See `TrackSurfaceCache`.
    @Default(false) bool surfaceUnavailable,

    /// BRouter's turn instructions, anchored to indices of [geometry]. Empty
    /// for routes that never went through the router (file imports) and for
    /// rows saved before the app stored them.
    @Default(<TurnHint>[]) List<TurnHint> turns,

    /// Whether [description] was written by the model rather than by the
    /// rider. Shown next to the text and re-set when it is written again.
    @Default(false) bool aiDescriptionGenerated,

    /// The points of interest the route came with: an imported file's
    /// waypoints. Empty for a route planned here.
    @Default(<RoutePoi>[]) List<RoutePoi> pois,

    /// A web address the route came with: the file's `<link>`, or one the
    /// rider typed on the card.
    String? link,

    /// Who wrote the file the route came from, its `creator`, or the
    /// manufacturer of the device; `null` for a route planned here.
    String? creator,
  }) = _SavedRoute;

  const SavedRoute._();

  /// The track points, decoded from [geometryBlob] on every call.
  List<TrackPoint> get geometry => PackedTrack.decode(geometryBlob);

  /// Estimated riding time at the profile's typical speed.
  Duration get estimatedTime => profile.estimatedTime(distanceM);
}
