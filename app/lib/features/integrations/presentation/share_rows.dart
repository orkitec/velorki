import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/links/link_opener.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../planner/domain/saved_route.dart';
import '../../recording/domain/ride.dart';
import '../../sharing/presentation/share_card.dart';
import '../application/connections_controller.dart';
import '../application/ride_uploader.dart';
import '../application/route_sender.dart';
import '../common/data/connected_accounts_repository.dart';
import '../common/domain/connected_account.dart';
import '../common/domain/integration_exception.dart';
import '../strava/data/strava_auth.dart';
import 'integration_labels.dart';
import 'strava_brand.dart';

/// Closes the share card and goes to Settings → Connections.
void _goToConnections(BuildContext context) {
  final router = GoRouter.of(context);
  Navigator.of(context).pop();
  router.go(settingsConnectionsRoute);
}

IconData _serviceIcon(IntegrationService service) => switch (service) {
  IntegrationService.strava => Icons.directions_bike_outlined,
  IntegrationService.rwgps => Icons.map_outlined,
};

Widget _connectButton(BuildContext context) => TextButton(
  onPressed: () => _goToConnections(context),
  child: Text(AppLocalizations.of(context).shareConnect),
);

/// Whether [account] may upload rides: the rider can untick the upload
/// permission on Strava's page, and then nothing is uploaded.
bool canUploadToStrava(ConnectedAccount account) =>
    account.hasScope(StravaAuth.uploadScope);

/// The route share card's Ride with GPS row: Send when the account is
/// connected, Connect when it is not. A route that is Strava data goes to
/// no other service, so for one of those the row only says why.
class RwgpsRouteShareRow extends ConsumerStatefulWidget {
  /// Creates the row for [route].
  const RwgpsRouteShareRow({required this.route, super.key});

  /// The route to send.
  final SavedRoute route;

  @override
  ConsumerState<RwgpsRouteShareRow> createState() => _RwgpsRouteShareRowState();
}

class _RwgpsRouteShareRowState extends ConsumerState<RwgpsRouteShareRow> {
  bool _busy = false;
  SentRoute? _sent;
  String? _error;

