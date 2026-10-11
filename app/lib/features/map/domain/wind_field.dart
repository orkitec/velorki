import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'weather_map.dart';

// The wind layer: the DWD's global ICON model, its 10 m wind as the u (east)
// and v (north) components on a 0.25° grid, asked for one box of the view at
// a time as a plain-text grid (a WCS GetCoverage, see [dwdWind]) and drawn as
// our own arrows: points evenly spaced on the screen, each the wind
// interpolated there, pointing where the wind blows to, coloured and sized by
// its speed.

/// How far apart the arrows are on the screen, in logical pixels, about:
/// the spacing is worked out for the zoom rounded down to a half, so it
/// runs from this to some 1.4 times it.
const double windArrowSpacingPx = 70;

/// The model's own grid, in degrees.
const double windGridStep = 0.25;

/// How far the box asked for reaches beyond the view on each side, as a
/// share of the view's width and height.
const double windAreaMargin = 0.25;

/// The latitude the box asked for is clipped to.
const double windMaxLat = 85;

/// The speeds, in m/s, at which an arrow moves up a class: calm below the
/// first, light, moderate, fresh, and strong from the last on.
const List<double> windSpeedClasses = <double>[2, 5, 8, 11];

/// The most arrows drawn at once: a guard, far above what a phone's view
/// holds at [windArrowSpacingPx].
const int windMaxArrows = 4000;

/// The wind (u east, v north, in m/s) as where it blows to, in degrees
/// clockwise from north, and its speed in m/s.
({double dir, double ms}) windDirectionSpeed(double u, double v) {
  final ms = math.sqrt(u * u + v * v);
  var dir = math.atan2(u, v) * 180 / math.pi;
  if (dir < 0) dir += 360;
  if (dir >= 360) dir -= 360;
  return (dir: dir, ms: ms);
}

/// The class of a wind of [ms] m/s: 0 calm, 1 light, 2 moderate, 3 fresh,
/// 4 strong (see [windSpeedClasses]).
int windSpeedClass(double ms) {
  var i = 0;
  while (i < windSpeedClasses.length && ms >= windSpeedClasses[i]) {
    i++;
  }
  return i;
}

/// The zoom the arrows are spaced for: [zoom] rounded down to a half, so a
/// small zoom does not move every arrow.
double windSpacingZoom(double zoom) => (zoom * 2).floorToDouble() / 2;

/// How many Web Mercator metres apart the arrows are at [zoom]: on
/// MapLibre's 512-pixel tiles, [windArrowSpacingPx] at [windSpacingZoom].
double windArrowSpacingMetres(double zoom) =>
    windArrowSpacingPx *
    2 *
    _origin /
    (512 * math.pow(2, windSpacingZoom(zoom)).toDouble());

/// How many of the model's cells one cell of the grid asked for at [zoom]
/// spans: 1 zoomed in, more zoomed out, where the arrows lie several cells
/// apart and the cells between them would only be thrown away. A power of
/// two, with at least two cells of the grid between neighbouring arrows.
int windThinning(double zoom) {
  final metres = windArrowSpacingMetres(zoom);
  // A degree of longitude in Web Mercator metres.
  final degrees = metres / (2 * _origin / 360);
  final cells = degrees / 2 / windGridStep;
  var k = 1;
  while (k * 2 <= cells) {
    k *= 2;
  }
  return k;
}

const double _origin = 20037508.342789244;

/// One request for the wind of a box: [box] (west may lie east of 180°
/// for a view across the antimeridian: the service wraps), on a grid
/// [thinning] model cells a step, and the [area] it serves: the view and
/// its margin.
@immutable
class WindRequest {
  /// Creates the request.
  const WindRequest({
    required this.box,
    required this.thinning,
    required this.area,
  });

  /// The box asked for, in degrees, its edges on the grid; [box.east] may
  /// be over 180.
  final BoundingBox box;

  /// Model cells per step of the grid asked for.
  final int thinning;

  /// The view and its margin, which the box covers; its east may be over
  /// 180 like the box's.
  final BoundingBox area;

  /// The grid's step, in degrees.
  double get step => windGridStep * thinning;

  /// How many columns and rows the grid asked for has: the box at [step],
  /// both ends in.
  int get columns => ((box.east - box.west) / step).round() + 1;
  int get rows => ((box.north - box.south) / step).round() + 1;

  /// What names this request in the cache: its box and its step.
  String get key {
    String f(double v) => v.toStringAsFixed(2);
    return '${f(box.west)}_${f(box.south)}_${f(box.east)}_${f(box.north)}'
        '_$thinning';
  }

