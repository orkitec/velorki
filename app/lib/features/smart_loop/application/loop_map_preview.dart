import 'package:velorki_geo/velorki_geo.dart';

import '../../map/domain/map_controller.dart';

/// Id of loop preview line [index] on the map.
///
/// The `loop-` prefix keeps these lines out of the planner's own namespace
/// (`main` and `alt-N`): `PlannerMapBinding` only removes the ids it drew
/// itself, so a preview survives a planner redraw and is cleared here instead.
String loopPreviewLineId(int index) => 'loop-$index';

/// Draws the loop candidates on the planner's map.
///
/// The smart-loop sheet owns no map. Rather than reaching into the planner —
/// whose `PlannerMapBinding` is private to its screen — the planner screen
/// hands its [MapController] to the sheet when it opens it, and the sheet
/// drives it through this one small object. That is the whole hook: three
/// methods, no state in the planner, nothing for the planner to undo.
class LoopMapPreview {
  /// Draws on [map]; a `null` map makes every call a no-op, which is what a
  /// widget test without a map and a sheet opened before the style finished
  /// loading both need.
  LoopMapPreview(this.map);

  /// The planner's map, or `null` when there is none.
  final MapController? map;

  int _drawn = 0;
  bool _fitted = false;

  /// Draws [lines], highlighting the one at [selected].
  ///
  /// The selected line is drawn last so it lies on top of the others. The
  /// camera is moved once, to the first loop that appears; after that the user
  /// stays in charge of the viewport.
  Future<void> previewRoutes(List<List<LatLng>> lines, int selected) async {
    final map = this.map;
    if (map == null) return;

    for (var i = 0; i < lines.length; i++) {
      if (i == selected || lines[i].isEmpty) continue;
      await map.setRouteLine(
        loopPreviewLineId(i),
        lines[i],
        style: RouteLineStyle.alternative,
      );
    }
    if (selected >= 0 &&
        selected < lines.length &&
        lines[selected].isNotEmpty) {
      await map.setRouteLine(loopPreviewLineId(selected), lines[selected]);
    }
    for (var i = lines.length; i < _drawn; i++) {
      await map.removeRouteLine(loopPreviewLineId(i));
    }
    _drawn = lines.length;

    if (_fitted || lines.isEmpty) return;
    final first = lines[selected.clamp(0, lines.length - 1)];
    if (first.isEmpty) return;
    _fitted = true;
    await map.fitBounds(BoundingBox.fromPoints(first));
  }

  /// Removes every preview line, e.g. when the sheet closes or its candidate
  /// has been handed to the planner.
  Future<void> clear() async {
    final map = this.map;
    if (map == null) return;
    for (var i = 0; i < _drawn; i++) {
      await map.removeRouteLine(loopPreviewLineId(i));
    }
    _drawn = 0;
    _fitted = false;
  }
}
