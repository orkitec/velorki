import '../../map/domain/map_controller.dart';
import '../../planner/presentation/poi_markers.dart';
import '../../planner/domain/route_poi.dart';
import '../application/route_cues.dart';

/// Zoom the map goes to for a cue: a corner and the streets around it.
const double cueZoom = 16;

/// Draws the markers a cue sheet refers to and reports taps on them as
/// cue indices, so a screen with a [CueSheetList] wires the map once.
void showCuesOnMap(
  MapController map,
  List<RouteCue> cues, {
  required List<RoutePoi> pois,
  required void Function(int cueIndex) onCueTapped,
}) {
  map.setPois(poiMarkers(pois));
  // The ends of the route, as the planner draws them: a route without a
  // visible start reads as a loop with no way in.
  final start = cues.firstWhere((c) => c.isStart, orElse: () => cues.first);
  final finish = cues.lastWhere((c) => c.isFinish, orElse: () => cues.last);
  map.setWaypoints(<MapWaypoint>[
    MapWaypoint(position: start.pos, kind: MapWaypointKind.start),
    MapWaypoint(position: finish.pos, kind: MapWaypointKind.end),
  ]);
  map.setTurnMarkers(<MapTurnMarker>[
    for (final cue in cues)
      if (cue.turnIndex != null) MapTurnMarker(position: cue.pos),
  ]);
  // The turn markers are the cues with a turn, in cue order, so the marker
  // index maps back through that same order.
  final turnCues = <int>[
    for (var i = 0; i < cues.length; i++)
      if (cues[i].turnIndex != null) i,
  ];
  map.onTurnTapped = (index) {
    if (index < turnCues.length) onCueTapped(turnCues[index]);
  };
  map.onPoiTapped = (index) {
    final cue = cues.indexWhere((c) => c.poiIndex == index);
    if (cue >= 0) onCueTapped(cue);
  };
}

/// Takes the map to [cue] and pins it with its name.
Future<void> goToCue(MapController map, RouteCue cue, String label) async {
  await map.setSearchPin(cue.pos, label: label);
  await map.moveTo(cue.pos, zoom: cueZoom);
}
