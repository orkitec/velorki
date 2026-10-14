import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../../core/db/daos/routes_dao.dart';
import '../../../core/db/database.dart';
import '../../planner/application/planner_controller.dart';
import '../../planner/data/route_repository.dart';
import '../../planner/domain/saved_route.dart';
import '../common/data/connected_accounts_repository.dart';
import '../common/domain/connected_account.dart';
import '../common/domain/integration_exception.dart';
import '../strava/data/strava_providers.dart';
import 'connections_controller.dart';

final Logger _log = Logger('StravaRouteChecks');

/// Asks Strava whether a route still exists: `true`, `false` for gone, or
/// throws when it could not be asked.
typedef StravaRouteProbe = Future<bool> Function(String routeId);

/// Keeps the routes read from Strava a cache, as Strava's API policy asks.
///
/// A route read from Strava, or edited from one, is checked against Strava
/// once it was last found there more than [recheckAfter] ago. Found, only its
/// `external_fetched_at` moves on: the rider's edits stay. Gone (Strava's
/// 404), it is deleted. One that could not be found for more than
/// [dropAfter] — offline, Strava disconnected, every check failing — is
/// deleted too, checked or not.
///
/// The checks are one at a time and at most [maxChecksPerRun] a run, so a
/// big library stays inside the relay's Strava limits (60 calls an hour per
/// install) and leaves room for what the rider does.
class StravaRouteChecks {
  /// Creates the checks over the routes table. The probe is `null` while
  /// Strava is not connected: then nothing is asked, and only [dropAfter]
  /// applies.
  StravaRouteChecks(this._routes, this._probe, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// How long a route found on Strava is kept before it is asked about again.
  static const Duration recheckAfter = Duration(hours: 48);

  /// How long a route is kept that could not be found on Strava.
  static const Duration dropAfter = Duration(days: 7);

  /// The most routes asked about in one run.
  static const int maxChecksPerRun = 30;

  final RoutesDao _routes;
  final StravaRouteProbe? _probe;
  final DateTime Function() _clock;

  /// Runs the checks that are due and returns the ids of the routes deleted.
  Future<List<String>> run() async {
    final now = _clock().toUtc();
    final removed = <String>[];
    var asked = 0;
    var canAsk = _probe != null;
    for (final row in await _routes.stravaRouteChecks()) {
      final age = now.difference(row.checkedAt.toUtc());
      if (age <= recheckAfter) continue;
      final routeId = decodeExternalIds(row.externalIdsJson)[stravaRouteIdKey];
      if (canAsk && routeId != null && asked < maxChecksPerRun) {
        asked++;
        try {
          if (await _probe!(routeId)) {
            await _routes.setExternalFetchedAt(row.id, now);
            continue;
          }
          _log.info('route ${row.id} is gone on Strava');
          await _routes.deleteRoute(row.id);
          removed.add(row.id);
          continue;
        } on IntegrationException catch (e) {
          _log.info('could not check route ${row.id}: ${e.failure.name}');
          // Strava's quota or the rider's access is the problem, not this
          // route: nothing more is asked this run.
          if (e.failure == IntegrationFailure.rateLimited ||
              e.failure == IntegrationFailure.revoked ||
              e.failure == IntegrationFailure.notConnected) {
            canAsk = false;
          }
        }
      }
      if (age > dropAfter) {
        _log.info('route ${row.id} could not be checked for 7 days');
        await _routes.deleteRoute(row.id);
        removed.add(row.id);
      }
    }
    return removed;
  }
}

/// How many routes from Strava the last checks deleted that the rider has
/// not been told about yet; the shell shows it once and sets it back to 0.
class StravaRoutesRemovedNotice extends Notifier<int> {
  @override
  int build() => 0;

  /// Adds [count] removed routes to the notice.
  void add(int count) => state += count;

  /// The rider has been told.
  void dismiss() => state = 0;
}

/// See [StravaRoutesRemovedNotice].
final stravaRoutesRemovedNoticeProvider =
    NotifierProvider<StravaRoutesRemovedNotice, int>(
      StravaRoutesRemovedNotice.new,
    );

/// The checks over the app's database and, when Strava is connected, its
/// client.
final stravaRouteChecksProvider = Provider<StravaRouteChecks>((ref) {
  final connected =
      ref.watch(integrationConfiguredProvider(IntegrationService.strava)) &&
      ref.watch(connectedAccountProvider(IntegrationService.strava)) != null;
  return StravaRouteChecks(
    ref.watch(routesDaoProvider),
    connected ? ref.watch(stravaClientProvider).routeExists : null,
  );
});

/// Runs the checks after launch and then every hour while the app runs;
/// an hourly run with nothing due asks nobody. Called once from
/// `bootstrap()` with the app's container; the answer stops the timers.
void Function() startStravaRouteChecks(
  ProviderContainer container, {
  Duration firstAfter = const Duration(seconds: 20),
  Duration every = const Duration(hours: 1),
}) {
  var running = false;
  Future<void> tick() async {
    if (running) return;
    running = true;
    try {
      // The accounts first, so a connected Strava is asked, not skipped.
      await container.read(connectedAccountsProvider.future);
      final removed = await container.read(stravaRouteChecksProvider).run();
      if (removed.isEmpty) return;
      final planner = container.read(plannerControllerProvider);
      if (removed.contains(planner.savedRouteId)) {
        container.read(plannerControllerProvider.notifier).forgetStravaRoute();
      }
      container
          .read(stravaRoutesRemovedNoticeProvider.notifier)
          .add(removed.length);
    } on Object catch (e, st) {
      _log.warning('the Strava route checks failed', e, st);
    } finally {
      running = false;
    }
  }

  final first = Timer(firstAfter, () => unawaited(tick()));
  final periodic = Timer.periodic(every, (_) => unawaited(tick()));
  return () {
    first.cancel();
    periodic.cancel();
  };
}
