import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:velorki_api/velorki_api.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../../app/router.dart';
import '../../../core/plus/plus_gate.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../planner/domain/route_poi.dart';
import '../../planner/presentation/route_format.dart';
import '../data/share_service.dart';
import '../../shared/presentation/docking_sheet.dart';

/// The detail pages' one "Share" button: it opens the share card, where the
/// services and the link are rows.
class ShareButton extends StatelessWidget {
  /// Creates the button; [onPressed] opens the card.
  const ShareButton({required this.onPressed, super.key});

  /// Opens the card.
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    icon: Icon(Icons.adaptive.share),
    label: Text(AppLocalizations.of(context).shareLinkAction),
  );
}

/// Opens the share card titled [title] with [rows], over the shell's
/// floating bar. The card scrolls, so it fits a phone turned sideways.
Future<void> showShareCard(
  BuildContext context, {
  required String title,
  required List<Widget> rows,
}) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  useSafeArea: true,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => ScrolledUnderLine(
    child: ShareCard(title: title, rows: rows),
  ),
);

/// The card itself: a title and one row per way out.
class ShareCard extends StatelessWidget {
  /// Creates the card.
  const ShareCard({required this.title, required this.rows, super.key});

  /// What is shared: "Share route" or "Share ride".
  final String title;

  /// The rows, each a [ShareCardRow] or a widget that builds one.
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        ...rows,
      ],
    ),
  );
}

/// One way out on the share card: what it is, a line about it, and its
/// action on the right.
class ShareCardRow extends StatelessWidget {
  /// Creates a row.
  const ShareCardRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
    this.onTap,
    this.enabled = true,
    this.subtitleIsError = false,
    super.key,
  });

  /// The row's icon.
  final IconData icon;

  /// The service, or "Link".
  final String title;

  /// What the action does, or why there is none.
  final String subtitle;

  /// The button on the right, if any.
  final Widget? action;

  /// What a tap on the row itself does.
  final VoidCallback? onTap;

  /// `false` greys the row out: the action is not for this route.
  final bool enabled;

  /// Whether [subtitle] reports a failure.
  final bool subtitleIsError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      enabled: enabled,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: subtitleIsError
            ? theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              )
            : null,
      ),
      trailing: action,
      onTap: onTap,
    );
  }
}

/// The spinner a row shows while its action runs.
class ShareRowProgress extends StatelessWidget {
  /// Creates the spinner.
  const ShareRowProgress({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 20,
    height: 20,
    child: CircularProgressIndicator(strokeWidth: 2),
  );
}

/// The card's link row: makes a share link and opens the system share sheet
/// with it at once; the card then says how long the link works.
///
/// Share links live on our server and are Velorki Plus: without it the row
/// shows a lock and leads to the paywall. A route that is Strava data
/// ([fromStrava]) is never put in a link, by Strava's terms.
class ShareLinkRow extends ConsumerStatefulWidget {
  /// Creates the row.
  const ShareLinkRow({
    required this.name,
    required this.points,
    required this.kind,
    required this.distanceM,
    super.key,
    this.ascentM,
    this.duration,
    this.pois = const <RoutePoi>[],
    this.fromStrava = false,
  });

  /// The title shown on the share page.
  final String name;

  /// The geometry to upload.
  final List<TrackPoint> points;

  /// Whether this is a planned route or a recorded ride.
  final ShareKind kind;

  /// Length in metres, for the summary on the share page.
  final double distanceM;

  /// Climbing in metres, when it is known.
  final double? ascentM;

  /// How long the ride took, for a ride.
  final Duration? duration;

  /// The route's points of interest, for a route.
  final List<RoutePoi> pois;

  /// Whether the route is Strava data.
  final bool fromStrava;

  @override
  ConsumerState<ShareLinkRow> createState() => _ShareLinkRowState();
}

class _ShareLinkRowState extends ConsumerState<ShareLinkRow> {
  bool _busy = false;
  ShareLink? _link;
  String? _error;

  Future<void> _share() async {
    final l10n = AppLocalizations.of(context);
    final sharer = ref.read(textSharerProvider);
    var link = _link;
    if (link == null) {
      final service = ref.read(shareServiceProvider);
      if (service == null) return;
      setState(() {
        _busy = true;
        _error = null;
      });
      try {
        link = await service.share(
          name: widget.name,
          points: widget.points,
          kind: widget.kind,
          distanceM: widget.distanceM,
          ascentM: widget.ascentM,
          duration: widget.duration,
          pois: widget.pois,
          fromStrava: widget.fromStrava,
        );
      } on ShareException catch (e) {
        if (mounted) {
          setState(() => _error = l10n.shareLinkFailed(e.describe(l10n)));
        }
        return;
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      if (!mounted) return;
      setState(() => _link = link);
    }
    await sharer(link.url, subject: widget.name);
  }

  void _offerPlus() {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    unawaited(router.push(paywallRoute));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (ref.watch(shareServiceProvider) == null) return const SizedBox.shrink();
    if (widget.fromStrava) {
      return ShareCardRow(
        icon: Icons.link_rounded,
        title: l10n.shareLinkRowTitle,
        subtitle: l10n.shareNotForStravaRoutes,
        enabled: false,
      );
    }
    if (!ref.watch(plusFeatureProvider(PlusFeature.linkSharing))) {
      return ShareCardRow(
        icon: Icons.link_rounded,
        title: l10n.shareLinkRowTitle,
        subtitle: l10n.shareLinkRowBody,
        onTap: _offerPlus,
        action: TextButton.icon(
          onPressed: _offerPlus,
          icon: const Icon(Icons.lock_outline, size: 18),
          label: Text(l10n.sharePlusLabel),
        ),
      );
    }
    final expires = _link?.expiresAtUtc;
    final error = _error;
    return ShareCardRow(
      icon: Icons.link_rounded,
      title: l10n.shareLinkRowTitle,
      subtitle:
          error ??
          (expires != null
              ? l10n.shareLinkWorksUntil(formatDate(l10n, expires.toLocal()))
              : l10n.shareLinkRowBody),
      subtitleIsError: error != null,
      action: _busy
          ? const ShareRowProgress()
          : FilledButton.tonal(
              onPressed: () => unawaited(_share()),
              child: Text(l10n.shareLinkTitle),
            ),
    );
  }
}
