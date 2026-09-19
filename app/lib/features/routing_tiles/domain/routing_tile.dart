import 'package:flutter/foundation.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

import '../../../core/db/database.dart';

/// One rd5 segment tile as the app knows it: the `routing_tiles` row with its
/// name parsed into a [TileName].
@immutable
class RoutingTile {
  /// Creates a tile record.
  const RoutingTile({
    required this.tile,
    required this.bytes,
    required this.updatedAt,
    required this.formatVersion,
    required this.state,
  });

  /// Reads a database row.
  factory RoutingTile.fromRow(RoutingTileRow row) => RoutingTile(
    tile: TileName.parse(row.name),
    bytes: row.bytes,
    updatedAt: row.updatedAt,
    formatVersion: row.formatVersion,
    state: row.state,
  );

  /// Which 5° × 5° tile this is.
  final TileName tile;

  /// Size on disk, or the size the manifest promises while downloading.
  final int bytes;

  /// When the mirror last rebuilt this tile.
  final DateTime updatedAt;

  /// The rd5 format version the mirror declared for it.
  final String formatVersion;

  /// Where the tile is in its life cycle.
  final RoutingTileState state;

  /// `E10_N45`.
  String get name => tile.name;

  /// Whether the file is on disk and the engine may read it.
  ///
  /// A `stale` tile is complete and usable; it only means the mirror has a
  /// newer build of it.
  bool get isUsable =>
      state == RoutingTileState.ready || state == RoutingTileState.stale;

  /// Whether a newer build is on the mirror.
  bool get isStale => state == RoutingTileState.stale;

  /// Whether the mirror's [entry] is a newer build than this copy.
  ///
  /// The mirror's build date is the only field that can say so: a rebuilt tile
  /// keeps its name, and its size may well come out the same. A tile the
  /// manifest does not list any more, or lists without a date, is left alone —
  /// there is nothing newer to fetch.
  bool isOutdatedBy(SegmentEntry? entry) {
    final mirror = entry?.updatedAt;
    return mirror != null && mirror.isAfter(updatedAt);
  }

  /// Whether a download is running for this tile.
  bool get isDownloading => state == RoutingTileState.downloading;

  /// This tile with another [state].
  RoutingTile copyWith({RoutingTileState? state}) => RoutingTile(
    tile: tile,
    bytes: bytes,
    updatedAt: updatedAt,
    formatVersion: formatVersion,
    state: state ?? this.state,
  );

  @override
  bool operator ==(Object other) =>
      other is RoutingTile &&
      other.tile == tile &&
      other.bytes == bytes &&
      other.updatedAt == updatedAt &&
      other.formatVersion == formatVersion &&
      other.state == state;

  @override
  int get hashCode => Object.hash(tile, bytes, updatedAt, formatVersion, state);

  @override
  String toString() => 'RoutingTile($name, $bytes B, ${state.name})';
}
