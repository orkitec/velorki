import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:velorki_api/velorki_api.dart' show WeatherSource;

import '../../../app/router.dart';
import '../../../core/links/link_opener.dart';
import '../../../core/plus/plus_gate.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../integrations/common/data/relay_client_provider.dart';
import '../../map/data/weather_map_preferences.dart';
import '../../map/domain/weather_map.dart';
import '../../planner/presentation/route_format.dart';
import '../../settings/data/units.dart';
import '../../shared/application/covering_sheets.dart';
import '../../shared/presentation/error_text.dart';
import '../../shared/presentation/metric_chart.dart' show DistanceWindow;
import '../../shared/presentation/stat_tile.dart';
import '../../subscription/application/plus_access.dart';
import '../application/free_route_weather.dart';
import '../application/route_colouring.dart';
import '../application/route_overlay.dart';
import '../application/route_weather_controller.dart';
import '../data/dwd_route_forecast.dart';
import '../domain/route_weather.dart';
import '../domain/route_sampling.dart' show departureAfter;
import '../domain/route_weather_state.dart';
import 'route_weather_strip.dart';
import 'weather_digest_text.dart';
import 'weather_keys.dart';

/// The weather on the way, in the planner's sheet under the surfaces and on
/// a saved route's page.
///
/// For everyone: the weather [routeColourWeatherProvider] gives, the one the
/// route is coloured by, so the section, the colours and their key always
/// tell the same forecast. With Velorki Plus the relay's, finer, from local
/// weather services, with gusts and the chance of rain; without it (or in a
/// build without the relay) the free forecast the phone loads from the DWD
/// itself: wind, rain and temperature. Then a locked line says what Plus
/// adds, where the build offers Plus, and the source line under it leads to
/// the Plus page.
///
/// Nothing while there is no route, nor, in a build with the relay, while
/// the store has not said whether the rider has Plus (which forecast to
/// show is not known yet). While the forecast is on its way the section
/// keeps the height it will have, so the sheet's content does not jump
/// when it arrives.
///
/// Its strip shares the elevation profile's [window] and [cursor].
class RouteWeatherSection extends ConsumerWidget {
  /// Creates the section of [route]'s weather.
  const RouteWeatherSection({
    super.key,
    this.route = plannerWeatherRoute,
    this.window,
    this.onWindow,
    this.cursor,
  });

  /// Whose weather it is: the planner's route, or a saved one.
  final WeatherRoute route;

  /// See [RouteWeatherStrip.window].
  final DistanceWindow? window;

  /// See [RouteWeatherStrip.onWindow].
  final ValueChanged<DistanceWindow?>? onWindow;

  /// See [RouteWeatherStrip.cursor].
  final ValueNotifier<double?>? cursor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(relayClientProvider) != null &&
        ref.watch(plusAccessProvider(PlusFeature.weather)) ==
            PlusAccess.unknown) {
      return const SizedBox.shrink();
    }
    final plus = ref.watch(routeWeatherFromRelayProvider);
    return switch (ref.watch(routeColourWeatherProvider(route))) {
      AsyncError(:final error) => _Frame(
        child: _WeatherError(route: route, plus: plus, error: error),
      ),
      AsyncLoading() => _Frame(
        child: _WeatherBody(route: route, plus: plus, state: null),
      ),
      AsyncData(:final value) =>
        value == null
            ? const SizedBox.shrink()
            : _Frame(
                child: _WeatherBody(
                  route: route,
                  plus: plus,
                  state: value,
                  window: window,
                  onWindow: onWindow,
                  cursor: cursor,
                ),
              ),
    };
  }
}

/// The space above the section, as the surfaces have above them.
class _Frame extends StatelessWidget {
  const _Frame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.only(top: 24), child: child);
}

/// The forecast could not be had: why, and a way to ask again.
class _WeatherError extends ConsumerWidget {
  const _WeatherError({
    required this.route,
    required this.plus,
    required this.error,
  });

  final WeatherRoute route;

