import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../settings/data/units.dart';
import '../../shared/presentation/stat_tile.dart';
import '../application/navigation_controller.dart';
import '../data/navigation_settings.dart';
import '../domain/navigation_progress.dart';
import '../domain/off_route_guidance.dart';
import 'turn_phrases.dart';

/// How much room the banner takes at the top of the record screen, so the map
/// controls can be pushed below it.
const double turnBannerHeight = 56;

/// The smallest share of its own size the instruction may shrink to before a
/// rider on a handlebar would stop reading it at a glance.
const double _minInstructionScale = 0.78;

/// The next turn, over the map, while a guided ride is running.
///
/// One row, as wide as its content: the turn arrow, the distance in big
/// figures and the instruction beside it. A turn that follows straight after
/// is a second, smaller arrow at the end rather than a line of its own.
/// Re-routing and arrival replace all of that with a single tinted line.
///
/// A rider who has left the route is read the way back in the same shape as a
/// turn — how far, and which way — because that is what they need and it is
/// the layout they are already used to. Tapping it asks for a way back to be
/// computed now instead of waiting the half minute out; the button beside it
/// throws the rest of the plan away and re-routes to the destination.

/// How close behind the next turn the one after it has to follow for the
/// banner to preview it. Further than this the rider will be told in time by
/// the banner itself once the first turn is done.
const double thenPreviewM = 250;

class TurnBanner extends ConsumerWidget {
  /// Creates the banner.
  const TurnBanner({required this.progress, super.key});

  /// Where the rider stands on the route.
  final NavigationProgress progress;

  /// The room the banner needs; a fixed figure, kept as a method so callers
  /// do not have to care that it never varies.
  static double heightFor(NavigationProgress progress) => turnBannerHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final units = ref.watch(unitSystemProvider);
    final colors = theme.velorki;
    final next = progress.next;
    final voice = ref.watch(navigationSettingsProvider.select((s) => s.voice));
    final muted = ref.watch(voiceMutedForRideProvider);

    final IconData icon;
    final Color tint;
    final List<Widget> row;
    final guidance = progress.guidance;
    final guiding =
        progress.offRouteState == OffRouteState.guiding && guidance != null;

