/// A [RoutingWorker] runs the ported engine in its own isolate so that the UI
/// isolate stays responsive, with cooperative cancellation: the engine yields
/// to the worker's event loop every [RoutingWorker.yieldInterval] node
/// expansions (`RoutingEngine.yieldHook`), which is when a `cancel` message
/// can reach it (`RoutingEngine.terminate()`, the thread-priority watchdog
/// of upstream) and when progress is reported.
///
/// ```dart
/// final worker = await RoutingWorker.spawn(
///   segmentsDir: Directory('/data/segments4'),
///   profilesDir: Directory('/data/profiles'),
/// );
/// final result = await worker.route(RoutingRequest(
///   points: [LonLat(-16.86, 32.65), LonLat(-16.89, 32.65)],
///   profile: 'trekking',
/// ));
/// await worker.dispose();
/// ```
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'brouter_dart.dart';

/// Search progress: links expanded so far and the size of the open set.
class RoutingProgress {
  const RoutingProgress(this.linksProcessed, this.openSetSize);

  final int linksProcessed;
  final int openSetSize;

  @override
  String toString() =>
      'RoutingProgress($linksProcessed links, $openSetSize open)';
}

/// The request in progress was cancelled with [RoutingWorker.cancel].
class RoutingCancelledException implements Exception {
  @override
  String toString() => 'RoutingCancelledException';
}

class _Init {
  _Init(
    this.port,
    this.segmentsDir,
    this.profilesDir,
    this.memoryclass,
    this.yieldInterval,
    this.retainRawCache,
    this.rawCacheBytes,
  );

  final SendPort port;
  final String segmentsDir;
  final String profilesDir;
  final int memoryclass;
  final int yieldInterval;
  final bool retainRawCache;
  final int rawCacheBytes;
}

class RoutingWorker {
  RoutingWorker._(
    this._isolate,
    this._toWorker,
    this._fromWorker,
    this.yieldInterval,
  );

  final Isolate _isolate;
  final SendPort _toWorker;
  final ReceivePort _fromWorker;

  /// Node expansions between two yields of the engine.
  final int yieldInterval;

  int _nextId = 1;
  Future<void> _queue = Future<void>.value();
  final Map<int, Completer<String>> _pending = <int, Completer<String>>{};
  final Map<int, void Function(RoutingProgress)?> _progress =
      <int, void Function(RoutingProgress)?>{};
  int? _current;
  bool _disposed = false;

  /// `RoutingContext.memoryclass` (MB) for a normal and for a large device.
  static const int defaultMemoryclass = 64;
  static const int largeDeviceMemoryclass = 128;

  /// Starts the worker isolate.
  ///
  /// [memoryclass] is upstream's `maxmem` choice in MB (the node-graph
  /// budget of `NodesCache`; the server uses 128): by default 64, or 128
  /// when [largeDevice] is set (the plan's >= 6 GB devices); an explicit
  /// value wins. [rawCacheBytes] bounds the byte-level cell cache, which is
  /// released after every route unless [retainRawCache] is set.
  static Future<RoutingWorker> spawn({
    required Directory segmentsDir,
    required Directory profilesDir,
    int? memoryclass,
    bool largeDevice = false,
    int yieldInterval = 2000,
    bool retainRawCache = false,
    int rawCacheBytes = RawCellCache.defaultMaxBytes,
  }) async {
    final fromWorker = ReceivePort();
    final ready = Completer<SendPort>();
    late final RoutingWorker worker;
    fromWorker.listen((Object? message) {
      if (message is SendPort) {
        ready.complete(message);
        return;
      }
      worker._onMessage(message as Map<Object?, Object?>);
    });
    final isolate = await Isolate.spawn<_Init>(
      _workerMain,
      _Init(
        fromWorker.sendPort,
        segmentsDir.path,
        profilesDir.path,
        memoryclass ??
            (largeDevice ? largeDeviceMemoryclass : defaultMemoryclass),
        yieldInterval,
        retainRawCache,
        rawCacheBytes,
      ),
      debugName: 'brouter_dart RoutingWorker',
    );
    final toWorker = await ready.future;
    worker = RoutingWorker._(isolate, toWorker, fromWorker, yieldInterval);
    return worker;
  }

  /// Routes [request]; requests are processed one after the other.
  Future<RoutingResult> route(
    RoutingRequest request, {
    void Function(RoutingProgress progress)? onProgress,
  }) async {
    final body = await routeQuery(
      request.toQuery(),
      onProgress: onProgress,
      memoryclass: request.memoryclass,
    );
    return RoutingResult.parse(body);
  }

