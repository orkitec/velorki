import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/painting.dart' show EdgeInsets, Size;
import 'package:velorki_geo/velorki_geo.dart';

/// The part of the map the rider can see.
///
/// A tab map fills the screen, but its top is under the search field, the
/// chips or the turn banner, its bottom under the sheet or the card, and a
/// strip at the right under the control column. A locate, a searched place
/// or a fitted route that lands in the middle of the *whole* map lands
/// under the sheet; these two functions put it in the middle of what is
/// visible instead.

/// The insets of the visible part of a [size] map: [topInset] is the safe
/// area, [chromeTop] how far the owning tab's chrome reaches below it,
/// [sheetExtent] the sheet's fraction of the height, [columnWidth] the
/// control column's width at the right, [margin] the air kept around a fit.
EdgeInsets visibleMapInsets({
  required Size size,
  required double topInset,
  required double chromeTop,
  required double sheetExtent,
  required double columnWidth,
  double margin = 24,
}) => EdgeInsets.fromLTRB(
  margin,
  topInset + chromeTop + margin,
  columnWidth + margin,
  sheetExtent.clamp(0.0, 1.0) * size.height + margin,
);

/// How far down the visible map a rider being followed heading-up sits, as
/// a share of its height: most of what shows is the road ahead, as on a
/// bike computer, and a strip behind is left to see where they came from.
const double followAheadShare = 0.7;

/// The least of the map, in logical pixels, worth placing a rider in with
/// room ahead; with less showing, the rider is centred in what there is.
const double followMinVisiblePx = 120;

/// The padding a follow move sends so the rider lands where they should in
/// a [size] map whose visible part runs from [top] down to [bottom] above
/// the bottom edge: [followAheadShare] of the way down it when the map
/// turns with them ([headingUp]), in its middle when north is up, since
/// ahead can then be any way. Horizontally the rider stays in the middle.
///
/// With less than [followMinVisiblePx] showing, the rider is centred in
/// what is visible, and never above [top]: under the chrome nobody sees
/// them.
EdgeInsets followPadding({
  required Size size,
  required double top,
  required double bottom,
  required bool headingUp,
}) {
  final visible = size.height - top - bottom;
  final share = !headingUp || visible < followMinVisiblePx
      ? 0.5
      : followAheadShare;
  final y = top + math.max(visible, 0) * share;
  // Where a padded move lands its target: the middle of what the padding
  // leaves. One side's padding is enough to put it at any height.
  final offset = 2 * y - size.height;
  return offset >= 0
      ? EdgeInsets.only(top: offset)
      : EdgeInsets.only(bottom: -offset);
}

/// The camera centre that puts [target] in the middle of the part of a
/// [size] map that [padding] leaves visible, at [zoom] with the map turned
/// by [bearing] degrees clockwise.
///
/// The visible middle is offset from the map's own middle by half the
/// difference of the opposite insets; the camera aims that far the other
/// way in the world, in Web Mercator pixels at the target zoom, so the
/// target ends up on the visible middle rather than under the sheet.
LatLng offsetCenter(
  LatLng target, {
  required Size size,
  required EdgeInsets padding,
  required double zoom,
  double bearing = 0,
}) {
  // Screen offset of the visible middle from the map's middle, y down.
  final dx = (padding.left - padding.right) / 2;
  final dy = (padding.top - padding.bottom) / 2;
  if (dx == 0 && dy == 0) return target;
  // A screen vector in world axes. The bearing is where the camera faces,
  // clockwise from north, so screen-up is that direction in the world and
  // every screen vector turns clockwise by it: at 90, up is east and down,
  // where the sheet is, west.
  final rad = bearing * math.pi / 180;
  final wx = dx * math.cos(rad) - dy * math.sin(rad);
  final wy = dx * math.sin(rad) + dy * math.cos(rad);
  final world = _worldSize(zoom);
  final x = _worldX(target.lon, world) - wx;
  final y = _worldY(target.lat, world) - wy;
  return LatLng(_latOf(y, world), _lonOf(x, world));
}

/// A camera that fits some bounds: where it aims and how far in.
@immutable
class FitCamera {
  const FitCamera({required this.center, required this.zoom});

  final LatLng center;
  final double zoom;

  @override
  bool operator ==(Object other) =>
      other is FitCamera && other.center == center && other.zoom == zoom;

  @override
  int get hashCode => Object.hash(center, zoom);

  @override
  String toString() => 'FitCamera($center, z$zoom)';
}

/// The camera that fits [bounds] into the part of a [size] map that
/// [padding] leaves visible: the zoom at which the bounds just fill that
/// rectangle (capped at [maxZoom], so a short route is not a wall of
/// buildings), aimed so the bounds' middle is the visible middle.
///
/// Computed here rather than asked of the map: MapLibre's bounds camera on
/// iOS spreads per-side padding evenly, which puts a route under the card.
FitCamera fitCamera(
  BoundingBox bounds, {
  required Size size,
  required EdgeInsets padding,
  double maxZoom = 18,
}) {
  final visibleW = math.max(1.0, size.width - padding.left - padding.right);
  final visibleH = math.max(1.0, size.height - padding.top - padding.bottom);
  // The bounds in world pixels at zoom 0, the east span wrapped when the
  // box crosses the antimeridian.
  const world0 = 512.0;
  var spanX = _worldX(bounds.east, world0) - _worldX(bounds.west, world0);
  if (spanX < 0) spanX += world0;
  final top = _worldY(bounds.north, world0);
  final spanY = _worldY(bounds.south, world0) - top;
  final zoomX = spanX <= 0 ? maxZoom : _log2(visibleW / spanX);
  final zoomY = spanY <= 0 ? maxZoom : _log2(visibleH / spanY);
  final zoom = math.min(zoomX, zoomY).clamp(0.0, maxZoom);
  // The middle in world pixels, not in degrees: Mercator stretches the
  // north, so the arithmetic middle of the latitudes sits too far south.
  final midX = _worldX(bounds.west, world0) + spanX / 2;
  final mid = LatLng(_latOf(top + spanY / 2, world0), _lonOf(midX, world0));
  return FitCamera(
    center: offsetCenter(mid, size: size, padding: padding, zoom: zoom),
    zoom: zoom,
  );
}

double _log2(double x) => math.log(x) / math.ln2;

/// MapLibre's world is 512 px wide at zoom 0 and doubles per zoom.
double _worldSize(double zoom) => 512 * math.pow(2, zoom).toDouble();

double _worldX(double lon, double world) => (lon + 180) / 360 * world;

double _worldY(double lat, double world) {
  final rad = lat.clamp(-85.05112878, 85.05112878) * math.pi / 180;
  final y = math.log(math.tan(rad) + 1 / math.cos(rad));
  return (1 - y / math.pi) / 2 * world;
}

double _lonOf(double x, double world) {
  final lon = x / world * 360 - 180;
  // The world wraps at the antimeridian.
  return ((lon + 180) % 360 + 360) % 360 - 180;
}

double _latOf(double y, double world) {
  final n = math.pi * (1 - 2 * y / world);
  return math.atan(_sinh(n)) * 180 / math.pi;
}

double _sinh(double x) => (math.exp(x) - math.exp(-x)) / 2;
