import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../app/app_config.dart';
import '../domain/connected_account.dart';

final Logger _log = Logger('ExternalRouteCache');

/// A route list as it was read from a partner service.
class CachedRouteList {
  /// Creates a cached list.
  const CachedRouteList({required this.fetchedAt, required this.routes});

  /// When the list was read from the service.
  final DateTime fetchedAt;

  /// The raw JSON of each route summary, as the service's model parses it.
  final List<Map<String, Object?>> routes;

  /// Whether the list is older than [ExternalRouteListCache.maxAge].
  bool isStale({required Duration maxAge, DateTime? now}) =>
      (now ?? DateTime.now()).toUtc().difference(fetchedAt) > maxAge;
}

/// The seven-day cache of the route lists read from Strava and Ride with GPS.
///
/// Strava's API agreement allows Strava data to be kept for seven days; after
/// that it must be fetched again or thrown away. The rule is applied to both
/// services so there is only one policy to reason about, and it is enforced on
/// read as well as by [purgeExpired] at launch — an app that is never opened
/// for a fortnight must not still be holding a Strava route list.
///
/// Only the list is cached. A route the rider actually imported becomes their
/// own `routes` row; its `external_fetched_at` records when it was read so a
/// later milestone can refresh it.
class ExternalRouteListCache {
  /// Creates a cache over [prefs].
  ExternalRouteListCache(this._prefs, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// How long a fetched list may be kept.
  static const Duration maxAge = Duration(days: 7);

  /// The shared_preferences key [service] is cached under.
  static String keyFor(IntegrationService service) =>
      'integrations.${service.id}.route_list';

  final SharedPreferences _prefs;
  final DateTime Function() _clock;

  /// The cached list for [service], or `null` when there is none or it has
  /// expired — an expired entry is deleted on the way out.
  CachedRouteList? read(IntegrationService service) {
    final raw = _prefs.getString(keyFor(service));
    if (raw == null || raw.isEmpty) return null;
    final decoded = _decode(raw);
    if (decoded == null) {
      _prefs.remove(keyFor(service)).ignore();
      return null;
    }
    if (decoded.isStale(maxAge: maxAge, now: _clock().toUtc())) {
      _log.info('dropping the ${service.id} route list: older than 7 days');
      _prefs.remove(keyFor(service)).ignore();
      return null;
    }
    return decoded;
  }

  /// Caches [routes] for [service] with the current instant.
  Future<void> write(
    IntegrationService service,
    List<Map<String, Object?>> routes,
  ) => _prefs.setString(
    keyFor(service),
    jsonEncode(<String, Object?>{
      'fetched_at': _clock().toUtc().toIso8601String(),
      'routes': routes,
    }),
  );

  /// Forgets the list of [service]; a disconnect does this.
  Future<void> clear(IntegrationService service) =>
      _prefs.remove(keyFor(service));

  /// Drops every list that is older than [maxAge].
  ///
  /// Called at launch so the rule holds even for an app that is never opened
  /// on the Strava screen again.
  Future<void> purgeExpired() async {
    for (final service in IntegrationService.values) {
      read(service);
    }
  }

  CachedRouteList? _decode(String raw) {
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?>) return null;
    final fetchedAt = DateTime.tryParse(decoded['fetched_at'] as String? ?? '')
        ?.toUtc();
    final routes = decoded['routes'];
    if (fetchedAt == null || routes is! List) return null;
    return CachedRouteList(
      fetchedAt: fetchedAt,
      routes: <Map<String, Object?>>[
        for (final entry in routes)
          if (entry is Map<String, Object?>) entry,
      ],
    );
  }
}

/// The route-list cache over the app's preferences.
final externalRouteListCacheProvider = Provider<ExternalRouteListCache>(
  (ref) => ExternalRouteListCache(ref.watch(sharedPreferencesProvider)),
);
