import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../../core/permissions/location_permission.dart';

part 'position_provider.g.dart';

/// What the map needs from a GPS fix, without geolocator's types leaking into
/// the presentation layer.
@immutable
class MapPosition {
  const MapPosition({
    required this.position,
    required this.accuracyM,
    required this.timestamp,
    this.headingDeg,
    this.speedMps,
  });

  /// Builds one from a geolocator [geo.Position].
  factory MapPosition.fromGeolocator(geo.Position p) => MapPosition(
    position: LatLng(p.latitude, p.longitude),
    accuracyM: measuredValue(p.accuracy, flagged: p.hasAccuracy) ?? 0,
    timestamp: p.timestamp,
    headingDeg: measuredValue(p.heading, flagged: p.hasHeading),
    speedMps: measuredValue(p.speed, flagged: p.hasSpeed),
  );

  /// A geolocator field's value, or `null` when the platform measured none.
  ///
  /// The `has*` flags cannot be trusted on Android: geolocator_android's
  /// `AndroidPosition.fromMap` rebuilds the position through a constructor
  /// that never forwards them, so every fix claims to have no accuracy, no
  /// course and no speed — which is why the puck had neither an accuracy ring
  /// nor a heading. A set flag is therefore taken at face value (iOS reports
  /// them properly, and an honest 0.0 stays a 0.0), while a clear flag falls
  /// back to the only other evidence there is: a non-zero finite value.
  static double? measuredValue(double value, {required bool flagged}) {
    if (!value.isFinite) return null;
    if (flagged) return value;
    return value == 0 ? null : value;
  }

  final LatLng position;
  final double accuracyM;
  final DateTime timestamp;
  final double? headingDeg;
  final double? speedMps;

  @override
  bool operator ==(Object other) =>
      other is MapPosition &&
      other.position == position &&
      other.accuracyM == accuracyM &&
      other.timestamp == timestamp &&
      other.headingDeg == headingDeg &&
      other.speedMps == speedMps;

  @override
  int get hashCode =>
      Object.hash(position, accuracyM, timestamp, headingDeg, speedMps);

  @override
  String toString() => 'MapPosition($position, ±${accuracyM}m)';
}

/// Five metres of movement between updates: enough for a smooth puck, far
/// less battery than a fix per second.
const geo.LocationSettings mapLocationSettings = geo.LocationSettings(
  accuracy: geo.LocationAccuracy.high,
  distanceFilter: 5,
);

/// The position stream, behind an interface so tests need no plugin.
abstract interface class PositionSource {
  /// A stream of fixes for the given [settings].
  Stream<geo.Position> positions(geo.LocationSettings settings);

  /// The last fix the OS cached, if any.
  Future<geo.Position?> lastKnown();

  /// One fresh fix, or `null` when none arrives within [timeLimit].
  Future<geo.Position?> current({Duration timeLimit});
}

/// [PositionSource] over geolocator.
class GeolocatorPositionSource implements PositionSource {
  const GeolocatorPositionSource();

  @override
  Stream<geo.Position> positions(geo.LocationSettings settings) =>
      geo.Geolocator.getPositionStream(locationSettings: settings);

  @override
  Future<geo.Position?> lastKnown() => geo.Geolocator.getLastKnownPosition();

  @override
  Future<geo.Position?> current({
    Duration timeLimit = const Duration(seconds: 10),
  }) async {
    try {
      return await geo.Geolocator.getCurrentPosition(
        locationSettings: geo.LocationSettings(
          accuracy: mapLocationSettings.accuracy,
          distanceFilter: mapLocationSettings.distanceFilter,
          timeLimit: timeLimit,
        ),
      );
    } on Object {
      // Timeout, or the fix was cancelled by the OS; the caller falls back to
      // the last known position.
      return null;
    }
  }
}

@Riverpod(keepAlive: true)
PositionSource positionSource(Ref ref) => const GeolocatorPositionSource();

/// The device position, or `null` while the permission is not granted.
///
/// Subscribing starts the GPS, so this provider is deliberately not
/// `keepAlive`: it stops as soon as the last map screen goes away.
@riverpod
Stream<MapPosition?> devicePosition(Ref ref) async* {
  final status = await ref.watch(locationPermissionControllerProvider.future);
  if (!status.isUsable) {
    yield null;
    return;
  }
  final source = ref.watch(positionSourceProvider);
  final last = await source.lastKnown();
  if (last != null) yield MapPosition.fromGeolocator(last);
  yield* source.positions(mapLocationSettings).map(MapPosition.fromGeolocator);
}
