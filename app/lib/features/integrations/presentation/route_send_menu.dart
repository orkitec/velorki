import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/links/link_opener.dart';
import '../../../core/plus/plus_gate.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../planner/domain/saved_route.dart';
import '../../shared/presentation/button_menu.dart';
import '../application/connections_controller.dart';
import '../application/route_sender.dart';
import '../common/data/connected_accounts_repository.dart';
import '../common/domain/connected_account.dart';
import '../common/domain/integration_exception.dart';
import 'connections_section.dart';
import 'integration_labels.dart';

/// The route detail's "Send to …" button.
///
/// Ride with GPS takes a route over the API. **Strava does not**: its API can
/// read routes but cannot create them, so the Strava entry opens a short
/// explanation and offers the GPX export instead — which is the free path into
/// Strava, Komoot and Garmin anyway.
class RouteSendMenu extends ConsumerStatefulWidget {
  /// Creates the button for [route].
  const RouteSendMenu({
    required this.route,
    required this.onExportGpx,
    super.key,
  });

  /// The route to send.
  final SavedRoute route;

  /// Runs the normal GPX export, for the Strava explanation's action.
  final Future<void> Function() onExportGpx;

  @override
  ConsumerState<RouteSendMenu> createState() => _RouteSendMenuState();
}

enum _SendTarget { rwgps, strava }

class _RouteSendMenuState extends ConsumerState<RouteSendMenu> {
  bool _busy = false;

  Future<void> _sendToRwgps() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final label = serviceLabel(l10n, IntegrationService.rwgps);
    setState(() => _busy = true);
    try {
      final sent = await ref
          .read(routeSenderProvider)
          .sendToRwgps(widget.route);
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.routeDetailSent(label)),
          action: SnackBarAction(
            label: l10n.routeDetailOpenSent,
            onPressed: () =>
                unawaited(ref.read(linkOpenerProvider)(Uri.parse(sent.url))),
          ),
        ),
      );
    } on IntegrationException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.routeDetailSendFailed(e.message))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _explainStrava() async {
    final l10n = AppLocalizations.of(context);
    final export = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.routeDetailSendToStravaTitle),
        content: Text(l10n.routeDetailSendToStravaBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.routeDetailSendToStravaAction),
          ),
        ],
      ),
    );
    if (export == true) await widget.onExportGpx();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final targets = <_SendTarget>[
      if (_canSend(IntegrationService.rwgps)) _SendTarget.rwgps,
      if (ref.watch(integrationConfiguredProvider(IntegrationService.strava)))
        _SendTarget.strava,
    ];
    if (targets.isEmpty) return const SizedBox.shrink();
    if (_busy) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return ButtonMenu<_SendTarget>(
      icon: Icons.cloud_upload_outlined,
      label: l10n.routeDetailSend,
      onSelected: (target) => unawaited(
        target == _SendTarget.rwgps ? _sendToRwgps() : _explainStrava(),
      ),
      entries: [
        for (final target in targets)
          PopupMenuItem(
            value: target,
            child: Text(
              target == _SendTarget.rwgps
                  ? l10n.routeDetailSendToRwgps
                  : l10n.routeDetailSendToStrava,
            ),
          ),
      ],
    );
  }

  bool _canSend(IntegrationService service) =>
      ref.watch(integrationConfiguredProvider(service)) &&
      ref.watch(plusFeatureProvider(plusFeatureFor(service))) &&
      ref.watch(connectedAccountProvider(service)) != null;
}
