import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:velorki_brouter/velorki_brouter.dart' show SurfaceKind;

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../core/plus/plus_gate.dart';
import '../../integrations/common/data/relay_client_provider.dart';
import '../../map/domain/map_controller.dart';
import '../../planner/domain/elevation_profile.dart';
import '../../planner/presentation/elevation_profile_chart.dart';
import '../../planner/presentation/surface_stats_bar.dart';
import '../../shared/presentation/metric_chart.dart';
import '../../subscription/application/plus_access.dart';
import '../application/route_colouring.dart';
import '../application/route_overlay.dart';
import '../application/route_weather_controller.dart';
import 'free_forecast_dialog.dart';
import 'weather_keys.dart';

/// A route's elevation profile with the fill under the line coloured as the
/// route on the map is. The choice of what that is, [RouteColourControls],
/// stands above it.
class RouteElevationProfile extends ConsumerWidget {
  /// Creates the profile of [route], whose heights are [samples].
  const RouteElevationProfile({
    required this.route,
    required this.samples,
    this.height = 140,
    this.window,
    this.onWindow,
    this.cursor,
    super.key,
  });

  /// Whose profile it is: the planner's route, or a saved one.
  final WeatherRoute route;

  /// See [ElevationProfileChart.samples].
  final List<ElevationSample> samples;

  /// See [ElevationProfileChart.height].
  final double height;

  /// See [ElevationProfileChart.window].
  final DistanceWindow? window;

  /// See [ElevationProfileChart.onWindow].
  final ValueChanged<DistanceWindow?>? onWindow;

  /// See [ElevationProfileChart.cursor].
  final ValueNotifier<double?>? cursor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colouring = ref.watch(routeColouringProvider(route));
    return ElevationProfileChart(
      samples: samples,
      height: height,
      window: window,
      onWindow: onWindow,
      cursor: cursor,
      bands: routeColouringBands(colouring, Theme.of(context)),
    );
  }
}

/// What [route] on the map and its profile are coloured by
/// ([RouteColourChoice]), and right under it what the colours mean
/// ([RouteColourKey]).
class RouteColourControls extends StatelessWidget {
  /// Creates the controls of [route]'s colours.
  const RouteColourControls({required this.route, super.key});

  /// Whose colours they are: the planner's route, or a saved one.
  final WeatherRoute route;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The choice's heading takes the room above it as its touch target.
        const RouteColourChoice(),
        const SizedBox(height: 8),
        // What the colours mean. A line's height whatever is chosen, so the
        // sheet under it does not jump between off and a key; a key that
        // wraps takes what it needs.
        Stack(
          children: [
            Text(' ', style: Theme.of(context).textTheme.labelSmall),
            RouteColourKey(route: route),
          ],
        ),
      ],
    );
  }
}

/// [colouring]'s stretches as a chart's bands, in the colours the map draws
/// them in: the wind's and the surface's from [theme], the gradient's and
/// the rain's their own.
List<DistanceBand> routeColouringBands(
  RouteColouring colouring,
  ThemeData theme,
) => <DistanceBand>[
  for (final run in colouring.surface)
    (
      start: run.startM,
      end: run.endM,
      colour: surfaceKindColour(theme, run.key),
    ),
  for (final run in colouring.wind)
    (
      start: run.startM,
      end: run.endM,
      colour: switch (run.key) {
        WindClassOnMap.head => theme.velorki.windHead,
        WindClassOnMap.cross => theme.velorki.windCross,
        WindClassOnMap.tail => theme.velorki.windTail,
        WindClassOnMap.calm => theme.velorki.windCalm,
      },
    ),
  for (final run in colouring.colours)
    (start: run.startM, end: run.endM, colour: Color(0xFF000000 | run.key)),
];

/// The theme's colours [routeColourLinesOf] draws with: a screen that
/// draws them redraws when these change (the accent, light or dark).
Object routeColourThemeKey(ThemeData theme) => Object.hashAll([
  for (final kind in SurfaceKind.values) surfaceKindColour(theme, kind),
]);

