import 'dart:async';
import 'dart:math' as math;

import 'package:velorki_brouter/velorki_brouter.dart';

import 'loop_request.dart';
import 'quality.dart';
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
    required this.quality,
    this.farFromTarget = false,
  });

  /// The query that produced [result].
  final RouteQuery query;

  /// The routed geometry and its statistics.
  final RouteResult result;

  /// How good it is; lower [LoopScore.total] is better.
  final LoopScore score;

  /// Which [CandidateStrategy] proposed it.
  final String strategy;

  /// What the geometry is made of: beeline metres and repeated metres. The
  /// planner's [LoopFilter] has already accepted this one.
  final LoopQuality quality;

  /// Whether this one misses the requested distance by more than
  /// [LoopFilter.maxLengthError] and is only being shown because the planner
  /// spent its whole retry budget without finding anything closer.
  ///
  /// The planner never emits one of these while it still has a loop at the
  /// right distance to offer, so a `true` here says "this is the best that
  /// was reachable", which is worth a line in the log.
  final bool farFromTarget;

  @override
  String toString() =>
      'LoopCandidate($strategy, '
      '${(result.lengthM / 1000).toStringAsFixed(1)} km, '
      'score ${score.total.toStringAsFixed(3)}'
      '${farFromTarget ? ', far from the target' : ''})';
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
    this.filter = const LoopFilter(),
    this.maxRetries = 3,
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

  /// What a routed candidate has to look like to count as a loop at all.
  final LoopFilter filter;

  /// How often a query that failed to route, came back as something the
  /// [filter] rejected, or answered too far from the requested distance
  /// ([LoopFilter.tooFarFromTarget]), is tried again with a rotated bearing
  /// and a corrected radius ([retryQuery]). Zero switches retrying off.
  ///
  /// The first rotation is always tried. Past that a strategy only keeps
  /// turning the wheel while it has produced **nothing** — a coastal start
  /// where every invented bearing runs into the sea needs three rotations to
  /// find land, and a strategy that already has a loop to show does not need
  /// to spend the deadline on more.
  final int maxRetries;

  /// Routes and scores candidates and returns the best [topN], best first.
  ///
  /// Queries that fail to route are skipped, so a partial network or an
  /// unroutable direction degrades the result instead of breaking it, and so
  /// are results the [filter] does not consider loops. Either is retried with
  /// a rotated bearing, and a strategy that has produced nothing at all keeps
  /// rotating up to [maxRetries] times. Returns an empty list when nothing
  /// routed.
  ///
  /// A loop that routed fine but missed the requested distance by more than
  /// [LoopFilter.maxLengthError] is held back rather than skipped: the same
  /// query is asked again with the radius corrected towards the target, and
  /// the held candidate is only shown once the retries are spent and nothing
  /// nearer the target came back — so the answer is never empty when
  /// something routed and passed the [filter].
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

    final accepted = <String, int>{};
    // Loops that are real loops but the wrong length: kept aside in case the
    // retries find nothing better.
    final held = <LoopCandidate>[];
    var shown = 0;

    // Queues another attempt at an entry, with the bearing rotated and the
    // radius corrected by what the result (when there is one) came back as.
    void retry(_PendingQuery entry, RouteResult? result) {
      if (entry.attempt >= maxRetries || cancel.isCancelled) return;
      // Everything gets one rotation; only a strategy with nothing to show
      // keeps going, since by then its own queries have all been answered.
      if (entry.attempt >= 1 && (accepted[entry.strategy] ?? 0) > 0) return;
      final again = retryQuery(request, entry.query, result: result);
      if (again == null) return;
      pending.add(
        _PendingQuery(again, entry.strategy, attempt: entry.attempt + 1),
      );
    }

    Future<void> worker() async {
      while (!cancel.isCancelled) {
        final i = next++;
        if (i >= pending.length) return;
        final entry = pending[i];
        try {
          final result = await backend.route(entry.query, cancel: cancel);
          if (out.isClosed) return;
          final quality = LoopQuality.of(
            result,
            waypoints: syntheticPoints(request, entry.query),
          );
          final rejected = filter.reject(
            quality,
            ridesBackTheSameWay: entry.query.allowSameWayBack,
          );
          if (rejected != null) {
            // Not a loop: a beeline over water, the same road twice, or a
            // waypoint the engine had to snap somewhere else entirely. Ask
            // again in another direction rather than offering the rider this.
            retry(entry, result);
            continue;
          }
          final tooFar = filter.tooFarFromTarget(
            quality,
            targetM: request.targetM,
          );
          final candidate = LoopCandidate(
            query: entry.query,
            result: result,
            score: scorer.score(result, targetM: request.targetM),
            strategy: entry.strategy,
            quality: quality,
            farFromTarget: tooFar != null,
          );
          if (tooFar != null) {
            // A loop, but not the distance that was asked for: a 30 km
            // request answered with 38 km. Hold it as a fallback and spend
            // the retry on the same query with the radius scaled by
            // target / length, which is what lands on the right ring.
            held.add(candidate);
            retry(entry, result);
            continue;
          }
          accepted[entry.strategy] = (accepted[entry.strategy] ?? 0) + 1;
          shown++;
          out.add(candidate);
        } on RoutingException catch (e) {
          // A candidate that does not route is simply not a candidate — but a
          // direction with no road in it is worth one more try, rotated.
          if (e.kind == RoutingErrorKind.noRoute) retry(entry, null);
        } catch (_) {
          // Neither is one whose answer we cannot make sense of.
        }
      }
    }

    final workers = math.max(1, math.min(concurrency, pending.length));
    await Future.wait(List.generate(workers, (_) => worker()));

    // Every retry is spent and nothing came back at the distance that was
    // asked for, so the held loops are all there is. Show them, best first:
    // a 38 km answer to a 30 km request is worse than a 30.7 km one and
    // better than an empty sheet.
    if (shown == 0 && held.isNotEmpty && !out.isClosed) {
      held.sort((a, b) => a.score.total.compareTo(b.score.total));
      for (final candidate in held) {
        out.add(candidate);
      }
    }

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
  const _PendingQuery(this.query, this.strategy, {this.attempt = 0});
  final RouteQuery query;
  final String strategy;

  /// 0 for a query a strategy proposed, 1 for its first retry.
  final int attempt;
}
