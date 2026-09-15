import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:velorki_geo/velorki_geo.dart';

import '../../map/data/position_provider.dart';
import '../domain/gps_precision.dart';

/// The position stream a recording needs, for [precision], per platform.
///
/// Three profiles. `precise` is the best fix the phone can give, every five
/// metres, a second apart — a ride is stored once and drawn forever, so a
/// mountain-bike track is worth the drain. `normal` keeps the same rhythm at
/// the ordinary high accuracy, which on a road is the same line for less
/// energy. `saver` halves the duty cycle again: ten metres, two seconds,
/// which at 20 km/h is still a fix every 1.8 s.
///
/// On Android geolocator's own foreground notification stays switched off: the
/// foreground service belongs to `flutter_foreground_task`, and two services
/// would mean two notifications. On iOS there is no service at all, so the
/// location manager itself has to be told to keep running in the background
/// and never to pause updates on its own.
geo.LocationSettings recordingLocationSettings({
  TargetPlatform? platform,
  GpsPrecision precision = GpsPrecision.normal,
}) {
  final target = platform ?? defaultTargetPlatform;
  final accuracy = precision == GpsPrecision.precise
      ? geo.LocationAccuracy.best
      : geo.LocationAccuracy.high;
  final distanceFilter = precision == GpsPrecision.saver ? 10 : 5;
  final interval = precision == GpsPrecision.saver
      ? const Duration(seconds: 2)
      : const Duration(seconds: 1);
  switch (target) {
    case TargetPlatform.android:
      return geo.AndroidSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
        intervalDuration: interval,
      );
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return geo.AppleSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
        activityType: geo.ActivityType.fitness,
      );
    case TargetPlatform.fuchsia:
    case TargetPlatform.linux:
    case TargetPlatform.windows:
      return geo.LocationSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
      );
  }
}

/// A geolocator fix as a track point, with the fields the platform did not
/// measure left `null` rather than zero.
///
/// The `has*` flags are not trusted on their own: geolocator_android drops
/// them when it rebuilds a position, which left every ride without an
/// altitude and so without any ascent. See [MapPosition.measuredValue]. The
/// course and the speed go through the stricter checks as well, because Core
/// Location reports -1 for both when it has neither.
TrackPoint trackPointFromPosition(geo.Position position) => TrackPoint(
  LatLng(position.latitude, position.longitude),
  ele: MapPosition.measuredValue(
    position.altitude,
    flagged: position.hasAltitude,
  ),
  time: position.timestamp.toUtc(),
  speedMps: MapPosition.measuredSpeed(
    position.speed,
    flagged: position.hasSpeed,
  ),
  accuracyM: MapPosition.measuredValue(
    position.accuracy,
    flagged: position.hasAccuracy,
  ),
  headingDeg: MapPosition.measuredHeading(
    position.heading,
    flagged: position.hasHeading,
  ),
);

/// The fixes of a recording, ready for the engine.
Stream<TrackPoint> recordingFixes(
  PositionSource source, {
  TargetPlatform? platform,
  GpsPrecision precision = GpsPrecision.normal,
}) => source
    .positions(
      recordingLocationSettings(platform: platform, precision: precision),
    )
    .map(trackPointFromPosition);
