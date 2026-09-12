// Port of btools.router.FormatKml (BRouter v1.7.10).

import '../mapaccess/matched_waypoint.dart';
import '../util/string_utils.dart';
import 'formatter.dart';
import 'osm_node_named.dart';
import 'osm_track.dart';
import 'routing_context.dart';

class FormatKml extends Formatter {
  FormatKml(RoutingContext rc) : super(rc);

  @override
  String format(OsmTrack t) {
    final sb = StringBuffer();

    sb.write('<?xml version="1.0" encoding="UTF-8"?>\n');

    sb.write('<kml xmlns="http://earth.google.com/kml/2.0">\n');
    sb.write('  <Document>\n');
    sb.write('    <name>KML Samples</name>\n');
    sb.write('    <open>1</open>\n');
    sb.write('    <distance>3.497064</distance>\n');
    sb.write('    <traveltime>872</traveltime>\n');
    sb.write(
      "    <description>To enable simple instructions add: 'instructions=1' as parameter to the URL</description>\n",
    );
    sb.write('    <Folder>\n');
    sb.write('      <name>Paths</name>\n');
    sb.write('      <visibility>0</visibility>\n');
    sb.write('      <description>Examples of paths.</description>\n');
    sb.write('      <Placemark>\n');
    sb.write('        <name>Tessellated</name>\n');
    sb.write('        <visibility>0</visibility>\n');
    sb.write(
      '        <description><![CDATA[If the <tessellate> tag has a value of 1, the line will contour to the underlying terrain]]></description>\n',
    );
    sb.write('        <LineString>\n');
    sb.write('          <tessellate>1</tessellate>\n');
    sb.write('         <coordinates>');

    for (final n in t.nodes) {
      sb.write(Formatter.formatILon(n.getILon()));
      sb.write(',');
      sb.write(Formatter.formatILat(n.getILat()));
      sb.write('\n');
    }

    sb.write('          </coordinates>\n');
    sb.write('        </LineString>\n');
    sb.write('      </Placemark>\n');
    sb.write('    </Folder>\n');
    if (t.exportWaypoints || t.exportCorrectedWaypoints || t.pois.isNotEmpty) {
      if (t.pois.isNotEmpty) {
        sb.write('    <Folder>\n');
        sb.write('      <name>poi</name>\n');
        for (var i = 0; i < t.pois.length; i++) {
          final poi = t.pois[i];
          _createPlaceMark(sb, poi.name!, poi.ilat, poi.ilon);
        }
        sb.write('    </Folder>\n');
      }

      if (t.exportWaypoints) {
        final size = t.matchedWaypoints!.length;
        _createFolder(sb, 'start', t.matchedWaypoints!.sublist(0, 1));
        if (t.matchedWaypoints!.length > 2) {
          _createFolder(sb, 'via', t.matchedWaypoints!.sublist(1, size - 1));
        }
        _createFolder(sb, 'end', t.matchedWaypoints!.sublist(size - 1, size));
      }
      if (t.exportCorrectedWaypoints) {
        final list = <OsmNodeNamed>[];
        for (var i = 0; i < t.matchedWaypoints!.length; i++) {
          final wp = t.matchedWaypoints![i];
          if (wp.correctedpoint != null) {
            final n = OsmNodeNamed(wp.correctedpoint);
            n.name = '${wp.name}_corr';
            list.add(n);
          }
        }
        final size = list.length;
        _createViaFolder(sb, 'via_corr', list.sublist(0, size));
      }
    }
    sb.write('  </Document>\n');
    sb.write('</kml>\n');

    return sb.toString();
  }

  void _createFolder(StringBuffer sb, String type, List<MatchedWaypoint> waypoints) {
    sb.write('    <Folder>\n');
    sb.write('      <name>$type</name>\n');
    for (var i = 0; i < waypoints.length; i++) {
      final wp = waypoints[i];
      _createPlaceMark(sb, wp.name!, wp.waypoint!.ilat, wp.waypoint!.ilon);
    }
    sb.write('    </Folder>\n');
  }

  void _createViaFolder(StringBuffer sb, String type, List<OsmNodeNamed> waypoints) {
    if (waypoints.isEmpty) return;
    sb.write('    <Folder>\n');
    sb.write('      <name>$type</name>\n');
    for (var i = 0; i < waypoints.length; i++) {
      final wp = waypoints[i];
      _createPlaceMark(sb, wp.name!, wp.ilat, wp.ilon);
    }
    sb.write('    </Folder>\n');
  }

  void _createPlaceMark(StringBuffer sb, String name, int ilat, int ilon) {
    sb.write('      <Placemark>\n');
    sb.write('        <name>${StringUtils.escapeXml10(name)}</name>\n');
    sb.write('        <Point>\n');
    sb.write(
      '         <coordinates>${Formatter.formatILon(ilon)},${Formatter.formatILat(ilat)}</coordinates>\n',
    );
    sb.write('        </Point>\n');
    sb.write('      </Placemark>\n');
  }
}
