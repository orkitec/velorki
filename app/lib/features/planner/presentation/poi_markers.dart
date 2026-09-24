import '../../map/domain/map_controller.dart';
import '../../navigation/presentation/turn_phrases.dart';
import '../domain/route_poi.dart';

/// The route's points of interest as the map draws them.
///
/// The kind picks the marker's colour out of the four the style knows, and
/// carries the app's own icon for that kind along: one icon table for the
/// sheet, the lists and the map.
List<MapPoi> poiMarkers(List<RoutePoi> pois) => <MapPoi>[
  for (final poi in pois)
    MapPoi(
      position: poi.pos,
      name: poi.name,
      icon: poiIcon(poi.kind),
      kind: switch (poi.kind) {
        PoiKind.danger => MapPoiKind.danger,
        PoiKind.water => MapPoiKind.water,
        PoiKind.food => MapPoiKind.food,
        _ => MapPoiKind.generic,
      },
    ),
];
