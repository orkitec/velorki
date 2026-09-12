import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../common/data/connected_accounts_repository.dart';
import '../common/data/external_route_cache.dart';
import '../common/domain/connected_account.dart';
import '../common/domain/external_route.dart';
import '../common/domain/integration_exception.dart';
import '../rwgps/data/rwgps_client.dart';
import '../rwgps/data/rwgps_providers.dart';
import '../strava/data/strava_client.dart';
import '../strava/data/strava_providers.dart';

/// Reads one service's route list and one route's GPX.
abstract class ExternalRoutesSource {
  /// The service this source speaks for.
  IntegrationService get service;

  /// The connected account's routes, newest first.
  Future<List<ExternalRoute>> fetchRoutes();

  /// One route as a GPX file.
  Future<Uint8List> fetchGpx(String routeId);
}

/// `GET /athletes/{id}/routes` and `GET /routes/{id}/export_gpx`.
class StravaRoutesSource implements ExternalRoutesSource {
  /// Creates a source.
  StravaRoutesSource({required this.client, required this.athleteId});

  /// The Strava client, already carrying the athlete's token.
  final StravaClient client;

  /// The connected athlete; Strava has no "current athlete" route list.
  final String athleteId;

  @override
  IntegrationService get service => IntegrationService.strava;

  @override
  Future<List<ExternalRoute>> fetchRoutes() async => <ExternalRoute>[
    for (final route in await client.listRoutes(athleteId: athleteId))
      ExternalRoute(
        id: route.id,
        name: route.name,
        distanceM: route.distanceM,
        elevationGainM: route.elevationGainM,
        description: route.description,
        createdAt: route.createdAt,
      ),
  ];

  @override
  Future<Uint8List> fetchGpx(String routeId) => client.exportRouteGpx(routeId);
}

/// `GET /api/v1/routes.json` and `GET /api/v1/routes/{id}.gpx`.
class RwgpsRoutesSource implements ExternalRoutesSource {
  /// Creates a source.
  RwgpsRoutesSource({required this.client});

  /// The Ride with GPS client.
  final RwgpsClient client;

  @override
  IntegrationService get service => IntegrationService.rwgps;

  @override
  Future<List<ExternalRoute>> fetchRoutes() async => <ExternalRoute>[
    for (final route in await client.listRoutes())
      ExternalRoute(
        id: route.id,
        name: route.name,
        distanceM: route.distanceM,
        elevationGainM: route.elevationGainM,
        description: route.description,
        createdAt: route.createdAt,
      ),
  ];

  @override
  Future<Uint8List> fetchGpx(String routeId) => client.routeGpx(routeId);
}

/// A route list together with when it was read.
class ExternalRoutesResult {
  /// Creates a result.
  const ExternalRoutesResult({
    required this.routes,
    required this.fetchedAt,
    required this.fromCache,
  });

  /// The routes, in the order the service returned them.
  final List<ExternalRoute> routes;

  /// When they were read from the service.
  final DateTime fetchedAt;

  /// Whether they came out of the seven-day cache rather than the network.
  final bool fromCache;
}

/// Reads a route list, through the seven-day cache.
class ExternalRoutesLoader {
  /// Creates a loader.
  ExternalRoutesLoader({
    required this.source,
    required this.cache,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Where the routes come from.
  final ExternalRoutesSource source;

  /// The seven-day list cache.
  final ExternalRouteListCache cache;

  final DateTime Function() _clock;

  /// The route list, from the cache when it is fresh.
  ///
  /// Every read of the cache enforces the seven-day rule, so a list that has
  /// been sitting there longer is dropped and fetched again.
  Future<ExternalRoutesResult> load({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = cache.read(source.service);
      if (cached != null) {
        return ExternalRoutesResult(
          routes: <ExternalRoute>[
            for (final entry in cached.routes) ExternalRoute.fromJson(entry),
          ],
          fetchedAt: cached.fetchedAt,
          fromCache: true,
        );
      }
    }
    final routes = await source.fetchRoutes();
    await cache.write(source.service, <Map<String, Object?>>[
      for (final route in routes) route.toJson(),
    ]);
    return ExternalRoutesResult(
      routes: routes,
      fetchedAt: _clock().toUtc(),
      fromCache: false,
    );
  }

  /// One route's GPX.
  Future<Uint8List> gpx(String routeId) => source.fetchGpx(routeId);
}

/// The route source of [service], or `null` when nothing is connected.
final externalRoutesSourceProvider =
    Provider.family<ExternalRoutesSource?, IntegrationService>((ref, service) {
      switch (service) {
        case IntegrationService.strava:
          final athleteId = ref.watch(stravaAthleteIdProvider);
          if (athleteId == null || athleteId.isEmpty) return null;
          return StravaRoutesSource(
            client: ref.watch(stravaClientProvider),
            athleteId: athleteId,
          );
        case IntegrationService.rwgps:
          if (ref.watch(connectedAccountProvider(service)) == null) return null;
          return RwgpsRoutesSource(client: ref.watch(rwgpsClientProvider));
      }
    });

/// The loader for [service], or `null` when nothing is connected.
final externalRoutesLoaderProvider =
    Provider.family<ExternalRoutesLoader?, IntegrationService>((ref, service) {
      final source = ref.watch(externalRoutesSourceProvider(service));
      if (source == null) return null;
      return ExternalRoutesLoader(
        source: source,
        cache: ref.watch(externalRouteListCacheProvider),
      );
    });

/// The exception shown when a route screen is opened without a connection.
IntegrationException notConnectedException(IntegrationService service) =>
    IntegrationException(
      IntegrationFailure.notConnected,
      'No ${service.id} account is connected.',
    );