  /// The request's URL from [source]'s template at [frame]: `{west}`,
  /// `{south}`, `{east}`, `{north}` and `{time}` filled in, and where the
  /// grid is thinned the size the service is to scale it to.
  String url(WeatherMapSource source, WeatherFrame frame) {
    String f(double v) => v.toStringAsFixed(3);
    final time = frame.time;
    final base = source.urlTemplate
        .replaceAll('{west}', f(box.west))
        .replaceAll('{south}', f(box.south))
        .replaceAll('{east}', f(box.east))
        .replaceAll('{north}', f(box.north))
        .replaceAll('{time}', time == null ? '' : formatWeatherTime(time));
    if (thinning <= 1) return base;
    return '$base&scalesize=i($columns),j($rows)';
  }

  /// Whether the grid of this request still serves [view] at [zoom]: the
  /// same thinning, and the view inside [area].
  bool fits(BoundingBox view, double zoom) {
    if (windThinning(zoom) != thinning) return false;
    final (west, east) = _unwrap(view);
    return west >= area.west - 1e-9 &&
        east <= area.east + 1e-9 &&
        view.south >= area.south - 1e-9 &&
        view.north <= area.north + 1e-9;
  }

  @override
  bool operator ==(Object other) =>
      other is WindRequest && other.key == key && other.area == area;

  @override
  int get hashCode => Object.hash(key, area);

  @override
  String toString() => 'WindRequest($key)';
}

/// [view]'s west and east, the east past 180° where the view runs across
/// the antimeridian (its west east of its east).
(double, double) _unwrap(BoundingBox view) => view.west <= view.east
    ? (view.west, view.east)
    : (view.west, view.east + 360);

/// The request for the wind of [view] at [zoom]: the view and
/// [windAreaMargin] around it, its latitude within ±[windMaxLat], its
/// longitude within a turn of the globe from -180° on, the edges put on a
/// grid of eight steps outward (so a small pan asks for the same box and
/// finds it in the cache) and one step more, so the edges of the view
/// have grid points beyond them. `null` below [weatherImageMinZoom], where
/// the view is a large part of the world.
///
/// A view across the antimeridian is one box whose east is over 180°: the
/// service wraps around, so it is still one request.
WindRequest? windRequestFor(BoundingBox view, double zoom) {
  if (zoom < weatherImageMinZoom) return null;
  final edges = <double>[view.west, view.south, view.east, view.north];
  if (edges.any((v) => !v.isFinite)) return null;
  var (west, east) = _unwrap(view);
  final dx = (east - west) * windAreaMargin;
  final dy = (view.north - view.south) * windAreaMargin;
  var area = BoundingBox(
    south: math.max(-windMaxLat, view.south - dy),
    west: west - dx,
    north: math.min(windMaxLat, view.north + dy),
    east: east + dx,
  );
  if (area.west < -180) {
    area = BoundingBox(
      south: area.south,
      west: -180,
      north: area.north,
      east: area.east,
    );
  }
  if (area.east - area.west > 360) {
    area = BoundingBox(
      south: area.south,
      west: area.west,
      north: area.north,
      east: area.west + 360,
    );
  }
  if (area.south >= area.north || area.west >= area.east) return null;
  final thinning = windThinning(zoom);
  final step = windGridStep * thinning;
  final snap = step * 8;
  double down(double v) => (v / snap).floorToDouble() * snap - step;
  double up(double v) => (v / snap).ceilToDouble() * snap + step;
  west = math.max(-180.0, down(area.west));
  east = math.min(west + 360, up(area.east));
  final box = BoundingBox(
    south: math.max(-windMaxLat, down(area.south)),
    west: west,
    north: math.min(windMaxLat, up(area.north)),
    east: east,
  );
  return WindRequest(box: box, thinning: thinning, area: area);
}

/// The wind's moment for the time control's step [offsetMinutes] from
/// [now]: the hour that moment falls in, the model's frames being hourly
/// for days ahead. Clamped to the hour of [now] and [forecastMinutes]
/// beyond it.
DateTime windFrameTime(
  DateTime now,
  int offsetMinutes, {
  int forecastMinutes = 24 * 60,
}) {
  const hour = Duration.millisecondsPerHour;
  final nowMs = now.toUtc().millisecondsSinceEpoch;
  final first = nowMs - nowMs % hour;
  final last = first + (forecastMinutes ~/ 60) * hour;
  final at = nowMs + offsetMinutes * Duration.millisecondsPerMinute;
  final wanted = (at - at % hour).clamp(first, last);
  return DateTime.fromMillisecondsSinceEpoch(wanted, isUtc: true);
}

