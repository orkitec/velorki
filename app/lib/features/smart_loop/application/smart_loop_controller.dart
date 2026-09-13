import 'dart:async';
import 'dart:math' as math;

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

import '../../planner/application/planner_controller.dart';
import '../../planner/data/routing_backend_provider.dart';
import '../../planner/domain/route_profile.dart';
import '../../planner/domain/routing_options.dart';
import '../../planner/domain/waypoint.dart';
import '../domain/loops.dart';
import '../domain/smart_loop_state.dart';

part 'smart_loop_controller.g.dart';

/// How many routing requests a loop search keeps in flight.
///
/// Three is what the architecture prescribes against the routing server; the
/// on-device engine will want one.
const int smartLoopConcurrency = 3;

/// Candidates run one at a time while routing happens on the device: the
/// engine is one isolate with one segment cache, so three parallel searches
/// would only fight over it.
const int smartLoopOnDeviceConcurrency = 1;

/// Deadline for one whole loop search.
const Duration smartLoopTimeout = Duration(seconds: 25);

/// How many directions one search heads off in.
const int smartLoopDirections = 8;

/// How far the next search is rotated once every loop of this one has been
/// shown: half a step, so it lands between the directions already tried.
const double smartLoopRotationDeg = 360 / smartLoopDirections / 2;

/// The planner waypoints a candidate is handed over with.
///
/// A round trip has a single query point — BRouter invents the rest — so it
/// arrives as a lone start waypoint. The geometry is still the computed loop,
/// which is what the planner draws and what gets saved.
List<Waypoint> waypointsForCandidate(LoopCandidate candidate) =>
    normalizeWaypointKinds(
      candidate.query.points
          .map((p) => Waypoint(pos: p))
          .toList(growable: false),
    );

/// The engine behind the "Make a loop" sheet.
///
/// One search runs at a time: [search] fires BRouter's own round-trip mode off
/// in [smartLoopDirections] directions, scores whatever comes back and hands
/// the best loop straight to the planner. [another] walks down that ranking
/// without touching the network and only searches again — rotated — when the
/// list is used up.
@Riverpod(keepAlive: true)
class SmartLoopController extends _$SmartLoopController {
  _LoopRun? _run;
  bool _disposed = false;
  bool _allowSameWayBack = false;
  double _directionOffsetDeg = 0;

  @override
  SmartLoopState build() {
    ref.onDispose(() {
      _disposed = true;
      _run?.cancel();
      _run = null;
    });
    return const SmartLoopState();
  }

  /// Searches loops for [request] and puts the best one in the planner.
  ///
  /// [allowSameWayBack] is BRouter's own switch: `false` sends the ride round
  /// a circle, `true` out to a far point and back the same way. The returned
  /// future completes when the search is done, cancelled or superseded.
  Future<void> search(
    LoopRequest request, {
    bool allowSameWayBack = false,
    double directionOffsetDeg = 0,
  }) async {
    _stopRun();
    if (_disposed) return;
    _allowSameWayBack = allowSameWayBack;
    _directionOffsetDeg = directionOffsetDeg;

    state = SmartLoopState(request: request, running: true);

    final backend = ref.read(routingBackendProvider);
    if (backend == null) {
      state = state.copyWith(running: false, error: noRoutingBackendError);
      return;
    }

    final strategy = RoundtripStrategy(
      directions: smartLoopDirections,
      offsetDeg: directionOffsetDeg,
      allowSameWayBack: allowSameWayBack,
    );
    final queries = await strategy.queries(request).toList();
    if (queries.isEmpty || _disposed) {
      if (!_disposed) state = state.copyWith(running: false, progress: 1);
      return;
    }

    final run = _LoopRun(queries.length);
    _run = run;
    run.onProgress = () {
      if (_disposed || !identical(_run, run)) return;
      state = state.copyWith(progress: run.progress);
    };
    final planner = LoopPlanner(
      backend: _CountingBackend(backend, run),
      strategies: <CandidateStrategy>[_ReplayStrategy(strategy.name, queries)],
      concurrency: backend is CompositeRoutingBackend && backend.local != null
          ? smartLoopOnDeviceConcurrency
          : smartLoopConcurrency,
      timeout: smartLoopTimeout,
      maxCandidates: queries.length,
      topN: queries.length,
    );

    try {
      await for (final candidate in planner.planStream(request)) {
        if (_disposed || !identical(_run, run)) break;
        _add(candidate);
      }
    } on Object catch (e) {
      if (!_disposed && identical(_run, run)) {
        _run = null;
        state = state.copyWith(running: false, error: _messageOf(e));
      }
      return;
    }

    if (_disposed || !identical(_run, run)) return;
    _run = null;
    run.cancel();
    state = state.copyWith(
      running: false,
      progress: 1,
      error: state.candidates.isEmpty ? run.lastFailure : null,
    );
    adopt();
  }

