import 'dart:async';
import 'dart:io';

import 'package:brouter_dart/brouter_dart.dart' as br;
import 'package:brouter_dart/isolate.dart';

import 'brouter_http_backend.dart';
import 'brouter_query.dart';
import 'route_query.dart';
import 'route_result.dart';
import 'routing_backend.dart';
import 'routing_exception.dart';
import 'tiles.dart';

/// A [RoutingBackend] that routes on the device with `brouter_dart`.
///
/// It builds the very same parameters the server backend sends
/// ([buildQueryParams]), runs them through a [RoutingWorker] isolate, and
/// parses the isolate's GeoJSON with [BRouterHttpBackend.parseResponse], so a
/// [RouteResult] from here is indistinguishable from one from the server —
/// including its `messages` table and [RouteResult.surfaceStats].
///
/// ```dart
/// final local = LocalRoutingBackend(
///   segmentsDir: '${appSupport.path}/brouter/segments',
///   profilesDir: '${appSupport.path}/brouter/profiles',
/// );
/// final route = await local.route(query);     // spawns the isolate
/// await local.dispose();                      // kills it again
/// ```
///
/// **Coverage is not checked here.** BRouter treats a missing rd5 tile as
/// empty land, so routing with partial coverage silently returns a detour or
/// nothing at all. [CompositeRoutingBackend] is what decides whether the tiles
/// for a query are on disk; use it rather than this class directly.
class LocalRoutingBackend implements RoutingBackend {
  /// Creates an on-device backend.
  ///
  /// [segmentsDir] holds the `.rd5` tiles, [profilesDir] the `.brf` profiles
  /// and `lookups.dat` (they ship as app assets). [maxMemMb] is BRouter's
  /// `memoryclass`, the budget of the decoded micro-cache: 64 MB by default,
  /// 128 MB is what the plan gives devices with 6 GB or more. Pass a [worker]
  /// to share one isolate between backends — one you pass in is yours to
  /// [RoutingWorker.dispose], one spawned here is disposed by [dispose].
  LocalRoutingBackend({
    required this.segmentsDir,
    required this.profilesDir,
    this.maxMemMb = 64,
    RoutingWorker? worker,
    this.roundTripPoints,
    this.yieldInterval = 2000,
  }) : _worker = worker,
       _ownsWorker = worker == null;

  /// Directory holding the `.rd5` segment tiles.
  final String segmentsDir;

  /// Directory holding the `.brf` profiles and `lookups.dat`.
  final String profilesDir;

  /// BRouter's `memoryclass` in MB: the budget for decoded micro-caches.
  final int maxMemMb;

  /// How many waypoints BRouter should generate in round-trip mode (3..20);
  /// `null` leaves BRouter's default of 5, like the HTTP backend.
  final int? roundTripPoints;

  /// Node expansions between two yields of the engine — how often a
  /// [CancelToken] can take effect. See [RoutingWorker.yieldInterval].
  final int yieldInterval;

  RoutingWorker? _worker;
  final bool _ownsWorker;
  Future<RoutingWorker>? _spawning;
  Future<void> _turn = Future<void>.value();
  bool _disposed = false;

  /// The worker isolate, once one has been spawned.
  RoutingWorker? get worker => _worker;

  @override
  Future<RouteResult> route(RouteQuery q, {CancelToken? cancel}) async {
    if (_disposed) {
      throw const RoutingException(
        kind: RoutingErrorKind.invalid,
        message: 'LocalRoutingBackend is disposed',
      );
    }
    if (cancel != null && cancel.isCancelled) throw cancel.toException();

    final query = buildQueryString(q, roundTripPoints: roundTripPoints);
    final worker = await _ensureWorker();

    // One request at a time. The isolate serialises anyway, but
    // [RoutingWorker.cancel] always hits the request it is *running*, so
    // without this a planner cancelling one candidate could kill another.
    final previous = _turn;
    final gate = Completer<void>();
    _turn = gate.future;
    await previous;

    try {
      if (cancel != null && cancel.isCancelled) throw cancel.toException();
      return await _routeNow(worker, query, q.timeout, cancel);
    } finally {
      gate.complete();
    }
  }

