// Port of btools.router.RoutingParamCollector (BRouter v1.7.10).
//
// The parameter map is a `JavaHashMap<String, String>` (the `HashMap`
// iteration order of `setParams` decides which of two conflicting keys wins,
// e.g. `heading` and `direction`), `String.split` keeps Java's trailing-empty
// rule (`javaSplit`) and `URLDecoder.decode` is `javaUrlDecode`.

import 'dart:convert';

import '../jfloat.dart';
import '../jvm.dart';
import '../mapaccess/matched_waypoint.dart';
import 'osm_node_named.dart';
import 'osm_nogo_polygon.dart';
import 'routing_context.dart';

/// `java.net.URLDecoder.decode(s, "UTF-8")`.
String javaUrlDecode(String s) {
  final bytes = <int>[];
  var i = 0;
  while (i < s.length) {
    final c = s.codeUnitAt(i);
    if (c == 0x2b) {
      // '+'
      bytes.add(0x20);
      i++;
    } else if (c == 0x25) {
      // '%'
      if (i + 2 >= s.length) {
        throw ArgumentError(
          'URLDecoder: Incomplete trailing escape (%) pattern',
        );
      }
      final v = int.tryParse(s.substring(i + 1, i + 3), radix: 16);
      if (v == null) {
        throw ArgumentError(
          'URLDecoder: Illegal hex characters in escape (%) pattern',
        );
      }
      bytes.add(v);
      i += 3;
    } else {
      bytes.addAll(utf8.encode(s[i]));
      i++;
    }
  }
  return utf8.decode(bytes, allowMalformed: true);
}

/// `java.util.StringTokenizer(s, delims)`: the non-empty pieces.
List<String> _tokens(String s, String delims) {
  final res = <String>[];
  final sb = StringBuffer();
  for (final c in s.codeUnits) {
    if (delims.codeUnits.contains(c)) {
      if (sb.isNotEmpty) {
        res.add(sb.toString());
        sb.clear();
      }
    } else {
      sb.writeCharCode(c);
    }
  }
  if (sb.isNotEmpty) res.add(sb.toString());
  return res;
}

class RoutingParamCollector {
  static const bool debug = false;

  /// get a list of points and optional extra info for the points
  ///
  /// [lonLats]: linked list separated by ';' or '|'
  List<OsmNodeNamed> getWayPointList(String? lonLats) {
    if (lonLats == null) throw ArgumentError('lonlats parameter not set');

    final coords = javaSplit(
      lonLats.replaceAll(';', '|'),
      '|',
    ); // use both variantes
    if (coords.isEmpty || !coords[0].contains(',')) {
      throw ArgumentError('we need one lat/lon point at least!');
    }

    final wplist = <OsmNodeNamed>[];
    for (var i = 0; i < coords.length; i++) {
      final lonLat = javaSplit(coords[i], ',');
      if (lonLat.isEmpty) {
        throw ArgumentError('we need one lat/lon point at least!');
      }
      wplist.add(
        _readPositionStrings(
          lonLat[0],
          lonLat.length > 1 ? lonLat[1] : null,
          'via$i',
        ),
      );
      if (lonLat.length > 2) {
        if (lonLat[2] == 'd') {
          wplist[wplist.length - 1].wpttype =
              MatchedWaypoint.waypointTypeDirect;
        } else if (lonLat[2] == 'm') {
          wplist[wplist.length - 1].wpttype =
              MatchedWaypoint.waypointTypeMeeting;
        } else {
          wplist[wplist.length - 1].name = lonLat[2];
          wplist[wplist.length - 1].wpttype =
              MatchedWaypoint.waypointTypeMeeting;
        }
      }
    }

    if (wplist[0].name!.startsWith('via')) wplist[0].name = 'from';
    if (wplist[wplist.length - 1].name!.startsWith('via')) {
      wplist[wplist.length - 1].name = 'to';
    }

    return wplist;
  }

  /// get a list of points (old style, positions only)
  List<OsmNodeNamed> readPositions(List<double>? lons, List<double>? lats) {
    final wplist = <OsmNodeNamed>[];

    if (lats == null || lats.length < 2 || lons == null || lons.length < 2) {
      return wplist;
    }

    for (var i = 0; i < lats.length && i < lons.length; i++) {
      final n = OsmNodeNamed();
      n.name = 'via$i';
      n.ilon = d2i((lons[i] + 180.0) * 1000000.0 + 0.5);
      n.ilat = d2i((lats[i] + 90.0) * 1000000.0 + 0.5);
      wplist.add(n);
    }

    if (wplist[0].name!.startsWith('via')) wplist[0].name = 'from';
    if (wplist[wplist.length - 1].name!.startsWith('via')) {
      wplist[wplist.length - 1].name = 'to';
    }

    return wplist;
  }

  OsmNodeNamed _readPositionStrings(String? vlon, String? vlat, String name) {
    if (vlon == null) throw ArgumentError('lon $name not found in input');
    if (vlat == null) throw ArgumentError('lat $name not found in input');

    return _readPosition(javaParseDouble(vlon), javaParseDouble(vlat), name);
  }

