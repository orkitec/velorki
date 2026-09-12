// Port of btools.router.FormatGpx (BRouter v1.7.10).
//
// Ported mechanically but unverified against the oracle (the corpus only
// records `format=geojson`); `Double.toString`/`Float.toString` conversions
// go through jfloat like FormatJson.

import 'dart:io';

import '../jfloat.dart';
import '../jvm.dart';
import '../mapaccess/matched_waypoint.dart';
import '../util/string_utils.dart';
import 'formatter.dart';
import 'osm_node_named.dart';
import 'osm_path_element.dart';
import 'osm_track.dart';
import 'routing_context.dart';

class FormatGpx extends Formatter {
  FormatGpx(RoutingContext super.rc);

  @override
  String format(OsmTrack t) {
    final sw = StringBuffer();
    formatAsGpx(sw, t);
    return sw.toString();
  }

  String formatAsGpx(StringBuffer sb, OsmTrack t) {
    final turnInstructionMode = t.voiceHints != null
        ? t.voiceHints!.turnInstructionMode
        : 0;

    sb.write('<?xml version="1.0" encoding="UTF-8"?>\n');
    if (turnInstructionMode != 9) {
      for (var i = t.messageList!.length - 1; i >= 0; i--) {
        String? message = t.messageList![i];
        if (i < t.messageList!.length - 1) {
          message = '(alt-index $i: $message )';
        }
        sb.write('<!-- $message -->\n');
      }
    }

    if (turnInstructionMode == 4) {
      // comment style
      sb.write(
        '<!-- \$transport-mode\$${t.voiceHints!.getTransportMode()}\$ -->\n',
      );
      sb.write(
        '<!--          cmd    idx        lon        lat d2next  geometry -->\n',
      );
      sb.write('<!-- \$turn-instruction-start\$\n');
      for (final hint in t.voiceHints!.list) {
        sb.write(
          '     \$turn\$${getCommandString(hint.cmd, hint.roundaboutExit, turnInstructionMode).padLeft(6)};${hint.indexInTrack.toString().padLeft(6)};${Formatter.formatILon(hint.ilon).padLeft(10)};${Formatter.formatILat(hint.ilat).padLeft(10)};${d2i(hint.distanceToNext).toString().padLeft(6)};${hint.formatGeometry()}\$\n',
        );
      }
      sb.write('    \$turn-instruction-end\$ -->\n');
    }
    sb.write('<gpx \n');
    sb.write(' xmlns="http://www.topografix.com/GPX/1/1" \n');
    sb.write(' xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" \n');
    if (turnInstructionMode == 9) {
      // BRouter style
      sb.write(' xmlns:brouter="Not yet documented" \n');
    }
    if (turnInstructionMode == 7) {
      // old locus style
      sb.write(' xmlns:locus="http://www.locusmap.eu" \n');
    }
    sb.write(
      ' xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd" \n',
    );

    if (turnInstructionMode == 3) {
      sb.write(' creator="OsmAndRouter" version="1.1">\n');
    } else {
      sb.write(' creator="BRouter-${OsmTrack.version}" version="1.1">\n');
    }
    if (turnInstructionMode == 9) {
      sb.write(' <metadata>\n');
      sb.write('  <name>${t.name}</name>\n');
      sb.write('  <extensions>\n');
      sb.write('   <brouter:info>${t.messageList![0]}</brouter:info>\n');
      if (t.params != null && t.params!.isNotEmpty) {
        sb.write('   <brouter:params><![CDATA[');
        var i = 0;
        for (final e in t.params!.entries) {
          if (i++ != 0) sb.write('&');
          sb.write('${e.key}=${e.value}');
        }
        sb.write(']]></brouter:params>\n');
      }
      sb.write('  </extensions>\n');
      sb.write(' </metadata>\n');
    }
    if (turnInstructionMode == 3 || turnInstructionMode == 8) {
      // osmand style, cruiser
      var lastRteTime = 0.0;

      sb.write(' <rte>\n');

      var rteTime = t.getVoiceHintTime(0);
      final first = StringBuffer();
      // define start point
      {
        first.write(
          '  <rtept lat="${Formatter.formatILat(t.nodes[0].getILat())}" lon="${Formatter.formatILon(t.nodes[0].getILon())}">\n   <desc>start</desc>\n   <extensions>\n',
        );
        if (rteTime != lastRteTime) {
          // add timing only if available
          final ti = f32(rteTime - lastRteTime);
          first.write('    <time>${d2i(ti + 0.5)}</time>\n');
          lastRteTime = rteTime;
        }
        first.write('    <offset>0</offset>\n  </extensions>\n </rtept>\n');
      }
      if (turnInstructionMode == 8) {
        if (t.matchedWaypoints![0].wpttype ==
                MatchedWaypoint.waypointTypeDirect &&
            t.voiceHints!.list[0].indexInTrack == 0) {
          // has a voice hint do nothing, voice hint will do
        } else {
          sb.write(first.toString());
        }
      } else {
        sb.write(first.toString());
      }

      for (var i = 0; i < t.voiceHints!.list.length; i++) {
        final hint = t.voiceHints!.list[i];
        sb.write(
          '  <rtept lat="${Formatter.formatILat(hint.ilat)}" lon="${Formatter.formatILon(hint.ilon)}">\n   <desc>${turnInstructionMode == 3 ? getMessageString(hint.cmd, hint.roundaboutExit, turnInstructionMode) : getCruiserMessageString(hint.cmd, hint.roundaboutExit)}</desc>\n   <extensions>\n',
        );

        rteTime = t.getVoiceHintTime(i + 1);

        if (rteTime != lastRteTime) {
          // add timing only if available
          final ti = f32(rteTime - lastRteTime);
          sb.write('    <time>${d2i(ti + 0.5)}</time>\n');
          lastRteTime = rteTime;
        }
        sb.write(
          '    <turn>${turnInstructionMode == 3 ? getCommandString(hint.cmd, hint.roundaboutExit, turnInstructionMode) : getCruiserCommandString(hint.cmd, hint.roundaboutExit)}</turn>\n    <turn-angle>${d2i(hint.angle)}</turn-angle>\n    <offset>${hint.indexInTrack}</offset>\n  </extensions>\n </rtept>\n',
        );
      }
      sb.write(
        '  <rtept lat="${Formatter.formatILat(t.nodes[t.nodes.length - 1].getILat())}" lon="${Formatter.formatILon(t.nodes[t.nodes.length - 1].getILon())}">\n   <desc>destination</desc>\n   <extensions>\n',
      );
      sb.write('    <time>0</time>\n');
      sb.write(
        '    <offset>${t.nodes.length - 1}</offset>\n  </extensions>\n </rtept>\n',
      );

      sb.write('</rte>\n');
    }

    if (turnInstructionMode == 7) {
      // old locus style
      var lastRteTime = t.getVoiceHintTime(0);

      for (var i = 0; i < t.voiceHints!.list.length; i++) {
        final hint = t.voiceHints!.list[i];
        sb.write(
          ' <wpt lon="${Formatter.formatILon(hint.ilon)}" lat="${Formatter.formatILat(hint.ilat)}">${hint.selev == shortMinValue ? '' : '<ele>${javaDoubleToString(hint.selev / 4.0)}</ele>'}<name>${getMessageString(hint.cmd, hint.roundaboutExit, turnInstructionMode)}</name><extensions><locus:rteDistance>${javaDoubleToString(hint.distanceToNext)}</locus:rteDistance>',
        );
        final rteTime = t.getVoiceHintTime(i + 1);
        if (rteTime != lastRteTime) {
          // add timing only if available
          final ti = f32(rteTime - lastRteTime);
          final speed = hint.distanceToNext / ti;
          sb.write(
            '<locus:rteTime>${javaDoubleToString(ti)}</locus:rteTime><locus:rteSpeed>${javaDoubleToString(speed)}</locus:rteSpeed>',
          );
          lastRteTime = rteTime;
        }
        sb.write(
          '<locus:rtePointAction>${getLocusAction(hint.cmd, hint.roundaboutExit)}</locus:rtePointAction></extensions></wpt>\n',
        );
      }
    }
    if (turnInstructionMode == 5) {
      // gpsies style
      for (final hint in t.voiceHints!.list) {
        sb.write(
          ' <wpt lon="${Formatter.formatILon(hint.ilon)}" lat="${Formatter.formatILat(hint.ilat)}"><name>${getMessageString(hint.cmd, hint.roundaboutExit, turnInstructionMode)}</name><sym>${getSymbolString(hint.cmd, hint.roundaboutExit, turnInstructionMode).toLowerCase()}</sym><type>${getSymbolString(hint.cmd, hint.roundaboutExit, turnInstructionMode)}</type></wpt>\n',
        );
      }
    }

    if (turnInstructionMode == 6) {
      // orux style
      for (final hint in t.voiceHints!.list) {
        sb.write(
          ' <wpt lat="${Formatter.formatILat(hint.ilat)}" lon="${Formatter.formatILon(hint.ilon)}">${hint.selev == shortMinValue ? '' : '<ele>${javaDoubleToString(hint.selev / 4.0)}</ele>'}<extensions>\n  <om:oruxmapsextensions xmlns:om="http://www.oruxmaps.com/oruxmapsextensions/1/0">\n   <om:ext type="ICON" subtype="0">${getOruxAction(hint.cmd, hint.roundaboutExit)}</om:ext>\n  </om:oruxmapsextensions>\n  </extensions>\n </wpt>\n',
        );
      }
    }

    for (var i = 0; i <= t.pois.length - 1; i++) {
      final poi = t.pois[i];
      formatWaypointGpx(sb, poi, 'poi');
    }

    if (t.exportWaypoints) {
      for (var i = 0; i <= t.matchedWaypoints!.length - 1; i++) {
        final wt = t.matchedWaypoints![i];
        if (i == 0) {
          formatMatchedWaypointGpx(
            sb,
            wt,
            wt.wpttype == MatchedWaypoint.waypointTypeDirect
                ? 'beeline'
                : 'via',
          );
        } else if (i == t.matchedWaypoints!.length - 1) {
          formatMatchedWaypointGpx(sb, wt, 'via');
        } else {
          if (wt.wpttype == MatchedWaypoint.waypointTypeDirect) {
            formatMatchedWaypointGpx(sb, wt, 'beeline');
          } else if (wt.wpttype == MatchedWaypoint.waypointTypeMeeting) {
            formatMatchedWaypointGpx(sb, wt, 'via');
          } else {
            formatMatchedWaypointGpx(sb, wt, 'shaping');
          }
        }
      }
    }
    if (t.exportCorrectedWaypoints) {
      sb.write('\n');
      for (var i = 0; i <= t.matchedWaypoints!.length - 1; i++) {
        final wt = t.matchedWaypoints![i];
        if (wt.correctedpoint != null) {
          final n = OsmNodeNamed(wt.correctedpoint);
          n.name = '${wt.name}_corr';
          formatWaypointGpx(sb, n, 'shaping');
        }
      }
      sb.write('\n');
    }

    sb.write(' <trk>\n');
    if (turnInstructionMode == 9 ||
        turnInstructionMode == 2 ||
        turnInstructionMode == 8 ||
        turnInstructionMode == 4) {
      // Locus, comment, cruise, brouter style
      sb.write('  <src>${t.name}</src>\n');
      sb.write('  <type>${t.voiceHints!.getTransportMode()}</type>\n');
    } else {
      sb.write('  <name>${t.name}</name>\n');
    }

    if (turnInstructionMode == 7) {
      sb.write('  <extensions>\n');
      sb.write(
        '   <locus:rteComputeType>${t.voiceHints!.getLocusRouteType()}</locus:rteComputeType>\n',
      );
      sb.write(
        '   <locus:rteSimpleRoundabouts>1</locus:rteSimpleRoundabouts>\n',
      );
      sb.write('  </extensions>\n');
    }

    // all points
    sb.write('  <trkseg>\n');
    var lastway = '';
    var bNextDirect = false;
    OsmPathElement? nn;

    for (var idx = 0; idx < t.nodes.length; idx++) {
      final n = t.nodes[idx];
      var sele = n.getSElev() == shortMinValue
          ? ''
          : '<ele>${javaDoubleToString(n.getElev())}</ele>';
      final hint = t.getVoiceHint(idx);
      final mwpt = t.getMatchedWaypoint(idx);

      if (t.showTime) {
        sele += '<time>${Formatter.getFormattedTime3(n.getTime())}</time>';
      }
      if (turnInstructionMode == 8) {
        if (mwpt != null &&
            !mwpt.name!.startsWith('via') &&
            !mwpt.name!.startsWith('from') &&
            !mwpt.name!.startsWith('to')) {
          sele += '<name>${mwpt.name}</name>';
        }
      }
      var bNeedHeader = false;
      if (turnInstructionMode == 9) {
        // trkpt/sym style

        if (hint != null) {
          if (mwpt != null &&
              !mwpt.name!.startsWith('via') &&
              !mwpt.name!.startsWith('from') &&
              !mwpt.name!.startsWith('to')) {
            sele += '<name>${mwpt.name}</name>';
          }
          sele +=
              '<desc>${getCruiserMessageString(hint.cmd, hint.roundaboutExit)}</desc>';
          sele +=
              '<sym>${getCommandString(hint.cmd, hint.roundaboutExit, turnInstructionMode)}</sym>';
          if (mwpt != null) {
            if (mwpt.wpttype == MatchedWaypoint.waypointTypeMeeting) {
              sele += '<type>via</type>';
            } else {
              sele += '<type>shaping</type>';
            }
          }
          sele += '<extensions>';
          if (t.showspeed) {
            var speed = 0.0;
            if (nn != null) {
              final dist = n.calcDistance(nn);
              final dt = f32(n.getTime() - nn.getTime());
              if (dt != 0.0) {
                speed = (f32(f32(f32(3.6) * dist) / dt) + 0.5);
              }
            }
            sele +=
                '<brouter:speed>${javaFloatToString(f32(d2i(speed * 10) / 10.0))}</brouter:speed>';
          }

          sele +=
              '<brouter:voicehint>${getCommandString(hint.cmd, hint.roundaboutExit, turnInstructionMode)};${d2i(hint.distanceToNext)},${hint.formatGeometry()}</brouter:voicehint>';
          if (n.message != null &&
              n.message!.wayKeyValues != null &&
              n.message!.wayKeyValues != lastway) {
            sele += '<brouter:way>${n.message!.wayKeyValues}</brouter:way>';
            lastway = n.message!.wayKeyValues!;
          }
          if (n.message != null && n.message!.nodeKeyValues != null) {
            sele += '<brouter:node>${n.message!.nodeKeyValues}</brouter:node>';
          }
          sele += '</extensions>';
        }
        if (idx == 0 && hint == null) {
          if (mwpt != null &&
              mwpt.wpttype == MatchedWaypoint.waypointTypeDirect) {
            sele += '<desc>beeline</desc>';
          } else {
            sele += '<desc>start</desc>';
          }
          sele += '<type>via</type>';
        } else if (idx == t.nodes.length - 1 && hint == null) {
          sele += '<desc>end</desc>';
          sele += '<type>via</type>';
        } else {
          if (mwpt != null && hint == null) {
            if (mwpt.wpttype == MatchedWaypoint.waypointTypeDirect) {
              // bNextDirect = true;
              sele += '<desc>beeline</desc>';
            } else {
              sele += '<desc>${mwpt.name}</desc>';
            }
            if (mwpt.wpttype == MatchedWaypoint.waypointTypeMeeting) {
              sele += '<type>via</type>';
            } else {
              sele += '<type>shaping</type>';
            }
            bNextDirect = false;
          }
        }

        if (hint == null) {
          bNeedHeader =
              (t.showspeed ||
                  (n.message != null &&
                      n.message!.wayKeyValues != null &&
                      n.message!.wayKeyValues != lastway)) ||
              (n.message != null && n.message!.nodeKeyValues != null);
          if (bNeedHeader) {
            sele += '<extensions>';
            if (t.showspeed) {
              var speed = 0.0;
              if (nn != null) {
                final dist = n.calcDistance(nn);
                final dt = f32(n.getTime() - nn.getTime());
                if (dt != 0.0) {
                  speed = (f32(f32(f32(3.6) * dist) / dt) + 0.5);
                }
              }
              sele +=
                  '<brouter:speed>${javaFloatToString(f32(d2i(speed * 10) / 10.0))}</brouter:speed>';
            }
            if (n.message != null &&
                n.message!.wayKeyValues != null &&
                n.message!.wayKeyValues != lastway) {
              sele += '<brouter:way>${n.message!.wayKeyValues}</brouter:way>';
              lastway = n.message!.wayKeyValues!;
            }
            if (n.message != null && n.message!.nodeKeyValues != null) {
              sele +=
                  '<brouter:node>${n.message!.nodeKeyValues}</brouter:node>';
            }
            sele += '</extensions>';
          }
        }
      }

      if (turnInstructionMode == 2) {
        // locus style new
        if (hint != null) {
          if (mwpt != null) {
            if (!mwpt.name!.startsWith('via') &&
                !mwpt.name!.startsWith('from') &&
                !mwpt.name!.startsWith('to') &&
                !mwpt.name!.startsWith('rt')) {
              sele += '<name>${mwpt.name}</name>';
            }
            if (mwpt.wpttype == MatchedWaypoint.waypointTypeDirect &&
                bNextDirect) {
              sele +=
                  '<src>${getLocusSymbolString(hint.cmd, hint.roundaboutExit)}</src><sym>pass_place</sym><type>Shaping</type>';
              // bNextDirect = false;
            } else if (mwpt.wpttype == MatchedWaypoint.waypointTypeDirect) {
              if (idx == 0) {
                sele += '<sym>pass_place</sym><type>Via</type>';
              } else {
                sele += '<sym>pass_place</sym><type>Shaping</type>';
              }
              bNextDirect = true;
            } else if (bNextDirect) {
              sele +=
                  '<src>beeline</src><sym>${getLocusSymbolString(hint.cmd, hint.roundaboutExit)}</sym><type>Shaping</type>';
              bNextDirect = false;
            } else {
              sele +=
                  '<sym>${getLocusSymbolString(hint.cmd, hint.roundaboutExit)}</sym><type>Via</type>';
            }
          } else {
            sele +=
                '<sym>${getLocusSymbolString(hint.cmd, hint.roundaboutExit)}</sym>';
          }
        } else {
          if (idx == 0 && hint == null) {
            final pos = sele.indexOf('<sym');
            if (pos != -1) {
              sele = sele.substring(0, pos);
            }
            if (mwpt != null && !mwpt.name!.startsWith('from')) {
              sele += '<name>${mwpt.name}</name>';
            }
            if (mwpt != null &&
                mwpt.wpttype == MatchedWaypoint.waypointTypeDirect) {
              bNextDirect = true;
            }
            sele += '<sym>pass_place</sym>';
            sele += '<type>Via</type>';
          } else if (idx == t.nodes.length - 1 && hint == null) {
            final pos = sele.indexOf('<sym');
            if (pos != -1) {
              sele = sele.substring(0, pos);
            }
            if (mwpt != null &&
                mwpt.name != null &&
                !mwpt.name!.startsWith('to')) {
              sele += '<name>${mwpt.name}</name>';
            }
            if (bNextDirect) {
              sele += '<src>beeline</src>';
            }
            sele += '<sym>pass_place</sym>';
            sele += '<type>Via</type>';
          } else {
            if (mwpt != null) {
              if (!mwpt.name!.startsWith('via') &&
                  !mwpt.name!.startsWith('from') &&
                  !mwpt.name!.startsWith('to') &&
                  !mwpt.name!.startsWith('rt')) {
                sele += '<name>${mwpt.name}</name>';
              }
              if (mwpt.wpttype == MatchedWaypoint.waypointTypeDirect &&
                  bNextDirect) {
                sele += '<src>beeline</src><sym>pass_place</sym><type>Shaping</type>';
              } else if (mwpt.wpttype == MatchedWaypoint.waypointTypeDirect) {
                if (idx == 0) {
                  sele += '<sym>pass_place</sym><type>Via</type>';
                } else {
                  sele += '<sym>pass_place</sym><type>Shaping</type>';
                }
                bNextDirect = true;
              } else if (bNextDirect) {
                sele += '<src>beeline</src><sym>pass_place</sym><type>Shaping</type>';
                bNextDirect = false;
              } else if (mwpt.name!.startsWith('via') ||
                  mwpt.name!.startsWith('from') ||
                  mwpt.name!.startsWith('to') ||
                  mwpt.name!.startsWith('rt')) {
                if (bNextDirect) {
                  sele += '<src>beeline</src><sym>pass_place</sym><type>Shaping</type>';
                } else {
                  sele += '<sym>pass_place</sym><type>Shaping</type>';
                }
                bNextDirect = false;
              } else {
                sele += '<name>${mwpt.name}</name>';
                sele += '<sym>pass_place</sym><type>Via</type>';
              }
            }
          }
        }
      }
      sb.write(
        '   <trkpt lon="${Formatter.formatILon(n.getILon())}" lat="${Formatter.formatILat(n.getILat())}">$sele</trkpt>\n',
      );

      nn = n;
    }

    sb.write('  </trkseg>\n');
    sb.write(' </trk>\n');
    sb.write('</gpx>\n');

    return sb.toString();
  }

