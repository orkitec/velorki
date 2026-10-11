import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../domain/route_weather.dart';

/// The left inset of the strip's plot: the elevation chart's
/// `MetricChart.leftReservedSize`, so a stretch of the strip sits under the
/// same stretch of the profile.
const double weatherStripLeftInset = 40;

/// The right inset: the elevation chart has no right axis.
const double weatherStripRightInset = 0;

/// The height of the strip.
const double weatherStripHeight = 96;

/// Rain this heavy, in mm/h, fills a rain bar.
const double weatherStripFullRainMm = 4;

/// The narrowest gap between two wind arrows, in logical pixels.
const double _arrowSpacingPx = 14;

/// The weather along the route over distance, under the elevation profile
/// and on its x-axis: the wind at each sample as an arrow pointing where it
/// blows (up is north) in the colour of how it meets the rider, the rain as
/// bars, and the temperature as a line with its lowest and highest values.
/// A sample without weather leaves a gap.
///
/// Without [weather] it draws the empty rows, the placeholder of the same
/// size while the forecast is on its way.
class RouteWeatherStrip extends StatelessWidget {
  /// Creates the strip.
  const RouteWeatherStrip({
    required this.weather,
    required this.semanticsLabel,
    this.maxTempLabel,
    this.minTempLabel,
    super.key,
  });

  /// The weather to draw; `null` for the placeholder.
  final RouteWeather? weather;

  /// What a screen reader says for the strip.
  final String semanticsLabel;

  /// The highest temperature, written beside the top of the line.
  final String? maxTempLabel;

  /// The lowest temperature, written beside the bottom of the line.
  final String? minTempLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.velorki;
    return Semantics(
      container: true,
      label: semanticsLabel,
      child: SizedBox(
        height: weatherStripHeight,
        width: double.infinity,
        child: CustomPaint(
          painter: RouteWeatherStripPainter(
            weather: weather,
            colors: RouteWeatherStripColors(
              head: colors.windHead,
              cross: colors.windCross,
              tail: colors.windTail,
              calm: colors.windCalm,
              rain: colors.rain,
              temperature: colors.temperature,
              baseline: theme.colorScheme.outlineVariant,
              label: theme.colorScheme.onSurfaceVariant,
            ),
            labelStyle: (theme.textTheme.labelSmall ?? const TextStyle())
                .copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 10,
                  height: 1,
                ),
            maxTempLabel: maxTempLabel,
            minTempLabel: minTempLabel,
            textDirection: Directionality.of(context),
          ),
        ),
      ),
    );
  }
}

/// The colours [RouteWeatherStripPainter] draws with, from the theme.
@immutable
class RouteWeatherStripColors {
  /// Creates the colours.
  const RouteWeatherStripColors({
    required this.head,
    required this.cross,
    required this.tail,
    required this.calm,
    required this.rain,
    required this.temperature,
    required this.baseline,
    required this.label,
  });

  final Color head;
  final Color cross;
  final Color tail;
  final Color calm;
  final Color rain;
  final Color temperature;

  /// The faint line each row stands on.
  final Color baseline;

  /// The icons and figures in the left inset.
  final Color label;

  /// The colour of [windClass].
  Color wind(WindClass windClass) => switch (windClass) {
    WindClass.headwind => head,
    WindClass.crosswind => cross,
    WindClass.tailwind => tail,
    WindClass.calm => calm,
  };

  @override
  bool operator ==(Object other) =>
      other is RouteWeatherStripColors &&
      other.head == head &&
      other.cross == cross &&
      other.tail == tail &&
      other.calm == calm &&
      other.rain == rain &&
      other.temperature == temperature &&
      other.baseline == baseline &&
      other.label == label;

  @override
  int get hashCode =>
      Object.hash(head, cross, tail, calm, rain, temperature, baseline, label);
}

/// Paints [RouteWeatherStrip].
class RouteWeatherStripPainter extends CustomPainter {
  /// Creates the painter.
  RouteWeatherStripPainter({
    required this.weather,
    required this.colors,
    required this.labelStyle,
    required this.textDirection,
    this.maxTempLabel,
    this.minTempLabel,
  });

  final RouteWeather? weather;
  final RouteWeatherStripColors colors;
  final TextStyle labelStyle;
  final TextDirection textDirection;
  final String? maxTempLabel;
  final String? minTempLabel;

  // The three rows, top to bottom.
  static const double _windTop = 0;
  static const double _windHeight = 22;
  static const double _rainTop = 28;
  static const double _rainHeight = 24;
  static const double _tempTop = 58;
  static const double _tempHeight = 34;

  @override
  void paint(Canvas canvas, Size size) {
    final left = weatherStripLeftInset;
    final right = size.width - weatherStripRightInset;
    if (right - left <= 0) return;

    _paintGutter(canvas);
    final baseline = Paint()
      ..color = colors.baseline
      ..strokeWidth = 1;
    for (final y in <double>[
      _windTop + _windHeight / 2,
      _rainTop + _rainHeight,
      _tempTop + _tempHeight,
    ]) {
      canvas.drawLine(Offset(left, y), Offset(right, y), baseline);
    }

    final w = weather;
    if (w == null || w.samples.isEmpty) return;
    final total = w.samples.last.distanceM;
    double xOf(double d) =>
        total > 0 ? left + (d / total) * (right - left) : left;

    _paintRain(canvas, w, xOf, left, right);
    _paintTemperature(canvas, w, xOf);
    _paintWind(canvas, w, xOf);
  }

