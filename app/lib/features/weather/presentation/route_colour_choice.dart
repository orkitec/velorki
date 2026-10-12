import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../core/plus/plus_gate.dart';
import '../../integrations/common/data/relay_client_provider.dart';
import '../../map/domain/map_controller.dart';
import '../../planner/domain/elevation_profile.dart';
import '../../planner/presentation/elevation_profile_chart.dart';
import '../../shared/presentation/metric_chart.dart';
import '../../subscription/application/plus_access.dart';
import '../application/route_colouring.dart';
import '../application/route_overlay.dart';
import '../application/route_weather_controller.dart';
import 'free_forecast_dialog.dart';
import 'weather_keys.dart';

/// A route's elevation profile with the fill under the line coloured as the
/// route on the map is, and under it the choice of what that is.
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevationProfileChart(
          samples: samples,
          height: height,
          window: window,
          onWindow: onWindow,
          cursor: cursor,
          bands: routeColouringBands(colouring, Theme.of(context).velorki),
        ),
        const SizedBox(height: 12),
        const RouteColourChoice(),
        const SizedBox(height: 8),
        // What the colours mean. A line's height whatever is chosen, so the
        // sheet under it does not jump between Off and a key; a key that
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
/// them in: the wind's from the theme, the gradient's and the rain's their
/// own.
List<DistanceBand> routeColouringBands(
  RouteColouring colouring,
  VelorkiColors colors,
) => <DistanceBand>[
  for (final run in colouring.wind)
    (
      start: run.startM,
      end: run.endM,
      colour: switch (run.key) {
        WindClassOnMap.head => colors.windHead,
        WindClassOnMap.cross => colors.windCross,
        WindClassOnMap.tail => colors.windTail,
        WindClassOnMap.calm => colors.windCalm,
      },
    ),
  for (final run in colouring.colours)
    (start: run.startM, end: run.endM, colour: Color(0xFF000000 | run.key)),
];

/// What the route on the map and the profile above are coloured by:
/// nothing, the gradient, the wind or the rain.
///
/// The wind and the rain come from the relay's forecast with Velorki Plus,
/// and from the free forecast the phone loads itself without it (or in a
/// build without the relay). The first time a rider without Plus picks
/// either, a dialog says what the free forecast is
/// ([showFreeForecastDialog]); only once they accept it is the choice made.
/// A pick while the store has not said whether the rider has Plus asks
/// nothing and counts as accepting it.
class RouteColourChoice extends ConsumerWidget {
  /// Creates the choice.
  const RouteColourChoice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final shown = ref.watch(routeOverlayShownProvider);
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
    Future<void> choose(RouteOverlay overlay) async {
      final choice = ref.read(routeOverlayChoiceProvider.notifier);
      if (isWeatherOverlay(overlay) &&
          !ref.read(routeWeatherFromRelayProvider) &&
          !ref.read(freeRouteForecastAcceptedProvider)) {
        final relay = ref.read(relayClientProvider) != null;
        if (relay &&
            ref.read(plusAccessProvider(PlusFeature.weather)) ==
                PlusAccess.unknown) {
          // The store has not said yet: no question for what may be a
          // Plus rider. The free forecast meanwhile, the relay's once Plus
          // is granted; and the pick stands for an acceptance, so no
          // dialog comes later out of nowhere should Plus turn out
          // missing.
          await ref.read(freeRouteForecastAcceptedProvider.notifier).accept();
          await choice.set(overlay);
          return;
        }
        final answer = await showFreeForecastDialog(context, offerPlus: relay);
        if (!context.mounted) return;
        switch (answer) {
          case FreeForecastAnswer.use:
            await ref.read(freeRouteForecastAcceptedProvider.notifier).accept();
          case FreeForecastAnswer.seePlus:
            unawaited(context.push(paywallRoute));
            return;
          case null:
            return;
        }
      }
      await choice.set(overlay);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.weatherRouteOverlay,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        SegmentedButton<RouteOverlay>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: RouteOverlay.off,
              label: label(l10n.weatherOverlayOff),
            ),
            ButtonSegment(
              value: RouteOverlay.gradient,
              label: label(l10n.colourByGradient),
            ),
            weather(RouteOverlay.wind, Icons.air, l10n.weatherWind),
            weather(
              RouteOverlay.rain,
              Icons.water_drop_outlined,
              l10n.weatherRain,
            ),
          ],
          selected: {shown},
          onSelectionChanged: (selection) =>
              unawaited(choose(selection.single)),
        ),
      ],
    );
  }
}
