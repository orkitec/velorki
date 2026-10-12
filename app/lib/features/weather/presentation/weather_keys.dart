import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../shared/presentation/stat_tile.dart';
import '../application/route_overlay.dart';
import '../application/route_weather_controller.dart';
import '../application/route_wind.dart';
import '../domain/route_weather.dart';

/// What the wind's colours mean: a dot in each colour and its name, as the
/// strip's arrows and the route on the map are drawn. [calm] adds calm air.
class WindColourKey extends StatelessWidget {
  /// Creates the key.
  const WindColourKey({this.calm = false, this.style, super.key});

  /// Whether calm air is named too.
  final bool calm;

  /// The style of the names; the theme's small label, muted, without it.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).velorki;
    return _Key(
      style: style,
      entries: [
        (<Color>[colors.windHead], l10n.weatherKeyHeadwind),
        (<Color>[colors.windCross], l10n.weatherKeyCrosswind),
        (<Color>[colors.windTail], l10n.weatherKeyTailwind),
        if (calm) (<Color>[colors.windCalm], l10n.weatherKeyCalm),
      ],
    );
  }
}

/// What the rain's colours mean: each strength with the rain map's colours
/// it spans, lightest first.
class RainColourKey extends StatelessWidget {
  /// Creates the key.
  const RainColourKey({this.style, super.key});

  /// See [WindColourKey.style].
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _Key(
      style: style,
      entries: [
        for (final strength in RainStrength.values)
          (
            <Color>[
              // A few of its colours: enough to see the run of them.
              for (final k in rainStrengthClasses(strength).take(3))
                Color(0xFF000000 | rainClassColour(k)),
            ],
            switch (strength) {
              RainStrength.light => l10n.weatherRainLight,
              RainStrength.moderate => l10n.weatherRainModerate,
              RainStrength.heavy => l10n.weatherRainHeavy,
            },
          ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.entries, this.style});

  final List<(List<Color>, String)> entries;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text =
        style ??
        theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        );
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final (colours, label) in entries)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Swatch(colours: colours),
              const SizedBox(width: 5),
              Text(label, style: text),
            ],
          ),
      ],
    );
  }
}

/// A dot in one colour, or a short pill running through several.
class _Swatch extends StatelessWidget {
  const _Swatch({required this.colours});

  final List<Color> colours;

  @override
  Widget build(BuildContext context) {
    final one = colours.length == 1;
    return Container(
      width: one ? 9 : 16,
      height: 9,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4.5),
        color: one ? colours.single : null,
        gradient: one ? null : LinearGradient(colors: colours),
      ),
    );
  }
}

/// The key to the weather the route on the map is coloured by, over the
/// map while it is: the wind's colours, the rain's, or that no rain is on
/// the way. Nothing while the route is in its own colour, or while its
/// weather is on its way, failed or not there.
class RouteOverlayLegend extends ConsumerWidget {
  /// Creates the legend of [route]'s weather.
  const RouteOverlayLegend({
    this.route = plannerWeatherRoute,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  /// Whose weather it is.
  final WeatherRoute route;

  /// Around the chip, while there is one.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overlay = ref.watch(routeOverlayChoiceProvider);
    if (overlay == RouteOverlay.off) return const SizedBox.shrink();
    final weather = ref.watch(routeWeatherControllerProvider(route));
    final state = weather.isLoading || weather.hasError ? null : weather.value;
    if (state == null || !state.weather.weather.any((w) => w != null)) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final style = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurface,
    );
    final rainy = state.weather.weather.any(
      (w) => w != null && rainClassOnRoute(w) != null,
    );
    final Widget key = switch (overlay) {
      RouteOverlay.off => const SizedBox.shrink(),
      RouteOverlay.wind => WindColourKey(
        style: style,
        calm: state.weather.weather.any((w) => w?.windClass == WindClass.calm),
      ),
      RouteOverlay.rain =>
        rainy
            ? RainColourKey(style: style)
            : Text(l10n.weatherRainNoneOnRoute, style: style),
    };
    return Padding(
      padding: padding,
      child: GlassPanel(
        key: const ValueKey<String>('route-overlay-legend'),
        radius: 18,
        padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              overlay == RouteOverlay.wind
                  ? Icons.air
                  : Icons.water_drop_outlined,
              size: 16,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Flexible(child: key),
          ],
        ),
      ),
    );
  }
}
