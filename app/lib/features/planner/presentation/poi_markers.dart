import '../../map/domain/map_controller.dart';
import '../domain/route_poi.dart';

/// The route's points of interest as the map draws them.
List<MapPoi> poiMarkers(List<RoutePoi> pois) => <MapPoi>[
  for (final poi in pois)
    MapPoi(
      position: poi.pos,
      name: poi.name,
      // The map style knows four icons; the rest wear the plain marker.
      kind: switch (poi.kind) {
        PoiKind.danger => MapPoiKind.danger,
        PoiKind.water => MapPoiKind.water,
        PoiKind.food => MapPoiKind.food,
        _ => MapPoiKind.generic,
      },
    ),
];
