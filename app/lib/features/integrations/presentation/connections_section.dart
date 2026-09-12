import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/plus/plus_gate.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../subscription/presentation/plus_upsell_card.dart';
import '../application/connections_controller.dart';
import '../common/data/connected_accounts_repository.dart';
import '../common/domain/connected_account.dart';
import '../common/domain/integration_exception.dart';
import 'integration_labels.dart';
import 'strava_brand.dart';

/// The Plus feature that gates [service].
PlusFeature plusFeatureFor(IntegrationService service) => switch (service) {
  IntegrationService.strava => PlusFeature.stravaConnection,
  IntegrationService.rwgps => PlusFeature.rwgpsConnection,
};

/// Settings → Connections: one tile per partner service.
///
/// Both connections are Velorki Plus features, so an unentitled rider sees
/// the upsell card, which leads to the paywall, and disabled Connect
/// buttons.
class ConnectionsSection extends ConsumerWidget {
  /// Creates the section.
  const ConnectionsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gated = IntegrationService.values.any(
      (service) => !ref.watch(plusFeatureProvider(plusFeatureFor(service))),
    );
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (gated) PlusUpsellCard(body: l10n.connectionsPlusBody),
        for (final service in IntegrationService.values)
          ConnectionTile(service: service),
      ],
    );
  }
}

/// One partner service's connect or disconnect tile.
class ConnectionTile extends ConsumerWidget {
  /// Creates a tile for [service].
  const ConnectionTile({required this.service, super.key});

  /// The service this tile connects.
  final IntegrationService service;

  Future<void> _connect(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(integrationConnectionsProvider.notifier).connect(service);
    } on IntegrationException catch (e) {
      // A rider who closed the page does not need to be told what they did.
      if (e.failure == IntegrationFailure.cancelled) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.connectionsConnectFailed(e.message))),
      );
    }
  }

  Future<void> _disconnect(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final label = serviceLabel(l10n, service);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.connectionsDisconnectTitle(label)),
        content: Text(l10n.connectionsDisconnectBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.connectionsDisconnect),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(integrationConnectionsProvider.notifier).disconnect(service);
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.connectionsDisconnected(label))),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final account = ref.watch(connectedAccountProvider(service));
    final entitled = ref.watch(plusFeatureProvider(plusFeatureFor(service)));
    final configured = ref.watch(integrationConfiguredProvider(service));
    final busy = ref.watch(integrationBusyProvider(service));
    final connect = entitled && configured
        ? () => unawaited(_connect(context, ref))
        : null;
    // Strava's button is their artwork at its own width, which does not fit
    // into a list tile's trailing slot, so it sits under the tile instead.
    final branded = service == IntegrationService.strava;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: Icon(
            service == IntegrationService.strava
                ? Icons.directions_bike_outlined
                : Icons.map_outlined,
          ),
          title: Text(serviceLabel(l10n, service)),
          subtitle: Text(
            !configured
                ? l10n.connectionsUnavailable
                : account == null
                ? l10n.connectionsNotConnected
                : account.athleteName ?? l10n.connectionsConnected,
          ),
          trailing: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : account != null
              ? TextButton(
                  onPressed: () => unawaited(_disconnect(context, ref)),
                  child: Text(l10n.connectionsDisconnect),
                )
              : branded
              ? null
              : FilledButton.tonal(
                  onPressed: connect,
                  child: Text(connectLabel(l10n, service)),
                ),
        ),
        if (branded && !busy && account == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: StravaConnectButton(
                label: connectLabel(l10n, service),
                onPressed: connect,
              ),
            ),
          ),
      ],
    );
  }
}
