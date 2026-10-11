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

/// The rain's time control, for the Plan and Record sheets while the rain
/// is on, nothing while it is off: the drop, the label and the slider in
/// one line, the label as wide as the widest it can get
/// ([weatherTimeLabelWidth]) and the slider in all the room that is left;
/// where that would leave the slider less than [weatherSliderMinShare] of
/// the row, the label on a small line of its own over a slider as wide as
/// the row ([weatherTimeRowStacks]). The step is the one all tabs share
/// ([weatherRadarOffsetProvider]); the map follows when the slider is let
/// go.
class WeatherTimeRow extends ConsumerStatefulWidget {
  /// Creates the row, with [padding] around it while it shows.
  const WeatherTimeRow({super.key, this.padding = EdgeInsets.zero});

  final EdgeInsetsGeometry padding;

  @override
  ConsumerState<WeatherTimeRow> createState() => _WeatherTimeRowState();
}

/// How tall [WeatherTimeRow] is in one line, without its padding.
const double weatherTimeRowHeight = 36;

/// How tall the label's own line is when the row stacks.
const double weatherTimeLabelLineHeight = 18;

/// How tall [WeatherTimeRow] is stacked, the label over the slider.
const double weatherTimeRowStackedHeight =
    weatherTimeLabelLineHeight + weatherTimeRowHeight;

/// The least share of the row the slider gets beside the label; with less
/// the row stacks.
const double weatherSliderMinShare = 0.55;

/// The drop and the room after it, before the label.
const double _weatherTimeLead = 18 + 8;

/// The key of the time control's label, for the tests.
const Key weatherTimeLabelKey = ValueKey<String>('weather-time-label');

/// The style of the time control's label in one line.
TextStyle? weatherTimeLabelStyle(ThemeData theme) =>
    theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurface);

/// The widest the time control's label can get here, so the slider keeps
/// its length, and its steps their places, while the label changes under
/// the finger: of every step, the label with the frame over the view's
/// middle now and each tag a moment ahead can carry, measured at the
/// label's style and the phone's text scale. Measured again only when one
/// of those changes.
double weatherTimeLabelWidth(
  BuildContext context,
  List<WeatherMapSource> sources,
  WeatherMapStatus status,
) {
  final l10n = AppLocalizations.of(context);
  final labels = <String>{};
  for (final offset in weatherRadarOffsets) {
    final rain = weatherRainAt(sources, status, offset);
    final parts = <String>[
      weatherStepText(l10n, offset),
      if (rain != null) weatherClockTime(context, rain.time),
    ];
    labels.add(parts.join(' · '));
    if (rain == null || offset <= 0) continue;
    for (final role in RainRole.values) {
      final tag = weatherSourceTag(l10n, role);
      if (tag != null) labels.add(<String>[...parts, tag].join(' · '));
    }
  }
  final style = weatherTimeLabelStyle(Theme.of(context));
  final scaler = MediaQuery.textScalerOf(context);
  final direction = Directionality.of(context);
  final key = Object.hash(Object.hashAll(labels), style, scaler, direction);
  final cached = _labelWidths[key];
  if (cached != null) return cached;
  var widest = 0.0;
  for (final label in labels) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: direction,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    widest = math.max(widest, painter.width);
    painter.dispose();
  }
  if (_labelWidths.length >= 8) _labelWidths.remove(_labelWidths.keys.first);
  return _labelWidths[key] = widest.ceilToDouble() + 1;
}

/// The last few widths [weatherTimeLabelWidth] measured.
final Map<int, double> _labelWidths = <int, double>{};

/// Whether a time control [rowWidth] wide puts its label on a line of its
/// own: beside a label [labelWidth] wide the slider would get less than
/// [weatherSliderMinShare] of the row.
bool weatherTimeRowStacks(double rowWidth, double labelWidth) =>
    rowWidth - _weatherTimeLead - labelWidth < rowWidth * weatherSliderMinShare;

/// How tall [WeatherTimeRow] is [rowWidth] wide, without its padding: 0
/// while the rain is off.
double weatherTimeRowHeightFor(
  BuildContext context,
  WidgetRef ref,
  double rowWidth,
) {
  if (!weatherRainOn(ref)) return 0;
  final width = weatherTimeLabelWidth(
    context,
    ref.watch(weatherMapSourcesProvider),
    ref.watch(sharedWeatherMapStatusProvider),
  );
  return weatherTimeRowStacks(rowWidth, width)
      ? weatherTimeRowStackedHeight
      : weatherTimeRowHeight;
}

class _WeatherTimeRowState extends ConsumerState<WeatherTimeRow> {
  /// The slider's step while a finger moves it.
  int? _dragging;

  @override
  Widget build(BuildContext context) {
    if (!weatherRainOn(ref)) return const SizedBox.shrink();
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
    final labelWidth = weatherTimeLabelWidth(context, sources, status);
    final drop = Icon(
      Icons.water_drop_outlined,
      size: 18,
      color: theme.colorScheme.primary,
    );
    // A label longer than measured (another font) is scaled down to fit.
    Widget text(TextStyle? style) => FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Text(label, key: weatherTimeLabelKey, maxLines: 1, style: style),
    );
    return Padding(
      padding: widget.padding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final slider = _slider(context, offset, label);
          if (weatherTimeRowStacks(constraints.maxWidth, labelWidth)) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: weatherTimeLabelLineHeight,
                  child: Row(
                    children: [
                      drop,
                      const SizedBox(width: 8),
                      Expanded(
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: text(
                            theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                slider,
              ],
            );
          }
          return Row(
            children: [
              drop,
              const SizedBox(width: 8),
              SizedBox(
                width: labelWidth,
                height: weatherTimeRowHeight,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: text(weatherTimeLabelStyle(theme)),
                ),
              ),
              Expanded(child: slider),
            ],
          );
        },
      ),
    );
  }

  Widget _slider(BuildContext context, int offset, String label) {
    final l10n = AppLocalizations.of(context);
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
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
              () => _dragging = weatherOffsetOfSliderIndex(value.round()),
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