  /// Shows the next-best loop of the current search.
  ///
  /// Nothing is routed while the ranking still holds one; once it is used up
  /// the same request is searched again with the directions rotated by
  /// [smartLoopRotationDeg], which is the cheapest way to different loops.
  Future<void> another() async {
    final request = state.request;
    if (request == null || state.running) return;
    if (state.index + 1 < state.candidates.length) {
      state = state.copyWith(index: state.index + 1);
      adopt();
      return;
    }
    await search(
      request,
      allowSameWayBack: _allowSameWayBack,
      directionOffsetDeg: _directionOffsetDeg + smartLoopRotationDeg,
    );
  }

  /// Stops the search and every routing request still in flight, keeping
  /// whatever was found.
  void cancel() {
    if (_run == null) return;
    _stopRun();
    if (_disposed) return;
    if (state.running) state = state.copyWith(running: false);
    adopt();
  }

  /// Forgets the last search, so reopening the sheet starts on a clean slate.
  void reset() {
    _stopRun();
    if (!_disposed) state = const SmartLoopState();
  }

  /// Hands the loop currently on show to the planner.
  ///
  /// The planner shows it without routing again, so the rider can look at the
  /// elevation profile, save it to the library or edit it. Returns `false`
  /// when there is nothing to hand over.
  bool adopt() {
    final candidate = state.current;
    if (candidate == null) return false;
    ref
        .read(plannerControllerProvider.notifier)
        .loadComputedRoute(
          result: candidate.result,
          waypoints: waypointsForCandidate(candidate),
          options: RoutingOptions(
            profile: RouteProfile.fromName(candidate.query.profile),
          ),
        );
    return true;
  }

  void _stopRun() {
    _run?.cancel();
    _run = null;
  }

  /// Inserts [candidate] into the ranking, best first.
  void _add(LoopCandidate candidate) {
    final ranked = <LoopCandidate>[...state.candidates, candidate]
      ..sort((a, b) => a.score.total.compareTo(b.score.total));
    state = state.copyWith(candidates: ranked, index: 0);
  }

  static String _messageOf(Object error) =>
      error is RoutingException ? error.message : error.toString();
}

/// One loop search: its cancel token and its progress counters.
class _LoopRun {
  _LoopRun(this.planned);

  /// How many routing requests this search will send.
  final int planned;

  /// Cancelled when the search is abandoned; see [_CountingBackend].
  final CancelToken token = CancelToken();

  /// How many requests have finished, successfully or not.
  int done = 0;

  /// Called whenever [done] changes, so the sheet's progress bar moves on a
  /// failed request too and not only on a candidate.
  void Function()? onProgress;

  /// The last routing failure worth reporting, shown when nothing routed.
  String? lastFailure;

  double get progress => planned == 0 ? 1 : math.min(1, done / planned);

  void cancel() => token.cancel('loop search cancelled');
}

/// Replays an already collected list of queries.
///
/// [LoopPlanner] takes strategies, not queries, so the materialised queries go
/// back in through this trivial strategy — which is what makes an honest
/// progress bar possible, since the planner's stream only ever reports the
/// queries that *succeeded*.
///
/// It is a generator rather than a `Stream.fromIterable` on purpose: the
/// planner stops reading at its candidate budget, and cancelling a
/// `fromIterable` subscription mid-stream never resumes under the widget
/// tests' fake clock, which would hang every search in a widget test.
class _ReplayStrategy implements CandidateStrategy {
  _ReplayStrategy(this.name, this.planned);

  @override
  final String name;

  /// The queries to hand to the planner, in order.
  final List<RouteQuery> planned;

  @override
  Stream<RouteQuery> queries(LoopRequest request) async* {
    for (final query in planned) {
      yield query;
    }
  }
}

/// Counts finished routing requests and relays the controller's cancellation.
///
/// [LoopPlanner] owns the token it hands to the backend, so cancelling a
/// search from outside means cancelling *that* token — which this decorator
/// does as soon as the run's own token goes off.
class _CountingBackend implements RoutingBackend {
  _CountingBackend(this._inner, this._run);

  final RoutingBackend _inner;
  final _LoopRun _run;

  @override
  Future<RouteResult> route(RouteQuery q, {CancelToken? cancel}) async {
    if (cancel != null) {
      if (_run.token.isCancelled) cancel.cancel(_run.token.reason!);
      unawaited(
        _run.token.whenCancelled.then((_) => cancel.cancel(_run.token.reason!)),
      );
    }
    try {
      return await _inner.route(q, cancel: cancel ?? _run.token);
    } on RoutingException catch (e) {
      // "No route from here" is the normal answer to an over-ambitious loop,
      // not a failure: it becomes the sheet's "try another distance" state.
      // Only a broken server or a rejected request is worth reporting.
      if (e.kind == RoutingErrorKind.network ||
          e.kind == RoutingErrorKind.invalid) {
        _run.lastFailure = e.message;
      }
      rethrow;
    } on Object catch (e) {
      _run.lastFailure = e.toString();
      rethrow;
    } finally {
      _run.done++;
      _run.onProgress?.call();
    }
  }
}
