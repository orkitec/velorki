import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

import '../../../core/db/daos/routing_tiles_dao.dart';
import '../../../core/db/database.dart';
import '../domain/routing_tile.dart';
import 'brouter_storage.dart';

part 'routing_tiles_repository.g.dart';

/// The downloaded rd5 segment tiles: the `routing_tiles` rows and the files
/// under `<appSupport>/brouter/segments/` they describe.
///
/// [readyTiles] is deliberately synchronous — it is what
/// `CompositeRoutingBackend.localTiles` calls before every single route, so it
/// answers from a cache the repository keeps in step with the table.
class RoutingTilesRepository {
  /// Creates the repository over [dao] and [segmentsDir].
  RoutingTilesRepository({
    required RoutingTilesDao dao,
    required Directory segmentsDir,
  }) // Named parameters cannot be private, so these cannot be initialising
    // formals.
    // ignore: prefer_initializing_formals
    : _dao = dao,
       // ignore: prefer_initializing_formals
       _segmentsDir = segmentsDir;

  final RoutingTilesDao _dao;
  final Directory _segmentsDir;
  StreamSubscription<List<RoutingTile>>? _sub;
  List<RoutingTile> _cache = const <RoutingTile>[];

  /// Where the `.rd5` files live.
  Directory get segmentsDir => _segmentsDir;

  /// The file of [tile], whether or not it exists.
  File fileFor(TileName tile) => File(p.join(_segmentsDir.path, tile.fileName));

  /// Every known tile, updated as rows change.
  Stream<List<RoutingTile>> watch() => _dao.watchTiles().map(_toTiles);

  /// Every known tile, once.
  Future<List<RoutingTile>> tiles() async => _toTiles(await _dao.allTiles());

  /// The tiles last read from the table, without touching the database.
  List<RoutingTile> get cached => _cache;

  /// The tiles the on-device engine can route on right now.
  ///
  /// `stale` counts: the file is complete, the mirror simply has a newer
  /// build of it.
  Set<TileName> readyTiles() => <TileName>{
    for (final tile in _cache)
      if (tile.isUsable) tile.tile,
  };

  /// The rd5 format version recorded for each usable tile, for
  /// `CompositeRoutingBackend.localFormatVersions`.
  Map<TileName, String> formatVersions() => <TileName, String>{
    for (final tile in _cache)
      if (tile.isUsable) tile.tile: tile.formatVersion,
  };

  /// Bytes the usable tiles occupy.
  int get totalBytes => _cache
      .where((t) => t.isUsable)
      .fold<int>(0, (sum, tile) => sum + tile.bytes);

  /// Fills the cache and keeps it up to date.
  ///
  /// Called once by the provider; every later change arrives through the
  /// table's stream.
  Future<void> load() async {
    _cache = await tiles();
    _sub ??= watch().listen((tiles) => _cache = tiles);
  }

  /// Reconciles the table with the disk.
  ///
  /// A row whose file is gone (a reinstall, a cleaner, a failed download that
  /// never resumed) is dropped, and a `.rd5` on disk with no row is adopted so
  /// a tile copied onto the device by hand is used rather than downloaded
  /// again. Interrupted `downloading` rows without a file are dropped too;
  /// their `.part` survives and a retry resumes from it.
  Future<void> reconcile({SegmentsManifest? manifest}) async {
    if (!_segmentsDir.existsSync()) {
      await _segmentsDir.create(recursive: true);
    }
    final onDisk = <TileName, File>{};
    for (final entity in _segmentsDir.listSync(followLinks: true)) {
      if (entity is! File) continue;
      final tile = TileName.tryParse(p.basename(entity.path));
      if (tile != null && entity.path.toLowerCase().endsWith('.rd5')) {
        onDisk[tile] = entity;
      }
    }

    final known = <TileName>{};
    for (final row in await tiles()) {
      known.add(row.tile);
      final file = onDisk[row.tile];
      if (file == null) {
        await _dao.deleteTile(row.name);
      } else if (!row.isUsable) {
        await _dao.markReady(
          row.name,
          bytes: await file.length(),
          updatedAt: row.updatedAt,
          formatVersion: row.formatVersion,
        );
      }
    }
    for (final entry in onDisk.entries) {
      if (known.contains(entry.key)) continue;
      final fromManifest = manifest?[entry.key];
      await _dao.markReady(
        entry.key.name,
        bytes: await entry.value.length(),
        updatedAt: fromManifest?.updatedAt ?? DateTime.now().toUtc(),
        formatVersion:
            fromManifest?.formatVersion ?? manifest?.formatVersion ?? '',
      );
    }
    await load();
  }

