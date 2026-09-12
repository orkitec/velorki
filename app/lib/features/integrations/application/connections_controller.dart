import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../common/data/connected_accounts_repository.dart';
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
        'This build cannot connect ${service.id}: no relay is configured.',
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

  /// Revokes at the service where that is possible and deletes the token.
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
      await ref.read(connectedAccountsProvider.notifier).remove(service);
      _log.info('disconnected ${service.id}');
    } finally {
      _end(service);
    }
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
