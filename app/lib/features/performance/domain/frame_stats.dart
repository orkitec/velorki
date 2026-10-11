import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/foundation.dart' show immutable;

/// How far back the frame rate looks.
const Duration fpsWindow = Duration(seconds: 1);

/// How far back the frame times and the jank share look.
const Duration timesWindow = Duration(seconds: 2);

/// One presented frame, as the engine timed it.
@immutable
class FrameSample {
  /// Creates a sample.
  const FrameSample({
    required this.presentedMicros,
    required this.build,
    required this.raster,
  });

  /// The sample of [timing]: when its raster finished, and how long the UI
  /// thread built it and the raster thread drew it.
  factory FrameSample.fromTiming(FrameTiming timing) => FrameSample(
    presentedMicros: timing.timestampInMicroseconds(FramePhase.rasterFinish),
    build: timing.buildDuration,
    raster: timing.rasterDuration,
  );

  /// When the frame was done, on the engine's clock.
  final int presentedMicros;

  /// The UI thread's time on the frame: build, layout and paint.
  final Duration build;

  /// The raster thread's time on the frame: what drawing it costs.
  final Duration raster;
}

/// An average and the worst of a set of frame times.
@immutable
class FrameTimes {
  /// Creates the pair.
  const FrameTimes({required this.average, required this.worst});

  /// The pair over [times]; [none] for no times.
  factory FrameTimes.of(Iterable<Duration> times) {
    var count = 0;
    var total = 0;
    var worst = 0;
    for (final time in times) {
      count++;
      total += time.inMicroseconds;
      if (time.inMicroseconds > worst) worst = time.inMicroseconds;
    }
    if (count == 0) return none;
    return FrameTimes(
      average: Duration(microseconds: (total / count).round()),
      worst: Duration(microseconds: worst),
    );
  }

  /// No frames.
  static const FrameTimes none = FrameTimes(
    average: Duration.zero,
    worst: Duration.zero,
  );

  /// The mean.
  final Duration average;

  /// The longest.
  final Duration worst;

  @override
  bool operator ==(Object other) =>
      other is FrameTimes && other.average == average && other.worst == worst;

  @override
  int get hashCode => Object.hash(average, worst);

  @override
  String toString() => 'FrameTimes($average, $worst)';
}

/// What the performance box shows.
@immutable
class PerformanceStats {
  /// Creates the figures.
  const PerformanceStats({
    required this.fps,
    required this.build,
    required this.raster,
    required this.jankShare,
    required this.residentBytes,
  });

  /// Before the first frame is timed.
  static const PerformanceStats empty = PerformanceStats(
    fps: 0,
    build: FrameTimes.none,
    raster: FrameTimes.none,
    jankShare: 0,
    residentBytes: 0,
  );

  /// Frames presented over the last [fpsWindow].
  final int fps;

  /// The UI thread's frame times over the last [timesWindow].
  final FrameTimes build;

  /// The raster thread's frame times over the last [timesWindow].
  final FrameTimes raster;

  /// The share of the frames over the last [timesWindow], 0 to 1, that took
  /// longer than the frame budget on either thread.
  final double jankShare;

  /// The app's resident memory.
  final int residentBytes;
}

/// The time one frame may take at [refreshRate] frames a second; at 60 when
/// the display does not say.
Duration frameBudget(double? refreshRate) {
  final rate = refreshRate == null || !refreshRate.isFinite || refreshRate <= 0
      ? 60.0
      : refreshRate;
  return Duration(
    microseconds: (Duration.microsecondsPerSecond / rate).round(),
  );
}

/// The frames presented within [window] up to [nowMicros].
Iterable<FrameSample> framesWithin(
  Iterable<FrameSample> samples,
  int nowMicros,
  Duration window,
) => samples.where(
  (s) =>
      s.presentedMicros > nowMicros - window.inMicroseconds &&
      s.presentedMicros <= nowMicros,
);

/// The frames presented over the [fpsWindow] up to [nowMicros].
int framesPerSecond(Iterable<FrameSample> samples, int nowMicros) =>
    framesWithin(samples, nowMicros, fpsWindow).length;

/// Whether [sample] overran [budget] on either thread.
bool isJanky(FrameSample sample, Duration budget) =>
    sample.build > budget || sample.raster > budget;

/// The share of [samples], 0 to 1, that overran [budget]; 0 for none.
double jankShare(Iterable<FrameSample> samples, Duration budget) {
  var count = 0;
  var janky = 0;
  for (final sample in samples) {
    count++;
    if (isJanky(sample, budget)) janky++;
  }
  return count == 0 ? 0 : janky / count;
}

/// The figures over [samples] at [nowMicros], on the engine's clock.
PerformanceStats performanceStats(
  Iterable<FrameSample> samples, {
  required int nowMicros,
  required Duration budget,
  int residentBytes = 0,
}) {
  final recent = framesWithin(samples, nowMicros, timesWindow).toList();
  return PerformanceStats(
    fps: framesPerSecond(recent, nowMicros),
    build: FrameTimes.of(recent.map((s) => s.build)),
    raster: FrameTimes.of(recent.map((s) => s.raster)),
    jankShare: jankShare(recent, budget),
    residentBytes: residentBytes,
  );
}
