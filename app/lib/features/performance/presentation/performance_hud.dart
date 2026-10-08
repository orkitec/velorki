import 'dart:async';
import 'dart:collection';
import 'dart:io' show ProcessInfo;
import 'dart:ui' show FontFeature, FrameTiming, PlatformDispatcher;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../data/show_performance_setting.dart';
import '../domain/frame_stats.dart';

/// The key of the performance box, for tests.
const Key performanceHudKey = Key('performance-hud');

/// The app's content with the performance box over it when Settings → About
/// → Show performance is on.
///
/// Sits in `MaterialApp.builder`, over the navigator, so the box stays above
/// every route and modal sheet. It never takes a touch.
class PerformanceHudLayer extends ConsumerWidget {
  /// Creates the layer over [child].
  const PerformanceHudLayer({required this.child, super.key});

  /// The app.
  final Widget? child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shown = ref.watch(showPerformanceProvider);
    return Stack(
      fit: StackFit.passthrough,
      children: [
        child ?? const SizedBox.shrink(),
        if (shown) const Positioned.fill(child: PerformanceHud()),
      ],
    );
  }
}

/// The box: frame rate, UI and raster frame times, the jank share and the
/// app's memory, refreshed twice a second.
///
/// Timings are only collected while it is on the screen.
class PerformanceHud extends StatefulWidget {
  /// Creates the box.
  const PerformanceHud({super.key});

  @override
  State<PerformanceHud> createState() => _PerformanceHudState();
}

class _PerformanceHudState extends State<PerformanceHud> {
  static const Duration _refresh = Duration(milliseconds: 500);

  final ListQueue<FrameSample> _samples = ListQueue<FrameSample>();

  /// Time since the last timings arrived, to move the window on while no
  /// frames are drawn.
  final Stopwatch _sinceLatest = Stopwatch();
  int _latestMicros = 0;
  Timer? _timer;
  PerformanceStats _stats = PerformanceStats.empty;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _timer = Timer.periodic(_refresh, (_) => _update());
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _timer?.cancel();
    super.dispose();
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      final sample = FrameSample.fromTiming(timing);
      _samples.add(sample);
      if (sample.presentedMicros > _latestMicros) {
        _latestMicros = sample.presentedMicros;
      }
    }
    _sinceLatest
      ..reset()
      ..start();
    final oldest = _latestMicros - timesWindow.inMicroseconds;
    while (_samples.isNotEmpty && _samples.first.presentedMicros <= oldest) {
      _samples.removeFirst();
    }
  }

  void _update() {
    if (!mounted) return;
    final now = _latestMicros + _sinceLatest.elapsedMicroseconds;
    setState(() {
      _stats = performanceStats(
        _samples,
        nowMicros: now,
        budget: frameBudget(_refreshRate()),
        residentBytes: _residentBytes(),
      );
    });
  }

  double? _refreshRate() {
    try {
      return View.maybeOf(context)?.display.refreshRate ??
          PlatformDispatcher.instance.displays.firstOrNull?.refreshRate;
    } on Object {
      return PlatformDispatcher.instance.displays.firstOrNull?.refreshRate;
    }
  }

  static int _residentBytes() {
    try {
      return ProcessInfo.currentRss;
    } on Object {
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final padding = MediaQuery.viewPaddingOf(context);
    final stats = _stats;
    // Padded to a steady width, so the box does not twitch as figures change.
    String ms(Duration d) => (d.inMicroseconds / 1000).toStringAsFixed(1);
    String times(FrameTimes t) =>
        l10n.perfFrameTimes(ms(t.average).padLeft(4), ms(t.worst));
    final fps = '${stats.fps}'.padLeft(3);
    final jank = l10n.unitPercent(
      '${(stats.jankShare * 100).round()}'.padLeft(3),
    );
    final memory = l10n.perfMegabytes(
      '${(stats.residentBytes / (1 << 20)).round()}',
    );
    const label = TextStyle(color: Color(0xB3FFFFFF));
    const key = TextStyle(
      color: Color(0xFFFFD54F),
      fontWeight: FontWeight.w700,
    );
    // Two short lines tucked under the status bar: low enough not to reach
    // the text of a search field below it.
    return IgnorePointer(
      child: Align(
        alignment: AlignmentDirectional.topStart,
        child: Padding(
          padding: EdgeInsets.only(
            top: padding.top,
            left: padding.left + 4,
            right: padding.right + 4,
          ),
          child: DecoratedBox(
            key: performanceHudKey,
            decoration: const BoxDecoration(
              color: Color(0xC8000000),
              borderRadius: BorderRadius.all(Radius.circular(5)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              child: MediaQuery.withNoTextScaling(
                child: DefaultTextStyle(
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontFamilyFallback: <String>[
                      'Menlo',
                      'Roboto Mono',
                      'Courier',
                    ],
                    fontSize: 9,
                    height: 1.2,
                    color: Color(0xFFFFFFFF),
                    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                    decoration: TextDecoration.none,
                  ),
                  softWrap: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: l10n.perfRaster, style: key),
                            TextSpan(
                              text: ' ${times(stats.raster)}',
                              style: key,
                            ),
                            TextSpan(text: '  ${l10n.perfUi}', style: label),
                            TextSpan(text: ' ${times(stats.build)}'),
                          ],
                        ),
                      ),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: l10n.perfFps, style: label),
                            TextSpan(text: ' $fps'),
                            TextSpan(text: '  ${l10n.perfJank}', style: label),
                            TextSpan(text: ' $jank'),
                            TextSpan(
                              text: '  ${l10n.perfMemory}',
                              style: label,
                            ),
                            TextSpan(text: ' $memory'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
