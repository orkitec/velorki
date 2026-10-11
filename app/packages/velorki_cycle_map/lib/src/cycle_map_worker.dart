import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'cycle_map_engine.dart';
import 'rd5_cell_reader.dart';

/// What makes cycle maps for the app: the [CycleMapWorker], or a fake.
abstract interface class CycleMapRenderer {
  /// The map for [request] for [client], or null when a newer request of
  /// the same client replaced it first.
  Future<CycleMapFile?> render(CycleMapRequest request, {Object client = 0});

  /// Drops [client]'s waiting request, if any.
  void release(Object client);

  /// Tells the renderer the downloaded tiles changed.
  void tilesChanged();
}

/// A cycle map written to a file for the map to load.
final class CycleMapFile {
  /// Creates the description of a written map.
  const CycleMapFile({required this.path, required this.result});

  /// The GeoJSON file.
  final String path;

  /// What was made; its `geojson` is empty here, the text is in the file.
  final CycleMapResult result;
}

/// The [CycleMapEngine] in its own isolate, so decoding tiles and writing
/// GeoJSON never take a frame from the app.
///
/// Each map is written to a new file in the output directory, which the
/// map loads itself: the text never crosses into the app's isolate. The two
/// newest files of each client are kept (a map shows one while it loads
/// the other).
///
/// Requests carry a client: one map on screen, say. Only a client's newest
/// view counts: a request made while another runs waits, and replaces the
/// same client's request already waiting, whose future completes with null.
/// Clients take turns.
final class CycleMapWorker implements CycleMapRenderer {
  CycleMapWorker._(this._isolate, this._replies) {
    _replies.listen((message) {
      final reply = _reply;
      _reply = null;
      reply?.complete(message);
    });
  }

  /// Starts a worker over the tiles in [segmentsDir], with the lookup table
  /// at [lookupsPath], keeping decoded cells under [cacheDir] and writing
  /// maps into [outputDir].
  static Future<CycleMapWorker> spawn({
    required String segmentsDir,
    required String lookupsPath,
    required String cacheDir,
    required String outputDir,
  }) async {
    final replies = ReceivePort();
    final isolate = await Isolate.spawn(_main, (
      replies.sendPort,
      segmentsDir,
      lookupsPath,
      cacheDir,
      outputDir,
    ), debugName: 'cycle map');
    final worker = CycleMapWorker._(isolate, replies);
    worker._commands = await worker._nextReply() as SendPort;
    return worker;
  }

  final Isolate _isolate;
  late final SendPort _commands;
  final ReceivePort _replies;
  Completer<Object?>? _reply;
  bool _running = false;
  final _waiting = <Object, (CycleMapRequest, Completer<CycleMapFile?>)>{};
  final _clientIds = <Object, int>{};
  int _nextClientId = 0;
  bool _disposed = false;

  @override
  Future<CycleMapFile?> render(CycleMapRequest request, {Object client = 0}) {
    if (_disposed) return Future.value();
    final completer = Completer<CycleMapFile?>();
    _waiting.remove(client)?.$2.complete(null);
    _waiting[client] = (request, completer);
    unawaited(_pump());
    return completer.future;
  }

  @override
  void release(Object client) {
    _waiting.remove(client)?.$2.complete(null);
    _clientIds.remove(client);
  }

  @override
  void tilesChanged() {
    if (!_disposed) _commands.send(const _TilesChanged());
  }

  int _clientId(Object client) =>
      client is int ? client : _clientIds[client] ??= 1 << 20 | _nextClientId++;

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (!_disposed && _waiting.isNotEmpty) {
        final client = _waiting.keys.first;
        final (request, completer) = _waiting.remove(client)!;
        final Object? reply;
        try {
          _commands.send((_clientId(client), request));
          reply = await _nextReply();
        } on Object catch (e) {
          completer.completeError(e);
          continue;
        }
        if (reply is CycleMapFile) {
          completer.complete(reply);
        } else if (_disposed) {
          completer.complete(null);
        } else {
          completer.completeError(reply ?? StateError('cycle map: no reply'));
        }
      }
    } finally {
      _running = false;
    }
  }

  Future<Object?> _nextReply() => (_reply = Completer<Object?>()).future;

  /// Stops the isolate.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final (_, completer) in _waiting.values) {
      completer.complete(null);
    }
    _waiting.clear();
    _commands.send(null);
    _isolate.kill(priority: Isolate.beforeNextEvent);
    _replies.close();
    _reply?.complete(null);
    _reply = null;
  }

  static void _main((SendPort, String, String, String, String) args) {
    final (replies, segmentsDir, lookupsPath, cacheDir, outputDir) = args;
    final commands = ReceivePort();
    replies.send(commands.sendPort);
    final engine = CycleMapEngine(
      reader: Rd5CellReader(File(lookupsPath).readAsLinesSync()),
      segmentsDir: Directory(segmentsDir),
      cacheDir: Directory(cacheDir),
    );
    final out = Directory(outputDir)..createSync(recursive: true);
    // Maps of an earlier run are no use; neither are stored cells of tiles
    // that are gone.
    for (final old in out.listSync()) {
      if (old is File && old.path.endsWith('.geojson')) {
        try {
          old.deleteSync();
        } on FileSystemException {
          // Overwritten never, deleted on the next start.
        }
      }
    }
    try {
      engine.pruneStore();
    } on FileSystemException {
      // Pruned on a later start.
    }
    var serial = 0;
    final written = <int, List<String>>{};
    commands.listen((message) {
      switch (message) {
        case null:
          engine.close();
          commands.close();
        case _TilesChanged():
          engine.tilesChanged();
        case (final int client, final CycleMapRequest request):
          try {
            final result = engine.render(request);
            final path = '${out.path}/cycle-map-$client-${serial++}.geojson';
            File(path).writeAsStringSync(result.geojson);
            final mine = written[client] ??= <String>[];
            mine.add(path);
            while (mine.length > 2) {
              try {
                File(mine.removeAt(0)).deleteSync();
              } on FileSystemException {
                // Already gone.
              }
            }
            replies.send(
              CycleMapFile(
                path: path,
                result: CycleMapResult(
                  geojson: '',
                  cells: result.cells,
                  cellsWithoutTile: result.cellsWithoutTile,
                  truncated: result.truncated,
                  decodedCells: result.decodedCells,
                ),
              ),
            );
          } on Object catch (e) {
            replies.send(StateError('cycle map: $e'));
          }
      }
    });
  }
}

final class _TilesChanged {
  const _TilesChanged();
}
