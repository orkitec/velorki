import 'dart:async';
import 'dart:math' as math;

import 'package:logging/logging.dart';
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

final Logger _log = Logger('SmartLoop');

/// How many routing requests a loop search keeps in flight.
///
/// Three is what the architecture prescribes against the routing server; the
/// on-device engine will want one.
const int smartLoopConcurrency = 3;

/// Candidates run one at a time while routing happens on the device: the
/// engine is one isolate with one segment cache, so three parallel searches
/// would only fight over it.
const int smartLoopOnDeviceConcurrency = 1;

/// Deadline for one whole loop search: a safety net against a runaway search,
/// never the limit an ordinary one runs into.
///
/// The search is bounded anyway — eight directions plus the planner's few
/// retries, with the rider able to stop it while the bar fills. Measured on
/// the on-device engine from Midtown Manhattan (`test/perf/loop_search_perf_test.dart`,
/// an M-series Mac): 24 km takes 54 s, 80 km 97 s, the slider's 200 km
/// 187 s. A six-year-old Android phone is up to eight times slower, so 200 km
/// takes it about 25 minutes; the net sits above that. 25 seconds, which it
/// used to be, ran out before a Pixel 3 XL had routed its first loop of 24 km.
const Duration smartLoopTimeout = Duration(minutes: 30);

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
/// in [smartLoopDirections] directions, throws away what is not a loop (a
/// beeline over water, the same road twice — `LoopFilter`), scores the rest
/// and hands the best so far to the planner as each one arrives. [another]
/// walks down that ranking without touching the network and only searches
/// again — rotated — when the list is used up. Once the rider has chosen a
/// loop, by "Another" or [adopt], later arrivals only extend the ranking.
@Riverpod(keepAlive: true)
class SmartLoopController extends _$SmartLoopController {
  _LoopRun? _run;
  bool _disposed = false;
  bool _allowSameWayBack = false;
  double _directionOffsetDeg = 0;

  /// The candidate last handed to the planner, so the same one is not
  /// handed over twice — which would undo an edit the rider made after
  /// taking it.
  LoopCandidate? _shown;

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
    _shown = null;

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
    // The status line under the bar is there from the first frame, so it
    // does not push the bar when the first direction comes back.
    state = state.copyWith(planned: run.planned);
    run.onProgress = () {
      if (_disposed || !identical(_run, run)) return;
      // Short of full until the search really ends: a retry can follow
      // the last request, and a full bar over a running search looked done.
      state = state.copyWith(
        progress: math.min(run.progress, _runningProgressCap),
        checked: run.done,
      );
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
      missingTiles: state.candidates.isEmpty
          ? run.missingTiles.toList()
          : const <TileName>[],
      timedOut: run.timedOut,
    );
    _show();
  }

  /// Shows the next-best loop of the current search.
  ///
  /// Nothing is routed while the ranking still holds one; once it is used up
  /// the same request is searched again with the directions rotated by
  /// [smartLoopRotationDeg], which is the cheapest way to different loops.
  /// While the search is still running there is no searching again: it moves
  /// on only when the ranking has a next one, and that choice stays put as
  /// more loops arrive.
  Future<void> another() async {
    final request = state.request;
    if (request == null) return;
    if (state.index + 1 < state.candidates.length) {
      state = state.copyWith(index: state.index + 1, pinned: true);
      _show();
      return;
    }
    if (state.running) return;
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
    if (state.running) state = state.copyWith(running: false, stopped: true);
    _show();
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
  ///
  /// While the search is still running it keeps running: what it finds later
  /// is only ranked, and never replaces this loop ([SmartLoopState.handedOver]).
  bool adopt() {
    final candidate = state.current;
    if (candidate == null) return false;
    if (state.running) {
      state = state.copyWith(pinned: true, handedOver: true);
    }
    _load(candidate);
    return true;
  }

  /// Hands the loop on show to the planner, unless it is there already.
  void _show() {
    final candidate = state.current;
    if (candidate == null || identical(candidate, _shown)) return;
    _load(candidate);
  }

  void _load(LoopCandidate candidate) {
    _shown = candidate;
    // What the rider is looking at, in the two numbers that say whether the
    // search did its job: the distance and how much of it is ridden twice.
    // A loop the planner marked far is it saying it spent every retry and
    // found nothing closer to the distance that was asked for.
    _log.fine(
      'showing ${(candidate.result.lengthM / 1000).toStringAsFixed(1)} km, '
      '${(candidate.quality.repeatedShare * 100).toStringAsFixed(0)} % '
      'ridden twice, score ${candidate.score.total.toStringAsFixed(3)}'
      '${candidate.farFromTarget ? ', retry budget exhausted' : ''}',
    );
    ref
        .read(plannerControllerProvider.notifier)
        .loadComputedRoute(
          result: candidate.result,
          waypoints: waypointsForCandidate(candidate),
          options: RoutingOptions(
            profile: RouteProfile.fromName(candidate.query.profile),
          ),
        );
  }

  void _stopRun() {
    _run?.cancel();
    _run = null;
  }

  /// Inserts [candidate] into the ranking, best first, and shows the best so
  /// far — or, once the rider has chosen one, keeps showing that one.
  void _add(LoopCandidate candidate) {
    final chosen = state.pinned ? state.current : null;
    final ranked = <LoopCandidate>[...state.candidates, candidate]
      ..sort((a, b) => a.score.total.compareTo(b.score.total));
    final index = chosen == null
        ? 0
        : ranked.indexWhere((c) => identical(c, chosen));
    state = state.copyWith(candidates: ranked, index: math.max(0, index));
    _show();
  }

  static String _messageOf(Object error) =>
      error is RoutingException ? error.message : error.toString();
}

/// The most the bar shows while a search still runs.
const double _runningProgressCap = 0.9;

/// One loop search: its cancel token and its progress counters.
class _LoopRun {
  _LoopRun(this.planned);

  /// How many routing requests this search will send, at least.
  int planned;

  /// Cancelled when the search is abandoned; see [_CountingBackend].
  final CancelToken token = CancelToken();

  /// How many requests have finished, successfully or not.
  int done = 0;

  /// How many have been started. The planner adds a retry of its own for a
  /// direction that came back unroutable or unridable, so a run can be longer
  /// than it was planned to be; the bar follows rather than sitting at 100 %.
  int started = 0;

  /// Called whenever [done] changes, so the sheet's progress bar moves on a
  /// failed request too and not only on a candidate.
  void Function()? onProgress;

  /// The last routing failure worth reporting, shown when nothing routed.
  String? lastFailure;

  /// The tiles the on-device engine lacked, with no server to fall back to.
  final Set<TileName> missingTiles = <TileName>{};

  /// Whether the planner's deadline cut a request short.
  bool timedOut = false;

  double get progress => planned == 0 ? 1 : math.min(1, done / planned);

  /// Notes one more request going out, growing [planned] when the planner
  /// retries more than it was given.
  void starting() {
    started++;
    if (started > planned) planned = started;
  }

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
    _run.starting();
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
      // Nor is a region that is not downloaded yet: it becomes the sheet's
      // download offer.
      if (e.kind == RoutingErrorKind.missingTiles) {
        _run.missingTiles.addAll(e.missingTiles);
      }
      rethrow;
    } on Object catch (e) {
      _run.lastFailure = e.toString();
      rethrow;
    } finally {
      // The planner cancels what is still running when its deadline is up;
      // the token says so, which is how "too slow" is told from "no loop".
      if (cancel?.reason == LoopPlanner.timeoutReason) _run.timedOut = true;
      _run.done++;
      _run.onProgress?.call();
    }
  }
}