  /// Whether it is the relay's forecast that failed, or the free one.
  final bool plus;
  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionCaption(l10n.weatherTitle),
        const SizedBox(height: 8),
        Text(
          errorText(l10n, error),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        TextButton(
          style: TextButton.styleFrom(padding: EdgeInsets.zero),
          onPressed: plus
              ? () => ref
                    .read(routeWeatherControllerProvider(route).notifier)
                    .retry()
              : () => ref.invalidate(freeRouteWeatherProvider(route)),
          child: Text(l10n.weatherTryAgain),
        ),
      ],
    );
  }
}

/// The best departure of each route's samples, worked out once for the
/// forecast, where its steps start, the departure chosen and, from the free
/// forecast, how many of its grids had come.
final Expando<_Best> _bestDepartures = Expando<_Best>('bestDeparture');

class _Best {
  const _Best(
    this.forecast,
    this.from,
    this.departure,
    this.loaded,
    this.offset,
  );

  final Object forecast;
  final DateTime from;
  final DateTime departure;
  final int loaded;

  /// The time control's step it is at, minutes from [from].
  final int? offset;
}

/// The forecast: the line that sums it up, the strip with its key, the
/// departure and the attribution; from the free forecast, the line of what
/// Plus adds over the departure and the free source line for the
/// attribution. Without [state], the same rows, empty, at the same height.
class _WeatherBody extends ConsumerWidget {
  const _WeatherBody({
    required this.route,
    required this.plus,
    required this.state,
    this.window,
    this.onWindow,
    this.cursor,
  });

  final WeatherRoute route;

  /// Whether [state] is the relay's forecast, not the free one.
  final bool plus;
  final RouteWeatherState? state;
  final DistanceWindow? window;
  final ValueChanged<DistanceWindow?>? onWindow;
  final ValueNotifier<double?>? cursor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final system = ref.watch(unitSystemProvider);
    final s = state;
    final summary = s?.summary;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    final parts = s == null
        ? null
        : weatherDigestParts(
            l10n,
            system,
            s.digest,
            clock: (at) => _clock(context, at),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCaption(l10n.weatherTitle),
        const SizedBox(height: 8),
        _SummaryLine(
          text: parts == null
              ? null
              : parts.isEmpty
              ? l10n.weatherNoForecast
              : parts.join(' · '),
        ),
        const SizedBox(height: 8),
        RouteWeatherStrip(
          weather: s?.weather,
          window: window,
          onWindow: onWindow,
          cursor: cursor,
          rowLabels: (
            wind: l10n.weatherWind,
            rain: l10n.weatherRain,
            temperature: l10n.weatherTemperatureShort,
          ),
          maxTempLabel: summary?.maxTemp == null
              ? null
              : formatTemperature(l10n, system, summary!.maxTemp!),
          minTempLabel: summary?.minTemp == null
              ? null
              : formatTemperature(l10n, system, summary!.minTemp!),
          semanticsLabel: parts == null || parts.isEmpty
              ? l10n.weatherTitle
              : l10n.weatherStripSemantics(
                  parts[1],
                  parts[0],
                  parts.length > 2 ? parts[2] : '',
                ),
        ),
        const SizedBox(height: 6),
        // The arrows' colours, under the plot as the profile's axis is.
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: weatherStripLeftInset,
          ),
          child: WindColourKey(
            calm:
                s?.weather.weather.any((w) => w?.windClass == WindClass.calm) ??
                false,
          ),
        ),
        // What the relay's forecast has and the free one has not.
        if (!plus && ref.watch(relayClientProvider) != null) ...[
          const SizedBox(height: 4),
          const _LockedPlusRows(),
        ],
        const SizedBox(height: 12),
        _Departure(route: route, plus: plus, state: s),
        const SizedBox(height: 4),
        // Always there while the forecast is shown: the services ask for it.
        if (!plus)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: FreeForecastSourceLine(),
          )
        else if (s == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(' ', style: muted),
          )
        else
          _Attribution(sources: _sources(s), style: muted),
      ],
    );
  }

  static List<WeatherSource> _sources(RouteWeatherState s) {
    final used = s.summary.sources;
    return used.isNotEmpty ? used : s.forecast.sources;
  }

  /// [at]'s time of day as the phone writes it, in its time zone.
  static String _clock(BuildContext context, DateTime at) =>
      MaterialLocalizations.of(context).formatTimeOfDay(
        TimeOfDay.fromDateTime(at.toLocal()),
        alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
      );
}

