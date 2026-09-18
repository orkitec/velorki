import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../../core/permissions/location_permission.dart';
import '../../recording/application/recording_controller.dart';
import 'shared_position_source.dart';

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
    headingDeg: measuredHeading(p.heading, flagged: p.hasHeading),
    speedMps: measuredSpeed(p.speed, flagged: p.hasSpeed),
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

  /// A geolocator course as a heading, or `null` when there is none.
  ///
  /// Core Location answers "I have no course" with -1 and still says the fix
  /// has one, so [measuredValue] hands that -1 straight on and the cone and
  /// the heading-up map swing to north every time the rider slows down.
  /// Anything off the compass rose is therefore dropped here, and the 360 a
  /// platform may report for due north is folded back to 0.
  static double? measuredHeading(double value, {required bool flagged}) {
    final heading = measuredValue(value, flagged: flagged);
    if (heading == null) return null;
    if (heading == 360) return 0;
    if (heading < 0 || heading > 360) return null;
    return heading;
  }

  /// A geolocator ground speed, or `null` when there is none.
  ///
  /// The same -1 as [measuredHeading]: nobody rides backwards through the
  /// ground, so a negative speed is the platform saying it did not measure
  /// one.
  static double? measuredSpeed(double value, {required bool flagged}) {
    final speed = measuredValue(value, flagged: flagged);
    if (speed == null || speed < 0) return null;
    return speed;
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

/// One shared platform stream for every consumer: geolocator on iOS refuses
/// a second stream, and the recorder subscribes while the map's is open.
@Riverpod(keepAlive: true)
PositionSource positionSource(Ref ref) =>
    SharedPositionSource(const GeolocatorPositionSource());

/// The device position, or `null` while the permission is not granted.
///
/// Subscribing starts the GPS, so this provider is deliberately not
/// `keepAlive`: it stops as soon as the last map screen goes away.
///
/// It also stands aside for the duration of a recording. The recorder already
/// holds a GPS client — on Android inside the foreground service — and the
/// record screen draws the puck from its snapshots, so a second client here
/// would double the most expensive part of a ride for a puck nobody is
/// looking at. The stream simply ends: ending it rather than reporting `null`
/// leaves the last fix on the maps that are not the record screen's, and the
/// provider is rebuilt, permission and all, the moment the ride is over.
@riverpod
Stream<MapPosition?> devicePosition(Ref ref) async* {
  final recording = ref.watch(
    recordingControllerProvider.select((state) => state.isRecording),
  );
  if (recording) return;
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
