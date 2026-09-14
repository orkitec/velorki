import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../shared/presentation/stat_tile.dart';
import '../domain/navigation_progress.dart';
import 'turn_phrases.dart';

/// How much room the banner takes at the top of the record screen, so the map
/// controls can be pushed below it.
const double turnBannerHeight = 88;

/// The next turn, over the map, while a guided ride is running.
///
/// Three lines at most: the distance in big figures, the instruction under it
/// and, when a second turn follows straight after, a "then ..." preview. Off
/// route and arrival replace all of that with a single line.
class TurnBanner extends StatelessWidget {
  /// Creates the banner.
  const TurnBanner({required this.progress, super.key});

  /// Where the rider stands on the route.
  final NavigationProgress progress;

  /// The room the banner needs; a fixed figure, kept as a method so callers
  /// do not have to care that it never varies.
  static double heightFor(NavigationProgress progress) => turnBannerHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final colors = theme.velorki;
    final next = progress.next;

    final IconData icon;
    final Color tint;
    final List<Widget> lines;

    if (progress.offRoute) {
      icon = Icons.error_outline;
      tint = colors.warning;
      lines = [_headline(theme, l10n.navOffRoute, tint)];
    } else if (progress.arrived) {
      icon = Icons.flag;
      tint = colors.success;
      lines = [_headline(theme, l10n.navArrived, tint)];
    } else if (next == null) {
      icon = Icons.straight;
      tint = colors.accent;
      lines = [
        _headline(theme, distanceLabel(progress.remainingM, l10n), tint),
        _instruction(theme, l10n.navContinue),
      ];
    } else {
      icon = turnIcon(next.kind);
      tint = colors.accent;
      final after = progress.after;
      lines = [
        _headline(theme, distanceLabel(progress.distanceToNextM, l10n), tint),
        _instruction(theme, turnLabel(next, l10n)),
        if (after != null) _preview(theme, thenLabel(after, l10n)),
      ];
    }

    return SizedBox(
      height: turnBannerHeight,
      child: GlassPanel(
        radius: 20,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 36, color: tint),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: lines,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // The three text styles are pinned to a size and a line height rather than
  // taken from the theme as they are: the banner has a fixed height, and the
  // three lines together have to fit inside it.
  Widget _headline(ThemeData theme, String text, Color color) => Text(
    text,
    style: theme.textTheme.headlineSmall?.copyWith(
      fontSize: 26,
      height: 1.1,
      fontWeight: FontWeight.w700,
      color: color,
    ),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );

  Widget _instruction(ThemeData theme, String text) => Text(
    text,
    style: theme.textTheme.titleMedium?.copyWith(fontSize: 15, height: 1.2),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );

  Widget _preview(ThemeData theme, String text) => Text(
    text,
    style: theme.textTheme.bodySmall?.copyWith(fontSize: 12, height: 1.2),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );
}
