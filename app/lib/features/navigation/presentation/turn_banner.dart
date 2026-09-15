import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../shared/presentation/stat_tile.dart';
import '../domain/navigation_progress.dart';
import 'turn_phrases.dart';

/// How much room the banner takes at the top of the record screen, so the map
/// controls can be pushed below it.
const double turnBannerHeight = 56;

/// How wide the banner may grow, as a share of the room it is given. The rest
/// of the row stays map, which is what the rider is actually looking at.
const double _maxWidthFactor = 0.8;

/// The next turn, over the map, while a guided ride is running.
///
/// One row, as wide as its content: the turn arrow, the distance in big
/// figures and the instruction beside it. A turn that follows straight after
/// is a second, smaller arrow at the end rather than a line of its own. Off
/// route, re-routing and arrival replace all of that with a single tinted line.
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
    final List<Widget> row;

    if (progress.rerouting) {
      // A request is out for a way back onto the route: say that rather than
      // leave the rider looking at a bare "off route".
      icon = Icons.autorenew;
      tint = colors.warning;
      row = [_state(theme, l10n.navRerouting, tint)];
    } else if (progress.offRoute) {
      icon = Icons.error_outline;
      tint = colors.warning;
      row = [_state(theme, l10n.navOffRoute, tint)];
    } else if (progress.arrived) {
      icon = Icons.flag;
      tint = colors.success;
      row = [_state(theme, l10n.navArrived, tint)];
    } else if (next == null) {
      icon = Icons.straight;
      tint = colors.accent;
      row = [
        _distance(theme, distanceLabel(progress.remainingM, l10n), tint),
        _instruction(theme, l10n.navContinue),
      ];
    } else {
      icon = turnIcon(next.kind);
      tint = colors.accent;
      final after = progress.after;
      row = [
        _distance(theme, distanceLabel(progress.distanceToNextM, l10n), tint),
        _instruction(theme, turnLabel(next, l10n)),
        // The turn behind the next one is an arrow, not a sentence: it only
        // has to tell the rider which way the road goes after this one.
        if (after != null) ...[
          const SizedBox(width: 8),
          Icon(
            turnIcon(after.kind),
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ];
    }

    // Left-aligned and only as wide as it needs to be, so the map keeps the
    // rest of the row. The outer row stretches the panel to the full banner
    // height; the cap keeps a long instruction from taking the whole width.
    return SizedBox(
      height: turnBannerHeight,
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: constraints.maxWidth * _maxWidthFactor,
              ),
              child: GlassPanel(
                radius: 20,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 28, color: tint),
                    const SizedBox(width: 10),
                    ...row,
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // The distance keeps the stat font the rest of the app uses for figures, so
  // it reads at arm's length on the handlebar.
  Widget _distance(ThemeData theme, String text, Color color) => Padding(
    padding: const EdgeInsets.only(right: 10),
    child: Text(
      text,
      style: theme.textTheme.statMedium.copyWith(color: color),
      maxLines: 1,
    ),
  );

  // Flexible, not fixed: at the 80 % cap a long instruction gives way rather
  // than pushing the arrows out of the panel.
  Widget _instruction(ThemeData theme, String text) => Flexible(
    child: Text(
      text,
      style: theme.textTheme.titleSmall,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
  );

  Widget _state(ThemeData theme, String text, Color color) => Flexible(
    child: Text(
      text,
      style: theme.textTheme.titleMedium?.copyWith(
        color: color,
        fontWeight: FontWeight.w700,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
  );
}
