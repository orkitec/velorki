import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:velorki/core/db/database.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// A packed track of [count] points, a ride's with times and heart rate.
Uint8List packedTrack(int count, {int seed = 0}) => PackedTrack.encode([
  for (var i = 0; i < count; i++)
    TrackPoint(
      LatLng(32.65 + (i + seed) * 1e-5, -16.9 + i * 1e-5),
      ele: 100 + (i % 50).toDouble(),
      time: DateTime.utc(2026, 9, 12, 8).add(Duration(seconds: i)),
      heartRateBpm: 120 + i % 30,
    ),
]);

/// A route with every column filled.
RoutesCompanion fullRoute(
  String id, {
  int points = 50,
  RouteSource source = RouteSource.importedGpx,
  String? name,
}) {
  final at = DateTime(2026, 9, 12, 10, 30);
  return RoutesCompanion.insert(
    id: id,
    name: name ?? 'Route $id',
    description: const Value('Along the levada'),
    source: source,
    profile: 'trekking',
    createdAt: at,
    updatedAt: at.add(const Duration(hours: 1)),
    distanceM: 42000.5,
    ascentM: 310,
    descentM: 305.25,
    bboxMinLat: 32.6,
    bboxMinLon: -17.0,
    bboxMaxLat: 32.8,
    bboxMaxLon: -16.8,
    geometry: packedTrack(points),
    waypointsJson: '[{"lat":32.65,"lon":-16.9},{"lat":32.7,"lon":-16.85}]',
    routingOptionsJson: '{"profile":"trekking"}',
    surfaceStatsJson: const Value('{"paved":0.8}'),
    turnsJson: const Value('[{"i":3,"k":2}]'),
    poisJson: const Value('[{"lat":32.66,"lon":-16.89,"name":"Fountain"}]'),
    aiDescriptionGenerated: const Value(true),
    link: const Value('https://example.org/route'),
    creator: const Value('Garmin'),
    originalJson: const Value('{"waypoints":[]}'),
    originalGeometry: Value(packedTrack(points ~/ 2 + 1, seed: 7)),
    turnsGenerated: const Value(true),
  );
}

/// A ride with every column filled.
RidesCompanion fullRide(String id, {int points = 50, String? routeId}) {
  final start = DateTime(2026, 9, 12, 8);
  return RidesCompanion.insert(
    id: id,
    name: 'Ride $id',
    startedAt: start,
    endedAt: start.add(const Duration(hours: 2)),
    distanceM: 38000,
    movingTimeS: 6400,
    elapsedTimeS: 7200,
    ascentM: 280,
    descentM: 275,
    avgSpeedMps: 5.9,
    maxSpeedMps: 13.2,
    avgHeartRateBpm: const Value(141),
    maxHeartRateBpm: const Value(178),
    avgCadenceRpm: const Value(82),
    avgPowerW: const Value(190),
    routeId: Value(routeId),
    geometry: packedTrack(points),
    pausesJson: '[{"start":100,"end":200}]',
    notes: const Value('Windy at the top'),
    surfaceStatsJson: const Value('{"paved":0.9}'),
    lapsJson: const Value('[{"start":0}]'),
    deviceTotalsJson: const Value('{"calories":900}'),
    temperatures: Value(Uint8List.fromList(List.filled(points * 2, 1))),
    sourceFormat: const Value('fit'),
    creator: const Value('Wahoo'),
  );
}
