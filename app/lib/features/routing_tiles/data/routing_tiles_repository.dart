import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:velorki_io/io.dart';

import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

import '../../../core/db/daos/routing_tiles_dao.dart';
import '../../../core/db/database.dart';
import '../domain/routing_tile.dart';
import 'brouter_storage.dart';
import 'content_digest.dart';

part 'routing_tiles_repository.g.dart';

/// The downloaded rd5 segment tiles: the `routing_tiles` rows and the files
/// under `<appSupport>/brouter/segments/` they describe.
///
/// [readyTiles] is deliberately synchronous — it is what
/// `CompositeRoutingBackend.localTiles` calls before every single route, so it
/// answers from a cache the repository keeps in step with the table.
class RoutingTilesRepository {
  /// Creates the repository over [dao], [segmentsDir] and [gazetteerDir].
  RoutingTilesRepository({
    required RoutingTilesDao dao,
    required Directory segmentsDir,
    required Directory gazetteerDir,
  }) // Named parameters cannot be private, so these cannot be initialising
    // formals.
    // ignore: prefer_initializing_formals
    : _dao = dao,
       // ignore: prefer_initializing_formals
       _segmentsDir = segmentsDir,
       // ignore: prefer_initializing_formals
       _gazetteerDir = gazetteerDir;

  final RoutingTilesDao _dao;
  final Directory _segmentsDir;
  final Directory _gazetteerDir;
  StreamSubscription<List<RoutingTile>>? _sub;
  List<RoutingTile> _cache = const <RoutingTile>[];

  /// Where the `.rd5` files live.
  Directory get segmentsDir => _segmentsDir;

  /// Where the `.gaz` offline gazetteers live.
  Directory get gazetteerDir => _gazetteerDir;

  /// The file of [tile], whether or not it exists.
  File fileFor(TileName tile) => File(p.join(_segmentsDir.path, tile.fileName));

  /// The gazetteer file of [tile], whether or not it exists.
  ///
  /// A tile is routable without it; it only decides whether place search for
  /// that area works offline.
  File gazetteerFileFor(TileName tile) =>
      File(p.join(_gazetteerDir.path, tile.gazetteerFileName));

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
  ///
  /// The entry's content digest is recorded with the tile, `null` when the
  /// mirror has none. The gazetteer's is recorded only when [gazetteerFetched]:
  /// otherwise the `.gaz` beside the tile is still the old one (or none), and
  /// its digest stays as it was.
  Future<void> markReady(
    SegmentEntry entry, {
    required int bytes,
    bool gazetteerFetched = false,
  }) async {
    await _dao.markReady(
      entry.tile.name,
      bytes: bytes,
      updatedAt: entry.updatedAt ?? DateTime.now().toUtc(),
      formatVersion: entry.formatVersion ?? '',
      contentSha256: Value(entry.contentSha256),
      gazetteerContentSha256: gazetteerFetched
          ? Value(entry.gazetteer?.contentSha256)
          : const Value.absent(),
    );
    await load();
  }

  /// Records that [entry]'s gazetteer was fetched on its own, and clears the
  /// tile's `stale` mark when that was all the mirror had newer.
  Future<void> markGazetteerFetched(SegmentEntry entry) async {
    await _dao.setGazetteerDigest(
      entry.tile.name,
      entry.gazetteer?.contentSha256,
    );
    final row = await _dao.tileByName(entry.tile.name);
    if (row != null) {
      final tile = RoutingTile.fromRow(row);
      // Only ever clears the mark: whether the rd5 is outdated is the
      // manifest's to say, not a gazetteer's arrival.
      if (tile.isStale && !tile.isOutdatedBy(entry)) {
        await _setStale(tile, false);
      }
    }
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

  /// Deletes the files and the row of [tile], and any interrupted `.part`.
  ///
  /// The tile's gazetteer goes with it: without the tile there is nothing to
  /// route on in that area, and a search index for it would only take up room.
  Future<void> delete(TileName tile) async {
    for (final file in <File>[fileFor(tile), gazetteerFileFor(tile)]) {
      if (file.existsSync()) await file.delete();
      final part = File('${file.path}.part');
      if (part.existsSync()) await part.delete();
    }
    await _dao.deleteTile(tile.name);
    await load();
  }

  /// Marks every usable tile whose content differs from the mirror's as
  /// `stale`, and clears the mark again when it no longer applies (see
  /// [RoutingTile.isOutdatedBy] for what counts).
  ///
  /// Returns the tiles that are now stale.
  Future<List<TileName>> applyManifest(SegmentsManifest manifest) async {
    final stale = <TileName>[];
    for (final tile in await tiles()) {
      if (!tile.isUsable) continue;
      final outdated = tile.isOutdatedBy(manifest[tile.tile]);
      if (outdated) stale.add(tile.tile);
      await _setStale(tile, outdated);
    }
    await load();
    return stale;
  }

  Future<void> _setStale(RoutingTile tile, bool outdated) async {
    final wanted = outdated ? RoutingTileState.stale : RoutingTileState.ready;
    if (tile.state != wanted) await _dao.setState(tile.name, wanted);
  }

  Future<void>? _backfill;

  /// Works out the content digests the device does not know yet, for the
  /// usable tiles whose [manifest] entry carries one: the digest of the rd5
  /// and of the `.gaz` beside it, read from the files, once. Then the
  /// manifest is applied again, since those digests are what decides.
  ///
  /// Meant to run in the background; a file that cannot be read keeps its
  /// digest unknown and is tried again with the next manifest. Runs one at a
  /// time: a call while another is running joins it.
  Future<void> backfillDigests(SegmentsManifest manifest) =>
      _backfill ??= _runBackfill(manifest).whenComplete(() => _backfill = null);

  Future<void> _runBackfill(SegmentsManifest manifest) async {
    var filled = false;
    for (final tile in await tiles()) {
      if (!tile.isUsable) continue;
      final entry = manifest[tile.tile];
      if (entry == null) continue;
      String? rd5;
      String? gaz;
      try {
        final file = fileFor(tile.tile);
        if (tile.contentSha256 == null &&
            entry.contentSha256 != null &&
            file.existsSync()) {
          rd5 = await rd5ContentDigest(file.path);
        }
        final gazFile = gazetteerFileFor(tile.tile);
        if (tile.gazetteerContentSha256 == null &&
            entry.gazetteer?.contentSha256 != null &&
            gazFile.existsSync()) {
          gaz = await gazetteerContentDigest(gazFile.path);
        }
      } on Object catch (e) {
        debugPrint('velorki: no content digest for ${tile.tile}: $e');
      }
      if (rd5 == null && gaz == null) continue;
      await _dao.fillDigests(
        tile.name,
        contentSha256: rd5,
        gazetteerContentSha256: gaz,
      );
      filled = true;
    }
    if (filled) await applyManifest(manifest);
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
    gazetteerDir: storage.gazetteer,
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