  /// Runs a server-style query string (see `BRouter.routeQuery`);
  /// [memoryclass] overrides the worker's for this request.
  Future<String> routeQuery(
    String query, {
    void Function(RoutingProgress progress)? onProgress,
    int? memoryclass,
  }) {
    if (_disposed) throw StateError('RoutingWorker is disposed');
    final id = _nextId++;
    final completer = Completer<String>();
    _pending[id] = completer;
    _progress[id] = onProgress;
    final previous = _queue;
    _queue = previous.then((_) async {
      if (_disposed) {
        _fail(id, RoutingCancelledException());
        return;
      }
      _current = id;
      _toWorker.send(<String, Object?>{
        'cmd': 'route',
        'id': id,
        'query': query,
        'memoryclass': memoryclass,
      });
      try {
        await completer.future;
      } catch (_) {
        // reported through the returned future
      } finally {
        if (_current == id) _current = null;
      }
    });
    return completer.future;
  }

  /// Cancels the request in progress (its future fails with
  /// [RoutingCancelledException]); a no-op when the worker is idle.
  void cancel() {
    final id = _current;
    if (id == null || _disposed) return;
    _toWorker.send(<String, Object?>{'cmd': 'cancel', 'id': id});
  }

  /// Cancels the request in progress and kills the isolate.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    cancel();
    for (final id in _pending.keys.toList()) {
      _fail(id, RoutingCancelledException());
    }
    _toWorker.send(const <String, Object?>{'cmd': 'dispose'});
    _fromWorker.close();
    _isolate.kill(priority: Isolate.beforeNextEvent);
  }

  void _fail(int id, Object error) {
    final c = _pending.remove(id);
    _progress.remove(id);
    if (c != null && !c.isCompleted) c.completeError(error);
  }

  void _onMessage(Map<Object?, Object?> m) {
    final id = m['id'] as int;
    switch (m['type']) {
      case 'progress':
        final p = _progress[id];
        if (p != null) p(RoutingProgress(m['links'] as int, m['open'] as int));
        break;
      case 'result':
        _progress.remove(id);
        final c = _pending.remove(id);
        if (c != null && !c.isCompleted) c.complete(m['body'] as String);
        break;
      case 'cancelled':
        _fail(id, RoutingCancelledException());
        break;
      case 'error':
        _fail(id, RoutingException(m['message'] as String));
        break;
      case 'failure':
        _fail(id, StateError(m['message'] as String));
        break;
    }
  }
}

void _workerMain(_Init init) {
  final port = ReceivePort();
  init.port.send(port.sendPort);
  final router =
      BRouter(
          segmentsDir: Directory(init.segmentsDir),
          profilesDir: Directory(init.profilesDir),
        )
        ..memoryclass = init.memoryclass
        ..yieldInterval = init.yieldInterval
        ..retainRawCache = init.retainRawCache
        ..rawCache = RawCellCache(maxBytes: init.rawCacheBytes);
  var cancelled = false;
  int? currentId;
  router.yieldHook = () => Future<void>.delayed(Duration.zero);
  router.progressListener = (links, open) {
    final id = currentId;
    if (id != null) {
      init.port.send(<String, Object?>{
        'type': 'progress',
        'id': id,
        'links': links,
        'open': open,
      });
    }
  };

  // A plain listener, not `await for`: that would pause the port while a
  // route is in progress and a `cancel` could never reach the engine.
  Future<void> route(int id, String query, int? memoryclass) async {
    currentId = id;
    cancelled = false;
    try {
      final body = await router.routeQuery(query, memoryclass: memoryclass);
      if (cancelled) {
        init.port.send(<String, Object?>{'type': 'cancelled', 'id': id});
      } else {
        init.port.send(<String, Object?>{
          'type': 'result',
          'id': id,
          'body': body,
        });
      }
    } on RoutingException catch (e) {
      init.port.send(<String, Object?>{
        'type': cancelled ? 'cancelled' : 'error',
        'id': id,
        'message': e.message,
      });
    } catch (e, st) {
      init.port.send(<String, Object?>{
        'type': 'failure',
        'id': id,
        'message': '$e\n$st',
      });
    } finally {
      currentId = null;
    }
  }

  port.listen((Object? message) {
    final m = message as Map<Object?, Object?>;
    switch (m['cmd']) {
      case 'route':
        unawaited(
          route(m['id'] as int, m['query'] as String, m['memoryclass'] as int?),
        );
        break;
      case 'cancel':
        if (currentId == m['id']) {
          cancelled = true;
          router.currentEngine?.terminate();
        }
        break;
      case 'dispose':
        port.close();
        break;
    }
  });
}
