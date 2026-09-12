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

/// Deadline for one whole loop search.
const Duration smartLoopTimeout = Duration(seconds: 25);

/// Upper bound on the routing requests one search may spend.
const int smartLoopMaxCandidates = 12;

/// How many candidates the sheet keeps and the map draws.
const int smartLoopTopN = 3;

/// The seed the first search of a session uses, so the same request produces
/// the same loops until the user asks to regenerate.
const int smartLoopSeed = 0x76656c6f;

/// The strategies a [LoopRequest] is generated from.
///
/// A request with a via is answered by routing through it and coming back a
/// different way; without one there is nothing to route through, so BRouter's
/// own round-trip mode takes over. The perimeter fallback is always there
/// because it produces *something* even where the other two give up.
List<CandidateStrategy> strategiesForRequest(
  LoopRequest request, {
  int seed = smartLoopSeed,
}) => <CandidateStrategy>[
  if (request.via.isEmpty)
    const RoundtripStrategy()
  else
    const ViaOutAndBackStrategy(),
  PerimeterStrategy(seed: seed),
];

/// The planner waypoints a candidate is handed over with.
///
/// These are the query's own points, so a via loop arrives in the planner with
/// its start and its via places. A round trip has a single point — BRouter
/// invents the rest — and therefore arrives as a lone start waypoint; the
/// geometry is still the computed loop, which is what gets saved.
List<Waypoint> waypointsForCandidate(LoopCandidate candidate) =>
    normalizeWaypointKinds(
      candidate.query.points
          .map((p) => Waypoint(pos: p))
          .toList(growable: false),
    );

/// The smart-loop sheet's state machine.
///
/// One search runs at a time. [start] materialises the queries the strategies
/// propose — which is what makes an honest progress bar possible, since the
/// planner's stream only ever reports the queries that *succeeded* — and then
/// lets [LoopPlanner.planStream] route them, adding each candidate to the
/// state as it arrives.
@Riverpod(keepAlive: true)
class SmartLoopController extends _$SmartLoopController {
  _LoopRun? _run;
  int _seed = smartLoopSeed;
  bool _disposed = false;

  @override
  SmartLoopState build() {
    ref.onDispose(() {
      _disposed = true;
      _run?.cancel();
      _run = null;
    });
    return const SmartLoopState();
  }

  /// Runs a loop search for [request].
  ///
  /// Any search still running is cancelled first. [seed] changes where the
  /// perimeter fallback puts its waypoints, which is what "Regenerate" hands
  /// in to get different loops for the same request. The returned future
  /// completes when this search is done, cancelled or superseded; the
  /// candidates appear in the state long before that.
  Future<void> start(LoopRequest request, {int? seed}) async {
    _stopRun();
    if (seed != null) _seed = seed;
    if (_disposed) return;

    state = SmartLoopState(request: request, running: true);

    final backend = ref.read(routingBackendProvider);
    if (backend == null) {
      state = state.copyWith(running: false, error: noRoutingBackendError);
      return;
    }

    final List<_ReplayStrategy> plans;
    try {
      plans = await _materialize(request, seed: _seed);
    } on Object catch (e) {
      if (!_disposed) {
        state = state.copyWith(running: false, error: e.toString());
      }
      return;
    }
    final planned = plans.fold<int>(0, (n, s) => n + s.planned.length);
    if (planned == 0 || _disposed) {
      if (!_disposed) state = state.copyWith(running: false, progress: 1);
      return;
    }

    final run = _LoopRun(planned);
    _run = run;
    run.onProgress = () {
      if (_disposed || !identical(_run, run)) return;
      state = state.copyWith(progress: run.progress);
    };
    final planner = LoopPlanner(
      backend: _CountingBackend(backend, run),
      strategies: plans,
      concurrency: smartLoopConcurrency,
      timeout: smartLoopTimeout,
      maxCandidates: planned,
      topN: smartLoopTopN,
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
  }

  /// Picks the candidate at [index]; out-of-range indices are ignored.
  void select(int index) {
    if (index < 0 || index >= state.candidates.length) return;
    if (state.selected == index) return;
    state = state.copyWith(selected: index);
  }

  /// Stops the search and every routing request still in flight.
  void cancel() {
    if (_run == null) return;
    _stopRun();
    if (!_disposed && state.running) {
      state = state.copyWith(running: false);
    }
  }

  /// Hands the selected candidate to the planner.
  ///
  /// The planner shows it without routing again, so the user can look at the
  /// elevation profile, save it to the library or edit it. Returns `false`
  /// when nothing is selected.
  bool adopt() {
    final candidate = state.selectedCandidate;
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

  /// Collects the queries the strategies propose, keeping each strategy's
  /// name, so the number of routing requests is known before the first one
  /// goes out.
  Future<List<_ReplayStrategy>> _materialize(
    LoopRequest request, {
    required int seed,
  }) async {
    final plans = <_ReplayStrategy>[];
    var budget = smartLoopMaxCandidates;
    for (final strategy in strategiesForRequest(request, seed: seed)) {
      if (budget <= 0) break;
      final queries = await strategy.queries(request).take(budget).toList();
      if (queries.isEmpty) continue;
      budget -= queries.length;
      plans.add(_ReplayStrategy(strategy.name, queries));
    }
    return plans;
  }

  /// Inserts [candidate] into the ranking, keeping the best
  /// [smartLoopTopN] and the user's pick pointing at the same loop.
  void _add(LoopCandidate candidate) {
    final picked = state.selectedCandidate;
    final ranked = <LoopCandidate>[...state.candidates, candidate]
      ..sort((a, b) => a.score.total.compareTo(b.score.total));
    final kept = ranked.length <= smartLoopTopN
        ? ranked
        : ranked.sublist(0, smartLoopTopN);
    var selected = picked == null ? 0 : kept.indexOf(picked);
    if (selected < 0) selected = 0;
    state = state.copyWith(candidates: kept, selected: selected);
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
/// back in through this trivial strategy. The name is the original one, so a
/// candidate still says which strategy produced it.
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
      // not a failure: it becomes the sheet's "try a shorter distance" state.
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