  void _paintGutter(Canvas canvas) {
    _icon(canvas, Icons.air, _windTop + _windHeight / 2);
    _icon(canvas, Icons.water_drop_outlined, _rainTop + _rainHeight / 2);
    final max = maxTempLabel;
    final min = minTempLabel;
    if (max != null) _text(canvas, max, _tempTop, top: true);
    if (min != null && min != max) {
      _text(canvas, min, _tempTop + _tempHeight, top: false);
    }
  }

  void _icon(Canvas canvas, IconData icon, double centerY) {
    const size = 14.0;
    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: size,
          height: 1,
          color: colors.label,
        ),
      ),
      textDirection: textDirection,
    )..layout();
    painter.paint(
      canvas,
      Offset(
        weatherStripLeftInset - 8 - painter.width,
        centerY - painter.height / 2,
      ),
    );
  }

  /// [text] right-aligned against the plot, its top at [y] or its bottom.
  void _text(Canvas canvas, String text, double y, {required bool top}) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: labelStyle),
      textDirection: textDirection,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: weatherStripLeftInset - 4);
    painter.paint(
      canvas,
      Offset(
        weatherStripLeftInset - 4 - painter.width,
        top ? y : y - painter.height,
      ),
    );
  }

  void _paintRain(
    Canvas canvas,
    RouteWeather w,
    double Function(double) xOf,
    double left,
    double right,
  ) {
    final samples = w.samples;
    final bottom = _rainTop + _rainHeight;
    for (var i = 0; i < samples.length; i++) {
      final s = i < w.weather.length ? w.weather[i] : null;
      if (s == null || s.precipMm <= 0) continue;
      final x0 = i == 0
          ? left
          : xOf((samples[i - 1].distanceM + samples[i].distanceM) / 2);
      final x1 = i == samples.length - 1
          ? right
          : xOf((samples[i].distanceM + samples[i + 1].distanceM) / 2);
      final share = (s.precipMm / weatherStripFullRainMm).clamp(0.0, 1.0);
      final height = math.max(2.0, share * _rainHeight);
      final prob = s.precipProb;
      final opacity = prob == null
          ? 1.0
          : (0.25 + 0.75 * (prob / 100)).clamp(0.25, 1.0);
      canvas.drawRect(
        Rect.fromLTRB(x0, bottom - height, math.max(x1, x0 + 1), bottom),
        Paint()..color = colors.rain.withValues(alpha: opacity),
      );
    }
  }

  void _paintTemperature(
    Canvas canvas,
    RouteWeather w,
    double Function(double) xOf,
  ) {
    double? lo;
    double? hi;
    for (final s in w.weather) {
      if (s == null) continue;
      lo = lo == null ? s.temp : math.min(lo, s.temp);
      hi = hi == null ? s.temp : math.max(hi, s.temp);
    }
    if (lo == null || hi == null) return;
    const pad = 3.0;
    final top = _tempTop + pad;
    final bottom = _tempTop + _tempHeight - pad;
    double yOf(double t) => hi! - lo! < 1e-6
        ? (top + bottom) / 2
        : bottom - (t - lo) / (hi - lo) * (bottom - top);

    final path = Path();
    final dots = <Offset>[];
    var open = false;
    for (var i = 0; i < w.samples.length; i++) {
      final s = i < w.weather.length ? w.weather[i] : null;
      if (s == null) {
        open = false;
        continue;
      }
      final p = Offset(xOf(w.samples[i].distanceM), yOf(s.temp));
      final nextHas =
          i + 1 < w.samples.length &&
          i + 1 < w.weather.length &&
          w.weather[i + 1] != null;
      if (!open) {
        path.moveTo(p.dx, p.dy);
        open = true;
        // A lone sample between two gaps is a dot, not a line.
        if (!nextHas) dots.add(p);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    final stroke = Paint()
      ..color = colors.temperature
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, stroke);
    final fill = Paint()..color = colors.temperature;
    for (final d in dots) {
      canvas.drawCircle(d, 1.5, fill);
    }
  }

  void _paintWind(Canvas canvas, RouteWeather w, double Function(double) xOf) {
    final centerY = _windTop + _windHeight / 2;
    double? lastX;
    for (var i = 0; i < w.samples.length; i++) {
      final s = i < w.weather.length ? w.weather[i] : null;
      if (s == null) continue;
      final x = xOf(w.samples[i].distanceM);
      if (lastX != null && x - lastX < _arrowSpacingPx) continue;
      lastX = x;
      _arrow(
        canvas,
        Offset(x, centerY),
        // Where it blows to: the opposite of where it comes from.
        (s.windFromDeg + 180) * math.pi / 180,
        colors.wind(s.windClass),
      );
    }
  }

  /// An arrow of about 12 px centred on [center], pointing [angle] radians
  /// clockwise from up.
  void _arrow(Canvas canvas, Offset center, double angle, Color color) {
    const half = 6.0;
    const head = 4.0;
    final dir = Offset(math.sin(angle), -math.cos(angle));
    final tip = center + dir * half;
    final tail = center - dir * half;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawLine(tail, tip, paint);
    final back = -dir * head;
    final side = Offset(-dir.dy, dir.dx) * (head * 0.7);
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx + back.dx + side.dx, tip.dy + back.dy + side.dy)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(tip.dx + back.dx - side.dx, tip.dy + back.dy - side.dy),
      paint,
    );
  }

  @override
  bool shouldRepaint(RouteWeatherStripPainter old) =>
      !identical(old.weather, weather) ||
      old.colors != colors ||
      old.labelStyle != labelStyle ||
      old.textDirection != textDirection ||
      old.maxTempLabel != maxTempLabel ||
      old.minTempLabel != minTempLabel;
}