  String formatAsWaypoint(OsmNodeNamed n) {
    final sw = StringBuffer();
    formatGpxHeader(sw);
    formatWaypointGpx(sw, n, null);
    formatGpxFooter(sw);
    return sw.toString();
  }

  void formatGpxHeader(StringBuffer sb) {
    sb.write('<?xml version="1.0" encoding="UTF-8"?>\n');
    sb.write('<gpx \n');
    sb.write(' xmlns="http://www.topografix.com/GPX/1/1" \n');
    sb.write(' xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" \n');
    sb.write(
      ' xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd" \n',
    );
    sb.write(' creator="BRouter-${OsmTrack.version}" version="1.1">\n');
  }

  void formatGpxFooter(StringBuffer sb) {
    sb.write('</gpx>\n');
  }

  /// `formatWaypointGpx(BufferedWriter, OsmNodeNamed, String)`
  void formatWaypointGpx(StringBuffer sb, OsmNodeNamed n, String? type) {
    sb.write(
      ' <wpt lon="${Formatter.formatILon(n.ilon)}" lat="${Formatter.formatILat(n.ilat)}">',
    );
    if (n.getSElev() != shortMinValue) {
      sb.write('<ele>${javaDoubleToString(n.getElev())}</ele>');
    }
    if (n.name != null) {
      sb.write('<name>${StringUtils.escapeXml10(n.name!)}</name>');
    }
    if (n.nodeDescription != null && rc != null) {
      sb.write(
        '<desc>${rc!.expctxWay!.getKeyValueDescription(false, n.nodeDescription!)}</desc>',
      );
    }
    if (type != null) {
      sb.write('<type>$type</type>');
    }
    sb.write('</wpt>\n');
  }

