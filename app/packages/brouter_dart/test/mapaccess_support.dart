// Helpers for the L2-mapaccess parity tests: the segment directory, the
// "every way" validator the oracle's `nodes-cache-walk` uses, and a Dart
// replica of that walk producing the same JSON structure.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:brouter_dart/brouter_dart.dart';
import 'package:test/test.dart';

import 'vectors.dart';

/// The rd5 tiles are not committed (1.5 + 2.7 MB); the tests read them from
/// `BROUTER_SEGMENTS_DIR`, by default the oracle's cache
/// (`tools/brouter-oracle/fetch.sh` downloads and checksums them).
final Directory segmentsDir = Directory(
  Platform.environment['BROUTER_SEGMENTS_DIR'] ??
      '../../../tools/brouter-oracle/.cache/segments4',
);

const List<String> tiles = ['W20_N30', 'W25_N60'];

/// A skip reason when the tiles are absent, else null.
String? get tilesMissing {
  for (final t in tiles) {
    final f = File('${segmentsDir.path}/$t.rd5');
    if (!f.existsSync()) {
      return 'rd5 tiles not found in ${segmentsDir.absolute.path} '
          '(run tools/brouter-oracle/fetch.sh or set BROUTER_SEGMENTS_DIR)';
    }
  }
  return null;
}

Map<String, dynamic> loadMapaccessVector(String name) =>
    jsonDecode(File('test/vectors/mapaccess/$name').readAsStringSync())
        as Map<String, dynamic>;

/// What `nodes-cache-walk` builds on the Java side: a `BExpressionContextWay`
/// with `lookups.dat`, a profile of just `assign costfactor = 1` (accessType 2
/// for every way, no `noStartWay`) and `setAllTagsUsed()`.
class AllWaysValidator implements TagValueValidator, IByteArrayUnifier {
  final ByteArrayUnifier _unifier = ByteArrayUnifier(16384, false);

  @override
  int accessType(Uint8List tagValueSet) => 2;

  @override
  Uint8List unify(Uint8List ab, int offset, int len) =>
      _unifier.unify(ab, offset, len);

  @override
  bool isLookupIdxUsed(int idx) => true;

  @override
  void setDecodeForbidden(bool decodeForbidden) {}

  @override
  bool checkStartWay(Uint8List ab) => true;
}

int toIlon(double lon) => d2i((lon + 180.0) * 1000000.0 + 0.5);
int toIlat(double lat) => d2i((lat + 90.0) * 1000000.0 + 0.5);

/// `Long.toHexString(Double.doubleToRawLongBits(v))`.
String hexd(double v) =>
    doubleToRawLongBits(v).toUnsigned(64).toRadixString(16);

Map<String, Object?>? _pos(OsmNode? n) =>
    n == null ? null : {'ilon': n.ilon, 'ilat': n.ilat};

Map<String, Object?> _mwpJson(MatchedWaypoint w, bool withNearest) {
  final m = <String, Object?>{
    'name': w.name,
    'waypoint': _pos(w.waypoint),
    'crosspoint': _pos(w.crosspoint),
    'node1': _pos(w.node1),
    'node2': _pos(w.node2),
    'radius': hexd(w.radius),
    'directionToNext': hexd(w.directionToNext),
    'directionDiff': hexd(w.directionDiff),
    'wpttype': w.wpttype,
  };
  if (withNearest) {
    m['wayNearest'] = [for (final n in w.wayNearest) _mwpJson(n, false)];
  }
  return m;
}

int _linkCount(OsmNode n) {
  var c = 0;
  for (OsmLink? l = n.firstlink; l != null; l = l.getNext(n)) {
    c++;
  }
  return c;
}

Map<String, Object?> nodeJson(OsmNode node, GeometryDecoder gd) {
  final trs = <Map<String, Object?>>[];
  for (var tr = node.firstRestriction; tr != null; tr = tr.next) {
    trs.add({
      'isPositive': tr.isPositive,
      'exceptions': tr.exceptions,
      'fromLon': tr.fromLon,
      'fromLat': tr.fromLat,
      'toLon': tr.toLon,
      'toLat': tr.toLat,
    });
  }
  final links = <Map<String, Object?>>[];
  for (
    OsmLink? link = node.firstlink;
    link != null;
    link = link.getNext(node)
  ) {
    final target = link.getTarget(node);
    final reverse = link.isReverse(node);
    final g = link.geometry;
    final tns = <Map<String, Object?>>[];
    if (g != null) {
      for (
        var tn = gd.decodeGeometry(g, node, target, reverse);
        tn != null;
        tn = tn.next
      ) {
        tns.add({'ilon': tn.ilon, 'ilat': tn.ilat, 'selev': tn.selev});
      }
    }
    final d = link.descriptionBitmap;
    links.add({
      'targetIlon': target.ilon,
      'targetIlat': target.ilat,
      'targetSelev': target.selev,
      'targetHollow': target.isHollow(),
      'targetVisitID': target.visitID,
      'targetLinks': _linkCount(target),
      'reverse': reverse,
      'bidirectional': link.isBidirectional(),
      'linkIsNode': link is OsmNode,
      'descriptionBitmap': d == null ? null : hex(d),
      'geometryBytes': g == null ? null : hex(g),
      'transferNodes': tns,
    });
  }
  final nd = node.nodeDescription;
  return {
    'id64': node.getIdFromPos(),
    'ilon': node.ilon,
    'ilat': node.ilat,
    'selev': node.selev,
    'hollow': node.isHollow(),
    'visitID': node.visitID,
    'nodeDescription': nd == null ? null : hex(nd),
    'turnRestrictions': trs,
    'links': links,
  };
}