    if (guiding) {
      // The plan is still the route; this only says where to pick it up.
      icon = Icons.u_turn_left;
      tint = colors.warning;
      row = [
        _distance(theme, distanceLabel(guidance.distanceM, l10n, units), tint),
        _instruction(theme, backToRouteLabel(guidance.direction, l10n)),
        const SizedBox(width: 4),
        TextButton(
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(0, 36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: theme.textTheme.labelLarge,
          ),
          onPressed: () => ref
              .read(navigationControllerProvider.notifier)
              .requestFullReroute(),
          child: Text(l10n.navNewRouteFromHere),
        ),
      ];
    } else if (progress.rerouting) {
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
        _distance(theme, distanceLabel(progress.remainingM, l10n, units), tint),
        _instruction(theme, l10n.navContinue),
      ];
    } else {
      icon = turnIcon(next.kind);
      tint = colors.accent;
      final after = progress.after;
      // The turn behind the next one is a word and an arrow, not a sentence:
      // it only has to say which way the road goes after this one, and only
      // when that comes soon enough to matter at the first turn.
      final showAfter =
          after != null &&
          next.distanceToNextM > 0 &&
          next.distanceToNextM <= thenPreviewM;
      row = [
        _distance(
          theme,
          distanceLabel(progress.distanceToNextM, l10n, units),
          tint,
        ),
        _instruction(theme, turnLabel(next, l10n)),
        if (showAfter) ...[
          const SizedBox(width: 10),
          Text(
            l10n.navThenLabel,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            turnIcon(after.kind),
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ];
    }

    // Left-aligned and only as wide as it needs to be, so a short instruction
    // leaves the rest of the row to the map. The outer row stretches the
    // panel to the full banner height.
    return SizedBox(
      height: turnBannerHeight,
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              // The whole row, minus nothing: while the banner is up the
              // control column starts below it (`controlsTop`), so there is
              // no chrome beside it to keep clear of. A row does not bound
              // its inflexible child's width by itself, and the instruction
              // has to know how much room it has, so it is bounded here.
              constraints: BoxConstraints(maxWidth: constraints.maxWidth),
              child: GestureDetector(
                // Tapping the way back asks for one to be computed now,
                // rather than waiting the half minute out.
                onTap: guiding
                    ? () => ref
                          .read(navigationControllerProvider.notifier)
                          .requestRejoin()
                    : null,
                child: GlassPanel(
                  radius: 20,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 28, color: tint),
                      const SizedBox(width: 10),
                      ...row,
                      // Quiet for this ride, without walking to Settings and
                      // losing the choice for every ride after it. Nothing to
                      // mute while the voice is off, so the button is gone.
                      if (voice) ...[
                        const SizedBox(width: 4),
                        IconButton(
                          icon: Icon(
                            muted ? Icons.volume_off : Icons.volume_up,
                            size: 22,
                          ),
                          color: muted
                              ? theme.colorScheme.onSurfaceVariant
                              : colors.accent,
                          tooltip: muted
                              ? l10n.navUnmuteVoice
                              : l10n.navMuteVoice,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                          onPressed: () => ref
                              .read(voiceMutedForRideProvider.notifier)
                              .toggle(),
                        ),
                      ],
                    ],
                  ),
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

  // Flexible, not fixed: the instruction gives way to the figures and the
  // arrows rather than pushing them out of the panel.
  Widget _instruction(ThemeData theme, String text) =>
      _Instruction(text: text, style: theme.textTheme.titleSmall!);

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

/// The instruction beside the distance, in as much of the style as fits.
///
/// A turn instruction cut off at an ellipsis is worse than a small one: "Im
/// Kreisverkehr die 2. Ausfahrt nehmen" is three times the length of "Turn
/// right", and "Rechts abbieg…" tells a rider nothing they can act on. So the
/// text is measured against the room it actually has — a [TextPainter], no
/// package — and the first of these that fits is what is drawn: one line at
/// the full style, which is every short instruction and so the usual look,
/// then two lines, shrinking in small steps down to [_minInstructionScale].
class _Instruction extends StatelessWidget {
  const _Instruction({required this.text, required this.style});

  /// The instruction to draw.
  final String text;

  /// The style it is drawn in while it fits on one line.
  final TextStyle style;

  /// How much smaller each step makes the text.
  static const double _step = 0.06;

  @override
  Widget build(BuildContext context) => Flexible(
    child: LayoutBuilder(
      builder: (context, constraints) {
        // The same scaler the Text will use, or the measurement would be of
        // a different size than the one on screen.
        final scaler = MediaQuery.textScalerOf(context);
        final direction = Directionality.of(context);
        final fit = _fit(constraints, direction, scaler);
        return Text(
          text,
          style: fit.style,
          maxLines: fit.lines,
          textScaler: scaler,
        );
      },
    ),
  );

  /// The largest style, and the fewest lines, the whole instruction fits in.
  ({TextStyle style, int lines}) _fit(
    BoxConstraints constraints,
    TextDirection direction,
    TextScaler scaler,
  ) {
    final width = constraints.maxWidth;
    final height = constraints.hasBoundedHeight
        ? constraints.maxHeight
        : double.infinity;
    final base = style.fontSize ?? 14;
    if (_fits(style, 1, width, height, direction, scaler)) {
      return (style: style, lines: 1);
    }
    for (var scale = 1.0; scale >= _minInstructionScale; scale -= _step) {
      final smaller = style.copyWith(fontSize: base * scale);
      if (_fits(smaller, 2, width, height, direction, scaler)) {
        return (style: smaller, lines: 2);
      }
    }
    // Two lines at the smallest size the rider can still read: past this the
    // instruction is longer than any turn phrase we have, and a readable
    // couple of lines beats a legible-but-useless ellipsis.
    return (
      style: style.copyWith(fontSize: base * _minInstructionScale),
      lines: 2,
    );
  }

  /// Whether [text] fits in [lines] lines of [style] inside the given room.
  bool _fits(
    TextStyle style,
    int lines,
    double width,
    double height,
    TextDirection direction,
    TextScaler scaler,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: lines,
      textDirection: direction,
      textScaler: scaler,
    )..layout(maxWidth: width);
    final fits = !painter.didExceedMaxLines && painter.height <= height;
    painter.dispose();
    return fits;
  }
}