  /// `formatWaypointGpx(BufferedWriter, MatchedWaypoint, String)`
  void formatMatchedWaypointGpx(
    StringBuffer sb,
    MatchedWaypoint wp,
    String? type,
  ) {
    sb.write(
      ' <wpt lon="${Formatter.formatILon(wp.waypoint!.ilon)}" lat="${Formatter.formatILat(wp.waypoint!.ilat)}">',
    );
    if (wp.waypoint!.getSElev() != shortMinValue) {
      sb.write('<ele>${javaDoubleToString(wp.waypoint!.getElev())}</ele>');
    }
    if (wp.name != null) {
      sb.write('<name>${StringUtils.escapeXml10(wp.name!)}</name>');
    }
    if (type != null) {
      sb.write('<type>$type</type>');
    }
    sb.write('</wpt>\n');
  }

  static String getWaypoint(int ilon, int ilat, String name, String? desc) {
    return '<wpt lon="${Formatter.formatILon(ilon)}" lat="${Formatter.formatILat(ilat)}"><name>$name</name>${desc != null ? '<desc>$desc</desc>' : ''}</wpt>';
  }

  @override
  OsmTrack? read(String filename) {
    final f = File(filename);
    if (!f.existsSync()) {
      return null;
    }
    final track = OsmTrack();
    for (final line in f.readAsLinesSync()) {
      var idx0 = line.indexOf('<trkpt ');
      if (idx0 >= 0) {
        idx0 = line.indexOf(' lon="');
        idx0 += 6;
        final idx1 = line.indexOf('"', idx0);
        final ilon = d2i(
          (javaParseDouble(line.substring(idx0, idx1)) + 180.0) * 1000000.0 +
              0.5,
        );
        var idx2 = line.indexOf(' lat="');
        if (idx2 < 0) continue;
        idx2 += 6;
        final idx3 = line.indexOf('"', idx2);
        final ilat = d2i(
          (javaParseDouble(line.substring(idx2, idx3)) + 90.0) * 1000000.0 +
              0.5,
        );
        track.nodes.add(OsmPathElement.createAt(ilon, ilat, 0, null));
      }
    }
    return track;
  }
}
