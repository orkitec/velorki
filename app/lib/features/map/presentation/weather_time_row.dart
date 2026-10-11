import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../shared/presentation/stat_tile.dart';
import '../application/weather_map_binding.dart';
import '../application/weather_map_driver.dart';
import '../data/weather_map_preferences.dart';
import '../domain/weather_map.dart';

/// What the time control calls the step [offsetMinutes] from now: "Now",
/// "+45 min", "+2 h".
String weatherStepText(AppLocalizations l10n, int offsetMinutes) {
  if (offsetMinutes <= 0) return l10n.mapWeatherNow;
  if (offsetMinutes % 60 == 0) {
    return l10n.mapWeatherHoursAhead(offsetMinutes ~/ 60);
  }
  return l10n.mapWeatherMinutesAhead(offsetMinutes);
}

/// [utc] in the phone's own clock format, local time.
String weatherClockTime(BuildContext context, DateTime utc) =>
    MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(utc.toLocal()),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );

/// What the rain over the middle of the view shows at [offsetMinutes], by
/// the sources in force and the map's [status]; `null` where nothing does.
({RainRole role, DateTime time})? weatherRainAt(
  List<WeatherMapSource> sources,
  WeatherMapStatus status,
  int offsetMinutes,
) {
  final centre = status.centre;
  if (centre == null) return null;
  return rainAtPoint(
    sources,
    centre,
    status.at ?? DateTime.now(),
    offsetMinutes,
  );
}

/// What a moment ahead is: the DWD's nowcast or a model's forecast.
String? weatherSourceTag(AppLocalizations l10n, RainRole role) =>
    switch (role) {
      RainRole.radar => l10n.mapWeatherNowcast,
      RainRole.model => l10n.mapWeatherForecast,
      RainRole.satellite => null,
    };

/// The time control's label: the step, the moment the rain over the
/// middle of the view shows, and ahead what that is. "Now · 20:25",
/// "+45 min · 21:30 · Nowcast", "+3 h · 23:00 · Forecast".
String weatherRainLabel(
  BuildContext context,
  int offsetMinutes,
  ({RainRole role, DateTime time})? rain,
) {
  final l10n = AppLocalizations.of(context);
  return <String>[
    weatherStepText(l10n, offsetMinutes),
    if (rain != null) weatherClockTime(context, rain.time),
    if (rain != null && offsetMinutes > 0) ?weatherSourceTag(l10n, rain.role),
  ].join(' · ');
}

/// Whether the rain is on and some source of it in use: whether the
/// sheets show [WeatherTimeRow].
bool weatherRainOn(WidgetRef ref) =>
    ref.watch(weatherMapPreferencesProvider).radar &&
    weatherKindAvailable(
      ref.watch(weatherMapSourcesProvider),
      WeatherKind.radar,
    );

/// The rain's time control, for the Plan and Record sheets: one line, the
/// drop, the label and the slider in the room that is left, while the rain
/// is on; nothing while it is off. The step is the one all tabs share
/// ([weatherRadarOffsetProvider]); the map follows when the slider is let
/// go.
class WeatherTimeRow extends ConsumerStatefulWidget {
  /// Creates the row, with [padding] around it while it shows.
  const WeatherTimeRow({super.key, this.padding = EdgeInsets.zero});

  final EdgeInsetsGeometry padding;

  @override
  ConsumerState<WeatherTimeRow> createState() => _WeatherTimeRowState();
}

/// How tall [WeatherTimeRow] is, without its padding.
const double weatherTimeRowHeight = 36;

/// The key of the time control's label, for the tests.
const Key weatherTimeLabelKey = ValueKey<String>('weather-time-label');

class _WeatherTimeRowState extends ConsumerState<WeatherTimeRow> {
  /// The slider's step while a finger moves it.
  int? _dragging;

