import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:velorki_api/velorki_api.dart' show WeatherSource;

import '../../../app/router.dart';
import '../../../core/links/link_opener.dart';
import '../../../core/plus/plus_gate.dart';
import '../../../core/units/units.dart' as units;
import '../../../l10n/generated/app_localizations.dart';
import '../../integrations/common/data/relay_client_provider.dart';
import '../../planner/presentation/route_format.dart';
import '../../settings/data/units.dart';
import '../../shared/application/covering_sheets.dart';
import '../../shared/presentation/error_text.dart';
import '../../shared/presentation/stat_tile.dart';
import '../../subscription/application/plus_access.dart';
import '../application/route_weather_controller.dart';
import '../application/wind_on_map.dart';
import '../domain/route_weather.dart';
import '../domain/route_weather_state.dart';
import 'route_weather_strip.dart';

/// The gust from which the summary names it, m/s: a strong breeze, force 6.
const double weatherGustShownMs = 10;

/// The departure can be moved this far past the earliest one.
const Duration weatherDepartureRange = Duration(hours: 24);

/// The departure moves in steps of this.
const Duration weatherDepartureStep = Duration(minutes: 15);

/// The weather on the way, in the planner's sheet under the surfaces.
///
/// Nothing in a build without the relay, nor while the store has not said
/// whether the rider has Velorki Plus; a short teaser for a rider without
/// it. While the forecast is on its way the section keeps the height it will
/// have, so the sheet's content does not jump when it arrives.
class RouteWeatherSection extends ConsumerWidget {
  /// Creates the section.
  const RouteWeatherSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(relayClientProvider) == null) return const SizedBox.shrink();
    switch (ref.watch(plusAccessProvider(PlusFeature.weather))) {
      case PlusAccess.unknown:
        return const SizedBox.shrink();
      case PlusAccess.missing:
        return const _Frame(child: _LockedTeaser());
      case PlusAccess.granted:
        break;
    }
    return switch (ref.watch(routeWeatherControllerProvider)) {
      AsyncError(:final error) => _Frame(child: _WeatherError(error: error)),
      AsyncLoading() => const _Frame(child: _WeatherBody(state: null)),
      AsyncData(:final value) =>
        value == null
            ? const SizedBox.shrink()
            : _Frame(child: _WeatherBody(state: value)),
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

/// What a rider without Velorki Plus sees: what the section would show and
/// the way to the paywall.
class _LockedTeaser extends StatelessWidget {
  const _LockedTeaser();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: SectionCaption(l10n.weatherTitle)),
                // The product name, not a translatable label.
                const SectionCaption('Plus', accent: true),
              ],
            ),
            const SizedBox(height: 6),
            Text(l10n.plusFeatureWeatherBody, style: theme.textTheme.bodySmall),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: () => context.push(paywallRoute),
                child: Text(l10n.plusSeeDetails),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The forecast could not be had: why, and a way to ask again.
class _WeatherError extends ConsumerWidget {
  const _WeatherError({required this.error});

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
          onPressed: () =>
              ref.read(routeWeatherControllerProvider.notifier).retry(),
          child: Text(l10n.weatherTryAgain),
        ),
      ],
    );
  }
}

/// The best departure of each forecast, worked out once: it does not depend
/// on the departure chosen, only on the forecast and where it starts.
final Expando<_Best> _bestDepartures = Expando<_Best>('bestDeparture');

class _Best {
  const _Best(this.from, this.at);

  final DateTime from;
  final DateTime? at;
}

/// The forecast: the summary, the strip, the departure and the switches.
/// Without [state], the same rows, empty, at the same height.
class _WeatherBody extends ConsumerWidget {
  const _WeatherBody({required this.state});

  final RouteWeatherState? state;

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

    final facts = s == null ? null : _facts(l10n, system, s);
    final temperature = summary == null ? null : _temperature(l10n, system, s!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCaption(l10n.weatherTitle),
        const SizedBox(height: 10),
        _FactsRow(facts: facts),
        const SizedBox(height: 12),
        RouteWeatherStrip(
          weather: s?.weather,
          maxTempLabel: summary?.maxTemp == null
              ? null
              : formatTemperature(l10n, system, summary!.maxTemp!),
          minTempLabel: summary?.minTemp == null
              ? null
              : formatTemperature(l10n, system, summary!.minTemp!),
          semanticsLabel: facts == null
              ? l10n.weatherTitle
              : l10n.weatherStripSemantics(
                  facts.wind ?? '',
                  facts.rain ?? '',
                  temperature ?? '',
                ),
        ),
        const SizedBox(height: 8),
        _Departure(state: s),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(l10n.weatherWindOnMap),
          value: ref.watch(windOnMapProvider),
          onChanged: (on) =>
              unawaited(ref.read(windOnMapProvider.notifier).set(on)),
        ),
        // Always there while the forecast is shown: the services ask for it.
        if (s == null)
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

  static String? _temperature(
    AppLocalizations l10n,
    units.UnitSystem system,
    RouteWeatherState s,
  ) {
    final lo = s.summary.minTemp;
    final hi = s.summary.maxTemp;
    if (lo == null || hi == null) return null;
    final low = units.temperatureIn(system, lo).round();
    final high = units.temperatureIn(system, hi).round();
    if (low == high) return formatTemperature(l10n, system, hi);
    return l10n.weatherTemperatureRange(
      '$low',
      formatTemperature(l10n, system, hi),
    );
  }

