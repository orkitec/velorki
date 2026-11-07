import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/links/link_opener.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../application/connections_controller.dart';
import '../common/data/connected_accounts_repository.dart';
import '../common/domain/connected_account.dart';
import '../common/domain/integration_exception.dart';
import 'integration_labels.dart';
import 'strava_brand.dart';
import 'strava_consent_sheet.dart';

/// Settings → Connections: one tile per partner service this build can
/// actually connect. Both are free.
///
/// A service with no client id (or a build with no relay to hold the secret)
/// is left out rather than shown greyed out: the F-Droid flavour ships
/// without either, and Settings hides the whole row then — see
/// `docs/FDROID.md`.
class ConnectionsSection extends ConsumerWidget {
  /// Creates the section.
  const ConnectionsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final service in IntegrationService.values)
        if (ref.watch(integrationConfiguredProvider(service)))
          ConnectionTile(service: service),
    ],
  );
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
    // Strava's terms: the rider hears what is read and written, and how to
    // undo it, before Strava's own page opens.
    if (service == IntegrationService.strava &&
        !await showStravaConsentSheet(context)) {
      return;
    }
    try {
      await ref.read(integrationConnectionsProvider.notifier).connect(service);
    } on IntegrationException catch (e) {
      // A rider who closed the page does not need to be told what they did.
      if (e.failure == IntegrationFailure.cancelled) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.connectionsConnectFailed(e.describe(l10n))),
        ),
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
        content: Text(
          service == IntegrationService.strava
              ? l10n.connectionsDisconnectStravaBody
              : l10n.connectionsDisconnectBody,
        ),
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
    if (service != IntegrationService.strava) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.connectionsDisconnected(label))),
      );
      return;
    }
    // Strava's terms ask for a written confirmation that their data is gone.
    if (!context.mounted) return;
    await showStravaDataDeletedDialog(
      context,
      title: l10n.connectionsDisconnected(label),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final account = ref.watch(connectedAccountProvider(service));
    final busy = ref.watch(integrationBusyProvider(service));
    void connect() => unawaited(_connect(context, ref));
    // Strava's button is their artwork at its own width; RideWithGPS' label is
    // long enough to squeeze the title into three lines. Neither fits a list
    // tile's trailing slot, so the connect button sits under the tile.
    final branded = service == IntegrationService.strava;

    final theme = Theme.of(context);
    final connected = account != null;
    final stravaAthlete = service == IntegrationService.strava
        ? account?.athleteId
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          leading: Icon(
            service == IntegrationService.strava
                ? Icons.directions_bike_outlined
                : Icons.map_outlined,
            color: connected ? theme.velorki.success : null,
          ),
          title: Text(serviceLabel(l10n, service)),
          subtitle: Text(
            account == null
                ? l10n.connectionsNotConnected
                : account.athleteName ?? l10n.connectionsConnected,
            style: theme.textTheme.labelMedium?.copyWith(
              color: connected
                  ? theme.velorki.success
                  : theme.colorScheme.onSurfaceVariant,
            ),
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
              : null,
        ),
        // Strava's brand guidelines: a link back to the athlete on Strava.
        if (stravaAthlete case final id? when id.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(48, 0, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ViewOnStravaLink(
                onPressed: () => unawaited(
                  ref.read(linkOpenerProvider)(stravaAthleteUrl(id)),
                ),
              ),
            ),
          ),
        if (!busy && account == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: branded
                  ? StravaConnectButton(
                      label: connectLabel(l10n, service),
                      onPressed: connect,
                    )
                  : FilledButton.tonal(
                      onPressed: connect,
                      child: Text(connectLabel(l10n, service)),
                    ),
            ),
          ),
      ],
    );
  }
}
