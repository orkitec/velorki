// The decoded cells an OsmFile keeps for the next routing pass (WovenCell,
// upstream pull request abrensch/brouter#1015): a pass that weaves a cell
// from its recording has to build exactly the graph a pass that decodes it
// builds. The corpus proves that for whole routes against the oracle; this
// compares the graphs node by node, with the recordings and without.

import 'dart:convert';
import 'dart:typed_data';

import 'package:brouter_dart/brouter_dart.dart';
import 'package:test/test.dart';

import 'corpus_support.dart';
import 'mapaccess_support.dart';

const _maxmem = 64 * 1024 * 1024;

/// The id of the graph node nearest to a position.
int _startId(BExpressionContextWay ctxWay, double lon, double lat) {
  final cache = NodesCache(segmentsDir, ctxWay, false, _maxmem, null, false);
  final w = MatchedWaypoint()
    ..waypoint = OsmNode(toIlon(lon), toIlat(lat))
    ..name = 'from';
  expect(cache.matchWaypointsToNodes([w], 250.0, OsmNodePairSet(500)), isTrue);
  final id = w.node1!.getIdFromPos();
  cache.close();
  return id;
}

/// Breadth-first over [steps] nodes from [startId], every node as
/// [nodeJson]: position, elevation, description, turn restrictions and each
/// link with its target, direction, way tags and geometry.
List<Map<String, Object?>> _walk(NodesCache cache, int startId, int steps) {
  final gd = GeometryDecoder();
  final start = cache.getStartNode(startId)!;
  final queue = <OsmNode>[start];
  final seen = <int>{startId};
  final out = <Map<String, Object?>>[];
  var head = 0;
  while (head < queue.length && out.length < steps) {
    final n = queue[head++];
    for (OsmLink? link = n.firstlink; link != null; link = link.getNext(n)) {
      final t = link.getTarget(n);
      if (cache.obtainNonHollowNode(t) && seen.add(t.getIdFromPos())) {
        queue.add(t);
      }
    }
    out.add(nodeJson(n, gd));
  }
  return out;
}

class _Passes {
  _Passes(this.first, this.second, this.third, this.keptAfter);
  final List<Map<String, Object?>> first;
  final List<Map<String, Object?>> second;
  final List<Map<String, Object?>> third;

  /// The bytes kept after each pass, those of the passes before included.
  final List<int> keptAfter;
  int get kept => keptAfter.last;
}

/// Three passes over the same nodes, each cache made from the one before as
/// the routing engine does it.
_Passes _threePasses({
  required String profile,
  required bool detailed,
  required double lon,
  required double lat,
  required int steps,
  int maxmem = _maxmem,
}) {
  final ctxWay = profileWayContext(profile);
  final id = _startId(ctxWay, lon, lat);
  final c1 = NodesCache(segmentsDir, ctxWay, false, maxmem, null, detailed);
  final first = _walk(c1, id, steps);
  final kept1 = c1.wovenSum;
  final c2 = NodesCache(segmentsDir, ctxWay, false, maxmem, c1, detailed);
  final second = _walk(c2, id, steps);
  final kept2 = c2.wovenSum;
  // further than before: recorded and newly decoded cells side by side
  final c3 = NodesCache(segmentsDir, ctxWay, false, maxmem, c2, detailed);
  final third = _walk(c3, id, steps * 2);
  final kept3 = c3.wovenSum;
  c3.close();
  return _Passes(first, second, third, [kept1, kept2, kept3]);
}

