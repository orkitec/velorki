// Port of btools.router.FormatJson (BRouter v1.7.10).
//
// Number formatting: `int`s print as such; `double`s appended to the
// `StringBuilder` go through `Double.toString` (`javaDoubleToString`), the
// `float` speed hack through `Float.toString`, the travel times through
// `DecimalFormat("0.###")` (`javaDecimalFormat`).

import '../jfloat.dart';
import '../jvm.dart';
import '../mapaccess/matched_waypoint.dart';
import '../util/string_utils.dart';
import 'formatter.dart';
import 'osm_node_named.dart';
import 'osm_path_element.dart';
import 'osm_track.dart';
import 'routing_context.dart';

class FormatJson extends Formatter {
  FormatJson(RoutingContext rc) : super(rc);

  @override
  String format(OsmTrack t) {
    final turnInstructionMode = t.voiceHints != null
        ? t.voiceHints!.turnInstructionMode
        : 0;

    final sb = JStringBuilder();

    sb.append('{\n');
    sb.append('  "type": "FeatureCollection",\n');
    sb.append('  "features": [\n');
    sb.append('    {\n');
    sb.append('      "type": "Feature",\n');
    sb.append('      "properties": {\n');
    sb.append('        "creator": "BRouter-${OsmTrack.version}",\n');
    sb.append('        "name": "${t.name}",\n');
    sb.append('        "track-length": "${t.distance}",\n');
    sb.append('        "filtered ascend": "${t.ascend}",\n');
    sb.append('        "plain-ascend": "${t.plainAscend}",\n');
    sb.append('        "total-time": "${t.getTotalSeconds()}",\n');
    sb.append('        "total-energy": "${t.energy}",\n');
    sb.append('        "cost": "${t.cost}",\n');
    if (t.voiceHints != null && t.voiceHints!.list.isNotEmpty) {
      sb.append('        "voicehints": [\n');
      for (final hint in t.voiceHints!.list) {
        sb.append('          [');
        sb.append(hint.indexInTrack);
        sb.append(',');
        sb.append(getJsonCommandIndex(hint.cmd, turnInstructionMode));
        sb.append(',');
        sb.append(hint.getExitNumber());
        sb.append(',');
        sb.append(javaDoubleToString(hint.distanceToNext));
        sb.append(',');
        sb.append(d2i(hint.angle));

        // not always include geometry because longer and only needed for comment style
        if (turnInstructionMode == 4 || turnInstructionMode == 9) {
          // comment style
          sb.append(',"');
          sb.append(hint.formatGeometry());
          sb.append('"');
        }

        sb.append('],\n');
      }
      sb.deleteLastComma();
      sb.append('        ],\n');
    }
    if (t.showSpeedProfile) {
      // set in profile
      final sp = t.aggregateSpeedProfile();
      if (sp.isNotEmpty) {
        sb.append('        "speedprofile": [\n');
        for (var i = sp.length - 1; i >= 0; i--) {
          sb.append('          [');
          sb.append(sp[i]);
          sb.append(i > 0 ? '],\n' : ']\n');
        }
        sb.append('        ],\n');
      }
    }
    //  ... traditional message list
    {
      sb.append('        "messages": [\n');
      sb.append('          ["');
      sb.append(Formatter.messagesHeader.replaceAll('\t', '", "'));
      sb.append('"],\n');
      for (final m in t.aggregateMessages()) {
        sb.append('          ["');
        sb.append(m.replaceAll('\t', '", "'));
        sb.append('"],\n');
      }
      sb.deleteLastComma();
      sb.append('        ],\n');
    }

    if (t.getTotalSeconds() > 0) {
      sb.append('        "times": [');
      for (final n in t.nodes) {
        sb.append(javaDecimalFormat(n.getTime()));
        sb.append(',');
      }
      sb.deleteLastComma();
      sb.append(']\n');
    } else {
      sb.deleteLastComma();
    }

    sb.append('      },\n');

    if (t.iternity != null) {
      sb.append('      "iternity": [\n');
      for (final s in t.iternity!) {
        sb.append('        "');
        sb.append(s);
        sb.append('",\n');
      }
      sb.deleteLastComma();
      sb.append('        ],\n');
    }
    sb.append('      "geometry": {\n');
    sb.append('        "type": "LineString",\n');
    sb.append('        "coordinates": [\n');

    OsmPathElement? nn;
    for (final n in t.nodes) {
      var sele = n.getSElev() == shortMinValue
          ? ''
          : ', ${javaDoubleToString(n.getElev())}';
      if (t.showspeed) {
        // hack: show speed instead of elevation
        var speed = 0.0;
        if (nn != null) {
          final dist = n.calcDistance(nn);
          final dt = f32(n.getTime() - nn.getTime());
          if (dt != 0.0) {
            speed = (f32(f32(f32(3.6) * dist) / dt) + 0.5);
          }
        }
        sele = ', ${javaFloatToString(f32(d2i(speed * 10) / 10.0))}';
      }
      sb.append('          [');
      sb.append(Formatter.formatILon(n.getILon()));
      sb.append(', ');
      sb.append(Formatter.formatILat(n.getILat()));
      sb.append(sele);
      sb.append('],\n');
      nn = n;
    }
    sb.deleteLastComma();

    sb.append('        ]\n');
    sb.append('      }\n');
    if (t.exportWaypoints || t.exportCorrectedWaypoints || t.pois.isNotEmpty) {
      sb.append('    },\n');
      for (var i = 0; i <= t.pois.length - 1; i++) {
        final poi = t.pois[i];
        _addFeature(sb, 'poi', poi.name!, poi.ilat, poi.ilon, poi.getSElev());
        if (i < t.pois.length - 1) {
          sb.append(',');
        }
        sb.append('    \n');
      }
      if (t.exportWaypoints) {
        if (t.pois.isNotEmpty) sb.append('    ,\n');
        for (var i = 0; i <= t.matchedWaypoints!.length - 1; i++) {
          final wp = t.matchedWaypoints![i];
          String type;
          switch (wp.wpttype) {
            case MatchedWaypoint.waypointTypeDirect:
              type = 'beeline';
              break;
            case MatchedWaypoint.waypointTypeMeeting:
              type = 'via';
              break;
            default:
              type = 'shaping';
          }
          _addFeature(
            sb,
            type,
            wp.name!,
            wp.waypoint!.ilat,
            wp.waypoint!.ilon,
            wp.waypoint!.getSElev(),
          );
          if (i < t.matchedWaypoints!.length - 1) {
            sb.append(',');
          }
          sb.append('    \n');
        }
      }
      if (t.exportCorrectedWaypoints) {
        if (t.exportWaypoints) sb.append('    ,\n');
        var hasCorrPoints = false;
        for (var i = 0; i <= t.matchedWaypoints!.length - 1; i++) {
          const type = 'via_corr';

          final wp = t.matchedWaypoints![i];
          if (wp.correctedpoint != null) {
            if (hasCorrPoints) {
              sb.append(',');
            }
            _addFeature(
              sb,
              type,
              '${wp.name}_corr',
              wp.correctedpoint!.ilat,
              wp.correctedpoint!.ilon,
              wp.correctedpoint!.getSElev(),
            );
            sb.append('    \n');
            hasCorrPoints = true;
          }
        }
      }
    } else {
      sb.append('    }\n');
    }
    sb.append('  ]\n');
    sb.append('}\n');

    return sb.toString();
  }

