import 'dart:math' as math;

import 'package:velorki_geo/velorki_geo.dart';

import '../domain/map_controller.dart';

/// Pure builders for the GeoJSON the map layers are fed with.
///
/// Everything here is free of Flutter and of maplibre_gl, so the shapes the
/// adapter hands to the platform view can be unit tested on the desktop VM.

/// Feature id of the waypoint at [index]. Android and iOS only report a
/// feature's top level `id` back in a drag event, so the index has to travel
/// inside it.
String waypointFeatureId(int index) => 'velorki-wp-$index';

/// Inverse of [waypointFeatureId]; `null` for anything else.
int? waypointIndexFromFeatureId(String? featureId) {
  if (featureId == null) return null;
  const prefix = 'velorki-wp-';
  if (!featureId.startsWith(prefix)) return null;
  return int.tryParse(featureId.substring(prefix.length));
}

/// A GeoJSON `FeatureCollection` with no features, used to blank a source.
Map<String, dynamic> emptyFeatureCollection() => <String, dynamic>{
  'type': 'FeatureCollection',
  'features': <Map<String, dynamic>>[],
};

/// `[lon, lat]`, the order GeoJSON mandates (RFC 7946 §3.1.1).
List<double> lngLat(LatLng p) => <double>[p.lon, p.lat];

/// One `LineString` feature, or an empty collection for fewer than two points
/// — a one point line is invalid GeoJSON and MapLibre drops the whole source.
Map<String, dynamic> lineFeatureCollection(
  List<LatLng> points, {
  Map<String, dynamic> properties = const <String, dynamic>{},
}) {
  if (points.length < 2) return emptyFeatureCollection();
  return <String, dynamic>{
    'type': 'FeatureCollection',
    'features': <Map<String, dynamic>>[
      <String, dynamic>{
        'type': 'Feature',
        'properties': Map<String, dynamic>.from(properties),
        'geometry': <String, dynamic>{
          'type': 'LineString',
          'coordinates': points.map(lngLat).toList(),
        },
      },
    ],
  };
}

/// The label drawn inside a waypoint circle: the 1-based position in the
/// list. A place name would not fit a 20 px disc; it lives in the plan.
String waypointLabel(MapWaypoint waypoint, int index) => '${index + 1}';

/// One `Point` feature per waypoint, each draggable and carrying its index.
///
/// `draggable: true` in the properties is what the Android and iOS sides look
/// for before they start a drag gesture on a raw style layer feature.
Map<String, dynamic> waypointsFeatureCollection(List<MapWaypoint> waypoints) {
  final features = <Map<String, dynamic>>[];
  for (var i = 0; i < waypoints.length; i++) {
    final w = waypoints[i];
    features.add(<String, dynamic>{
      'type': 'Feature',
      'id': waypointFeatureId(i),
      'properties': <String, dynamic>{
        'index': i,
        'kind': w.kind.name,
        'label': waypointLabel(w, i),
        'draggable': true,
      },
      'geometry': <String, dynamic>{
        'type': 'Point',
        'coordinates': lngLat(w.position),
      },
    });
  }
  return <String, dynamic>{'type': 'FeatureCollection', 'features': features};
}

/// Below this ground speed a GNSS course is noise, not a direction.
///
/// Geolocator reports course over ground, not where the phone is pointing:
/// standing still it jitters through the full circle. Half a walking pace is
/// where it settles into something worth drawing a cone for.
const double minHeadingSpeedMps = 0.8;

/// [headingDeg] folded into [0, 360), or `null` when it is no angle at all.
double? normalizedHeading(double? headingDeg) {
  if (headingDeg == null || !headingDeg.isFinite) return null;
  final normalized = headingDeg % 360;
  return normalized < 0 ? normalized + 360 : normalized;
}

/// The course to draw the heading cone at, or `null` when there is none worth
/// drawing — no course, a broken one, or the rider is not moving.
///
/// Only for a course over ground; a compass heading means something standing
/// still and goes through [normalizedHeading] instead.
double? puckHeading(double? headingDeg, double? speedMps) {
  if (speedMps == null || !speedMps.isFinite) return null;
  if (speedMps < minHeadingSpeedMps) return null;
  return normalizedHeading(headingDeg);
}

/// A single `Point` feature for the position puck, or an empty collection when
/// there is no fix.
///
/// `heading` is only written when [puckHeading] accepts the course, so the
/// cone layer can hide itself with `['has', 'heading']`. A caller that has
/// already decided on a course — the adapter, which smooths it over several
/// fixes — passes it as [resolvedHeadingDeg] and leaves [headingDeg] and
/// [speedMps] out.
Map<String, dynamic> positionFeatureCollection(
  LatLng? position, {
  double? accuracyM,
  double? headingDeg,
  double? speedMps,
  double? resolvedHeadingDeg,
}) {
  if (position == null) return emptyFeatureCollection();
  final heading = resolvedHeadingDeg ?? puckHeading(headingDeg, speedMps);
  return <String, dynamic>{
    'type': 'FeatureCollection',
    'features': <Map<String, dynamic>>[
      <String, dynamic>{
        'type': 'Feature',
        'id': 'velorki-position',
        'properties': <String, dynamic>{
          'accuracy': ?accuracyM,
          'heading': ?heading,
        },
        'geometry': <String, dynamic>{
          'type': 'Point',
          'coordinates': lngLat(position),
        },
      },
    ],
  };
}

/// Web Mercator ground resolution at zoom 0 in metres per pixel for a 256 px
/// tile, at the equator.
const double metersPerPixelAtZoom0 = 156543.03392804097;

/// Metres one screen pixel covers at [zoom] and [latitude].
double metersPerPixel(double zoom, double latitude) {
  final cos = math.max(math.cos(latitude * math.pi / 180.0), 1e-6);
  return metersPerPixelAtZoom0 * cos / math.pow(2, zoom);
}

/// A `circle-radius` style expression that keeps the accuracy ring at
/// [accuracyM] metres on the ground whatever the zoom.
///
/// Circle radii are in screen pixels, so the only way to express a real world
/// radius is to interpolate exponentially with base 2 between two zoom stops —
/// which is exactly how the pixels-per-metre ratio behaves.
List<Object> accuracyRingRadiusExpression(
  double accuracyM,
  double latitude, {
  double maxZoom = 22,
}) {
  final radiusAtZoom0 = accuracyM / metersPerPixel(0, latitude);
  return <Object>[
    'interpolate',
    <Object>['exponential', 2],
    <Object>['zoom'],
    0,
    radiusAtZoom0,
    maxZoom,
    radiusAtZoom0 * math.pow(2, maxZoom).toDouble(),
  ];
}
