import 'dart:async';
import 'dart:math' as math;

import 'package:velorki_brouter/velorki_brouter.dart';

import 'loop_request.dart';
import 'scorer.dart';
import 'strategies.dart';

/// One routed and scored loop: the query that produced it, the route itself
/// and its score.
class LoopCandidate {
  /// Creates a candidate.
  const LoopCandidate({
    required this.query,
    required this.result,
    required this.score,
    required this.strategy,
  });

  /// The query that produced [result].
  final RouteQuery query;

  /// The routed geometry and its statistics.
  final RouteResult result;

  /// How good it is; lower [LoopScore.total] is better.
  final LoopScore score;

  /// Which [CandidateStrategy] proposed it.
  final String strategy;

  @override
  String toString() =>
      'LoopCandidate($strategy, '
      '${(result.lengthM / 1000).toStringAsFixed(1)} km, '
      'score ${score.total.toStringAsFixed(3)})';
}

/// Generates loop candidates, routes them and keeps the best few.
///
/// The planner is the whole "smart loops" feature: no model, just candidate
/// generation, real routing and a weighted score.
class LoopPlanner {
  /// Creates a planner.
  ///
  /// [strategies] defaults to all three built-in strategies. [scorer] is
  /// optional because the weights depend on the rider's [LoopPrefs], which
  /// arrive with the request; when it is `null` a `RouteScorer(request.prefs)`
  /// is built per call, which is what the app wants. Pass one explicitly only
  /// to pin the weights in a test.
  LoopPlanner({
    required this.backend,
    List<CandidateStrategy>? strategies,
    this.scorer,
    this.concurrency = 3,
    this.timeout = const Duration(seconds: 25),
    this.maxCandidates = 12,
    this.topN = 3,
  }) : strategies =
           strategies ??
           <CandidateStrategy>[
             const RoundtripStrategy(),
             const ViaOutAndBackStrategy(),
             PerimeterStrategy(),
           ];

  /// Where the routes come from.
  final RoutingBackend backend;

  /// The candidate generators, tried in order.
  final List<CandidateStrategy> strategies;

  /// Fixed scorer, or `null` to derive one from each request.
  final RouteScorer? scorer;

  /// How many routing requests may be in flight at once.
  final int concurrency;

  /// Deadline for the whole planning run; queries still running are cancelled.
  final Duration timeout;

  /// Upper bound on the number of queries taken from the strategies.
  final int maxCandidates;

  /// How many candidates [plan] returns.
  final int topN;

  /// Routes and scores candidates and returns the best [topN], best first.
  ///
  /// Queries that fail to route are skipped, so a partial network or an
  /// unroutable direction degrades the result instead of breaking it. Returns
  /// an empty list when nothing routed.
  Future<List<LoopCandidate>> plan(LoopRequest request) async {
    final found = await planStream(request).toList();
    found.sort((a, b) => a.score.total.compareTo(b.score.total));
    return found.length <= topN ? found : found.sublist(0, topN);
  }

  /// The same work as [plan], but each candidate is emitted as soon as it is
  /// routed and scored, so the UI can draw them while the rest are still
  /// running.
  ///
  /// The order is completion order, **not** score order; the caller sorts.
  Stream<LoopCandidate> planStream(LoopRequest request) {
    final out = StreamController<LoopCandidate>();
    out.onListen = () {
      unawaited(_run(request, out));
    };
    return out.stream;
  }

  Future<void> _run(
    LoopRequest request,
    StreamController<LoopCandidate> out,
  ) async {
    final scorer = this.scorer ?? RouteScorer(request.prefs);
    final pending = await _collectQueries(request);
    if (pending.isEmpty) {
      await out.close();
      return;
    }

    final cancel = CancelToken();
    final deadline = Timer(timeout, () => cancel.cancel('planning timed out'));
    var next = 0;

    Future<void> worker() async {
      while (!cancel.isCancelled) {
        final i = next++;
        if (i >= pending.length) return;
        final entry = pending[i];
        try {
          final result = await backend.route(entry.query, cancel: cancel);
          if (out.isClosed) return;
          out.add(
            LoopCandidate(
              query: entry.query,
              result: result,
              score: scorer.score(result, targetM: request.targetM),
              strategy: entry.strategy,
            ),
          );
        } on RoutingException {
          // A candidate that does not route is simply not a candidate.
        } catch (_) {
          // Neither is one whose answer we cannot make sense of.
        }
      }
    }

    final workers = math.max(1, math.min(concurrency, pending.length));
    await Future.wait(List.generate(workers, (_) => worker()));
    deadline.cancel();
    if (!cancel.isCancelled) cancel.cancel('planning finished');
    await out.close();
  }

  Future<List<_PendingQuery>> _collectQueries(LoopRequest request) async {
    final out = <_PendingQuery>[];
    for (final strategy in strategies) {
      if (out.length >= maxCandidates) break;
      await for (final query in strategy.queries(request)) {
        out.add(_PendingQuery(query, strategy.name));
        if (out.length >= maxCandidates) break;
      }
    }
    return out;
  }
}

class _PendingQuery {
  const _PendingQuery(this.query, this.strategy);
  final RouteQuery query;
  final String strategy;
}