String walkRecord(
  OsmNode n,
  GeometryDecoder gd,
  ByteDataWriter w,
  Uint8List buf,
) {
  w.reset(buf);
  var nlinks = 0;
  var nhollow = 0;
  for (OsmLink? link = n.firstlink; link != null; link = link.getNext(n)) {
    final t = link.getTarget(n);
    final reverse = link.isReverse(n);
    nlinks++;
    if (t.isHollow()) nhollow++;
    w.writeLong(t.getIdFromPos());
    w.writeBoolean(reverse);
    w.writeBoolean(link.isBidirectional());
    w.writeShort(t.selev);
    w.writeVarBytes(link.descriptionBitmap);
    w.writeVarBytes(link.geometry);
    final g = link.geometry;
    if (g != null) {
      for (
        var tn = gd.decodeGeometry(g, n, t, reverse);
        tn != null;
        tn = tn.next
      ) {
        w.writeInt(tn.ilon);
        w.writeInt(tn.ilat);
        w.writeShort(tn.selev);
      }
    }
  }
  for (var tr = n.firstRestriction; tr != null; tr = tr.next) {
    w.writeBoolean(tr.isPositive);
    w.writeShort(tr.exceptions);
    w.writeInt(tr.fromLon);
    w.writeInt(tr.fromLat);
    w.writeInt(tr.toLon);
    w.writeInt(tr.toLat);
  }
  final data = w.toByteArray();
  return '${n.getIdFromPos()} ${n.selev} ${n.visitID} $nlinks $nhollow ${Crc32.crc(data, 0, data.length)}';
}

int _recordsCrc(List<String> records) {
  final bytes = Uint8List.fromList(ascii.encode(records.join()));
  return Crc32.crc(bytes, 0, bytes.length);
}

MatchedWaypoint _mwp(String name, double lon, double lat) {
  final w = MatchedWaypoint();
  w.waypoint = OsmNode(toIlon(lon), toIlat(lat));
  w.name = name;
  return w;
}

