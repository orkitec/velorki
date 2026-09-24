import '../../map/domain/map_controller.dart';
import '../../planner/presentation/poi_markers.dart';
import '../../planner/domain/route_poi.dart';
import '../application/route_cues.dart';

/// Draws the markers a cue sheet refers to and reports taps on them as
/// cue indices, so a screen with a [CueSheetList] wires the map once.
void showCuesOnMap(
  MapController map,
  List<RouteCue> cues, {
  required List<RoutePoi> pois,
  required void Function(int cueIndex) onCueTapped,
  int? selected,
}) {
  final chosen = selected == null || selected >= cues.length
      ? null
      : cues[selected];
  map.setPois(poiMarkers(pois, selected: chosen?.poiIndex));
  // The ends of the route, as the planner draws them: a route without a
  // visible start reads as a loop with no way in.
  final start = cues.firstWhere((c) => c.isStart, orElse: () => cues.first);
  final finish = cues.lastWhere((c) => c.isFinish, orElse: () => cues.last);
  map.setWaypoints(
    endMarkers(
      start: start.pos,
      finish: finish.pos,
      startSelected: chosen != null && chosen.isStart,
      finishSelected: chosen != null && chosen.isFinish,
    ),
  );
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

/// Takes the map to the cue at [index] and draws it as the chosen one, at
/// whatever zoom the rider has: reading a route is done at the zoom they
/// chose.
///
/// A cue that is a place or an end of the route is drawn chosen by the
/// marker itself, which keeps its icon and shows one name. A turn has only
/// a dot on the map and no name of its own, so that one is still pinned,
/// with the words the cue sheet uses for it.
Future<void> goToCue(
  MapController map,
  List<RouteCue> cues,
  int index, {
  required List<RoutePoi> pois,
  required void Function(int cueIndex) onCueTapped,
  String turnLabel = '',
}) async {
  if (index < 0 || index >= cues.length) return;
  final cue = cues[index];
  showCuesOnMap(
    map,
    cues,
    pois: pois,
    onCueTapped: onCueTapped,
    selected: index,
  );
  final isPoint = cue.poiIndex != null || cue.isStart || cue.isFinish;
  await map.setSearchPin(isPoint ? null : cue.pos, label: turnLabel);
  await map.moveTo(cue.pos);
}
