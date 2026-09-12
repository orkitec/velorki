import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/links/link_opener.dart';
import '../../../core/plus/plus_gate.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../recording/domain/ride.dart';
import '../application/connections_controller.dart';
import '../application/ride_uploader.dart';
import '../common/data/connected_accounts_repository.dart';
import '../common/domain/connected_account.dart';
import '../common/domain/integration_exception.dart';
import 'connections_section.dart';
import 'integration_labels.dart';

/// One entry of the ride detail's Upload menu.
class _UploadAction {
  const _UploadAction({required this.service, required this.open});

  final IntegrationService service;

  /// `true` when the ride is already there and this only opens it.
  final bool open;
}

/// The ride detail's "Upload" menu.
///
/// A ride that is already on a service is never uploaded again — Strava would
/// create a second activity and spend a write against the quota — so the entry
/// becomes "View on Strava" or "Open on Ride with GPS" instead.
///
/// The menu is hidden when the build has no relay, and an unconnected or
/// unentitled service is simply not offered; connecting happens in
/// Settings → Connections, which is the one place that explains the
/// subscription.
class RideUploadMenu extends ConsumerStatefulWidget {
  /// Creates the menu for [ride].
  const RideUploadMenu({required this.ride, super.key});

  /// The ride that would be uploaded.
  final Ride ride;

  @override
  ConsumerState<RideUploadMenu> createState() => _RideUploadMenuState();
}

class _RideUploadMenuState extends ConsumerState<RideUploadMenu> {
  IntegrationService? _busy;

  Future<void> _upload(IntegrationService service) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final label = serviceLabel(l10n, service);
    setState(() => _busy = service);
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.rideDetailUploading(label))),
    );
    try {
      final uploader = ref.read(rideUploaderProvider);
      final upload = switch (service) {
        IntegrationService.strava => await uploader.uploadToStrava(widget.ride),
        IntegrationService.rwgps => await uploader.uploadToRwgps(widget.ride),
      };
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.rideDetailUploaded(label)),
          action: upload.url == null
              ? null
              : SnackBarAction(
                  label: service == IntegrationService.strava
                      ? l10n.rideDetailViewOnStrava
                      : l10n.rideDetailOpenOn(label),
                  onPressed: () => unawaited(_open(Uri.parse(upload.url!))),
                ),
        ),
      );
    } on IntegrationException catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.rideDetailUploadFailed(e.message))),
      );
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _open(Uri url) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final opened = await ref.read(linkOpenerProvider)(url);
    if (!opened) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.integrationsOpenFailed('$url'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final actions = <_UploadAction>[
      for (final service in IntegrationService.values)
        if (ref.watch(integrationConfiguredProvider(service)) &&
            ref.watch(plusFeatureProvider(plusFeatureFor(service))) &&
            ref.watch(connectedAccountProvider(service)) != null)
          _UploadAction(
            service: service,
            open: widget.ride.uploadFor(service.id)?.isDone ?? false,
          ),
    ];
    if (actions.isEmpty) return const SizedBox.shrink();
    if (_busy != null) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return PopupMenuButton<_UploadAction>(
      icon: const Icon(Icons.cloud_upload_outlined),
      tooltip: l10n.rideDetailUpload,
      onSelected: (action) {
        if (!action.open) {
          unawaited(_upload(action.service));
          return;
        }
        final url = widget.ride.uploadFor(action.service.id)?.url;
        if (url != null) unawaited(_open(Uri.parse(url)));
      },
      itemBuilder: (context) => [
        for (final action in actions)
          PopupMenuItem<_UploadAction>(
            value: action,
            child: Text(
              action.open
                  ? action.service == IntegrationService.strava
                        ? l10n.rideDetailViewOnStrava
                        : l10n.rideDetailOpenOn(
                            serviceLabel(l10n, action.service),
                          )
                  : l10n.rideDetailUploadTo(serviceLabel(l10n, action.service)),
            ),
          ),
      ],
    );
  }
}
