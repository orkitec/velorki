import 'dart:ui' show FrameTiming;

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/performance/domain/frame_stats.dart';

/// A frame that ends at [endMs] (milliseconds on the engine's clock) after
/// [buildMs] on the UI thread and [rasterMs] on the raster thread.
FrameSample _frame(int endMs, {int buildMs = 2, int rasterMs = 4}) {
  final end = endMs * 1000;
  final rasterStart = end - rasterMs * 1000;
  final buildFinish = rasterStart;
  final buildStart = buildFinish - buildMs * 1000;
  return FrameSample.fromTiming(
    FrameTiming(
      vsyncStart: buildStart,
      buildStart: buildStart,
      buildFinish: buildFinish,
      rasterStart: rasterStart,
      rasterFinish: end,
      rasterFinishWallTime: end,
    ),
  );
}

void main() {
  test('a sample takes its times from the FrameTiming', () {
    final sample = _frame(1000, buildMs: 3, rasterMs: 7);
    expect(sample.presentedMicros, 1000000);
    expect(sample.build, const Duration(milliseconds: 3));
    expect(sample.raster, const Duration(milliseconds: 7));
  });

  test('the frame budget follows the refresh rate, 60 Hz when unknown', () {
    expect(frameBudget(60), const Duration(microseconds: 16667));
    expect(frameBudget(120), const Duration(microseconds: 8333));
    expect(frameBudget(null), frameBudget(60));
    expect(frameBudget(0), frameBudget(60));
    expect(frameBudget(double.nan), frameBudget(60));
  });

  test('fps counts the frames presented in the last second', () {
    // 60 frames a second for two seconds.
    final frames = [for (var i = 1; i <= 120; i++) _frame(i * 1000 ~/ 60)];
    expect(framesPerSecond(frames, 2000 * 1000), 60);
    // Half a second after the last frame, half the window is empty.
    expect(framesPerSecond(frames, 2500 * 1000), 30);
    expect(framesPerSecond(frames, 10000 * 1000), 0);
    expect(framesPerSecond(const [], 0), 0);
  });

  test('frame times are the average and the worst', () {
    expect(
      FrameTimes.of(const [
        Duration(milliseconds: 2),
        Duration(milliseconds: 4),
        Duration(milliseconds: 12),
      ]),
      const FrameTimes(
        average: Duration(milliseconds: 6),
        worst: Duration(milliseconds: 12),
      ),
    );
    expect(FrameTimes.of(const []), FrameTimes.none);
  });

  test('a frame is janky when either thread overruns the budget', () {
    final budget = frameBudget(60);
    expect(isJanky(_frame(0, buildMs: 2, rasterMs: 4), budget), isFalse);
    expect(isJanky(_frame(0, buildMs: 20, rasterMs: 4), budget), isTrue);
    expect(isJanky(_frame(0, buildMs: 2, rasterMs: 17), budget), isTrue);
    // The same raster time fits at 60 Hz and overruns at 120 Hz.
    expect(isJanky(_frame(0, rasterMs: 10), budget), isFalse);
    expect(isJanky(_frame(0, rasterMs: 10), frameBudget(120)), isTrue);
  });

  test('the jank share is the janky frames over all of them', () {
    final budget = frameBudget(60);
    final frames = [
      _frame(10),
      _frame(20, rasterMs: 30),
      _frame(30),
      _frame(40, buildMs: 25),
    ];
    expect(jankShare(frames, budget), 0.5);
    expect(jankShare(const [], budget), 0);
  });

  test('the stats look back two seconds for times and jank', () {
    final frames = [
      // Older than two seconds before now: left out.
      _frame(500, rasterMs: 50),
      _frame(3000, buildMs: 2, rasterMs: 4),
      _frame(3500, buildMs: 4, rasterMs: 20),
      _frame(4000, buildMs: 6, rasterMs: 6),
    ];
    final stats = performanceStats(
      frames,
      nowMicros: 4000 * 1000,
      budget: frameBudget(60),
      residentBytes: 42,
    );
    expect(stats.fps, 2);
    expect(
      stats.raster,
      const FrameTimes(
        average: Duration(milliseconds: 10),
        worst: Duration(milliseconds: 20),
      ),
    );
    expect(
      stats.build,
      const FrameTimes(
        average: Duration(milliseconds: 4),
        worst: Duration(milliseconds: 6),
      ),
    );
    expect(stats.jankShare, closeTo(1 / 3, 1e-9));
    expect(stats.residentBytes, 42);
  });
}