/// The wind on a regular grid, as the service sent it: [columns] × [rows]
/// points, the first at [lon0]/[lat0] (a cell's middle), [lonStep] east and
/// [latStep] (negative: rows run south) apart; [u] and [v] in m/s, row by
/// row from the north, NaN where the model has none.
class WindGrid {
  /// Creates the grid.
  WindGrid({
    required this.lon0,
    required this.lat0,
    required this.lonStep,
    required this.latStep,
    required this.columns,
    required this.rows,
    required this.u,
    required this.v,
  }) : assert(u.length == columns * rows && v.length == columns * rows);

  final double lon0;
  final double lat0;
  final double lonStep;
  final double latStep;
  final int columns;
  final int rows;
  final Float32List u;
  final Float32List v;

  /// The wind (u, v) at [lat]/[lon], interpolated between the four grid
  /// points around it, a point without a value left out and the others
  /// weighed up (on a point without one, the four alike); `null` outside
  /// the grid or where none of the four has one. A [lon] west of the grid is taken a turn further east, for a
  /// grid across the antimeridian.
  (double, double)? sample(double lat, double lon) {
    if (columns < 1 || rows < 1) return null;
    var x = (lon - lon0) / lonStep;
    if (x < -1e-9 && lonStep > 0) x = (lon + 360 - lon0) / lonStep;
    final y = (lat - lat0) / latStep;
    if (x < -1e-9 || y < -1e-9) return null;
    if (x > columns - 1 + 1e-9 || y > rows - 1 + 1e-9) return null;
    final x0 = x.floor().clamp(0, math.max(0, columns - 2)).toInt();
    final y0 = y.floor().clamp(0, math.max(0, rows - 2)).toInt();
    final x1 = math.min(x0 + 1, columns - 1);
    final y1 = math.min(y0 + 1, rows - 1);
    final fx = (x - x0).clamp(0.0, 1.0);
    final fy = (y - y0).clamp(0.0, 1.0);
    var su = 0.0;
    var sv = 0.0;
    var sw = 0.0;
    void add(int cx, int cy, double w) {
      if (w <= 0) return;
      final i = cy * columns + cx;
      final a = u[i];
      final b = v[i];
      if (a.isNaN || b.isNaN) return;
      su += a * w;
      sv += b * w;
      sw += w;
    }

    add(x0, y0, (1 - fx) * (1 - fy));
    add(x1, y0, fx * (1 - fy));
    add(x0, y1, (1 - fx) * fy);
    add(x1, y1, fx * fy);
    if (sw <= 0) {
      // On a line of points without values (the model's has one at 180°):
      // the four around, alike.
      add(x0, y0, 1);
      add(x1, y0, 1);
      add(x0, y1, 1);
      add(x1, y1, 1);
    }
    if (sw <= 0) return null;
    return (su / sw, sv / sw);
  }
}

/// Reads the plain-text grid GeoServer's WCS answers with
/// (`format=text/plain`): a header naming the grid's range
/// (`Grid range: GridEnvelope2D[741..760, 153..168]`, columns then rows,
/// both ends in) and the affine from grid to degrees (`elt_0_0` and so on,
/// a parameter equal to the identity's left out; the point it gives is a
/// cell's middle), then `Band 0:` (u) and `Band 1:` (v), each a line of
/// values per row, from the north. `null` where it is not such a grid.
WindGrid? parseWcsWindGrid(String text) {
  final range = RegExp(
    r'Grid range:\s*\w+\[(-?\d+)\.\.(-?\d+),\s*(-?\d+)\.\.(-?\d+)\]',
  ).firstMatch(text);
  if (range == null) return null;
  final i0 = int.parse(range.group(1)!);
  final i1 = int.parse(range.group(2)!);
  final j0 = int.parse(range.group(3)!);
  final j1 = int.parse(range.group(4)!);
  final columns = i1 - i0 + 1;
  final rows = j1 - j0 + 1;
  if (columns < 1 || rows < 1) return null;
  final affine = <String, double>{
    'elt_0_0': 1,
    'elt_0_1': 0,
    'elt_0_2': 0,
    'elt_1_0': 0,
    'elt_1_1': 1,
    'elt_1_2': 0,
  };
  for (final m in RegExp(
    r'PARAMETER\["(elt_\d_\d)",\s*(-?[\d.Ee+-]+)\]',
  ).allMatches(text)) {
    final value = double.tryParse(m.group(2)!);
    if (value != null) affine[m.group(1)!] = value;
  }
  // A grid turned or sheared is not one this reads.
  if (affine['elt_0_1'] != 0 || affine['elt_1_0'] != 0) return null;
  final lonStep = affine['elt_0_0']!;
  final latStep = affine['elt_1_1']!;
  if (lonStep == 0 || latStep == 0) return null;
  final bands = <Float32List>[];
  for (final band in <String>['Band 0:', 'Band 1:']) {
    final start = text.indexOf(band);
    if (start < 0) return null;
    final body = text.substring(start + band.length);
    final end = body.indexOf('Band ');
    final values = (end < 0 ? body : body.substring(0, end))
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    if (values.length != columns * rows) return null;
    final out = Float32List(columns * rows);
    for (var k = 0; k < values.length; k++) {
      out[k] = double.tryParse(values[k]) ?? double.nan;
    }
    bands.add(out);
  }
  return WindGrid(
    lon0: lonStep * i0 + affine['elt_0_2']!,
    lat0: latStep * j0 + affine['elt_1_2']!,
    lonStep: lonStep,
    latStep: latStep,
    columns: columns,
    rows: rows,
    u: bands[0],
    v: bands[1],
  );
}