  void _addFeature(
    JStringBuilder sb,
    String type,
    String name,
    int ilat,
    int ilon,
    int selev,
  ) {
    sb.append('    {\n');
    sb.append('      "type": "Feature",\n');
    sb.append('      "properties": {\n');
    sb.append('        "name": "${StringUtils.escapeJson(name)}",\n');
    sb.append('        "type": "$type"\n');
    sb.append('      },\n');
    sb.append('      "geometry": {\n');
    sb.append('        "type": "Point",\n');
    sb.append('        "coordinates": [\n');
    sb.append('          ${Formatter.formatILon(ilon)},\n');
    sb.append(
      '          ${Formatter.formatILat(ilat)}${selev != shortMinValue ? ',\n          ${javaDoubleToString(selev / 4.0)}' : ''}\n',
    );
    sb.append('        ]\n');
    sb.append('      }\n');
    sb.append('    }');
  }

  String formatAsWaypoint(OsmNodeNamed n) {
    final sb = StringBuffer();
    _addJsonHeader(sb);
    _addJsonFeature(
      sb,
      'info',
      'wpinfo',
      n.ilon,
      n.ilat,
      n.getElev(),
      (n.nodeDescription != null
          ? rc!.expctxWay!.getKeyValueDescription(false, n.nodeDescription!)
          : null),
    );
    _addJsonFooter(sb);
    return sb.toString();
  }

  void _addJsonFeature(
    StringBuffer sb,
    String type,
    String name,
    int ilon,
    int ilat,
    double elev,
    String? desc,
  ) {
    sb.write('    {\n');
    sb.write('      "type": "Feature",\n');
    sb.write('      "properties": {\n');
    sb.write('        "creator": "BRouter-${OsmTrack.version}",\n');
    sb.write('        "name": "${StringUtils.escapeJson(name)}",\n');
    sb.write('        "type": "$type"');
    if (desc != null) {
      sb.write(',\n        "message": "$desc"\n');
    } else {
      sb.write('\n');
    }
    sb.write('      },\n');
    sb.write('      "geometry": {\n');
    sb.write('        "type": "Point",\n');
    sb.write('        "coordinates": [\n');
    sb.write('          ${Formatter.formatILon(ilon)},\n');
    sb.write('          ${Formatter.formatILat(ilat)},\n');
    sb.write('          ${javaDoubleToString(elev)}\n');
    sb.write('        ]\n');
    sb.write('      }\n');
    sb.write('    }\n');
  }

  static void _addJsonHeader(StringBuffer sb) {
    sb.write('{\n');
    sb.write('  "type": "FeatureCollection",\n');
    sb.write('  "features": [\n');
  }

  static void _addJsonFooter(StringBuffer sb) {
    sb.write('  ]\n');
    sb.write('}\n');
  }
}