  /// Records that [entry] is being downloaded.
  Future<void> markDownloading(SegmentEntry entry) async {
    await _dao.markDownloading(
      entry.tile.name,
      bytes: entry.bytes,
      updatedAt: entry.updatedAt ?? DateTime.now().toUtc(),
      formatVersion: entry.formatVersion ?? '',
    );
    await load();
  }

  /// Records a finished download of [entry]; [bytes] is the real file size.
  Future<void> markReady(SegmentEntry entry, {required int bytes}) async {
    await _dao.markReady(
      entry.tile.name,
      bytes: bytes,
      updatedAt: entry.updatedAt ?? DateTime.now().toUtc(),
      formatVersion: entry.formatVersion ?? '',
    );
    await load();
  }

  /// Drops the row of [tile] after a download failed, keeping any `.part` for
  /// the retry.
  Future<void> forgetFailed(TileName tile) async {
    final row = await _dao.tileByName(tile.name);
    if (row == null) return;
    if (row.state == RoutingTileState.downloading) {
      await _dao.deleteTile(tile.name);
    }
    await load();
  }

  /// Deletes the file and the row of [tile], and any interrupted `.part`.
  Future<void> delete(TileName tile) async {
    final file = fileFor(tile);
    if (file.existsSync()) await file.delete();
    final part = File('${file.path}.part');
    if (part.existsSync()) await part.delete();
    await _dao.deleteTile(tile.name);
    await load();
  }

  /// Marks every usable tile the mirror has rebuilt since it was downloaded
  /// as `stale`, and clears the mark again when it no longer applies.
  ///
  /// Returns the tiles that are now stale.
  Future<List<TileName>> applyManifest(SegmentsManifest manifest) async {
    final stale = <TileName>[];
    for (final tile in await tiles()) {
      if (!tile.isUsable) continue;
      final entry = manifest[tile.tile];
      final updatedAt = entry?.updatedAt;
      final outdated = updatedAt != null && updatedAt.isAfter(tile.updatedAt);
      if (outdated) stale.add(tile.tile);
      final wanted = outdated ? RoutingTileState.stale : RoutingTileState.ready;
      if (tile.state != wanted) await _dao.setState(tile.name, wanted);
    }
    await load();
    return stale;
  }

  /// Stops watching the table.
  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }

  List<RoutingTile> _toTiles(List<RoutingTileRow> rows) => <RoutingTile>[
    for (final row in rows)
      if (TileName.tryParse(row.name) != null) RoutingTile.fromRow(row),
  ];
}

/// The app's [RoutingTilesRepository], loaded and reconciled with the disk.
@Riverpod(keepAlive: true)
Future<RoutingTilesRepository> routingTilesRepository(Ref ref) async {
  final storage = await ref.watch(brouterStorageProvider.future);
  final repository = RoutingTilesRepository(
    dao: ref.watch(routingTilesDaoProvider),
    segmentsDir: storage.segments,
  );
  ref.onDispose(repository.dispose);
  await repository.reconcile();
  return repository;
}

/// Every known tile, as rows change.
@Riverpod(keepAlive: true)
Stream<List<RoutingTile>> routingTiles(Ref ref) async* {
  final repository = await ref.watch(routingTilesRepositoryProvider.future);
  yield* repository.watch();
}
