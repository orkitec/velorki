import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../application/connections_controller.dart';
import '../common/domain/connected_account.dart';
import 'external_routes_screen.dart';

/// The library's "Import from Strava / Ride with GPS" app bar action.
///
/// Hidden entirely when the build has neither service configured — an empty
/// `VELORKI_API_URL` is the pure-local fork build, and a menu that only ever
/// says "not available" is worse than no menu.
class ImportFromServiceButton extends ConsumerWidget {
  /// Creates the action.
  const ImportFromServiceButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final services = <IntegrationService>[
      for (final service in IntegrationService.values)
        if (ref.watch(integrationConfiguredProvider(service))) service,
    ];
    if (services.isEmpty) return const SizedBox.shrink();
    return PopupMenuButton<IntegrationService>(
      icon: const Icon(Icons.cloud_download_outlined),
      tooltip: l10n.libraryImportFromStrava,
      onSelected: (service) => unawaited(openExternalRoutes(context, service)),
      itemBuilder: (context) => [
        for (final service in services)
          PopupMenuItem<IntegrationService>(
            value: service,
            child: Text(switch (service) {
              IntegrationService.strava => l10n.libraryImportFromStrava,
              IntegrationService.rwgps => l10n.libraryImportFromRwgps,
            }),
          ),
      ],
    );
  }
}
