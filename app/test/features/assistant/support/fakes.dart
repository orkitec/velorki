import 'package:geolocator/geolocator.dart' as geo;
import 'package:velorki/core/permissions/location_permission.dart';
import 'package:velorki/features/assistant/domain/intent_resolver.dart';
import 'package:velorki/features/map/data/position_provider.dart';
import 'package:velorki/features/search/domain/search_result.dart';
import 'package:velorki_api/velorki_api.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// A geocoder whose answers the test writes down.
class FakeGeocoder implements PlaceGeocoder {
  /// Creates a geocoder answering from [results], keyed by the query.
  FakeGeocoder([Map<String, List<SearchResult>>? results])
    : results = results ?? <String, List<SearchResult>>{};

  /// What each query answers; an unknown query answers with nothing.
  final Map<String, List<SearchResult>> results;

  /// Thrown instead of answering, when set.
  Object? failure;

  /// Every query that arrived, in order.
  final List<String> queries = <String>[];

  /// The bias handed in with each query.
  final List<LatLng?> biases = <LatLng?>[];

  @override
  Future<List<SearchResult>> lookup(
    String query, {
    LatLng? bias,
    int limit = 5,
  }) async {
    queries.add(query);
    biases.add(bias);
    if (failure != null) throw failure!;
    return results[query] ?? const <SearchResult>[];
  }
}

/// A place the geocoder can answer with.
SearchResult place(String name, double lat, double lon, {String? city}) =>
    SearchResult(name: name, position: LatLng(lat, lon), city: city);

/// A `propose_route` answer, with the fields a test cares about.
RouteRequest routeRequest({
  double distanceKm = 60,
  bool loop = true,
  RouteStart start = const RouteStart(useCurrent: true),
  List<String> via = const <String>[],
  SurfacePreference surface = SurfacePreference.mixed,
  HillPreference hills = HillPreference.neutral,
  TrafficTolerance trafficTolerance = TrafficTolerance.low,
  ProfileHint profileHint = ProfileHint.trekking,
  String? notes,
  double confidence = 0.9,
}) => RouteRequest(
  distanceKm: distanceKm,
  loop: loop,
  start: start,
  via: via,
  surface: surface,
  hills: hills,
  trafficTolerance: trafficTolerance,
  profileHint: profileHint,
  notes: notes,
  confidence: confidence,
);

/// A location permission that is simply granted, so the assistant's position
/// lookup needs no plugin.
class GrantedLocationPermission implements LocationPermissionGateway {
  /// Creates the gateway.
  const GrantedLocationPermission();

  @override
  Future<LocationPermissionStatus> check() async =>
      LocationPermissionStatus.granted;

  @override
  Future<LocationPermissionStatus> request() async =>
      LocationPermissionStatus.granted;

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;
}

/// A position source that always answers with the same fix.
class FixedPositionSource implements PositionSource {
  /// Creates a source answering with [position].
  const FixedPositionSource(this.position);

  /// Where the device is.
  final LatLng position;

  geo.Position get _fix => geo.Position(
    latitude: position.lat,
    longitude: position.lon,
    timestamp: DateTime.utc(2026, 9, 12, 10),
    accuracy: 5,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
    hasAccuracy: true,
  );

  @override
  Stream<geo.Position> positions(geo.LocationSettings settings) =>
      Stream<geo.Position>.value(_fix);

  @override
  Future<geo.Position?> lastKnown() async => _fix;

  @override
  Future<geo.Position?> current({
    Duration timeLimit = const Duration(seconds: 10),
  }) async => _fix;
}