/// The Dart side of `Dump.nodesCacheWalk`, phase for phase.
Map<String, Object?> runWalk(Map<String, dynamic> v) {
  final from = (v['from'] as String).split(',').map(double.parse).toList();
  final to = (v['to'] as String).split(',').map(double.parse).toList();
  final maxmem = v['maxmem'] as int;
  final directWeaving = v['directWeaving'] as bool;
  final cleanupMode = v['cleanupMode'] as int;
  final steps = v['steps'] as int;
  final collectMaxCost = v['collectMaxCost'] as int;
  final lookupVersion = v['lookupVersion'] as int;
  final lookupMinorVersion = v['lookupMinorVersion'] as int;

  NodesCache.disableDirectWeaving = !directWeaving;
  final ctxWay = AllWaysValidator();
  final gd = GeometryDecoder();
  final out = <String, Object?>{};

  // phase 1: matchWaypointsToNodes
  final cache = NodesCache(
    segmentsDir,
    ctxWay,
    false,
    maxmem,
    null,
    false,
    lookupVersion: lookupVersion,
    lookupMinorVersion: lookupMinorVersion,
  );
  final list = [_mwp('from', from[0], from[1]), _mwp('to', to[0], to[1])];
  final islands = OsmNodePairSet(500);
  final ok = cache.matchWaypointsToNodes(list, 250.0, islands);
  out['match'] = {
    'ok': ok,
    'firstFileAccessFailed': cache.firstFileAccessFailed,
    'firstFileAccessName': cache.firstFileAccessName,
    'status': cache.formatStatus(),
    'nodesCreated': cache.nodesMap.nodesCreated,
    'elevationType': cache.getElevationType(toIlon(from[0]), toIlat(from[1])),
    'waypoints': [for (final w in list) _mwpJson(w, true)],
  };
  if (!ok) {
    out['expand'] = null;
    out['walk'] = null;
    out['startNode'] = null;
    cache.close();
    return out;
  }

  // phase 2: reset, graph nodes, obtain + expand
  final cache2 = NodesCache(
    segmentsDir,
    ctxWay,
    false,
    maxmem,
    cache,
    false,
    lookupVersion: lookupVersion,
    lookupMinorVersion: lookupMinorVersion,
  );
  cache2.nodesMap.cleanupMode = cleanupMode;
  final statusAfterReset2 = cache2.formatStatus();
  final graphNodes = <OsmNode>[];
  for (final w in list) {
    graphNodes.add(cache2.getGraphNode(w.node1!));
    graphNodes.add(cache2.getGraphNode(w.node2!));
  }
  final walkStart = graphNodes[0];
  final expandNodes = <Map<String, Object?>>[];
  for (final n in graphNodes) {
    final obtained = cache2.obtainNonHollowNode(n);
    cache2.expandHollowLinkTargets(n);
    expandNodes.add({'obtained': obtained, 'node': nodeJson(n, gd)});
  }
  out['expand'] = {
    'statusAfterReset': statusAfterReset2,
    'nodes': expandNodes,
    'status': cache2.formatStatus(),
    'nodesCreated': cache2.nodesMap.nodesCreated,
  };

  // phase 3: breadth-first walk
  final queue = <OsmNode>[];
  var head = 0;
  final seen = <int>{};
  queue.add(walkStart);
  seen.add(walkStart.getIdFromPos());
  final records = <String>[];
  final walked = <OsmNode>[];
  final recordBuf = Uint8List(1 << 20);
  final w = ByteDataWriter(recordBuf);
  var obtainedCount = 0;
  var failedCount = 0;
  while (head < queue.length && records.length < steps) {
    final n = queue[head++];
    for (OsmLink? link = n.firstlink; link != null; link = link.getNext(n)) {
      final t = link.getTarget(n);
      final got = cache2.obtainNonHollowNode(t);
      if (got) {
        obtainedCount++;
      } else {
        failedCount++;
      }
      if (got && seen.add(t.getIdFromPos())) queue.add(t);
    }
    records.add(walkRecord(n, gd, w, recordBuf));
    walked.add(n);
  }
  out['walk'] = {
    'visited': records.length,
    'queued': queue.length - head,
    'obtained': obtainedCount,
    'failed': failedCount,
    'crc': _recordsCrc(records),
    'status': cache2.formatStatus(),
    'nodesCreated': cache2.nodesMap.nodesCreated,
    'records': records,
  };

  // phase 3b: collectOutreachers + canEscape
  final nm = cache2.nodesMap;
  nm.destination = graphNodes[2];
  nm.currentMaxCost = collectMaxCost;
  nm.currentPathCost = 0;
  final nodesCreatedBefore = nm.nodesCreated;
  nm.collectOutreachers();
  final nodesCreatedCollected = nm.nodesCreated;
  final escStart = nm.canEscape(walkStart);
  final escEnd = nm.canEscape(graphNodes[2]);
  nm.clearTemp();
  final records2 = [for (final n in walked) walkRecord(n, gd, w, recordBuf)];
  out['collect'] = {
    'nodesCreatedBefore': nodesCreatedBefore,
    'nodesCreated': nodesCreatedCollected,
    'canEscapeStart': escStart,
    'canEscapeEnd': escEnd,
    'nodesCreatedAfterEscape': nm.nodesCreated,
    'lastVisitID': nm.lastVisitID,
    'baseID': nm.baseID,
    'crc': _recordsCrc(records2),
    'records': records2,
  };

  // phase 4: fresh reset and getStartNode
  final cache3 = NodesCache(
    segmentsDir,
    ctxWay,
    false,
    maxmem,
    cache2,
    false,
    lookupVersion: lookupVersion,
    lookupMinorVersion: lookupMinorVersion,
  );
  cache3.nodesMap.cleanupMode = cleanupMode;
  final statusAfterReset3 = cache3.formatStatus();
  final start = cache3.getStartNode(list[0].node1!.getIdFromPos());
  out['startNode'] = {
    'statusAfterReset': statusAfterReset3,
    'node': start == null ? null : nodeJson(start, gd),
    'status': cache3.formatStatus(),
    'nodesCreated': cache3.nodesMap.nodesCreated,
  };
  cache3.close();
  return out;
}

/// Deep comparison that names the path of the first difference.
void expectJson(Object? actual, Object? expected, [String path = r'$']) {
  if (expected is Map) {
    if (actual is! Map) {
      throw TestFailure('$path: expected a map, got $actual');
    }
    for (final k in expected.keys) {
      if (!actual.containsKey(k)) throw TestFailure('$path.$k: missing');
      expectJson(actual[k], expected[k], '$path.$k');
    }
    for (final k in actual.keys) {
      if (!expected.containsKey(k)) throw TestFailure('$path.$k: unexpected');
    }
    return;
  }
  if (expected is List) {
    if (actual is! List) {
      throw TestFailure('$path: expected a list, got $actual');
    }
    final n = actual.length < expected.length ? actual.length : expected.length;
    for (var i = 0; i < n; i++) {
      expectJson(actual[i], expected[i], '$path[$i]');
    }
    if (actual.length != expected.length) {
      throw TestFailure(
        '$path: ${actual.length} elements, expected ${expected.length}',
      );
    }
    return;
  }
  if (actual != expected) {
    throw TestFailure('$path: got $actual, expected $expected');
  }
}
