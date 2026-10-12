import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../core/geo/route_gradient.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../application/route_colouring.dart';
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

/// What the gradient's colours mean: a dot in each and the gradient, in
/// percent, its class starts at; an arrow down for the descents. Numbers
/// rather than words, so it stays one short line in any language.
class GradientColourKey extends StatelessWidget {
  /// Creates the key.
  const GradientColourKey({super.key});

  @override
  Widget build(BuildContext context) {
    final locale = AppLocalizations.of(context).localeName;
    final percent = NumberFormat.percentPattern(locale);
    final number = NumberFormat.decimalPattern(locale);
    final bounds = gradientClassBounds;
    return _Key(
      spacing: 8,
      entries: [
        for (final gradient in GradientClass.values)
          (
            <Color>[Color(0xFF000000 | gradientClassColour(gradient))],
            switch (gradient) {
              // Not a word: an arrow says downhill in every language.
              GradientClass.descent => '\u2193',
              GradientClass.flat => number.format(0),
              GradientClass.moderate => number.format(bounds[1]),
              GradientClass.steep => number.format(bounds[2]),
              // The last says what the numbers are.
              GradientClass.verySteep => percent.format(bounds[3] / 100),
            },
          ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.entries, this.style, this.spacing = 12});

  final List<(List<Color>, String)> entries;
  final TextStyle? style;

  /// Between the entries.
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text =
        style ??
        theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        );
    return Wrap(
      spacing: spacing,
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

/// The key to what the route is coloured by, under the choice of it: the
/// gradient's colours, the wind's, the rain's, or that no rain is on the
/// way. Nothing while the route is in its own colour, while there is no
/// route to colour, or while its weather is on its way, failed or not
/// there.
class RouteColourKey extends ConsumerWidget {
  /// Creates the key to [route]'s colouring.
  const RouteColourKey({this.route = plannerWeatherRoute, super.key});

  /// Whose route it is.
  final WeatherRoute route;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overlay = ref.watch(routeOverlayShownProvider);
    switch (overlay) {
      case RouteOverlay.off:
        return const SizedBox.shrink();
      case RouteOverlay.gradient:
        return ref.watch(routeColouringProvider(route)).isEmpty
            ? const SizedBox.shrink()
            : const GradientColourKey();
      case RouteOverlay.wind || RouteOverlay.rain:
        final weather = ref.watch(routeWeatherControllerProvider(route));
        final state = weather.isLoading || weather.hasError
            ? null
            : weather.value;
        if (state == null || !state.weather.weather.any((w) => w != null)) {
          return const SizedBox.shrink();
        }
        if (overlay == RouteOverlay.wind) {
          return WindColourKey(
            calm: state.weather.weather.any(
              (w) => w?.windClass == WindClass.calm,
            ),
          );
        }
        final rainy = state.weather.weather.any(
          (w) => w != null && rainClassOnRoute(w) != null,
        );
        if (rainy) return const RainColourKey();
        final theme = Theme.of(context);
        return Text(
          AppLocalizations.of(context).weatherRainNoneOnRoute,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        );
    }
  }
}