  Future<void> _send() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final sent = await ref
          .read(routeSenderProvider)
          .sendToRwgps(widget.route);
      if (mounted) setState(() => _sent = sent);
    } on IntegrationException catch (e) {
      if (mounted) {
        setState(() => _error = l10n.routeDetailSendFailed(e.describe(l10n)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const service = IntegrationService.rwgps;
    final l10n = AppLocalizations.of(context);
    if (!ref.watch(integrationConfiguredProvider(service))) {
      return const SizedBox.shrink();
    }
    final label = serviceLabel(l10n, service);
    if (widget.route.fromStrava) {
      return ShareCardRow(
        icon: _serviceIcon(service),
        title: label,
        subtitle: l10n.shareNotForStravaRoutes,
        enabled: false,
      );
    }
    if (ref.watch(connectedAccountProvider(service)) == null) {
      return ShareCardRow(
        icon: _serviceIcon(service),
        title: label,
        subtitle: l10n.shareNotConnected,
        action: _connectButton(context),
      );
    }
    final sent = _sent;
    if (sent != null) {
      return ShareCardRow(
        icon: _serviceIcon(service),
        title: label,
        subtitle: l10n.routeDetailSent(label),
        action: TextButton(
          onPressed: () =>
              unawaited(ref.read(linkOpenerProvider)(Uri.parse(sent.url))),
          child: Text(l10n.routeDetailOpenSent),
        ),
      );
    }
    final error = _error;
    return ShareCardRow(
      icon: _serviceIcon(service),
      title: label,
      subtitle: error ?? l10n.shareRwgpsRouteBody,
      subtitleIsError: error != null,
      action: _busy
          ? const ShareRowProgress()
          : FilledButton.tonal(
              onPressed: () => unawaited(_send()),
              child: Text(l10n.shareSend),
            ),
    );
  }
}

/// The route share card's Strava row. **Strava's API cannot create routes**,
/// so the row says so, and a tap explains it and offers the GPX export, the
/// way into Strava that works.
class StravaRouteShareRow extends ConsumerWidget {
  /// Creates the row; [onExportGpx] runs the normal GPX export.
  const StravaRouteShareRow({required this.onExportGpx, super.key});

  /// Runs the GPX export.
  final Future<void> Function() onExportGpx;

  Future<void> _explain(BuildContext context) async {
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
    if (export == true) await onExportGpx();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const service = IntegrationService.strava;
    if (!ref.watch(integrationConfiguredProvider(service))) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    return ShareCardRow(
      icon: _serviceIcon(service),
      title: serviceLabel(l10n, service),
      subtitle: l10n.shareStravaRouteBody,
      onTap: () => unawaited(_explain(context)),
      action: const Icon(Icons.info_outline),
    );
  }
}

/// The ride share card's row for [service]: Upload when connected, Connect
/// when not, and the way to the ride once it is there. A ride is never
/// uploaded twice: Strava would make a second activity of it.
class RideUploadShareRow extends ConsumerStatefulWidget {
  /// Creates the row for [ride] and [service].
  const RideUploadShareRow({
    required this.ride,
    required this.service,
    super.key,
  });

  /// The ride to upload.
  final Ride ride;

  /// Where it goes.
  final IntegrationService service;

  @override
  ConsumerState<RideUploadShareRow> createState() => _RideUploadShareRowState();
}

class _RideUploadShareRowState extends ConsumerState<RideUploadShareRow> {
  bool _busy = false;
  String? _url;
  String? _error;

  Future<void> _upload() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final uploader = ref.read(rideUploaderProvider);
      final upload = switch (widget.service) {
        IntegrationService.strava => await uploader.uploadToStrava(widget.ride),
        IntegrationService.rwgps => await uploader.uploadToRwgps(widget.ride),
      };
      if (mounted) setState(() => _url = upload.url ?? '');
    } on IntegrationException catch (e) {
      if (mounted) {
        setState(() => _error = l10n.rideDetailUploadFailed(e.describe(l10n)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(String url) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final opened = await ref.read(linkOpenerProvider)(Uri.parse(url));
    if (!opened) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.integrationsOpenFailed(url))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final l10n = AppLocalizations.of(context);
    if (!ref.watch(integrationConfiguredProvider(service))) {
      return const SizedBox.shrink();
    }
    final label = serviceLabel(l10n, service);
    final icon = _serviceIcon(service);
    final account = ref.watch(connectedAccountProvider(service));
    final stored = widget.ride.uploadFor(service.id);
    final url = _url ?? (stored != null && stored.isDone ? stored.url : null);
    if (url != null) {
      return ShareCardRow(
        icon: icon,
        title: label,
        subtitle: l10n.rideDetailUploaded(label),
        action: url.isEmpty
            ? null
            : service == IntegrationService.strava
            ? ViewOnStravaLink(onPressed: () => unawaited(_open(url)))
            : TextButton(
                onPressed: () => unawaited(_open(url)),
                child: Text(l10n.routeDetailOpenSent),
              ),
      );
    }
    if (account == null) {
      return ShareCardRow(
        icon: icon,
        title: label,
        subtitle: l10n.shareNotConnected,
        action: _connectButton(context),
      );
    }
    if (service == IntegrationService.strava && !canUploadToStrava(account)) {
      return ShareCardRow(
        icon: icon,
        title: label,
        subtitle: l10n.shareStravaNoUpload,
        action: _connectButton(context),
      );
    }
    final error = _error;
    return ShareCardRow(
      icon: icon,
      title: label,
      subtitle:
          error ??
          (service == IntegrationService.strava
              ? l10n.shareStravaRideBody
              : l10n.shareRwgpsRideBody),
      subtitleIsError: error != null,
      action: _busy
          ? const ShareRowProgress()
          : FilledButton.tonal(
              onPressed: () => unawaited(_upload()),
              child: Text(l10n.shareUpload),
            ),
    );
  }
}