  static _Facts _facts(
    AppLocalizations l10n,
    units.UnitSystem system,
    RouteWeatherState s,
  ) {
    final summary = s.summary;
    final temperature = _temperature(l10n, system, s);
    if (temperature == null) return _Facts(none: l10n.weatherNoForecast);
    final shares = <(WindClass, double)>[
      (WindClass.headwind, summary.headwindShare),
      (WindClass.crosswind, summary.crosswindShare),
      (WindClass.tailwind, summary.tailwindShare),
      (WindClass.calm, summary.calmShare),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    final (windClass, share) = shares.first;
    final percent = formatPercent(l10n, share);
    final wind = switch (windClass) {
      WindClass.headwind => l10n.weatherHeadwind(percent),
      WindClass.crosswind => l10n.weatherCrosswind(percent),
      WindClass.tailwind => l10n.weatherTailwind(percent),
      WindClass.calm => l10n.weatherMostlyCalm,
    };
    final firstRain = summary.firstRainM;
    final rain = firstRain == null
        ? l10n.weatherDry
        : l10n.weatherRainFrom(formatDistance(l10n, system, firstRain));
    final gust = summary.maxGustMs;
    return _Facts(
      temperature: temperature,
      wind: wind,
      windClass: windClass,
      rain: rain,
      wet: firstRain != null,
      gusts: gust == null || gust < weatherGustShownMs
          ? null
          : l10n.weatherGusts(
              formatMeasure(l10n, units.formatSpeed(system, gust)),
            ),
    );
  }
}

/// The summary in words.
class _Facts {
  const _Facts({
    this.temperature,
    this.wind,
    this.windClass,
    this.rain,
    this.wet = false,
    this.gusts,
    this.none,
  });

  final String? temperature;
  final String? wind;
  final WindClass? windClass;
  final String? rain;
  final bool wet;
  final String? gusts;

  /// Said instead, when the forecast has nothing for the ride.
  final String? none;
}

/// The summary as small facts, an icon and a few words each, in the look of
/// the surface section's legend: two rows of two, always, so the section is
/// as tall with gusts as without, and as tall empty while the forecast is on
/// its way.
class _FactsRow extends StatelessWidget {
  const _FactsRow({required this.facts});

  final _Facts? facts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = facts;
    const blank = Opacity(
      opacity: 0,
      child: _Fact(icon: Icons.thermostat_rounded, text: ' '),
    );
    Widget grid(Widget a, Widget? b, Widget c, Widget? d) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: a),
            if (b != null) ...[const SizedBox(width: 16), Expanded(child: b)],
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: c),
            if (d != null) ...[const SizedBox(width: 16), Expanded(child: d)],
          ],
        ),
      ],
    );
    if (f == null) return grid(blank, blank, blank, blank);
    final none = f.none;
    if (none != null) {
      return grid(
        _Fact(icon: Icons.cloud_off_outlined, text: none),
        null,
        blank,
        null,
      );
    }
    return grid(
      _Fact(icon: Icons.thermostat_rounded, text: f.temperature!),
      _Fact(icon: Icons.air, text: f.wind!),
      _Fact(
        icon: f.wet ? Icons.water_drop : Icons.water_drop_outlined,
        text: f.rain!,
      ),
      f.gusts == null
          ? const SizedBox.shrink()
          : _Fact(
              icon: Icons.storm_outlined,
              text: f.gusts!,
              color: theme.colorScheme.error,
            ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(icon, size: 16, color: color ?? muted),
        const SizedBox(width: 6),
        // One line whatever the language: a fact too long for its half of
        // the row is set a little smaller.
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              text,
              maxLines: 1,
              softWrap: false,
              style: theme.textTheme.labelMedium?.copyWith(color: muted),
            ),
          ),
        ),
      ],
    );
  }
}

/// When the rider leaves: the time, a slider over the next twelve hours in
/// quarter hours, and the best time. Without [state], the same row, idle.
class _Departure extends ConsumerWidget {
  const _Departure({required this.state});

  final RouteWeatherState? state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final s = state;
    final controller = ref.read(routeWeatherControllerProvider.notifier);
    final steps =
        weatherDepartureRange.inMinutes ~/ weatherDepartureStep.inMinutes;

    String? when;
    var value = 0.0;
    DateTime? best;
    if (s != null) {
      final now = ref.read(weatherClockProvider)();
      when = _formatDeparture(context, l10n, s.departure, now);
      value =
          (s.departure.difference(s.earliestDeparture).inMinutes /
                  weatherDepartureStep.inMinutes)
              .clamp(0, steps)
              .toDouble();
      var cached = _bestDepartures[s.forecast];
      if (cached == null || cached.from != s.earliestDeparture) {
        cached = _Best(s.earliestDeparture, controller.suggestBestDeparture());
        _bestDepartures[s.forecast] = cached;
      }
      best = cached.at;
    }
    final bestIsNow = s != null && best != null && best == s.departure;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
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
                  : () => controller.setDeparture(best!),
              child: Text(
                bestIsNow ? l10n.weatherBestTimeNow : l10n.weatherBestTime,
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          max: steps.toDouble(),
          divisions: steps,
          label: when,
          semanticFormatterCallback: (_) => when ?? '',
          onChanged: s == null
              ? null
              : (v) {
                  final time = s.earliestDeparture.add(
                    weatherDepartureStep * v.round(),
                  );
                  if (time != s.departure) controller.setDeparture(time);
                },
        ),
      ],
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
