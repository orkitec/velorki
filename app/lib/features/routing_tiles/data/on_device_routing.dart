import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

import '../domain/routing_tile.dart';
import 'brouter_assets.dart';
import 'rd5_format_support.dart';
import 'routing_tiles_repository.dart';

part 'on_device_routing.g.dart';

/// Everything `LocalRoutingBackend` needs, once the profiles are copied and
/// the tile table has been read.
@immutable
class OnDeviceRouting {
  /// Creates the description.
  const OnDeviceRouting({
    required this.segmentsDir,
    required this.profilesDir,
    required this.readyTiles,
    required this.formatVersions,
  });

  /// Directory holding the `.rd5` tiles.
  final String segmentsDir;

  /// Directory holding the `.brf` profiles and `lookups.dat`.
  final String profilesDir;

  /// The tiles that are complete on disk.
  final Set<TileName> readyTiles;

  /// The rd5 format version recorded for each of [readyTiles].
  final Map<TileName, String> formatVersions;

  /// Whether there is at least one tile to route on.
  bool get hasTiles => readyTiles.isNotEmpty;

  @override
  String toString() => 'OnDeviceRouting(${readyTiles.length} tiles)';
}

/// The on-device routing setup, rebuilt whenever a tile is added or removed.
@Riverpod(keepAlive: true)
Future<OnDeviceRouting> onDeviceRouting(Ref ref) async {
  final profiles = await ref.watch(brouterProfilesProvider.future);
  final repository = await ref.watch(routingTilesRepositoryProvider.future);
  final tiles = await ref.watch(routingTilesProvider.future);
  final supported = await ref.watch(supportedRd5FormatProvider.future);
  // A tile in a format newer than the bundled lookup table is left out: the
  // engine could not decode its tags. The tiles screen says why.
  final readable = <RoutingTile>[
    for (final tile in tiles)
      if (tile.isUsable &&
          (supported?.canReadVersion(tile.formatVersion) ?? true))
        tile,
  ];
  return OnDeviceRouting(
    segmentsDir: repository.segmentsDir.path,
    profilesDir: profiles.path,
    readyTiles: <TileName>{for (final tile in readable) tile.tile},
    formatVersions: <TileName, String>{
      for (final tile in readable) tile.tile: tile.formatVersion,
    },
  );
}
