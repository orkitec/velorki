// Port of btools.router.AreaReader (BRouter v1.7.10).
//
// Only used by `RoutingEngine.getRandomDirectionFromData` (round trips
// without a `direction`), which the oracle never exercises.

import 'dart:collection';
import 'dart:io';

import '../codec/data_buffers.dart';
import '../expressions/b_expression_context_way.dart';
import '../jvm.dart';
import '../mapaccess/matched_waypoint.dart';
import '../mapaccess/nodes_cache.dart';
import '../mapaccess/osm_file.dart';
import '../mapaccess/osm_node.dart';
import '../mapaccess/osm_nodes_map.dart';
import '../mapaccess/physical_file.dart';
import 'area_info.dart';
import 'osm_node_named.dart';
import 'osm_nogo_polygon.dart';
import 'routing_context.dart';

class AreaReader {
  Directory? segmentFolder;

  void getDirectAllData(
    Directory folder,
    RoutingContext rc,
    OsmNodeNamed wp,
    int maxscale,
    BExpressionContextWay expctxWay,
    OsmNogoPolygon searchRect,
    List<AreaInfo> ais,
  ) {
    segmentFolder = folder;

    const div = 32;
    const cellsize = 1000000 ~/ div;
    final scale = maxscale;
    var count = 0;
    var used = 0;
    final checkBorder = maxscale > 7;

    final tiles = SplayTreeMap<int, String>();
    for (var idxLat = -scale; idxLat <= scale; idxLat++) {
      for (var idxLon = -scale; idxLon <= scale; idxLon++) {
        if (ignoreCenter(maxscale, idxLon, idxLat)) continue;
        final tmplon = wp.ilon + cellsize * idxLon;
        final tmplat = wp.ilat + cellsize * idxLat;
        final lonDegree = tmplon ~/ 1000000;
        final latDegree = tmplat ~/ 1000000;
        final lonMod5 = rem(lonDegree, 5);
        final latMod5 = rem(latDegree, 5);

        var lon = lonDegree - 180 - lonMod5;
        final slon = lon < 0 ? 'W${-lon}' : 'E$lon';
        var lat = latDegree - 90 - latMod5;
        final slat = lat < 0 ? 'S${-lat}' : 'N$lat';
        final filenameBase = '${slon}_$slat';

        final lonIdx = tmplon ~/ cellsize;
        final latIdx = tmplat ~/ cellsize;

        final subLonIdx = (lonIdx - div * lonDegree);
        final subLatIdx = (latIdx - div * latDegree);

        final dataRect = OsmNogoPolygon(true);
        lon = lonDegree * 1000000;
        lat = latDegree * 1000000;
        var tmplon2 = lon + cellsize * (subLonIdx);
        var tmplat2 = lat + cellsize * (subLatIdx);
        dataRect.addVertex(tmplon2, tmplat2);

        tmplon2 = lon + cellsize * (subLonIdx + 1);
        tmplat2 = lat + cellsize * (subLatIdx);
        dataRect.addVertex(tmplon2, tmplat2);

        tmplon2 = lon + cellsize * (subLonIdx + 1);
        tmplat2 = lat + cellsize * (subLatIdx + 1);
        dataRect.addVertex(tmplon2, tmplat2);

        tmplon2 = lon + cellsize * (subLonIdx);
        tmplat2 = lat + cellsize * (subLatIdx + 1);
        dataRect.addVertex(tmplon2, tmplat2);

        var intersects =
            checkBorder &&
            dataRect.intersects(
              searchRect.points[0].x,
              searchRect.points[0].y,
              searchRect.points[2].x,
              searchRect.points[2].y,
            );
        if (!intersects && checkBorder) {
          intersects = dataRect.intersects(
            searchRect.points[1].x,
            searchRect.points[1].y,
            searchRect.points[2].x,
            searchRect.points[3].y,
          );
        }
        if (intersects) {
          continue;
        }

        intersects = searchRect.intersects(
          dataRect.points[0].x,
          dataRect.points[0].y,
          dataRect.points[2].x,
          dataRect.points[2].y,
        );
        if (!intersects) {
          intersects = searchRect.intersects(
            dataRect.points[1].x,
            dataRect.points[1].y,
            dataRect.points[3].x,
            dataRect.points[3].y,
          );
        }
        if (!intersects) {
          intersects = containsRect(
            searchRect,
            dataRect.points[0].x,
            dataRect.points[0].y,
            dataRect.points[2].x,
            dataRect.points[2].y,
          );
        }

        if (!intersects) {
          continue;
        }

        tiles[(tmplon << 32) | tmplat] = filenameBase;
        count++;
      }
    }

    // Collections.sort (stable) by file name
    final list = tiles.entries.toList();
    final sorted = _stableSortBy(list, (e) => e.value);

    final maxmem = rc.memoryclass * 1024 * 1024; // in MB
    final nodesCache = NodesCache(
      segmentFolder!,
      expctxWay,
      rc.forceSecondaryData,
      maxmem,
      null,
      false,
    );
    PhysicalFile? pf;
    var lastFilenameBase = '';
    DataBuffers? dataBuffers;
    try {
      for (final entry in sorted) {
        final n = OsmNode.fromId(entry.key);
        final filenameBase = entry.value;
        if (filenameBase != lastFilenameBase) {
          if (pf != null) pf.close();
          lastFilenameBase = filenameBase;
          final file = File('${segmentFolder!.path}/$filenameBase.rd5');
          dataBuffers = DataBuffers();

          pf = PhysicalFile(file, dataBuffers, -1, -1);
        }
        if (getDirectData(
          pf!,
          dataBuffers!,
          n.getILon(),
          n.getILat(),
          rc,
          expctxWay,
          ais,
        )) {
          used++;
        }
      }
    } catch (e) {
      stderr.writeln('AreaReader: after $used/$count $e');
      ais.clear();
    } finally {
      if (pf != null) {
        try {
          pf.close();
        } catch (ee) {
          // ignore
        }
      }
      nodesCache.close();
    }
  }

