import 'package:flutter/material.dart';

import '../../../app/theme.dart';

/// How big the figure of a [StatTile] is.
enum StatSize {
  /// The dense grid on the ride screens.
  medium,

  /// The stats row under a route.
  large,

  /// The one figure a rider reads at a glance, as big as the screen allows.
  hero,
}

/// One figure with its upper-case caption: `DISTANCE` over `42.3 km`.
///
/// The value keeps its unit in the string, the caption goes upper-case here so
/// the callers hand over plain localised labels.
class StatTile extends StatelessWidget {
  /// Creates the tile.
  const StatTile({
    required this.label,
    required this.value,
    super.key,
    this.icon,
    this.size = StatSize.large,
    this.emphasize = false,
    this.alignEnd = false,
    this.detail,
    this.muted = false,
  });

  /// The caption.
  final String label;

  /// A small line under the figure: the ride's average, say.
  final String? detail;

  /// Draws the figure dimmed: a last-known value whose source fell silent.
  final bool muted;

  /// The figure, unit included.
  final String value;

  /// An optional icon next to the caption.
  final IconData? icon;

  /// The figure's size.
  final StatSize size;

  /// Draws the figure in the accent colour.
  final bool emphasize;

  /// Right-aligns the tile.
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final valueStyle = switch (size) {
      StatSize.hero => theme.textTheme.statHero,
      StatSize.large => theme.textTheme.statLarge,
      StatSize.medium => theme.textTheme.statMedium,
    };
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: scheme.onSurfaceVariant),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                label.toUpperCase(),
                style: theme.textTheme.overline.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Shrinks rather than truncates: "21.0 km" must never become "21.0…".
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
          child: Text(
            value,
            style: valueStyle.copyWith(
              color: muted
                  ? scheme.onSurfaceVariant
                  : emphasize
                  ? theme.velorki.accent
                  : scheme.onSurface,
            ),
            maxLines: 1,
          ),
        ),
        if (detail != null) ...[
          const SizedBox(height: 2),
          Text(
            detail!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
            // Two lines rather than dots: a detail that cannot be read is
            // no detail.
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

/// A row of [StatTile]s sharing the width evenly.
class StatRow extends StatelessWidget {
  /// Creates the row.
  const StatRow({required this.children, super.key});

  /// The tiles, in reading order.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) const SizedBox(width: 8),
        Expanded(child: children[i]),
      ],
    ],
  );
}

/// A small upper-case section caption: `RECENT RIDES`.
class SectionCaption extends StatelessWidget {
  /// Creates the caption.
  const SectionCaption(this.text, {super.key, this.accent = false});

  /// The caption; upper-cased here.
  final String text;

  /// Draws it in the accent colour.
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text.toUpperCase(),
      style: theme.textTheme.overline.copyWith(
        color: accent
            ? theme.velorki.accent
            : theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// A round, tonal icon button with a caption underneath: the planner toolbar.
class LabeledIconButton extends StatelessWidget {
  /// Creates the button.
  const LabeledIconButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    super.key,
    this.filled = false,
    this.busy = false,
  });

  /// The icon.
  final IconData icon;

  /// The caption under it.
  final String label;

  /// Disabled when `null`.
  final VoidCallback? onPressed;

  /// Draws the circle in the primary colour.
  final bool filled;

  /// Shows a spinner instead of the icon.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = onPressed != null;
    final background = filled
        ? scheme.primary
        : enabled
        ? scheme.surfaceContainerHigh
        : scheme.surfaceContainerLow;
    final foreground = filled
        ? scheme.onPrimary
        : enabled
        ? scheme.onSurface
        : scheme.onSurfaceVariant.withValues(alpha: 0.5);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: background,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(
              width: 48,
              height: 48,
              child: Center(
                child: busy
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: foreground,
                        ),
                      )
                    : Icon(icon, size: 22, color: foreground),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        // The buttons share the row evenly, so a longer translation would be
        // cut in the middle of the word: let the caption shrink into its
        // share instead. German "Rückgängig" is twice the width of "Undo".
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: enabled
                  ? scheme.onSurfaceVariant
                  : scheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            maxLines: 1,
            softWrap: false,
          ),
        ),
      ],
    );
  }
}

/// A panel with a translucent surface and a hairline, for controls floating
/// over the map.
class GlassPanel extends StatelessWidget {
  /// Creates the panel.
  const GlassPanel({
    required this.child,
    super.key,
    this.radius = 24,
    this.padding = EdgeInsets.zero,
  });

  /// The content.
  final Widget child;

  /// Corner radius.
  final double radius;

  /// Inner padding.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).velorki;
    // The colour lives on a Material, not a DecoratedBox: ListTiles inside
    // paint their ink on the nearest Material and would be hidden otherwise.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: colors.glass,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: colors.glassBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
