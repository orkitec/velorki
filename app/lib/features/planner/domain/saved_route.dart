import 'dart:typed_data';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../../core/db/database.dart' show RouteSource;
import 'route_legs.dart';
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

    /// Where each leg between two waypoints starts in [geometry], and
    /// whether it is a file's own line; `null` for a row saved before legs
    /// were stored, or from a route whose legs were not known.
    List<SavedLeg>? legs,

    /// The line and the markers the route was imported with, kept through
    /// every edit; `null` for a route planned here, or imported before
    /// that was kept.
    RouteOriginal? original,

    /// Whether [options] name a bike: `false` for a file that named none,
    /// which then opens with the bike the rider rode last.
    @Default(true) bool profileKnown,
  }) = _SavedRoute;

  const SavedRoute._();

  /// The track points, decoded from [geometryBlob] on every call.
  List<TrackPoint> get geometry => PackedTrack.decode(geometryBlob);

  /// Estimated riding time at the profile's typical speed.
  Duration get estimatedTime => profile.estimatedTime(distanceM);
}

/// A route as its file drew it: the line, the markers on it, where each leg
/// between them starts, and the file's cue sheet.
class RouteOriginal {
  /// Creates the original.
  RouteOriginal({
    required this.geometryBlob,
    required this.waypoints,
    required this.legs,
    this.turns = const <TurnHint>[],
  });

  /// The line, packed.
  final Uint8List geometryBlob;

  /// The markers: the ends and the named points on the line.
  final List<Waypoint> waypoints;

  /// Where the leg from each marker but the last starts; every one kept.
  final List<SavedLeg> legs;

  /// The file's turn instructions, anchored to the line.
  final List<TurnHint> turns;

  /// The line, decoded once.
  late final List<TrackPoint> geometry = PackedTrack.decode(geometryBlob);

  /// The line as bare coordinates.
  late final List<LatLng> positions = [for (final p in geometry) p.pos];
}