/// The forecast in a line of words, mostly one or two; at least two lines'
/// height, so the section does not grow when the forecast comes, nor when a
/// line of one becomes a line of two.
class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.text});

  final String? text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyMedium;
    // Two lines' height whatever the text: the strip below stays put
    // between a line of one and a line of two.
    final painter = TextPainter(
      text: TextSpan(text: ' \n ', style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final height = painter.height;
    painter.dispose();
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: height),
      child: Text(text ?? ' ', style: style),
    );
  }
}

/// When the rider leaves: the time and the best time. The departure is the
/// time control's ([weatherRadarOffsetProvider]): on the Plan tab the one
/// under Save, on a saved route's page [RouteDepartureSlider] under its
/// actions, so here only the time is said. Best time moves the control to
/// its step with the least rain and headwind. Without [state], the same
/// row, idle.
class _Departure extends ConsumerWidget {
  const _Departure({
    required this.route,
    required this.plus,
    required this.state,
  });

  final WeatherRoute route;

  /// Whether [state] is the relay's forecast, not the free one.
  final bool plus;
  final RouteWeatherState? state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final s = state;
    // The free forecast's best time is worked out from the grids fetched
    // ahead, again as more of them come.
    final loaded = plus ? 0 : ref.watch(freeForecastPrefetchProvider(route));

    String? when;
    int? best;
    if (s != null) {
      final now = ref.read(weatherClockProvider)();
      when = _formatDeparture(context, l10n, s.departure, now);
      var cached = _bestDepartures[s.samples];
      if (cached == null ||
          !identical(cached.forecast, s.forecast) ||
          cached.from != s.earliestDeparture ||
          cached.departure != s.departure ||
          cached.loaded != loaded) {
        cached = _Best(
          s.forecast,
          s.earliestDeparture,
          s.departure,
          loaded,
          plus
              ? ref
                    .read(routeWeatherControllerProvider(route).notifier)
                    .suggestBestOffset()
              : suggestFreeBestOffset(ref.read(dwdForecastClientProvider), s),
        );
        _bestDepartures[s.samples] = cached;
      }
      best = cached.offset;
    }
    final bestIsNow = s != null && best != null && best == s.offsetMinutes;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.weatherStart,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  when ?? ' ',
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  softWrap: false,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: s == null || best == null || bestIsNow
              ? null
              : () => ref.read(weatherRadarOffsetProvider.notifier).set(best!),
          child: Text(
            bestIsNow ? l10n.weatherBestTimeNow : l10n.weatherBestTime,
          ),
        ),
      ],
    );
  }
}

/// A saved route's departure, on its page under the actions: a slider on
/// the time control's steps ([weatherRadarOffsets]), set when it is let go
/// as the map's is ([weatherRadarOffsetProvider]), the departure the route
/// weather section and the colours follow. The page's only time control,
/// so there whenever there is a route, and movable while the forecast is
/// on its way or has failed: a new departure asks for it again. Nothing
/// without a route, nor, as the section, while the store has not said
/// whether the rider has Plus in a build with the relay.
class RouteDepartureSlider extends ConsumerStatefulWidget {
  /// Creates the slider of [route]'s departure.
  const RouteDepartureSlider({required this.route, super.key});

  /// Whose departure it is.
  final WeatherRoute route;

  @override
  ConsumerState<RouteDepartureSlider> createState() =>
      _RouteDepartureSliderState();
}

class _RouteDepartureSliderState extends ConsumerState<RouteDepartureSlider> {
  /// The slider's step while a finger moves it.
  int? _dragging;