void main() {
  final skip = tilesMissing;

  tearDown(() {
    NodesCache.disableWovenCells = false;
  });

  group('WovenCell', () {
    test('keeps what is added, in order, beyond its first size', () {
      final cell = WovenCell();
      final a = Uint8List.fromList([1, 2, 3]);
      for (var i = 0; i < 1000; i++) {
        cell.add(i * 7 - 3000);
      }
      for (var i = 0; i < 200; i++) {
        cell.addObject(i.isEven ? a : null);
      }
      cell.freeze();
      expect(cell.ints.length, 1000);
      expect(cell.objs.length, 200);
      expect(cell.ints, [for (var i = 0; i < 1000; i++) i * 7 - 3000]);
      expect(cell.objs, [for (var i = 0; i < 200; i++) i.isEven ? a : null]);
    });

    test('keeps the whole int range of a coordinate', () {
      final cell = WovenCell()
        ..add(0x7fffffff)
        ..add(-0x80000000)
        ..add(359999999);
      expect(cell.ints.sublist(0, 3), [0x7fffffff, -0x80000000, 359999999]);
    });

    test('counts its arrays and its geometries', () {
      final cell = WovenCell()
        ..add(1)
        ..add(2)
        ..addObject(null)
        ..addGeometry(Uint8List(10))
        ..addGeometry(null)
        ..freeze();
      expect(cell.getDataSize(), 48 + 4 * 2 + 8 * 3 + (16 + 10));
    });
  });

  for (final (name, lon, lat) in [
    ('Madeira', -16.92, 32.65),
    ('Iceland', -21.93, 64.14),
  ]) {
    for (final detailed in [false, true]) {
      test('$name, detailed=$detailed: a pass woven from the recordings builds '
          'the graph a decoding pass builds', () {
        _Passes run() => _threePasses(
          profile: 'trekking',
          detailed: detailed,
          lon: lon,
          lat: lat,
          steps: 4000,
        );
        final kept = run();
        NodesCache.disableWovenCells = true;
        final decoded = run();

        expect(kept.kept, greaterThan(0));
        expect(decoded.kept, 0);
        expect(kept.first.length, 4000);
        expect(kept.third.length, 8000);
        expectJson(kept.first, decoded.first, r'$.first');
        expectJson(kept.second, decoded.second, r'$.second');
        expectJson(kept.third, decoded.third, r'$.third');
        // the walk meets turn restrictions and geometries at all
        final all = jsonEncode(kept.third);
        expect(all, contains('"isPositive"'));
        expect(all, contains('"transferNodes":[{'));
      }, skip: skip);
    }
  }

  test('a pass over recorded cells does not read the tile again', () {
    List<Map<String, Object?>> secondPassWithTheFileClosed() {
      final ctxWay = profileWayContext('trekking');
      final id = _startId(ctxWay, -16.92, 32.65);
      final c1 = NodesCache(segmentsDir, ctxWay, false, _maxmem, null, true);
      final first = _walk(c1, id, 2000);
      c1.close();
      final c2 = NodesCache(segmentsDir, ctxWay, false, _maxmem, c1, true);
      final second = _walk(c2, id, 2000);
      expectJson(second, first);
      return second;
    }

    expect(secondPassWithTheFileClosed(), hasLength(2000));
    NodesCache.disableWovenCells = true;
    expect(secondPassWithTheFileClosed, throwsA(anything));
  }, skip: skip);

  test('the kept cells stop at an eighth of the memory', () {
    // 400 kB: room for a few cells, far fewer than the walk reads
    const maxmem = 400 * 1024;
    _Passes run() => _threePasses(
      profile: 'trekking',
      detailed: true,
      lon: -16.92,
      lat: 32.65,
      steps: 4000,
      maxmem: maxmem,
    );
    final unbounded = _threePasses(
      profile: 'trekking',
      detailed: true,
      lon: -16.92,
      lat: 32.65,
      steps: 4000,
    );
    final bounded = run();
    NodesCache.disableWovenCells = true;
    final decoded = run();

    // the second pass reads the first one's cells, the third reads further
    expect(unbounded.keptAfter[1], unbounded.keptAfter[0]);
    expect(unbounded.keptAfter[2], greaterThan(unbounded.keptAfter[1]));
    // at the limit after the first pass, and the later ones add nothing
    expect(bounded.keptAfter[1], bounded.keptAfter[0]);
    expect(bounded.keptAfter[2], bounded.keptAfter[0]);
    expect(bounded.kept, lessThan(unbounded.kept ~/ 2));
    // the cell that crosses the limit is the last one kept
    expect(bounded.kept, greaterThanOrEqualTo(maxmem ~/ 8));
    expectJson(bounded.second, decoded.second, r'$.second');
    expectJson(bounded.third, decoded.third, r'$.third');
  }, skip: skip);

  test('a route and its alternative are the same bytes without them', () async {
    final corpus = loadCorpus();
    final cases = [
      corpus.firstWhere((c) => c.id == 'pair-000'),
      corpus.firstWhere((c) => c.id == 'triple-031'),
      corpus.firstWhere((c) => c.id == 'roundtrip-000'),
    ];
    Future<List<String>> run() async {
      final router = BRouter(
        segmentsDir: segmentsDir,
        profilesDir: profilesDir,
      );
      return [for (final c in cases) await router.routeQuery(c.query)];
    }

    final kept = await run();
    NodesCache.disableWovenCells = true;
    final decoded = await run();
    for (var i = 0; i < cases.length; i++) {
      expect(kept[i], decoded[i], reason: cases[i].id);
      expect(
        utf8.encode(decoded[i]),
        cases[i].responseFile.readAsBytesSync(),
        reason: cases[i].id,
      );
    }
  }, skip: skip);
}