  OsmNodeNamed _readPosition(double lon, double lat, String name) {
    final n = OsmNodeNamed();
    n.name = name;
    n.ilon = d2i((lon + 180.0) * 1000000.0 + 0.5);
    n.ilat = d2i((lat + 90.0) * 1000000.0 + 0.5);
    return n;
  }

  /// read a url like parameter list linked with '&'
  JavaHashMap<String, String> getUrlParams(String url) {
    final params = JavaHashMap.ofStrings<String>();
    final decoded = javaUrlDecode(url);
    for (final t in _tokens(decoded, '?&')) {
      final tk2 = _tokens(t, '=');
      if (tk2.isNotEmpty) {
        final key = tk2[0];
        if (tk2.length > 1) {
          final value = tk2[1];
          params.put(key, value);
        }
      }
    }
    return params;
  }

  /// fill a parameter map into the routing context
  void setParams(
    RoutingContext rctx,
    List<OsmNodeNamed> wplist,
    JavaHashMap<String, String>? params,
  ) {
    if (params != null) {
      if (params.length == 0) return;

      // prepare nogos extra
      if (params.containsKey('profile')) {
        rctx.localFunction = params.get('profile')!;
      }
      if (params.containsKey('nogoLats') &&
          params.get('nogoLats')!.isNotEmpty) {
        final nogoList = readNogos(
          params.get('nogoLons'),
          params.get('nogoLats'),
          params.get('nogoRadi'),
        );
        if (nogoList != null) {
          RoutingContext.prepareNogoPoints(nogoList);
          if (rctx.nogopoints == null) {
            rctx.nogopoints = nogoList;
          } else {
            rctx.nogopoints!.addAll(nogoList);
          }
        }
        params.remove('nogoLats');
        params.remove('nogoLons');
        params.remove('nogoRadi');
      }
      if (params.containsKey('nogos')) {
        final nogoList = readNogoList(params.get('nogos'));
        if (nogoList != null) {
          RoutingContext.prepareNogoPoints(nogoList);
          if (rctx.nogopoints == null) {
            rctx.nogopoints = nogoList;
          } else {
            rctx.nogopoints!.addAll(nogoList);
          }
        }
        params.remove('nogos');
      }
      if (params.containsKey('polylines')) {
        final result = <OsmNodeNamed>[];
        _parseNogoPolygons(params.get('polylines'), result, false);
        if (rctx.nogopoints == null) {
          rctx.nogopoints = result;
        } else {
          rctx.nogopoints!.addAll(result);
        }
        params.remove('polylines');
      }
      if (params.containsKey('polygons')) {
        final result = <OsmNodeNamed>[];
        _parseNogoPolygons(params.get('polygons'), result, true);
        if (rctx.nogopoints == null) {
          rctx.nogopoints = result;
        } else {
          rctx.nogopoints!.addAll(result);
        }
        params.remove('polygons');
      }

      for (final e in params.entries.toList()) {
        final key = e.key;
        final value = e.value;

        if (key == 'straight') {
          try {
            final sa = javaSplit(value, ',');
            for (var i = 0; i < sa.length; i++) {
              final v = javaParseInt(sa[i]);
              if (wplist.length > v) {
                wplist[v].wpttype = MatchedWaypoint.waypointTypeDirect;
              }
            }
          } catch (ex) {
            // System.err.println("error ..." + ex);
          }
        } else if (key == 'pois') {
          rctx.poipoints = readPoisList(value);
        } else if (key == 'heading') {
          rctx.startDirection = javaParseInt(value);
          rctx.forceUseStartDirection = true;
        } else if (key == 'direction') {
          rctx.startDirection = javaParseInt(value);
        } else if (key == 'roundTripDistance') {
          rctx.roundTripDistance = javaParseInt(value);
        } else if (key == 'roundTripDirectionAdd') {
          rctx.roundTripDirectionAdd = javaParseInt(value);
        } else if (key == 'roundTripPoints') {
          rctx.roundTripPoints = javaParseInt(value);
          if (rctx.roundTripPoints == null ||
              rctx.roundTripPoints! < 3 ||
              rctx.roundTripPoints! > 20) {
            rctx.roundTripPoints = 5;
          }
        } else if (key == 'allowSamewayback') {
          rctx.allowSamewayback = javaParseInt(value) == 1;
        } else if (key == 'alternativeidx') {
          rctx.setAlternativeIdx(javaParseInt(value));
        } else if (key == 'turnInstructionMode') {
          rctx.turnInstructionMode = javaParseInt(value);
        } else if (key == 'timode') {
          rctx.turnInstructionMode = javaParseInt(value);
        } else if (key == 'turnInstructionFormat') {
          if ('osmand' == value.toLowerCase()) {
            rctx.turnInstructionMode = 3;
          } else if ('locus' == value.toLowerCase()) {
            rctx.turnInstructionMode = 2;
          }
        } else if (key == 'exportWaypoints') {
          rctx.exportWaypoints = (javaParseInt(value) == 1);
        } else if (key == 'exportCorrectedWaypoints') {
          rctx.exportCorrectedWaypoints = (javaParseInt(value) == 1);
        } else if (key == 'format') {
          rctx.outputFormat = value.toLowerCase();
        } else if (key == 'trackFormat') {
          rctx.outputFormat = value.toLowerCase();
        } else if (key.startsWith('profile:')) {
          rctx.keyValues ??= <String, String>{};
          rctx.keyValues![key.substring(8)] = value;
        }
        // ignore other params
      }
    }
  }