  Future<RouteResult> _routeNow(
    RoutingWorker worker,
    String query,
    Duration? timeout,
    CancelToken? cancel,
  ) async {
    // Cancelling the token cancels the request in the isolate; the engine
    // notices at its next yield and the pending future fails.
    StreamSubscription<void>? cancelSub;
    Timer? deadline;
    if (cancel != null) {
      cancelSub = cancel.whenCancelled.asStream().listen(
        (_) => worker.cancel(),
      );
    }
    var timedOut = false;
    if (timeout != null) {
      deadline = Timer(timeout, () {
        timedOut = true;
        worker.cancel();
      });
    }

    String body;
    try {
      body = await worker.routeQuery(query);
    } on RoutingCancelledException {
      if (cancel != null && cancel.isCancelled) throw cancel.toException();
      if (timedOut) {
        throw RoutingException(
          kind: RoutingErrorKind.network,
          message:
              'on-device routing did not finish within ${timeout!.inSeconds} s',
        );
      }
      throw const RoutingException(
        kind: RoutingErrorKind.cancelled,
        message: 'cancelled',
      );
    } on br.RoutingException catch (e) {
      // The engine's own error text, the same one the server would send as a
      // plain-text body, so it is classified the same way.
      throw RoutingException(
        kind: classifyBRouterError(e.message),
        message: e.message,
        cause: e,
      );
    } on RoutingException {
      rethrow;
    } catch (e) {
      // StateError from the isolate (a broken profile, an unreadable tile) and
      // anything else unforeseen.
      throw RoutingException(
        kind: RoutingErrorKind.invalid,
        message: 'on-device routing failed: $e',
        cause: e,
      );
    } finally {
      deadline?.cancel();
      unawaited(cancelSub?.cancel());
    }

    if (cancel != null && cancel.isCancelled) throw cancel.toException();
    return BRouterHttpBackend.parseResponse(200, body);
  }

  /// The tiles present in [segmentsDir], as `E10_N45` names.
  ///
  /// Reads the directory synchronously (it holds at most ~1100 entries) and
  /// skips everything that is not a `.rd5` file with a BRouter tile name, so
  /// `manifest.json`, `.part` downloads and lock files are ignored. A missing
  /// directory yields the empty set.
  ///
  /// Pass it straight to [CompositeRoutingBackend]'s `localTiles`.
  Set<TileName> availableTiles() {
    final dir = Directory(segmentsDir);
    if (!dir.existsSync()) return <TileName>{};
    final out = <TileName>{};
    for (final entity in dir.listSync(followLinks: true)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.toLowerCase().endsWith('.rd5')) continue;
      final tile = TileName.tryParse(name);
      if (tile != null) out.add(tile);
    }
    return out;
  }

  /// Spawns the worker isolate on first use and reuses it afterwards.
  Future<RoutingWorker> _ensureWorker() {
    final existing = _worker;
    if (existing != null) return Future<RoutingWorker>.value(existing);
    return _spawning ??=
        RoutingWorker.spawn(
          segmentsDir: Directory(segmentsDir),
          profilesDir: Directory(profilesDir),
          memoryclass: maxMemMb,
          yieldInterval: yieldInterval,
        ).then((w) {
          _worker = w;
          _spawning = null;
          if (_disposed) unawaited(w.dispose());
          return w;
        });
  }

  /// Cancels whatever is running and kills the isolate, unless the worker was
  /// passed in. The backend cannot be used afterwards.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final pending = _spawning;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {
        // a worker that never came up needs no disposing
      }
    }
    final worker = _worker;
    _worker = null;
    if (worker != null && _ownsWorker) await worker.dispose();
  }

  @override
  String toString() =>
      'LocalRoutingBackend($segmentsDir, ${maxMemMb}MB, '
      '${_worker == null ? 'idle' : 'running'})';
}
