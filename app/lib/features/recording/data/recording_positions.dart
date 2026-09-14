import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:velorki_geo/velorki_geo.dart';

import '../../map/data/position_provider.dart';

/// The position stream a recording needs, per platform.
///
/// Five metres of movement between fixes is the same filter the map puck uses,
/// but the accuracy is pushed to the maximum: a ride is stored once and drawn
/// forever, a puck only has to look right for a second.
///
/// On Android geolocator's own foreground notification stays switched off: the
/// foreground service belongs to `flutter_foreground_task`, and two services
/// would mean two notifications. On iOS there is no service at all, so the
/// location manager itself has to be told to keep running in the background
/// and never to pause updates on its own.
geo.LocationSettings recordingLocationSettings({TargetPlatform? platform}) {
  final target = platform ?? defaultTargetPlatform;
  switch (target) {
    case TargetPlatform.android:
      return geo.AndroidSettings(
        accuracy: geo.LocationAccuracy.best,
        distanceFilter: 5,
        intervalDuration: const Duration(seconds: 1),
      );
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return geo.AppleSettings(
        accuracy: geo.LocationAccuracy.best,
        distanceFilter: 5,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
        activityType: geo.ActivityType.fitness,
      );
    case TargetPlatform.fuchsia:
    case TargetPlatform.linux:
    case TargetPlatform.windows:
      return const geo.LocationSettings(
        accuracy: geo.LocationAccuracy.best,
        distanceFilter: 5,
      );
  }
}

/// A geolocator fix as a track point, with the fields the platform did not
/// measure left `null` rather than zero.
///
/// The `has*` flags are not trusted on their own: geolocator_android drops
/// them when it rebuilds a position, which left every ride without an
/// altitude and so without any ascent. See [MapPosition.measuredValue].
TrackPoint trackPointFromPosition(geo.Position position) => TrackPoint(
  LatLng(position.latitude, position.longitude),
  ele: MapPosition.measuredValue(
    position.altitude,
    flagged: position.hasAltitude,
  ),
  time: position.timestamp.toUtc(),
  speedMps: MapPosition.measuredValue(
    position.speed,
    flagged: position.hasSpeed,
  ),
  accuracyM: MapPosition.measuredValue(
    position.accuracy,
    flagged: position.hasAccuracy,
  ),
  headingDeg: MapPosition.measuredValue(
    position.heading,
    flagged: position.hasHeading,
  ),
);

/// The fixes of a recording, ready for the engine.
Stream<TrackPoint> recordingFixes(
  PositionSource source, {
  TargetPlatform? platform,
}) => source
    .positions(recordingLocationSettings(platform: platform))
    .map(trackPointFromPosition);