  @override
  Widget build(BuildContext context) {
    if (ref.watch(relayClientProvider) != null &&
        ref.watch(plusAccessProvider(PlusFeature.weather)) ==
            PlusAccess.unknown) {
      return const SizedBox.shrink();
    }
    final RouteWeatherState? s;
    switch (ref.watch(routeColourWeatherProvider(widget.route))) {
      case AsyncData(:final value):
        // No route.
        if (value == null) return const SizedBox.shrink();
        s = value;
      case AsyncError() || AsyncLoading():
        s = null;
    }
    final l10n = AppLocalizations.of(context);
    final committed = ref.watch(weatherRadarOffsetProvider);
    final offset = _dragging ?? committed;
    final now = ref.read(weatherClockProvider)();
    // The forecast's departure where there is one; else the step from now.
    final departure = s == null
        ? departureAfter(now, offset)
        : _dragging == null
        ? s.departure
        : s.earliestDeparture.add(Duration(minutes: offset));
    final when = _formatDeparture(context, l10n, departure, now);
    return Semantics(
      label: l10n.mapWeatherDepartureTime,
      child: Slider(
        value: weatherSliderIndexOf(offset).toDouble(),
        max: (weatherRadarOffsets.length - 1).toDouble(),
        divisions: weatherRadarOffsets.length - 1,
        label: when,
        semanticFormatterCallback: (_) => when,
        onChanged: (v) =>
            setState(() => _dragging = weatherOffsetOfSliderIndex(v.round())),
        onChangeEnd: (v) {
          setState(() => _dragging = null);
          ref
              .read(weatherRadarOffsetProvider.notifier)
              .set(weatherOffsetOfSliderIndex(v.round()));
        },
      ),
    );
  }
}

/// What the free forecast lacks and Velorki Plus has, the gusts and the
/// chance of rain, as one locked line under the strip's key: a lock where
/// the rows' names stand, the words on the plot's edge; a tap opens the
/// Plus page.
class _LockedPlusRows extends StatelessWidget {
  const _LockedPlusRows();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colour = theme.colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: () => unawaited(context.push(paywallRoute)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: weatherStripLeftInset,
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Padding(
                  // Where the rows' names end, clear of the plot.
                  padding: const EdgeInsetsDirectional.only(end: 10),
                  child: Icon(Icons.lock_outline, size: 14, color: colour),
                ),
              ),
            ),
            Flexible(
              child: Text(
                l10n.weatherPlusExtrasLocked,
                style: theme.textTheme.labelSmall?.copyWith(color: colour),
              ),
            ),
            Icon(Icons.chevron_right, size: 14, color: colour),
          ],
        ),
      ),
    );
  }
}

/// [departure] as the rider reads it: "Today 10:15", "Tomorrow 08:30", or
/// the weekday and the time, in the phone's time zone.
String _formatDeparture(
  BuildContext context,
  AppLocalizations l10n,
  DateTime departure,
  DateTime now,
) {
  final at = departure.toLocal();
  final today = now.toLocal();
  final time = MaterialLocalizations.of(context).formatTimeOfDay(
    TimeOfDay.fromDateTime(at),
    alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
  );
  final days = DateTime(
    at.year,
    at.month,
    at.day,
  ).difference(DateTime(today.year, today.month, today.day)).inHours;
  // Hours, not days: a day with a clock change is 23 or 25 of them.
  final dayIndex = (days / 24).round();
  if (dayIndex <= 0) return l10n.weatherDepartureToday(time);
  if (dayIndex == 1) return l10n.weatherDepartureTomorrow(time);
  return l10n.weatherDepartureOnDay(
    DateFormat.E(l10n.localeName).format(at),
    time,
  );
}

/// The services the forecast comes from, named; a tap lists their licences.
class _Attribution extends ConsumerWidget {
  const _Attribution({required this.sources, required this.style});

  final List<WeatherSource> sources;
  final TextStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final names = sources.map((s) => s.name).join(' · ');
    return InkWell(
      onTap: sources.isEmpty
          ? null
          : () => unawaited(_showSources(context, ref, sources)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(l10n.weatherAttribution(names), style: style),
      ),
    );
  }
}

Future<void> _showSources(
  BuildContext context,
  WidgetRef ref,
  List<WeatherSource> sources,
) {
  final open = ref.read(linkOpenerProvider);
  return coverTabSheet(
    context,
    () => showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        final theme = Theme.of(context);
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.paddingOf(context).bottom + 16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.weatherSourcesTitle, style: theme.textTheme.titleLarge),
              for (final source in sources) ...[
                const SizedBox(height: 16),
                Text(source.name, style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(source.licence, style: theme.textTheme.bodySmall),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    onPressed: () {
                      final url = Uri.tryParse(source.url);
                      if (url != null) unawaited(open(url));
                    },
                    child: Text(source.url),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    ),
  );
}
