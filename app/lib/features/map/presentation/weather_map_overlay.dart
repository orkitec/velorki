import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../shared/presentation/stat_tile.dart';
import '../application/weather_map_binding.dart';
import '../application/weather_map_driver.dart';
import '../data/weather_map_preferences.dart';
import '../domain/weather_map.dart';

/// How wide the radar's time control is.
const double weatherTimeControlWidth = 240;

/// What the time control calls [offsetMinutes] from now: "Now", "−45 min",
/// "+30 min".
String weatherOffsetLabel(AppLocalizations l10n, int offsetMinutes) =>
    offsetMinutes == 0
    ? l10n.mapWeatherNow
    : offsetMinutes < 0
    ? l10n.mapWeatherMinutesAgo(-offsetMinutes)
    : l10n.mapWeatherMinutesAhead(offsetMinutes);

/// [utc] in the phone's own clock format, local time.
String weatherClockTime(BuildContext context, DateTime utc) =>
    MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(utc.toLocal()),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );

/// What the weather layers put over the shell's map: the radar's time
/// control while the radar is on, the clouds' time while only they are,
/// and a short hint for a layer whose service did not answer, which would
/// otherwise look like a dry, clear day. Nothing while both are off.
class WeatherMapOverlay extends ConsumerStatefulWidget {
  /// Creates the overlay.
  const WeatherMapOverlay({
    super.key,
    this.alignment = CrossAxisAlignment.end,
    this.top = 8,
  });

  /// Which side its pieces line up on: the control column's.
  final CrossAxisAlignment alignment;

  /// The gap above it: under the controls a little, beside them none.
  final double top;

  @override
  ConsumerState<WeatherMapOverlay> createState() => _WeatherMapOverlayState();
}

class _WeatherMapOverlayState extends ConsumerState<WeatherMapOverlay> {
  /// The slider's position while a finger moves it; the layers follow when
  /// it is let go.
  int? _dragging;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(weatherMapPreferencesProvider);
    final sources = ref.watch(weatherMapSourcesProvider);
    final radar =
        settings.radar && weatherKindAvailable(sources, WeatherKind.radar);
    final clouds =
        settings.clouds && weatherKindAvailable(sources, WeatherKind.clouds);
    if (!radar && !clouds) return const SizedBox.shrink();
    final status = ref.watch(sharedWeatherMapStatusProvider);
    final offset = ref.watch(weatherRadarOffsetProvider);
    final l10n = AppLocalizations.of(context);
    final cloudsFrame = clouds ? status.cloudsFrame : null;
    final cloudsCaption = cloudsFrame == null
        ? null
        : l10n.mapWeatherCloudsAt(weatherClockTime(context, cloudsFrame));
    final children = <Widget>[
      if (radar)
        _TimeControl(
          offset: _dragging ?? offset,
          status: status,
          committedOffset: offset,
          cloudsCaption: cloudsCaption,
          onChanged: (value) => setState(() => _dragging = value),
          onChangeEnd: (value) {
            setState(() => _dragging = null);
            ref.read(weatherRadarOffsetProvider.notifier).set(value);
          },
        )
      else if (cloudsCaption != null)
        _Chip(text: cloudsCaption, icon: Icons.cloud_outlined),
      if (radar && status.failed.contains(WeatherKind.radar))
        _Chip(
          text: l10n.mapWeatherRadarUnavailable,
          icon: Icons.cloud_off_outlined,
          warning: true,
        ),
      if (clouds && status.failed.contains(WeatherKind.clouds))
        _Chip(
          text: l10n.mapWeatherCloudsUnavailable,
          icon: Icons.cloud_off_outlined,
          warning: true,
        ),
    ];
    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: widget.top),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: weatherTimeControlWidth),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: widget.alignment,
          children: [
            for (final (i, child) in children.indexed) ...[
              if (i > 0) const SizedBox(height: 6),
              child,
            ],
          ],
        ),
      ),
    );
  }
}

/// The radar's slider from two hours back to two ahead, with the moment it
/// shows: "Now · 14:35", "−45 min · 13:50".
class _TimeControl extends StatelessWidget {
  const _TimeControl({
    required this.offset,
    required this.committedOffset,
    required this.status,
    required this.cloudsCaption,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final int offset;
  final int committedOffset;
  final WeatherMapStatus status;
  final String? cloudsCaption;
  final ValueChanged<int> onChanged;
  final ValueChanged<int> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // The frame on the map is at the committed offset; the one under the
    // finger is as far from it as the finger moved.
    final frame = status.radarFrame?.add(
      Duration(minutes: offset - committedOffset),
    );
    final label = <String>[
      weatherOffsetLabel(l10n, offset),
      if (frame != null) weatherClockTime(context, frame),
    ].join(' · ');
    final small = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return GlassPanel(
      radius: 20,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.water_drop_outlined,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  key: const ValueKey<String>('weather-time-label'),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: SizedBox(
              height: 32,
              child: Slider(
                value: weatherSliderIndexOf(offset).toDouble(),
                max: (weatherRadarOffsets.length - 1).toDouble(),
                divisions: weatherRadarOffsets.length - 1,
                semanticFormatterCallback: (_) => label,
                label: null,
                onChanged: (value) =>
                    onChanged(weatherOffsetOfSliderIndex(value.round())),
                onChangeEnd: (value) =>
                    onChangeEnd(weatherOffsetOfSliderIndex(value.round())),
              ),
            ),
          ),
          if (status.forecastElsewhere)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(l10n.mapWeatherForecastGermanyOnly, style: small),
            ),
          if (cloudsCaption != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(cloudsCaption!, style: small),
            ),
        ],
      ),
    );
  }
}

/// A short line over the map: the clouds' time, or that a layer is
/// unavailable.
class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.icon, this.warning = false});

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