  @override
  Widget build(BuildContext context) {
    if (!weatherRainOn(ref)) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sources = ref.watch(weatherMapSourcesProvider);
    final status = ref.watch(sharedWeatherMapStatusProvider);
    final committed = ref.watch(weatherRadarOffsetProvider);
    final offset = _dragging ?? committed;
    final label = weatherRainLabel(
      context,
      offset,
      weatherRainAt(sources, status, offset),
    );
    return Padding(
      padding: widget.padding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The label's room is fixed, so the slider keeps its length, and
          // its steps their places, while the label changes under the
          // finger; a long label is scaled down to fit.
          final labelWidth = math.min(constraints.maxWidth * 0.5, 210.0);
          return Row(
            children: [
              Icon(
                Icons.water_drop_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: labelWidth,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      label,
                      key: weatherTimeLabelKey,
                      maxLines: 1,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 14,
                    ),
                  ),
                  child: SizedBox(
                    height: weatherTimeRowHeight,
                    child: Semantics(
                      label: l10n.mapWeatherRadarTime,
                      child: Slider(
                        value: weatherSliderIndexOf(offset).toDouble(),
                        max: (weatherRadarOffsets.length - 1).toDouble(),
                        divisions: weatherRadarOffsets.length - 1,
                        semanticFormatterCallback: (_) => label,
                        onChanged: (value) => setState(
                          () => _dragging = weatherOffsetOfSliderIndex(
                            value.round(),
                          ),
                        ),
                        onChangeEnd: (value) {
                          setState(() => _dragging = null);
                          ref
                              .read(weatherRadarOffsetProvider.notifier)
                              .set(weatherOffsetOfSliderIndex(value.round()));
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The weather's short lines over the map: the clouds' time while they are
/// on, and that a layer is unavailable where its service did not answer,
/// which would otherwise look like a dry, clear day. With [rainTime], also
/// the rain's moment, for the Library tab, which has no time control.
/// Nothing when there is nothing to say.
class WeatherMapHints extends ConsumerWidget {
  /// Creates the hints, with [padding] around them while there are any.
  const WeatherMapHints({
    super.key,
    this.rainTime = false,
    this.padding = EdgeInsets.zero,
  });

  final bool rainTime;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(weatherMapPreferencesProvider);
    final sources = ref.watch(weatherMapSourcesProvider);
    final rain = weatherRainOn(ref);
    final clouds =
        settings.clouds && weatherKindAvailable(sources, WeatherKind.clouds);
    if (!rain && !clouds) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final status = ref.watch(sharedWeatherMapStatusProvider);
    final cloudsFrame = clouds ? status.cloudsFrame : null;
    final chips = <Widget>[
      if (rain && rainTime) _rainChip(context, ref, sources, status),
      if (cloudsFrame != null)
        WeatherMapChip(
          text: l10n.mapWeatherCloudsAt(weatherClockTime(context, cloudsFrame)),
          icon: Icons.cloud_outlined,
        ),
      if (rain)
        for (final role in RainRole.values)
          if (status.failedRain.contains(role))
            WeatherMapChip(
              text: switch (role) {
                RainRole.radar => l10n.mapWeatherRadarUnavailable,
                RainRole.satellite => l10n.mapWeatherSatelliteUnavailable,
                RainRole.model => l10n.mapWeatherForecastUnavailable,
              },
              icon: Icons.cloud_off_outlined,
              warning: true,
            ),
      if (clouds && status.failed.contains(WeatherKind.clouds))
        WeatherMapChip(
          text: l10n.mapWeatherCloudsUnavailable,
          icon: Icons.cloud_off_outlined,
          warning: true,
        ),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, chip) in chips.indexed) ...[
            if (i > 0) const SizedBox(height: 6),
            chip,
          ],
        ],
      ),
    );
  }

  Widget _rainChip(
    BuildContext context,
    WidgetRef ref,
    List<WeatherMapSource> sources,
    WeatherMapStatus status,
  ) {
    final l10n = AppLocalizations.of(context);
    final offset = ref.watch(weatherRadarOffsetProvider);
    final rain = weatherRainAt(sources, status, offset);
    return WeatherMapChip(
      key: const ValueKey<String>('weather-rain-chip'),
      text: <String>[
        l10n.mapLayersRainRadar,
        if (offset > 0) weatherStepText(l10n, offset),
        if (rain != null) weatherClockTime(context, rain.time),
        if (rain != null && offset > 0) ?weatherSourceTag(l10n, rain.role),
      ].join(' · '),
      icon: Icons.water_drop_outlined,
    );
  }
}

/// A short glass line over the map: the clouds' or the rain's time, or
/// that a layer is unavailable.
class WeatherMapChip extends StatelessWidget {
  /// Creates the chip.
  const WeatherMapChip({
    required this.text,
    required this.icon,
    this.warning = false,
    super.key,
  });

  final String text;
  final IconData icon;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassPanel(
      radius: 18,
      padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: warning
                ? theme.colorScheme.error
                : theme.colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
