import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:velorki_brouter/velorki_brouter.dart' hide CancelToken;

import '../data/routing_tiles_repository.dart';
import '../data/tile_downloader.dart';

part 'tile_download_controller.g.dart';

/// What the download queue is doing.
@immutable
class TileDownloadQueueState {
  /// Creates the state.
  const TileDownloadQueueState({
    this.current,
    this.progress,
    this.queued = const <TileName>[],
    this.finished = const <TileName>[],
    this.failure,
  });

  /// The tile being downloaded, or `null` when the queue is idle.
  final TileName? current;

  /// How far [current] has got.
  final TileDownloadProgress? progress;

  /// Tiles waiting their turn, [current] excluded.
  final List<TileName> queued;

  /// Tiles this run has finished.
  final List<TileName> finished;

  /// The last failure, kept until the next run starts.
  final String? failure;

  /// Whether a download is running.
  bool get isRunning => current != null;

  /// Tiles still to go, including [current].
  int get remaining => queued.length + (current == null ? 0 : 1);

  /// This state with the given fields replaced.
  TileDownloadQueueState copyWith({
    TileName? current,
    bool clearCurrent = false,
    TileDownloadProgress? progress,
    bool clearProgress = false,
    List<TileName>? queued,
    List<TileName>? finished,
    String? failure,
    bool clearFailure = false,
  }) => TileDownloadQueueState(
    current: clearCurrent ? null : (current ?? this.current),
    progress: clearProgress ? null : (progress ?? this.progress),
    queued: queued ?? this.queued,
    finished: finished ?? this.finished,
    failure: clearFailure ? null : (failure ?? this.failure),
  );

  @override
  String toString() =>
      'TileDownloadQueueState(current: $current, queued: ${queued.length}, '
      'finished: ${finished.length}, failure: $failure)';
}

/// Downloads rd5 tiles one after another.
///
/// One at a time on purpose: the tiles are 125–250 MB each, and two parallel
/// downloads on a phone connection only make both slower and the progress bar
/// meaningless. A failure is recorded and the queue moves on to the next tile;
/// cancelling drops the whole queue and leaves the `.part` files for a resume.
@Riverpod(keepAlive: true)
class TileDownloadQueue extends _$TileDownloadQueue {
  final List<SegmentEntry> _queue = <SegmentEntry>[];
  CancelToken? _cancel;
  bool _running = false;
  bool _disposed = false;

  @override
  TileDownloadQueueState build() {
    ref.onDispose(() {
      _disposed = true;
      _cancel?.cancel('queue disposed');
      _queue.clear();
    });
    return const TileDownloadQueueState();
  }

  /// Adds [entries] to the queue and starts it if it is idle.
  ///
  /// Tiles already queued or already being downloaded are ignored, so tapping
  /// "Download" twice does not download twice.
  Future<void> enqueue(Iterable<SegmentEntry> entries) async {
    final known = <TileName>{
      ...state.queued,
      if (state.current != null) state.current!,
    };
    final added = <TileName>[];
    for (final entry in entries) {
      if (known.contains(entry.tile)) continue;
      known.add(entry.tile);
      _queue.add(entry);
      added.add(entry.tile);
    }
    if (added.isEmpty) return;
    state = state.copyWith(
      queued: <TileName>[...state.queued, ...added],
      clearFailure: true,
      finished: _running ? state.finished : const <TileName>[],
    );
    if (!_running) await _pump();
  }

  /// Stops the queue; the partly downloaded tile keeps its `.part`.
  void cancel() {
    _queue.clear();
    _cancel?.cancel('cancelled by the rider');
    state = state.copyWith(queued: const <TileName>[]);
  }

  Future<void> _pump() async {
    _running = true;
    final repository = await ref.read(routingTilesRepositoryProvider.future);
    final downloader = await ref.read(tileDownloaderProvider.future);
    StreamSubscription<TileDownloadProgress>? progress;
    try {
      while (_queue.isNotEmpty && !_disposed) {
        final entry = _queue.removeAt(0);
        final token = CancelToken();
        _cancel = token;
        state = state.copyWith(
          current: entry.tile,
          queued: <TileName>[
            for (final tile in state.queued)
              if (tile != entry.tile) tile,
          ],
          progress: TileDownloadProgress(
            tile: entry.tile,
            received: 0,
            total: entry.bytes,
          ),
        );
        await progress?.cancel();
        progress = downloader.progress
            .where((p) => p.tile == entry.tile)
            .listen((p) {
              if (!_disposed) state = state.copyWith(progress: p);
            });

        await repository.markDownloading(entry);
        try {
          final file = await downloader.download(entry, cancelToken: token);
          await _fetchGazetteer(downloader, entry, token);
          await repository.markReady(entry, bytes: await file.length());
          if (_disposed) return;
          state = state.copyWith(
            finished: <TileName>[...state.finished, entry.tile],
          );
        } on TileDownloadException catch (e) {
          await repository.forgetFailed(entry.tile);
          if (_disposed) return;
          if (e.kind == TileDownloadFailure.cancelled) {
            _queue.clear();
            break;
          }
          state = state.copyWith(failure: e.message);
        }
      }
    } finally {
      await progress?.cancel();
      _running = false;
      _cancel = null;
      if (!_disposed) {
        state = state.copyWith(clearCurrent: true, clearProgress: true);
      }
    }
  }

  /// Fetches [entry]'s offline gazetteer, when the mirror offers one.
  ///
  /// Runs after the rd5 has arrived and before the tile is marked ready, so
  /// that by the time the tiles list changes the `.gaz` is already there for
  /// `GazetteerStore` to pick up. A failure is only logged: the tile itself is
  /// complete and routable, and place search simply stays online for that
  /// area. Downloading the same (already ready) tile again retries it.
  Future<void> _fetchGazetteer(
    TileDownloader downloader,
    SegmentEntry entry,
    CancelToken token,
  ) async {
    final gazetteer = entry.gazetteer;
    if (gazetteer == null) return;
    try {
      await downloader.downloadGazetteer(gazetteer, cancelToken: token);
    } on TileDownloadException catch (e) {
      debugPrint('velorki: no offline search for ${entry.tile}: ${e.message}');
    }
  }
}
