import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../planner/application/planner_controller.dart';
import '../../planner/data/route_repository.dart';
import '../../recording/data/ride_repository.dart';
import '../common/data/connected_accounts_repository.dart';
import '../common/data/external_route_cache.dart';
import '../common/data/integration_connector.dart';
import '../common/domain/connected_account.dart';
import '../common/domain/integration_exception.dart';
import '../rwgps/data/rwgps_providers.dart';
import '../strava/data/strava_providers.dart';

final Logger _log = Logger('Connections');

/// The connector for [service], or `null` when this build has no relay or no
/// client id for it.
final integrationConnectorProvider =
    Provider.family<IntegrationConnector?, IntegrationService>(
      (ref, service) => switch (service) {
        IntegrationService.strava => ref.watch(stravaConnectorProvider),
        IntegrationService.rwgps => ref.watch(rwgpsConnectorProvider),
      },
    );

/// Whether [service] can be connected in this build.
final integrationConfiguredProvider = Provider.family<bool, IntegrationService>(
  (ref, service) => switch (service) {
    IntegrationService.strava => ref.watch(stravaConfiguredProvider),
    IntegrationService.rwgps => ref.watch(rwgpsConfiguredProvider),
  },
);

/// Runs the connect and disconnect actions and says which are in flight.
///
/// The state is the set of services with an action running, so both settings
/// tiles can show a spinner without a notifier each.
class IntegrationConnections extends Notifier<Set<IntegrationService>> {
  @override
  Set<IntegrationService> build() => const <IntegrationService>{};

  /// Whether an action is running for [service].
  bool isBusy(IntegrationService service) => state.contains(service);

  /// Runs the whole authorisation for [service] and stores the account.
  ///
  /// Throws [IntegrationException]; the caller shows it. A cancelled flow
  /// throws too, with [IntegrationFailure.cancelled], so the UI can stay
  /// silent for it.
  Future<void> connect(IntegrationService service) async {
    final connector = ref.read(integrationConnectorProvider(service));
    if (connector == null) {
      throw IntegrationException(
        IntegrationFailure.relayUnavailable,
        (l10n) => l10n.integrationNoRelay,
      );
    }
    if (!_begin(service)) return;
    try {
      final account = await connector.connect();
      await ref.read(connectedAccountsProvider.notifier).save(account);
      _log.info('connected ${service.id}');
    } finally {
      _end(service);
    }
  }

  /// Revokes at the service where that is possible, deletes the token and
  /// the service's route list, and for Strava every piece of Strava data on
  /// the phone ([forgetStravaData]).
  ///
  /// The local token always goes, even when the service could not be reached:
  /// a rider who pressed Disconnect has said what they want.
  Future<void> disconnect(IntegrationService service) async {
    if (!_begin(service)) return;
    try {
      final account = ref.read(connectedAccountProvider(service));
      final connector = ref.read(integrationConnectorProvider(service));
      if (account != null && connector != null) {
        await connector.revoke(account);
      }
      await _forget(service);
      _log.info('disconnected ${service.id}');
    } finally {
      _end(service);
    }
  }

  /// Strava refused the rider's authorization: they removed Velorki's access
  /// on strava.com. Strava's terms ask for the same as a disconnect, so the
  /// token and every piece of Strava data on the phone go, and the rider is
  /// told ([stravaAccessLostNoticeProvider]). Nothing to revoke: it is
  /// revoked already.
  Future<void> stravaAccessRevoked() async {
    const service = IntegrationService.strava;
    // A disconnect under way does the same and confirms it itself.
    if (!_begin(service)) return;
    try {
      if (ref.read(connectedAccountProvider(service)) == null &&
          await ref.read(connectedAccountsRepositoryProvider).read(service) ==
              null) {
        return;
      }
      await _forget(service);
      ref.read(stravaAccessLostNoticeProvider.notifier).show();
      _log.info('Strava access was revoked; Strava data deleted');
    } finally {
      _end(service);
    }
  }

  Future<void> _forget(IntegrationService service) async {
    await ref.read(connectedAccountsProvider.notifier).remove(service);
    await ref.read(externalRouteListCacheProvider).clear(service);
    if (service == IntegrationService.strava) await forgetStravaData();
  }

  /// Deletes everything on the phone that came from Strava: the routes read
  /// from Strava and the ones edited from them, a Strava route open in the
  /// planner, and the activity links of rides uploaded there. The rides
  /// themselves are the rider's own and stay.
  Future<void> forgetStravaData() async {
    final routes = await ref.read(routeRepositoryProvider).deleteStravaRoutes();
    await ref
        .read(rideRepositoryProvider)
        .forgetUploadsTo(IntegrationService.strava.id);
    if (ref.exists(plannerControllerProvider)) {
      ref.read(plannerControllerProvider.notifier).forgetStravaRoute();
    }
    _log.info('deleted $routes Strava routes');
  }

  bool _begin(IntegrationService service) {
    if (state.contains(service)) return false;
    state = <IntegrationService>{...state, service};
    return true;
  }

  void _end(IntegrationService service) =>
      state = <IntegrationService>{...state}..remove(service);
}

/// The connect and disconnect actions.
final integrationConnectionsProvider =
    NotifierProvider<IntegrationConnections, Set<IntegrationService>>(
      IntegrationConnections.new,
    );

/// Whether a connect or disconnect is running for [service].
final integrationBusyProvider = Provider.family<bool, IntegrationService>(
  (ref, service) => ref.watch(integrationConnectionsProvider).contains(service),
);

/// Whether the rider still has to be told that Strava refused Velorki's
/// access and the Strava data on the phone was deleted.
class StravaAccessLostNotice extends Notifier<bool> {
  @override
  bool build() => false;

  /// Asks for the notice.
  void show() => state = true;

  /// The rider has seen it.
  void dismiss() => state = false;
}

/// See [StravaAccessLostNotice].
final stravaAccessLostNoticeProvider =
    NotifierProvider<StravaAccessLostNotice, bool>(StravaAccessLostNotice.new);

/// Acts on every refusal [stravaAccessRevokedProvider] reports. Called once
/// from `bootstrap()` with the app's container.
void listenForStravaRevocation(ProviderContainer container) {
  container.listen<int>(stravaAccessRevokedProvider, (previous, next) {
    if (next == (previous ?? 0)) return;
    unawaited(
      container
          .read(integrationConnectionsProvider.notifier)
          .stravaAccessRevoked(),
    );
  });
}
