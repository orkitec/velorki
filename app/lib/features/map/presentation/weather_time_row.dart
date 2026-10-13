import 'dart:async';
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
/// "+45 min", "+2 h"; as a planned route's departure ([leave]), "Leave
/// now", "Leave +45 min", "Leave +2 h".
String weatherStepText(
  AppLocalizations l10n,
  int offsetMinutes, {
  bool leave = false,
}) {
  if (offsetMinutes <= 0) {
    return leave ? l10n.mapWeatherLeaveNow : l10n.mapWeatherNow;
  }
  final step = offsetMinutes % 60 == 0
      ? l10n.mapWeatherHoursAhead(offsetMinutes ~/ 60)
      : l10n.mapWeatherMinutesAhead(offsetMinutes);
  return leave ? l10n.mapWeatherLeaveAhead(step) : step;
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
    newest: status.newest,
    missing: status.missing,
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
/// "+45 min · 21:30 · Nowcast", "+3 h · 23:00 · Forecast"; and "Now · 20:00
/// · Forecast" where the model stands in for the satellite. As a planned
/// route's departure ([leave]) the step says so: "Leave now · 20:25".
String weatherRainLabel(
  BuildContext context,
  int offsetMinutes,
  ({RainRole role, DateTime time})? rain, {
  bool leave = false,
}) {
  final l10n = AppLocalizations.of(context);
  return <String>[
    weatherStepText(l10n, offsetMinutes, leave: leave),
    if (rain != null) weatherClockTime(context, rain.time),
    if (rain != null && _tagged(offsetMinutes, rain.role))
      ?weatherSourceTag(l10n, rain.role),
  ].join(' · ');
}

/// Whether the rain's label says what it shows: ahead, and at "Now" where
/// a model stands in for the satellite.
bool _tagged(int offsetMinutes, RainRole role) =>
    offsetMinutes > 0 || role == RainRole.model;

/// Whether the rain is on and some source of it in use.
bool weatherRainOn(WidgetRef ref) =>
    ref.watch(weatherMapPreferencesProvider).radar &&
    weatherKindAvailable(
      ref.watch(weatherMapSourcesProvider),
      WeatherKind.radar,
    );

/// Whether the wind is on and some source of it in use.
bool weatherWindOn(WidgetRef ref) =>
    ref.watch(weatherMapPreferencesProvider).wind &&
    weatherKindAvailable(
      ref.watch(weatherMapSourcesProvider),
      WeatherKind.wind,
    );

/// Whether the rain or the wind is on: whether the sheets show
/// [WeatherTimeRow], which both follow.
bool weatherTimeOn(WidgetRef ref) => weatherRainOn(ref) || weatherWindOn(ref);

/// The hour the wind shows at [offsetMinutes], by the sources in force and
/// the map's [status]; `null` without a wind source.
DateTime? weatherWindAt(
  List<WeatherMapSource> sources,
  WeatherMapStatus status,
  int offsetMinutes,
) {
  final source = sources
      .where((s) => s.enabled && s.kind == WeatherKind.wind)
      .firstOrNull;
  return source
      ?.frameAt(status.at ?? DateTime.now(), offsetMinutes: offsetMinutes)
      ?.time;
}

/// The time control's label with the wind alone on: the step, the hour
/// the wind shows and, ahead, that it is a forecast. "Now · 20:00",
/// "+3 h · 23:00 · Forecast"; as a planned route's departure ([leave]),
/// "Leave +3 h · 23:00 · Forecast".
String weatherWindLabel(
  BuildContext context,
  int offsetMinutes,
  DateTime? wind, {
  bool leave = false,
}) {
  final l10n = AppLocalizations.of(context);
  return <String>[
    weatherStepText(l10n, offsetMinutes, leave: leave),
    if (wind != null) weatherClockTime(context, wind),
    if (wind != null && offsetMinutes > 0) l10n.mapWeatherForecast,
  ].join(' · ');
}

/// The time control's label with the map's rain and wind off, shown as a
/// planned route's departure: the step and the moment it stands for, [now]
/// plus the step. "Leave now · 20:27", "Leave +45 min · 21:12".
String weatherDepartureLabel(
  BuildContext context,
  int offsetMinutes,
  DateTime now,
) => <String>[
  weatherStepText(AppLocalizations.of(context), offsetMinutes, leave: true),
  weatherClockTime(context, now.add(Duration(minutes: offsetMinutes))),
].join(' · ');

/// The rain's and the wind's time control, for the Plan and Record sheets
/// while either is on, nothing while both are off (with the rain off, its
/// label tells the wind's hour). On the Plan tab with a route it is also
/// the route's departure ([leave]: "Leave now", "Leave +45 min"), which the
/// route's forecast follows, and shown ([shown]) while the route's weather
/// is, the map's rain and wind on or not (then its label tells the
/// departure's time, [weatherDepartureLabel]). The drop, the label and the slider in
/// one line, the label as wide as the widest it can get
/// ([weatherTimeLabelWidth]) and the slider in all the room that is left;
/// where that would leave the slider less than [weatherSliderMinShare] of
/// the row, the label on a small line of its own over a slider as wide as
/// the row ([weatherTimeRowStacks]). The step is the one all tabs share
/// ([weatherRadarOffsetProvider]), set when the slider is let go; while it
/// is dragged the map shows the step under the finger where it is loaded,
/// else the nearest one that is ([weatherRadarPreviewProvider]), and the
/// label says which.
///
/// While what the map shows for the step set is still being fetched
/// ([WeatherMapStatus.loading]), or the route's forecast the caller says
/// is ([forecastLoading]), a small spinner stands in the drop's place,
/// once that has taken [weatherLoadingDelay]: a quick answer shows none.
class WeatherTimeRow extends ConsumerStatefulWidget {
  /// Creates the row, with [padding] around it while it shows.
  const WeatherTimeRow({
    super.key,
    this.padding = EdgeInsets.zero,
    this.leave = false,
    this.shown = false,
    this.forecastLoading = false,
  });

  final EdgeInsetsGeometry padding;

  /// Whether the control is a planned route's departure: its steps read
  /// "Leave now", "Leave +45 min".
  final bool leave;

  /// Whether it shows while the map's rain and wind are off.
  final bool shown;

  /// Whether the forecast the route is coloured by is being fetched.
  final bool forecastLoading;

  @override
  ConsumerState<WeatherTimeRow> createState() => _WeatherTimeRowState();
}

/// How long something is fetched before [WeatherTimeRow] shows its
/// spinner.
const Duration weatherLoadingDelay = Duration(milliseconds: 250);

/// The key of the time control's spinner, for the tests.
const Key weatherTimeLoadingKey = ValueKey<String>('weather-time-loading');

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
/// of those changes. [leave] measures the departure's steps; [departure]
/// the labels with the map's rain and wind off ([weatherDepartureLabel]).
double weatherTimeLabelWidth(
  BuildContext context,
  List<WeatherMapSource> sources,
  WeatherMapStatus status, {
  bool wind = false,
  bool leave = false,
  bool departure = false,
}) {
  final l10n = AppLocalizations.of(context);
  final labels = <String>{};
  for (final offset in weatherRadarOffsets) {
    if (departure) {
      labels.add(
        weatherDepartureLabel(context, offset, status.at ?? DateTime.now()),
      );
      continue;
    }
    if (wind) {
      labels.add(
        weatherWindLabel(
          context,
          offset,
          weatherWindAt(sources, status, offset),
          leave: leave,
        ),
      );
    }
    final rain = weatherRainAt(sources, status, offset);
    final parts = <String>[
      weatherStepText(l10n, offset, leave: leave),
      if (rain != null) weatherClockTime(context, rain.time),
    ];
    labels.add(parts.join(' · '));
    if (rain == null) continue;
    for (final role in RainRole.values) {
      // "Now" may say it is the model's, so it is measured with that too.
      if (!_tagged(offset, role)) continue;
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
/// while the rain and the wind are off.
double weatherTimeRowHeightFor(
  BuildContext context,
  WidgetRef ref,
  double rowWidth,
) {
  if (!weatherTimeOn(ref)) return 0;
  final width = weatherTimeLabelWidth(
    context,
    ref.watch(weatherMapSourcesProvider),
    ref.watch(sharedWeatherMapStatusProvider),
    wind: !weatherRainOn(ref),
  );
  return weatherTimeRowStacks(rowWidth, width)
      ? weatherTimeRowStackedHeight
      : weatherTimeRowHeight;
}

class _WeatherTimeRowState extends ConsumerState<WeatherTimeRow> {
  /// The slider's step while a finger moves it.
  int? _dragging;

  /// Whether the spinner shows, and the wait before it does.
  bool _spinning = false;
  Timer? _spinAfter;

  /// Follows whether something is being fetched: the spinner after
  /// [weatherLoadingDelay], gone at once when it is in. Called from
  /// `build`, which shows what it leaves.
  void _follow(bool loading) {
    if (!loading) {
      _spinAfter?.cancel();
      _spinAfter = null;
      _spinning = false;
      return;
    }
    if (_spinning || _spinAfter != null) return;
    _spinAfter = Timer(weatherLoadingDelay, () {
      _spinAfter = null;
      if (mounted) setState(() => _spinning = true);
    });
  }

  @override
  void dispose() {
    _spinAfter?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layers = weatherTimeOn(ref);
    if (!layers && !widget.shown) {
      _follow(false);
      return const SizedBox.shrink();
    }
    final leave = widget.leave;
    final theme = Theme.of(context);
    final sources = ref.watch(weatherMapSourcesProvider);
    final status = ref.watch(sharedWeatherMapStatusProvider);
    final committed = ref.watch(weatherRadarOffsetProvider);
    final dragging = _dragging;
    // The slider under the finger; the label the step the map shows, which
    // while dragging is the nearest one loaded (with no layer on, the one
    // under the finger).
    final offset = dragging ?? committed;
    final labelOffset = dragging == null
        ? committed
        : layers
        ? status.shownOffset ?? dragging
        : dragging;
    // As a route's departure the label tells the departure's clock time,
    // which the rider plans by (the rain's own moment is in the Layers
    // sheet); otherwise the rain's moment with the rain on, else the wind's.
    final rainOn = weatherRainOn(ref);
    final label = !layers || leave
        ? weatherDepartureLabel(
            context,
            labelOffset,
            status.at ?? DateTime.now(),
          )
        : rainOn
        ? weatherRainLabel(
            context,
            labelOffset,
            weatherRainAt(sources, status, labelOffset),
            leave: leave,
          )
        : weatherWindLabel(
            context,
            labelOffset,
            weatherWindAt(sources, status, labelOffset),
            leave: leave,
          );
    final labelWidth = weatherTimeLabelWidth(
      context,
      sources,
      status,
      wind: !rainOn,
      leave: leave,
      departure: !layers || leave,
    );
    _follow((layers && status.loading) || widget.forecastLoading);
    // The spinner in the drop's place, as large, so nothing moves.
    final drop = SizedBox.square(
      dimension: 18,
      child: _spinning
          ? Padding(
              padding: const EdgeInsets.all(2),
              child: CircularProgressIndicator(
                key: weatherTimeLoadingKey,
                strokeWidth: 2,
                color: theme.colorScheme.primary,
                semanticsLabel: AppLocalizations.of(context).mapWeatherLoading,
              ),
            )
          : Icon(
              !layers
                  ? Icons.schedule
                  : rainOn
                  ? Icons.water_drop_outlined
                  : Icons.air,
              size: 18,
              color: theme.colorScheme.primary,
            ),
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
          final slider = _slider(
            context,
            offset,
            label,
            semantics: leave
                ? AppLocalizations.of(context).mapWeatherDepartureTime
                : rainOn
                ? AppLocalizations.of(context).mapWeatherRadarTime
                : AppLocalizations.of(context).mapWeatherWindTime,
          );
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

  Widget _slider(
    BuildContext context,
    int offset,
    String label, {
    required String semantics,
  }) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
      ),
      child: SizedBox(
        height: weatherTimeRowHeight,
        child: Semantics(
          label: semantics,
          child: Slider(
            value: weatherSliderIndexOf(offset).toDouble(),
            max: (weatherRadarOffsets.length - 1).toDouble(),
            divisions: weatherRadarOffsets.length - 1,
            semanticFormatterCallback: (_) => label,
            onChanged: (value) {
              final step = weatherOffsetOfSliderIndex(value.round());
              setState(() => _dragging = step);
              ref.read(weatherRadarPreviewProvider.notifier).set(step);
            },
            onChangeEnd: (value) {
              setState(() => _dragging = null);
              ref
                  .read(weatherRadarOffsetProvider.notifier)
                  .set(weatherOffsetOfSliderIndex(value.round()));
              ref.read(weatherRadarPreviewProvider.notifier).set(null);
            },
          ),
        ),
      ),
    );
  }
}

/// The weather's short lines over the map: that a layer (the rain, the
/// clouds, the wind) is unavailable where its service did not answer, which
/// would otherwise look like a dry, clear day. Nothing when there is nothing
/// to say. (The rain's and the clouds' moments are in the Layers sheet.)
class WeatherMapHints extends ConsumerWidget {
  /// Creates the hints, with [padding] around them while there are any.
  const WeatherMapHints({super.key, this.padding = EdgeInsets.zero});

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(weatherMapPreferencesProvider);
    final sources = ref.watch(weatherMapSourcesProvider);
    final rain = weatherRainOn(ref);
    final wind = weatherWindOn(ref);
    final clouds =
        settings.clouds && weatherKindAvailable(sources, WeatherKind.clouds);
    if (!rain && !clouds && !wind) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final status = ref.watch(sharedWeatherMapStatusProvider);
    final chips = <Widget>[
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
      if (wind && status.failed.contains(WeatherKind.wind))
        WeatherMapChip(
          text: l10n.mapWeatherWindUnavailable,
          icon: Icons.air,
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
}

/// A short glass line over the map: that a layer is unavailable.
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