  /// fill profile parameter list
  void setProfileParams(RoutingContext rctx, Map<String, String>? params) {
    if (params != null) {
      if (params.isEmpty) return;
      rctx.keyValues ??= <String, String>{};
      for (final e in params.entries) {
        rctx.keyValues![e.key] = e.value;
      }
    }
  }

  void _parseNogoPolygons(
    String? polygons,
    List<OsmNodeNamed> result,
    bool closed,
  ) {
    if (polygons != null) {
      final polygonList = javaSplit(polygons, '|');
      for (var i = 0; i < polygonList.length; i++) {
        final lonLatList = javaSplit(polygonList[i], ',');
        if (lonLatList.length > 1) {
          final polygon = OsmNogoPolygon(closed);
          int j;
          for (j = 0; j < 2 * (lonLatList.length ~/ 2) - 1;) {
            final slon = lonLatList[j++];
            final slat = lonLatList[j++];
            final lon = d2i((javaParseDouble(slon) + 180.0) * 1000000.0 + 0.5);
            final lat = d2i((javaParseDouble(slat) + 90.0) * 1000000.0 + 0.5);
            polygon.addVertex(lon, lat);
          }

          var nogoWeight = 'NaN';
          if (j < lonLatList.length) {
            nogoWeight = lonLatList[j];
          }
          polygon.nogoWeight = javaParseDouble(nogoWeight);
          if (polygon.points.isNotEmpty) {
            polygon.calcBoundingCircle();
            result.add(polygon);
          }
        }
      }
    }
  }

  List<OsmNodeNamed>? readPoisList(String? pois) {
    // lon,lat,name|...
    if (pois == null) return null;

    final lonLatNameList = javaSplit(pois, '|');

    final poisList = <OsmNodeNamed>[];
    for (var i = 0; i < lonLatNameList.length; i++) {
      final lonLatName = javaSplit(lonLatNameList[i], ',');

      if (lonLatName.length != 3) continue;

      final n = OsmNodeNamed();
      n.ilon = d2i((javaParseDouble(lonLatName[0]) + 180.0) * 1000000.0 + 0.5);
      n.ilat = d2i((javaParseDouble(lonLatName[1]) + 90.0) * 1000000.0 + 0.5);
      n.name = lonLatName[2];
      poisList.add(n);
    }

    return poisList;
  }

  List<OsmNodeNamed>? readNogoList(String? nogos) {
    // lon,lat,radius[,weight]|...

    if (nogos == null) return null;

    final lonLatRadList = javaSplit(nogos, '|');

    final nogoList = <OsmNodeNamed>[];
    for (var i = 0; i < lonLatRadList.length; i++) {
      final lonLatRad = javaSplit(lonLatRadList[i], ',');
      var nogoWeight = 'NaN';
      if (lonLatRad.length > 3) {
        nogoWeight = lonLatRad[3];
      }
      nogoList.add(
        _readNogoStrings(lonLatRad[0], lonLatRad[1], lonLatRad[2], nogoWeight),
      );
    }

    return nogoList;
  }

  List<OsmNodeNamed>? readNogos(
    String? nogoLons,
    String? nogoLats,
    String? nogoRadi,
  ) {
    if (nogoLons == null || nogoLats == null || nogoRadi == null) return null;
    final nogoList = <OsmNodeNamed>[];

    final lons = javaSplit(nogoLons, ',');
    final lats = javaSplit(nogoLats, ',');
    final radi = javaSplit(nogoRadi, ',');
    const nogoWeight = 'undefined';
    for (
      var i = 0;
      i < lons.length && i < lats.length && i < radi.length;
      i++
    ) {
      final n = _readNogoStrings(
        javaTrim(lons[i]),
        javaTrim(lats[i]),
        javaTrim(radi[i]),
        nogoWeight,
      );
      nogoList.add(n);
    }
    return nogoList;
  }

  OsmNodeNamed _readNogoStrings(
    String lon,
    String lat,
    String radius,
    String nogoWeight,
  ) {
    final weight = 'undefined' == nogoWeight
        ? double.nan
        : javaParseDouble(nogoWeight);
    return _readNogo(
      javaParseDouble(lon),
      javaParseDouble(lat),
      d2i(javaParseDouble(radius)),
      weight,
    );
  }

  OsmNodeNamed _readNogo(
    double lon,
    double lat,
    int radius,
    double nogoWeight,
  ) {
    final n = OsmNodeNamed();
    n.name = 'nogo$radius';
    n.ilon = d2i((lon + 180.0) * 1000000.0 + 0.5);
    n.ilat = d2i((lat + 90.0) * 1000000.0 + 0.5);
    n.isNogo = true;
    n.nogoWeight = nogoWeight;
    return n;
  }
}
