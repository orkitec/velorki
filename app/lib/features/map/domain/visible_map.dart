import 'dart:math' as math;

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
  // A screen vector in world axes: turning the map by the bearing turns
  // every screen direction back by the same amount.
  final rad = bearing * math.pi / 180;
  final wx = dx * math.cos(rad) + dy * math.sin(rad);
  final wy = -dx * math.sin(rad) + dy * math.cos(rad);
  final world = _worldSize(zoom);
  final x = _worldX(target.lon, world) - wx;
  final y = _worldY(target.lat, world) - wy;
  return LatLng(_latOf(y, world), _lonOf(x, world));
}

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