  static List<MapEntry<int, String>> _stableSortBy(
    List<MapEntry<int, String>> list,
    String Function(MapEntry<int, String>) key,
  ) {
    if (list.length <= 1) return list;
    final mid = list.length ~/ 2;
    final a = _stableSortBy(list.sublist(0, mid), key);
    final b = _stableSortBy(list.sublist(mid), key);
    final res = <MapEntry<int, String>>[];
    var i = 0, j = 0;
    while (i < a.length && j < b.length) {
      if (key(b[j]).compareTo(key(a[i])) < 0) {
        res.add(b[j++]);
      } else {
        res.add(a[i++]);
      }
    }
    res.addAll(a.sublist(i));
    res.addAll(b.sublist(j));
    return res;
  }

  bool getDirectData(
    PhysicalFile pf,
    DataBuffers dataBuffers,
    int inlon,
    int inlat,
    RoutingContext rc,
    BExpressionContextWay expctxWay,
    List<AreaInfo> ais,
  ) {
    final lonDegree = inlon ~/ 1000000;
    final latDegree = inlat ~/ 1000000;

    final nodesMap = OsmNodesMap();

    try {
      final div = pf.divisor;

      final osmf = OsmFile(pf, lonDegree, latDegree, dataBuffers);
      if (osmf.hasData()) {
        final cellsize = 1000000 ~/ div;
        final tmplon = inlon;
        final tmplat = inlat;
        final lonIdx = tmplon ~/ cellsize;
        final latIdx = tmplat ~/ cellsize;

        final segment = osmf.createMicroCacheForIdx(
          lonIdx,
          latIdx,
          dataBuffers,
          expctxWay,
          null,
          true,
          null,
        );

        if (segment != null) {
          final size = segment.getSize();
          for (var i = 0; i < size; i++) {
            final id = segment.getIdForIndex(i);
            final node = OsmNode.fromId(id);
            if (segment.getAndClear(id)) {
              node.parseNodeBody(segment, nodesMap, expctxWay);
              if (node.firstlink != null) {
                for (
                  var link = node.firstlink;
                  link != null;
                  link = link.getNext(node)
                ) {
                  final nextNode = link.getTarget(node);
                  if (nextNode.firstlink == null) {
                    continue; // don't care about dead ends
                  }
                  if (nextNode.firstlink!.descriptionBitmap == null) {
                    continue;
                  }

                  for (final ai in ais) {
                    if (ai.polygon!.isWithin(node.ilon, node.ilat)) {
                      ai.checkAreaInfo(
                        expctxWay,
                        node.getElev(),
                        nextNode.firstlink!.descriptionBitmap!,
                      );
                      break;
                    }
                  }
                  break;
                }
              }
            }
          }
        }
        return true;
      }
    } catch (e) {
      stderr.writeln('AreaReader: $e');
    }
    return false;
  }

  bool ignoreCenter(int maxscale, int idxLon, int idxLat) {
    final centerScale = javaRound(maxscale * .2) - 1;
    if (centerScale < 0) return false;
    return idxLon >= -centerScale &&
        idxLon <= centerScale &&
        idxLat >= -centerScale &&
        idxLat <= centerScale;
  }

  /// in this case the polygon is 'only' a rectangle
  bool containsRect(
    OsmNogoPolygon searchRect,
    int p1x,
    int p1y,
    int p2x,
    int p2y,
  ) {
    return searchRect.isWithin(p1x, p1y) && searchRect.isWithin(p2x, p2y);
  }

  void writeAreaInfo(String filename, MatchedWaypoint wp, List<AreaInfo> ais) {
    final dos = DataOutputStream();

    wp.writeToStream(dos);
    for (final ai in ais) {
      dos.writeInt(ai.direction);
      dos.writeDouble(ai.elevStart);
      dos.writeInt(ai.ways);
      dos.writeInt(ai.greenWays);
      dos.writeInt(ai.riverWays);
      dos.writeInt(ai.elev50);
    }
    File(filename).writeAsBytesSync(dos.toByteArray());
  }

  void readAreaInfo(File fai, MatchedWaypoint wp, List<AreaInfo> ais) {
    try {
      final dis = DataInputStream(fai.readAsBytesSync());
      final ep = MatchedWaypoint.readFromStream(dis);
      if ((ep.waypoint!.ilon - wp.waypoint!.ilon).abs() > 500 &&
          (ep.waypoint!.ilat - wp.waypoint!.ilat).abs() > 500) {
        return;
      }
      if ((ep.radius - wp.radius).abs() > 500) {
        return;
      }
      for (var i = 0; i < 4; i++) {
        final direction = dis.readInt();
        final ai = AreaInfo(direction);
        ai.elevStart = dis.readDouble();
        ai.ways = dis.readInt();
        ai.greenWays = dis.readInt();
        ai.riverWays = dis.readInt();
        ai.elev50 = dis.readInt();
        ais.add(ai);
      }
    } on IOException {
      ais.clear();
    } on FileSystemException {
      ais.clear();
    }
  }
}
