import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/links/link_opener.dart';
import '../../../core/links/velorki_urls.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../shared/presentation/gesture_zone_guard.dart';
import '../../shared/presentation/stat_tile.dart';
import '../application/web_storage_notice.dart';

/// The web planner's legal chip, at the right end of the band the
/// attribution sits in: a link to the imprint, which § 5 DDG wants reachable
/// from every page of app.velorki.com, and a cookie button that brings back
/// [WebStorageNoticeCard], as the website's footer does for its notice. Each
/// target is a finger tall, reaching up from the chip, so a tap at the
/// bottom edge lands.
class WebLegalChip extends ConsumerWidget {
  /// Creates the chip.
  const WebLegalChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall;
    void openImprint() => unawaited(
      ref.read(linkOpenerProvider)(
        Uri.parse(
          velorkiImprintUrl(Localizations.localeOf(context).languageCode),
        ),
      ),
    );
    void showNotice() => ref.read(webStorageNoticeProvider.notifier).show();
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _Target(
          link: true,
          label: l10n.settingsImprint,
          onTap: openImprint,
          child: GlassPanel(
            radius: 999,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Text(l10n.settingsImprint, style: style),
            ),
          ),
        ),
        _Target(
          label: l10n.webStorageNoticeLabel,
          onTap: showNotice,
          child: GlassPanel(
            radius: 999,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.cookie_outlined,
                size: 16,
                color: style?.color ?? theme.colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A tap target of the chip: [child] on the chip's bottom edge, the clear
/// space above it and 4 dp either side taking the tap too.
class _Target extends StatelessWidget {
  const _Target({
    required this.label,
    required this.onTap,
    required this.child,
    this.link = false,
  });

  final String label;
  final VoidCallback onTap;
  final Widget child;
  final bool link;

  @override
  Widget build(BuildContext context) => Semantics(
    button: !link,
    link: link,
    label: label,
    onTap: onTap,
    excludeSemantics: true,
    child: GestureZonePassThrough(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: onTap,
        child: SizedBox(
          height: kMinInteractiveDimension,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}

/// What the web planner keeps in the browser, in a card over the map:
/// shown while [webStorageNoticeProvider] says so, closed with OK, with a
/// way to the privacy policy. Nothing is asked: the storage is what the
/// planner needs, so the card informs and goes.
class WebStorageNoticeCard extends ConsumerWidget {
  /// Creates the card.
  const WebStorageNoticeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: GlassPanel(
        radius: 16,
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.webStorageNoticeTitle, style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(l10n.webStorageNoticeBody, style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => unawaited(
                    ref.read(linkOpenerProvider)(Uri.parse(velorkiPrivacyUrl)),
                  ),
                  child: Text(l10n.settingsPrivacyPolicy),
                ),
                const SizedBox(width: 4),
                FilledButton.tonal(
                  onPressed: () => unawaited(
                    ref.read(webStorageNoticeProvider.notifier).dismiss(),
                  ),
                  child: Text(l10n.commonOk),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
