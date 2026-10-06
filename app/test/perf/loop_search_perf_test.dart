/// How long a loop search takes on the on-device engine, over New York.
///
/// Not an assertion of speed: it runs the sheet's own search (the same
/// directions, concurrency and filter as `SmartLoopController`, with no
/// deadline) from Midtown Manhattan at a few slider distances and prints
/// every routing request, what came of it and the total, so the search's
/// safety net (`smartLoopTimeout`) can be sized against a slow phone, which
/// runs the engine several times slower than a desktop. Each distance ends
/// on a one-line SUMMARY: time to the first loop, the whole search, the
/// routings and the best loop's distance off the target.
///
///     VELORKI_NYC_SEGMENTS_DIR=/dir/with/W75_N40.rd5 \
///       flutter test test/perf/loop_search_perf_test.dart
///
/// Skipped when `VELORKI_NYC_SEGMENTS_DIR` does not hold the tile.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/planner/domain/route_profile.dart';
import 'package:velorki/features/smart_loop/application/smart_loop_controller.dart';
import 'package:velorki/features/smart_loop/domain/loops.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

const String _profiles = '../brouter/profiles';
const LatLng _midtown = LatLng(40.758, -73.992);

/// The distances measured, in km: 15 mi (the reported case), two between
/// and the slider's top.
const List<double> _distancesKm = <double>[24, 50, 80, 200];

void main() {
  final dir = Platform.environment['VELORKI_NYC_SEGMENTS_DIR'];
  final skip = dir == null || !File('$dir/W75_N40.rd5').existsSync()
      ? 'VELORKI_NYC_SEGMENTS_DIR does not hold W75_N40.rd5'
      : null;

  late LocalRoutingBackend backend;
  setUpAll(() {
    if (skip != null) return;
    backend = LocalRoutingBackend(segmentsDir: dir!, profilesDir: _profiles);
  });
  tearDownAll(() async {
    if (skip != null) return;
    await backend.dispose();
  });

  for (final km in _distancesKm) {
    test(
      '${km.round()} km from Midtown, different way back',
      () async {
        final request = LoopRequest(
          start: _midtown,
          targetM: km * 1000,
          profile: RouteProfile.trekking.engineName,
        );
        final strategy = RoundtripStrategy(directions: smartLoopDirections);
        final queries = await strategy.queries(request).toList();
        final clock = Stopwatch()..start();
        final timed = _TimedBackend(backend, request, clock);
        final planner = LoopPlanner(
          backend: timed,
          strategies: <CandidateStrategy>[strategy],
          concurrency: smartLoopOnDeviceConcurrency,
          timeout: const Duration(hours: 1),
          maxCandidates: queries.length,
          topN: queries.length,
        );
        final found = <String>[];
        Duration? first;
        LoopCandidate? best;
        await for (final c in planner.planStream(request)) {
          first ??= clock.elapsed;
          if (best == null || c.score.total < best.score.total) best = c;
          found.add(
            '${_s(clock.elapsed)} candidate '
            '${(c.result.lengthM / 1000).toStringAsFixed(1)} km'
            '${c.farFromTarget ? ' (far from target)' : ''}',
          );
        }
        final total = clock.elapsed;
        final routing = timed.log.fold<Duration>(
          Duration.zero,
          (sum, e) => sum + e.took,
        );
        final buf = StringBuffer()
          ..writeln('== ${km.round()} km: ${timed.log.length} requests')
          ..writeAll(timed.log.map((e) => '  $e\n'))
          ..writeAll(found.map((f) => '  $f\n'))
          ..writeln(
            '  total ${_s(total)}, routing ${_s(routing)}, '
            'first candidate at ${found.isEmpty ? '-' : found.first}',
          )
          ..writeln(
            '  SUMMARY ${km.round()} km: '
            'first ${first == null ? '-' : _s(first)}, total ${_s(total)}, '
            '${timed.log.length} routings, best ${_best(best, request)}',
          );
        // ignore: avoid_print
        print(buf);
      },
      skip: skip,
      timeout: const Timeout(Duration(minutes: 30)),
    );
  }
}

/// The best loop's length and how far it is off the target.
String _best(LoopCandidate? best, LoopRequest request) {
  if (best == null) return '-';
  final km = best.result.lengthM / 1000;
  final off = (best.result.lengthM - request.targetM) / request.targetM * 100;
  return '${km.toStringAsFixed(1)} km (${off.toStringAsFixed(1)} %)';
}

String _s(Duration d) => '${(d.inMilliseconds / 1000).toStringAsFixed(1)} s';

class _Entry {
  _Entry(this.query, this.at, this.took, this.outcome);
  final RouteQuery query;
  final Duration at;
  final Duration took;
  final String outcome;

  @override
  String toString() =>
      '@${_s(at)} dir ${query.roundTripDirectionDeg?.round()}° '
      'r ${((query.roundTripDistanceM ?? 0) / 1000).toStringAsFixed(1)} km: '
      '${_s(took)} -> $outcome';
}

/// Times each request and says what the planner's filter will make of it.
class _TimedBackend implements RoutingBackend {
  _TimedBackend(this._inner, this._request, this._clock);

  final RoutingBackend _inner;
  final LoopRequest _request;
  final Stopwatch _clock;
  final List<_Entry> log = <_Entry>[];

  @override
  Future<RouteResult> route(RouteQuery q, {CancelToken? cancel}) async {
    final at = _clock.elapsed;
    try {
      final r = await _inner.route(q, cancel: cancel);
      const filter = LoopFilter();
      final quality = LoopQuality.of(
        r,
        waypoints: syntheticPoints(_request, q),
      );
      final rejected = filter.reject(
        quality,
        ridesBackTheSameWay: q.allowSameWayBack,
      );
      final far = filter.tooFarFromTarget(quality, targetM: _request.targetM);
      log.add(
        _Entry(
          q,
          at,
          _clock.elapsed - at,
          '${(r.lengthM / 1000).toStringAsFixed(1)} km'
          '${rejected != null ? ', rejected: $rejected' : ''}'
          '${far != null ? ', far: $far' : ''}',
        ),
      );
      return r;
    } on RoutingException catch (e) {
      log.add(
        _Entry(q, at, _clock.elapsed - at, '${e.kind.name}: ${e.message}'),
      );
      rethrow;
    }
  }
}
