import 'dart:math' as math;
import 'dart:typed_data';

import 'cell_ways.dart';
import 'cycle_attrs.dart';
import 'simplify.dart';

/// What the map wants drawn, as bits: a line goes into the GeoJSON when any
/// of its parts is wanted. The layers on the map filter the same way, so
/// leaving out what is not wanted only makes the file smaller.
abstract final class CycleContent {
  /// Cycleways, cycle streets, and lanes and tracks beside roads.
  static const int infrastructure = 1 << 0;

  /// Paths shared with walkers, and footways bikes may use.
  static const int paths = 1 << 1;

  /// One-ways open to bikes both ways.
  static const int contraflow = 1 << 2;

  /// National and international cycle routes.
  static const int routesNational = 1 << 3;

  /// Regional cycle routes.
  static const int routesRegional = 1 << 4;

  /// Local cycle routes.
  static const int routesLocal = 1 << 5;

  /// Unpaved and rough surfaces.
  static const int surface = 1 << 6;

  /// Mountain-bike difficulty.
  static const int mtb = 1 << 7;

  /// Barriers on the way.
  static const int barriers = 1 << 8;

  /// Everything.
  static const int all = (1 << 9) - 1;

  /// Whether a line with [attrs] has anything [wanted].
  static bool wants(int wanted, int attrs) {
    final a = CycleAttrs(attrs);
    final kind = a.kind;
    if (wanted & infrastructure != 0 &&
        (kind == CycleKind.cycleway ||
            kind == CycleKind.cyclestreet ||
            a.track != 0 ||
            a.lane != 0)) {
      return true;
    }
    if (wanted & paths != 0 &&
        (kind == CycleKind.shared || kind == CycleKind.allowed)) {
      return true;
    }
    if (wanted & contraflow != 0 && a.contraflow) return true;
    final routes = a.routes;
    if (wanted & routesNational != 0 && routes & CycleBits.routeNational != 0) {
      return true;
    }
    if (wanted & routesRegional != 0 && routes & CycleBits.routeRegional != 0) {
      return true;
    }
    if (wanted & routesLocal != 0 && routes & CycleBits.routeLocal != 0) {
      return true;
    }
    if (wanted & surface != 0 && (a.unpaved || a.rough)) return true;
    if (wanted & mtb != 0 && a.mtbScale != null) return true;
    return false;
  }
}

/// Writes cells as GeoJSON features, comma-separated, without the
/// collection around them: a cell's features are written once per zoom and
/// content and kept, and a view is the kept pieces joined.
///
/// Each line carries short properties the map's layers read:
/// `k` the [CycleKind] index, `t` and `l` the [Side] masks of tracks and
/// lanes, and when set `cf` contraflow, `nn`/`nr`/`nl` the national,
/// regional and local routes, `u` unpaved, `r` rough, `m` the mtb scale.
/// A barrier is a point with `b`, its [BarrierClass].
final class GeoJsonWriter {
  final _keep = Int32List(4096);
  final _stack = <int>[];

  /// The features of [cell] that are [wanted], simplified for [zoom].
  String cellFeatures(CellWays cell, int wanted, int zoom) {
    final out = StringBuffer();
    final coords = cell.coords;
    if (cell.pointCount > 0) {
      final lat = coords[1] / 1e6 - 90;
      final tolerance = toleranceAtZoom(zoom, lat);
      final lonScale = math.cos(lat * math.pi / 180);
      for (var i = 0; i < cell.lineCount; i++) {
        final attrs = cell.attrs[i];
        if (!CycleContent.wants(wanted, attrs)) continue;
        final from = cell.starts[i];
        final to = cell.starts[i + 1];
        final keep = to - from <= _keep.length ? _keep : Int32List(to - from);
        final kept = simplifyLine(
          coords,
          from,
          to,
          tolerance,
          lonScale,
          keep,
          _stack,
        );
        if (out.isNotEmpty) out.write(',');
        out.write('{"type":"Feature","properties":');
        _properties(out, CycleAttrs(attrs));
        out.write(',"geometry":{"type":"LineString","coordinates":[');
        for (var k = 0; k < kept; k++) {
          if (k > 0) out.write(',');
          final p = keep[k];
          _position(out, coords[p * 2], coords[p * 2 + 1]);
        }
        out.write(']}}');
      }
    }
    if (wanted & CycleContent.barriers != 0) {
      final b = cell.barriers;
      for (var i = 0; i + 2 < b.length; i += 3) {
        if (out.isNotEmpty) out.write(',');
        out.write('{"type":"Feature","properties":{"b":${b[i + 2]}},');
        out.write('"geometry":{"type":"Point","coordinates":');
        _position(out, b[i], b[i + 1]);
        out.write('}}');
      }
    }
    return out.toString();
  }

  /// A feature collection of [pieces], each a [cellFeatures] result.
  static String collection(Iterable<String> pieces) {
    final out = StringBuffer('{"type":"FeatureCollection","features":[');
    var first = true;
    for (final piece in pieces) {
      if (piece.isEmpty) continue;
      if (!first) out.write(',');
      out.write(piece);
      first = false;
    }
    out.write(']}');
    return out.toString();
  }

  static void _properties(StringBuffer out, CycleAttrs a) {
    out
      ..write('{"k":')
      ..write(a.kind.index)
      ..write(',"t":')
      ..write(a.track)
      ..write(',"l":')
      ..write(a.lane);
    if (a.contraflow) out.write(',"cf":1');
    final routes = a.routes;
    if (routes & CycleBits.routeNational != 0) out.write(',"nn":1');
    if (routes & CycleBits.routeRegional != 0) out.write(',"nr":1');
    if (routes & CycleBits.routeLocal != 0) out.write(',"nl":1');
    if (a.unpaved) out.write(',"u":1');
    if (a.rough) out.write(',"r":1');
    final mtb = a.mtbScale;
    if (mtb != null) out.write(',"m":$mtb');
    out.write('}');
  }

  /// `[lon,lat]` from BRouter's integers, to five decimals (about a metre).
  static void _position(StringBuffer out, int ilon, int ilat) {
    out.write('[');
    _degrees(out, ilon - 180000000);
    out.write(',');
    _degrees(out, ilat - 90000000);
    out.write(']');
  }

  static void _degrees(StringBuffer out, int micro) {
    var q = micro >= 0 ? (micro + 5) ~/ 10 : -((-micro + 5) ~/ 10);
    if (q < 0) {
      out.write('-');
      q = -q;
    }
    out.write(q ~/ 100000);
    var frac = q % 100000;
    if (frac == 0) return;
    var digits = 5;
    while (frac % 10 == 0) {
      frac ~/= 10;
      digits--;
    }
    out.write('.');
    final s = frac.toString();
    for (var i = s.length; i < digits; i++) {
      out.write('0');
    }
    out.write(s);
  }
}
