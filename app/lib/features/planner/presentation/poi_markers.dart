import 'package:velorki_geo/velorki_geo.dart';

import '../../map/domain/map_controller.dart';
import '../../navigation/presentation/turn_phrases.dart';
import '../domain/route_poi.dart';
import '../domain/waypoint.dart';

/// The one place that turns the app's points into the map's markers.
///
/// Four screens draw points — the planner, the route card, the ride card and
/// the import preview — and each used to decide for itself what a marker's
/// label and icon were. That is how the planner came to write a name across
/// a disc while the library wrote it above one. Both kinds of point are
/// built here, from the same icon table the sheet and the lists use, and the
/// map lays them out from [MarkerLayers].
///
/// What a marker carries is all this file decides; where it is drawn is the
/// style's business.

/// The route's points of interest as the map draws them.
///
/// The kind picks the marker's colour out of the four the style knows, and
/// carries the app's own icon for that kind along.
///
/// [selected] is the index of the one the rider has chosen, which the map
/// draws wider and in the chosen colour, icon and all.
List<MapPoi> poiMarkers(List<RoutePoi> pois, {int? selected}) => <MapPoi>[
  for (final (i, poi) in pois.indexed)
    MapPoi(
      position: poi.pos,
      name: poi.name,
      icon: poiIcon(poi.kind),
      selected: i == selected,
      kind: switch (poi.kind) {
        PoiKind.danger => MapPoiKind.danger,
        PoiKind.water => MapPoiKind.water,
        PoiKind.food => MapPoiKind.food,
        _ => MapPoiKind.generic,
      },
    ),
];

/// The points the route is routed through as the map draws them.
///
/// A point that stands for something wears that kind's icon on its disc and
/// carries its number in its name; a plain one keeps the number on the disc.
/// Which of the two it is comes down to whether the marker has an icon, so
/// the rule lives with the marker and the map only reads it — see
/// `waypointLabelText`.
///
/// A turn is a cue of the route rather than a place, and the cue sheet draws
/// it; on the map it is a plain numbered point like any other.
List<MapWaypoint> waypointMarkers(List<Waypoint> waypoints, {int? selected}) =>
    <MapWaypoint>[
      for (final (i, w) in waypoints.indexed)
        MapWaypoint(
          position: w.pos,
          kind: switch (w.kind) {
            WaypointKind.start => MapWaypointKind.start,
            WaypointKind.via => MapWaypointKind.via,
            WaypointKind.end => MapWaypointKind.end,
          },
          label: w.name,
          icon: w.poiKind == PoiKind.generic || w.poiKind == PoiKind.turn
              ? null
              : poiIcon(w.poiKind),
          selected: i == selected,
        ),
    ];

/// The two ends of a route that was not planned here, for a screen that
/// reads a route rather than edits it.
///
/// An imported route has no waypoints worth drawing, only a start and a
/// finish, and they are plain numbered points: built here so they are the
/// same markers the planner draws, not a second idea of one.
List<MapWaypoint> endMarkers({
  required LatLng start,
  required LatLng finish,
  bool startSelected = false,
  bool finishSelected = false,
}) => <MapWaypoint>[
  MapWaypoint(
    position: start,
    kind: MapWaypointKind.start,
    selected: startSelected,
  ),
  MapWaypoint(
    position: finish,
    kind: MapWaypointKind.end,
    selected: finishSelected,
  ),
];