/// One arrow on the map: where it stands, where the wind blows to (degrees
/// clockwise from north) and how fast, in m/s.
@immutable
class WindArrow {
  /// Creates the arrow.
  const WindArrow({required this.at, required this.dir, required this.ms});

  final LatLng at;
  final double dir;
  final double ms;

  @override
  bool operator ==(Object other) =>
      other is WindArrow &&
      other.at == at &&
      other.dir == dir &&
      other.ms == ms;

  @override
  int get hashCode => Object.hash(at, dir, ms);

  @override
  String toString() => 'WindArrow($at, $dir°, $ms m/s)';
}

/// The arrows over [view] at [zoom] from [grid]: on a grid in Web Mercator
/// [windArrowSpacingMetres] apart and fixed to the world, so a pan keeps
/// every arrow where it was, over the view and [windAreaMargin] around it;
/// each the wind there, interpolated ([WindGrid.sample]). Longitudes come
/// back within ±180°. At most [windMaxArrows].
List<WindArrow> windArrowsFor(WindGrid grid, BoundingBox view, double zoom) {
  final spacing = windArrowSpacingMetres(zoom);
  var (west, east) = _unwrap(view);
  final dx = (east - west) * windAreaMargin;
  final south = math.max(-windMaxLat, view.south);
  final north = math.min(windMaxLat, view.north);
  if (south >= north) return const <WindArrow>[];
  final y0 = mercatorY(south);
  final y1 = mercatorY(north);
  final dy = (y1 - y0) * windAreaMargin;
  final xs = _onGrid(
    _mercatorXUnclamped(west - dx),
    _mercatorXUnclamped(east + dx),
    spacing,
  );
  final ys = _onGrid(
    math.max(mercatorY(-windMaxLat), y0 - dy),
    math.min(mercatorY(windMaxLat), y1 + dy),
    spacing,
  );
  final out = <WindArrow>[];
  for (final y in ys) {
    final lat = latOfMercatorY(y);
    for (final x in xs) {
      if (out.length >= windMaxArrows) return out;
      var lon = x * 180 / _origin;
      final wind = grid.sample(lat, lon);
      if (wind == null) continue;
      final (u, v) = wind;
      final w = windDirectionSpeed(u, v);
      while (lon > 180) {
        lon -= 360;
      }
      while (lon < -180) {
        lon += 360;
      }
      out.add(
        WindArrow(
          at: LatLng(_round(lat, 5), _round(lon, 5)),
          dir: w.dir.roundToDouble() % 360,
          ms: _round(w.ms, 1),
        ),
      );
    }
  }
  return out;
}

double _mercatorXUnclamped(double lon) => lon * _origin / 180;

/// The multiples of [step] from [from] to [to].
List<double> _onGrid(double from, double to, double step) {
  if (!(step > 0) || to < from) return const <double>[];
  final first = (from / step).ceil();
  final last = (to / step).floor();
  return <double>[for (var k = first; k <= last; k++) k * step];
}

double _round(double v, int digits) {
  final f = math.pow(10, digits).toDouble();
  return (v * f).roundToDouble() / f;
}

/// The wind arrows a map is asked to draw, and the credit shown with them.
@immutable
class WindArrows {
  /// Creates the set.
  const WindArrows({required this.arrows, required this.attribution});

  final List<WindArrow> arrows;
  final String attribution;

  @override
  bool operator ==(Object other) =>
      other is WindArrows &&
      other.attribution == attribution &&
      listEquals(other.arrows, arrows);

  @override
  int get hashCode => Object.hash(attribution, Object.hashAll(arrows));

  @override
  String toString() => 'WindArrows(${arrows.length})';
}
