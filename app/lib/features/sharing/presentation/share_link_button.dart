import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:velorki_api/velorki_api.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../../app/router.dart';
import '../../../core/plus/plus_gate.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../planner/presentation/route_format.dart';
import '../data/share_service.dart';

/// The "Share link" button on the route and ride detail screens.
///
/// Hidden entirely in a build without a relay — there is nowhere to put the
/// file — and, for a rider without Velorki Plus, it leads to the paywall
/// rather than disappearing: a feature nobody can see is a feature nobody
/// buys.
class ShareLinkButton extends ConsumerStatefulWidget {
  /// Creates the button.
  const ShareLinkButton({
    required this.name,
    required this.points,
    required this.kind,
    required this.distanceM,
    super.key,
    this.ascentM,
    this.duration,
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

  @override
  ConsumerState<ShareLinkButton> createState() => _ShareLinkButtonState();
}

class _ShareLinkButtonState extends ConsumerState<ShareLinkButton> {
  bool _busy = false;

  Future<void> _share() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final service = ref.read(shareServiceProvider);
    if (service == null) return;

    final ShareLink link;
    setState(() => _busy = true);
    try {
      link = await service.share(
        name: widget.name,
        points: widget.points,
        kind: widget.kind,
        distanceM: widget.distanceM,
        ascentM: widget.ascentM,
        duration: widget.duration,
      );
    } on ShareException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.shareLinkFailed(e.message))),
      );
      return;
    } finally {
      // The spinner goes before the sheet opens, not after it closes.
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    await showShareLinkSheet(context, link);
  }

  void _offerPlus() {
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.shareLinkPlus),
        action: SnackBarAction(
          label: l10n.plusSeeDetails,
          onPressed: () => context.push(paywallRoute),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (ref.watch(shareServiceProvider) == null) return const SizedBox.shrink();
    final entitled = ref.watch(plusFeatureProvider(PlusFeature.linkSharing));

    return OutlinedButton.icon(
      onPressed: _busy
          ? null
          : entitled
          ? () => unawaited(_share())
          : _offerPlus,
      icon: _busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.link),
      label: Text(l10n.shareLinkAction),
    );
  }
}

/// Shows the created [link] with copy and share actions.
Future<void> showShareLinkSheet(BuildContext context, ShareLink link) =>
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (context) => ShareLinkSheet(link: link),
    );

/// The sheet that shows a freshly created share link.
class ShareLinkSheet extends ConsumerWidget {
  /// Creates the sheet for [link].
  const ShareLinkSheet({required this.link, super.key});

  /// The link that was created.
  final ShareLink link;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final expires = link.expiresAtUtc;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.shareLinkTitle, style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(l10n.shareLinkBody, style: theme.textTheme.bodySmall),
          const SizedBox(height: 16),
          SelectableText(link.url, style: theme.textTheme.bodyMedium),
          if (expires != null) ...[
            const SizedBox(height: 8),
            Text(
              l10n.shareLinkExpires(formatDate(l10n, expires.toLocal())),
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final navigator = Navigator.of(context);
                  await ref.read(clipboardWriterProvider)(link.url);
                  navigator.pop();
                  messenger.showSnackBar(
                    SnackBar(content: Text(l10n.shareLinkCopied)),
                  );
                },
                icon: const Icon(Icons.copy),
                label: Text(l10n.shareLinkCopy),
              ),
              FilledButton.icon(
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  await ref.read(textSharerProvider)(link.url);
                  navigator.pop();
                },
                icon: const Icon(Icons.ios_share),
                label: Text(l10n.shareLinkShare),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
