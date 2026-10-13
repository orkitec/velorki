import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../map/data/weather_map_preferences.dart';
import '../../map/domain/weather_map.dart';
import '../../map/presentation/layers_sheet.dart' show switchRainRadar;
import '../application/route_colouring.dart';
import '../application/route_overlay.dart';
import '../application/weather_time_hint.dart';
import 'route_colour_choice.dart';

/// What the rider picked in the time control's dialog.
enum WeatherTimeHintAction {
  /// Switch the map's rain radar on.
  rainRadar,

  /// Switch the map's wind on.
  wind,

  /// Colour the route by the wind.
  colourByWind,

  /// Colour the route by the rain.
  colourByRain,
}

/// The key of the dialog's "Don't show again" box, for the tests.
const Key weatherTimeHintNeverKey = ValueKey<String>('weather-time-hint-never');

/// Whether the Plan tab's time control, let go at another step, would change
/// nothing in view: a route whose colours do not follow the weather (not
/// coloured, or by the gradient or the surface) and the map's rain and wind
/// off. Then only the route's weather further down the sheet moves.
bool weatherTimeMovesNothingInView(WidgetRef ref) {
  if (ref.read(plannerTimeControlProvider) !=
      PlannerTimeControl.departureShown) {
    return false;
  }
  if (ref.read(routeColouringOnProvider) &&
      isWeatherOverlay(ref.read(routeOverlayShownProvider))) {
    return false;
  }
  final settings = ref.read(weatherMapPreferencesProvider);
  final sources = ref.read(weatherMapSourcesProvider);
  return !(settings.radar &&
          weatherKindAvailable(sources, WeatherKind.radar)) &&
      !(settings.wind && weatherKindAvailable(sources, WeatherKind.wind));
}

/// The Plan tab's time control was let go at another step: where that
/// changes nothing in view ([weatherTimeMovesNothingInView]), a dialog says
/// what it moves and offers to show it ([showWeatherTimeHintDialog]), each
/// choice made as its own control would make it. At most once a run, and
/// never again once the rider ticks "Don't show again" ([WeatherTimeHint]).
Future<void> showWeatherTimeHint(BuildContext context, WidgetRef ref) async {
  if (!ref.read(weatherTimeHintProvider) ||
      !weatherTimeMovesNothingInView(ref)) {
    return;
  }
  final hint = ref.read(weatherTimeHintProvider.notifier)..shown();
  final sources = ref.read(weatherMapSourcesProvider);
  final action = await showWeatherTimeHintDialog(
    context,
    rainRadar: weatherKindAvailable(sources, WeatherKind.radar),
    wind: weatherKindAvailable(sources, WeatherKind.wind),
    onNever: (never) => unawaited(hint.setNever(never: never)),
  );
  if (!context.mounted) return;
  switch (action) {
    case WeatherTimeHintAction.rainRadar:
      await switchRainRadar(context, ref, on: true);
    case WeatherTimeHintAction.wind:
      await ref.read(weatherMapPreferencesProvider.notifier).setWind(true);
    case WeatherTimeHintAction.colourByWind:
      await colourRouteBy(context, ref, RouteOverlay.wind);
    case WeatherTimeHintAction.colourByRain:
      await colourRouteBy(context, ref, RouteOverlay.rain);
    case null:
      break;
  }
}

/// Says what the route's departure slider moves: the weather on the map
/// and along the route, and the route's weather further down. Offers the
/// map's rain radar ([rainRadar]) and wind ([wind]) where the build has
/// them, and the route coloured by the wind or the rain; `null` when
/// closed. [onNever] hears the "Don't show again" box ticked or unticked.
///
/// Scrollable, so a phone turned sideways still reaches every choice.
Future<WeatherTimeHintAction?> showWeatherTimeHintDialog(
  BuildContext context, {
  required bool rainRadar,
  required bool wind,
  required ValueChanged<bool> onNever,
}) => showDialog<WeatherTimeHintAction>(
  context: context,
  useRootNavigator: true,
  builder: (context) {
    final l10n = AppLocalizations.of(context);
    Widget choice(WeatherTimeHintAction action, IconData icon, String text) =>
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon),
          title: Text(text),
          onTap: () => Navigator.of(context).pop(action),
        );
    return AlertDialog(
      scrollable: true,
      title: Text(l10n.weatherTimeHintTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.weatherTimeHintBody),
          const SizedBox(height: 8),
          if (rainRadar)
            choice(
              WeatherTimeHintAction.rainRadar,
              Icons.water_drop_outlined,
              l10n.weatherTimeHintRainRadar,
            ),
          if (wind)
            choice(
              WeatherTimeHintAction.wind,
              Icons.air,
              l10n.weatherTimeHintWind,
            ),
          choice(
            WeatherTimeHintAction.colourByWind,
            Icons.route_outlined,
            l10n.weatherTimeHintColourWind,
          ),
          choice(
            WeatherTimeHintAction.colourByRain,
            Icons.route_outlined,
            l10n.weatherTimeHintColourRain,
          ),
          _NeverBox(onChanged: onNever),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.weatherTimeHintClose),
        ),
      ],
    );
  },
);

/// The dialog's "Don't show again" box, which keeps its tick while the
/// dialog is rebuilt (turned sideways).
class _NeverBox extends StatefulWidget {
  const _NeverBox({required this.onChanged});

  final ValueChanged<bool> onChanged;

  @override
  State<_NeverBox> createState() => _NeverBoxState();
}

class _NeverBoxState extends State<_NeverBox> {
  bool _never = false;

  @override
  Widget build(BuildContext context) => CheckboxListTile(
    key: weatherTimeHintNeverKey,
    contentPadding: EdgeInsets.zero,
    controlAffinity: ListTileControlAffinity.leading,
    value: _never,
    onChanged: (value) {
      setState(() => _never = value ?? false);
      widget.onChanged(_never);
    },
    title: Text(AppLocalizations.of(context).weatherTimeHintDontShowAgain),
  );
}
