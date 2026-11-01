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
    this.contentSha256,
    this.gazetteerContentSha256,
  });

  /// Reads a database row.
  factory RoutingTile.fromRow(RoutingTileRow row) => RoutingTile(
    tile: TileName.parse(row.name),
    bytes: row.bytes,
    updatedAt: row.updatedAt,
    formatVersion: row.formatVersion,
    state: row.state,
    contentSha256: row.contentSha256,
    gazetteerContentSha256: row.gazetteerContentSha256,
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

  /// Digest of the rd5's content, or `null` while not known (a tile from an
  /// older version, until the backfill has read it).
  final String? contentSha256;

  /// The same for the tile's `.gaz`.
  final String? gazetteerContentSha256;

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

  /// Whether the mirror's [entry] holds something this copy lacks: a changed
  /// rd5 ([isRd5OutdatedBy]) or a changed gazetteer ([isGazetteerOutdatedBy]).
  bool isOutdatedBy(SegmentEntry? entry) =>
      isRd5OutdatedBy(entry) || isGazetteerOutdatedBy(entry);

  /// Whether the mirror's rd5 differs from this copy.
  ///
  /// The mirror rebuilds every tile every month, so its build date says
  /// nothing about whether the data changed: where the manifest carries a
  /// content digest and this copy's is known, they are compared and nothing
  /// else. A manifest digest against an unknown local one means the backfill
  /// has not read the file yet; it decides, so the date does not. Only a
  /// manifest without digests falls back to the date, as a mirror from before
  /// them is all there is to go by. A tile the manifest does not list, or
  /// lists without either, is left alone.
  bool isRd5OutdatedBy(SegmentEntry? entry) {
    if (entry == null) return false;
    final mirrorDigest = entry.contentSha256;
    if (mirrorDigest != null) {
      final own = contentSha256;
      return own != null && own != mirrorDigest;
    }
    final mirror = entry.updatedAt;
    return mirror != null && mirror.isAfter(updatedAt);
  }

  /// Whether the mirror's gazetteer differs from the one on the device.
  ///
  /// Only digests can say so; with either unknown there is nothing to go by
  /// and the gazetteer is left alone.
  bool isGazetteerOutdatedBy(SegmentEntry? entry) {
    final mirror = entry?.gazetteer?.contentSha256;
    final own = gazetteerContentSha256;
    return mirror != null && own != null && mirror != own;
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
    contentSha256: contentSha256,
    gazetteerContentSha256: gazetteerContentSha256,
  );

  @override
  bool operator ==(Object other) =>
      other is RoutingTile &&
      other.tile == tile &&
      other.bytes == bytes &&
      other.updatedAt == updatedAt &&
      other.formatVersion == formatVersion &&
      other.state == state &&
      other.contentSha256 == contentSha256 &&
      other.gazetteerContentSha256 == gazetteerContentSha256;

  @override
  int get hashCode => Object.hash(
    tile,
    bytes,
    updatedAt,
    formatVersion,
    state,
    contentSha256,
    gazetteerContentSha256,
  );

  @override
  String toString() => 'RoutingTile($name, $bytes B, ${state.name})';
}
