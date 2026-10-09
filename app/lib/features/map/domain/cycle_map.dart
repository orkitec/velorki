import 'package:flutter/foundation.dart';
import 'package:velorki_cycle_map/velorki_cycle_map.dart';

/// What the cycle map can show, each switched on and off in the Layers
/// sheet.
enum CycleMapPart {
  /// Cycleways, cycle streets, and lanes and tracks beside roads.
  infrastructure,

  /// Paths shared with walkers, and footways bikes may use.
  paths,

  /// One-ways open to bikes both ways.
  contraflow,

  /// International and national cycle routes.
  routesNational,

  /// Regional cycle routes.
  routesRegional,

  /// Local cycle routes.
  routesLocal,

  /// Unpaved and bumpy surfaces.
  surface,

  /// Gates, bollards and other barriers.
  barriers,
}

/// The parts shown until the rider picks their own.
const Set<CycleMapPart> defaultCycleMapParts = <CycleMapPart>{
  CycleMapPart.infrastructure,
  CycleMapPart.paths,
  CycleMapPart.contraflow,
  CycleMapPart.routesNational,
  CycleMapPart.routesRegional,
  CycleMapPart.routesLocal,
};

/// The zoom the cycle map is drawn from: closer than this a view is a
/// handful of the tiles' cells, farther it would be a region's worth.
const double cycleMapMinZoom = 13;

/// The [CycleContent] bits of [parts].
int cycleContentOf(Set<CycleMapPart> parts) {
  var bits = 0;
  for (final part in parts) {
    bits |= switch (part) {
      CycleMapPart.infrastructure => CycleContent.infrastructure,
      CycleMapPart.paths => CycleContent.paths,
      CycleMapPart.contraflow => CycleContent.contraflow,
      CycleMapPart.routesNational => CycleContent.routesNational,
      CycleMapPart.routesRegional => CycleContent.routesRegional,
      CycleMapPart.routesLocal => CycleContent.routesLocal,
      CycleMapPart.surface => CycleContent.surface,
      CycleMapPart.barriers => CycleContent.barriers,
    };
  }
  return bits;
}

/// What the Layers sheet says about the offline cycle map: whether it is
/// drawn, and which of its parts.
@immutable
class CycleMapSettings {
  /// Creates the preferences.
  const CycleMapSettings({
    this.shown = false,
    this.parts = defaultCycleMapParts,
  });

  /// Whether the cycle map is drawn at all.
  final bool shown;

  /// The parts drawn.
  final Set<CycleMapPart> parts;

  /// A copy with the named fields replaced.
  CycleMapSettings copyWith({bool? shown, Set<CycleMapPart>? parts}) =>
      CycleMapSettings(shown: shown ?? this.shown, parts: parts ?? this.parts);

  @override
  bool operator ==(Object other) =>
      other is CycleMapSettings &&
      other.shown == shown &&
      setEquals(other.parts, parts);

  @override
  int get hashCode => Object.hash(shown, Object.hashAllUnordered(parts));

  @override
  String toString() =>
      'CycleMapSettings(shown: $shown, parts: ${parts.map((p) => p.name)})';
}