/// [colouring] on the map: its [RouteColouring.lines], and the surface's
/// stretches each in its colour from [theme], as the Surface section has
/// it.
RouteColourLines routeColourLinesOf(RouteColouring colouring, ThemeData theme) {
  if (colouring.surfaceLines.isEmpty) return colouring.lines;
  return RouteColourLines(
    wind: colouring.lines.wind,
    colours: [
      ...colouring.lines.colours,
      for (final segment in colouring.surfaceLines)
        ColouredSegment(
          points: segment.points,
          colour: surfaceKindColour(theme, segment.kind).toARGB32() & 0xFFFFFF,
        ),
    ],
  );
}

/// Whether the route on the map and the profile under it are coloured, a
/// switch at the end of the heading, and by what: the gradient, the
/// surface, the wind or the rain. Switched off, the choice stays, greyed,
/// for when it is switched on again.
///
/// The wind and the rain come from the relay's forecast with Velorki Plus,
/// and from the free forecast the phone loads itself without it (or in a
/// build without the relay). Each time a rider without Plus picks either,
/// or switches the colouring on with either chosen, a dialog says what the
/// free forecast is ([showFreeForecastDialog]); only once they accept it is
/// the choice made, or the colouring switched on. A pick while the store
/// has not said whether the rider has Plus asks nothing.
class RouteColourChoice extends ConsumerWidget {
  /// Creates the choice.
  const RouteColourChoice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final shown = ref.watch(routeOverlayShownProvider);
    final on = ref.watch(routeColouringOnProvider);
    Widget label(String text) => FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(text, maxLines: 1, softWrap: false),
    );
    ButtonSegment<RouteOverlay> weather(
      RouteOverlay value,
      IconData icon,
      String text,
    ) => ButtonSegment(
      value: value,
      icon: Icon(icon, size: 18),
      label: label(text),
    );
    // Whether [overlay] may be drawn: asked of a rider without Plus about
    // the wind and the rain from the free forecast.
    Future<bool> confirmed(RouteOverlay overlay) async {
      if (!isWeatherOverlay(overlay) ||
          ref.read(routeWeatherFromRelayProvider)) {
        return true;
      }
      final relay = ref.read(relayClientProvider) != null;
      if (relay &&
          ref.read(plusAccessProvider(PlusFeature.weather)) ==
              PlusAccess.unknown) {
        // The store has not said yet: no question for what may be a Plus
        // rider. The free forecast meanwhile, the relay's once Plus is
        // granted.
        return true;
      }
      final answer = await showFreeForecastDialog(context, offerPlus: relay);
      if (!context.mounted) return false;
      switch (answer) {
        case FreeForecastAnswer.use:
          return true;
        case FreeForecastAnswer.seePlus:
          unawaited(context.push(paywallRoute));
          return false;
        case null:
          return false;
      }
    }

    Future<void> choose(RouteOverlay overlay) async {
      if (!await confirmed(overlay)) return;
      await ref.read(routeOverlayChoiceProvider.notifier).set(overlay);
    }

    Future<void> switchTo({required bool on}) async {
      if (on) {
        final overlay = ref.read(routeOverlayShownProvider);
        if (!await confirmed(overlay)) return;
        // The wind or the rain from the free forecast, now asked for in this
        // launch.
        if (isWeatherOverlay(overlay)) {
          await ref.read(routeOverlayChoiceProvider.notifier).set(overlay);
        }
      }
      await ref.read(routeColouringOnProvider.notifier).set(on: on);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The heading names the switch, read out as one, and the whole row,
        // with the room above and below it, toggles it: a target as wide as
        // the card and 48 high, in no more room than the row had.
        MergeSemantics(
          child: InkWell(
            onTap: () => unawaited(switchTo(on: !on)),
            child: Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.weatherRouteOverlay,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  // Beside a small label: no taller than the switch's track.
                  SizedBox(
                    height: 32,
                    child: Switch(
                      value: on,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onChanged: (value) => unawaited(switchTo(on: value)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SegmentedButton<RouteOverlay>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: RouteOverlay.gradient,
              label: label(l10n.colourByGradient),
            ),
            ButtonSegment(
              value: RouteOverlay.surface,
              label: label(l10n.surfaceTitle),
            ),
            weather(RouteOverlay.wind, Icons.air, l10n.weatherWind),
            weather(
              RouteOverlay.rain,
              Icons.water_drop_outlined,
              l10n.weatherRain,
            ),
          ],
          selected: {shown},
          // Off, the choice is kept, greyed, for when it is on again.
          onSelectionChanged: on
              ? (selection) => unawaited(choose(selection.single))
              : null,
        ),
      ],
    );
  }
}
