// Unit checks for the mapaccess classes the oracle walk does not reach:
// MatchedWaypoint streams, TurnRestriction, the node/link mechanics of
// OsmNode/OsmLink, GeometryDecoder's pool and JavaHashMap's iteration order.

import 'dart:io';
import 'dart:typed_data';

import 'package:brouter_dart/brouter_dart.dart';
import 'package:test/test.dart';

void main() {
  test('MatchedWaypoint writeToStream / readFromStream round trip', () {
    final w = MatchedWaypoint()
      ..node1 = OsmNode(1, 2)
      ..node2 = OsmNode(3, 4)
      ..crosspoint = OsmNode(5, 6)
      ..waypoint = OsmNode(7, 8)
      ..radius = 12.5
      ..wpttype = MatchedWaypoint.waypointTypeDirect
      ..name = 'via 1';
    final dos = DataOutputStream();
    w.writeToStream(dos);
    final bytes = dos.toByteArray();
    expect(bytes.length, 8 * 4 + 8 + 1 + 2 + 5);
    final r = MatchedWaypoint.readFromStream(DataInputStream(bytes));
    expect([r.node1!.ilon, r.node1!.ilat], [1, 2]);
    expect([r.node2!.ilon, r.node2!.ilat], [3, 4]);
    expect([r.crosspoint!.ilon, r.crosspoint!.ilat], [5, 6]);
    expect([r.waypoint!.ilon, r.waypoint!.ilat], [7, 8]);
    expect(r.radius, 12.5);
    expect(r.wpttype, MatchedWaypoint.waypointTypeDirect);
    expect(r.name, 'via 1');
  });

  test('TurnRestriction.isTurnForbidden', () {
    TurnRestriction tr(bool positive, int exc, int toLon) => TurnRestriction()
      ..isPositive = positive
      ..exceptions = exc
      ..fromLon = 10
      ..fromLat = 10
      ..toLon = toLon
      ..toLat = 20;
    // a negative restriction forbids exactly that turn
    final neg = tr(false, 0, 30);
    expect(
      TurnRestriction.isTurnForbidden(neg, 10, 10, 30, 20, false, false),
      isTrue,
    );
    expect(
      TurnRestriction.isTurnForbidden(neg, 10, 10, 31, 20, false, false),
      isFalse,
    );
    expect(
      TurnRestriction.isTurnForbidden(neg, 11, 10, 30, 20, false, false),
      isFalse,
    );
    // a positive ("only") restriction forbids every other turn from that way
    final pos = tr(true, 0, 30);
    expect(
      TurnRestriction.isTurnForbidden(pos, 10, 10, 30, 20, false, false),
      isFalse,
    );
    expect(
      TurnRestriction.isTurnForbidden(pos, 10, 10, 31, 20, false, false),
      isTrue,
    );
    // exceptions: bit 1 bikes, bit 2 motorcars
    final excBikes = tr(false, 1, 30);
    expect(excBikes.exceptBikes(), isTrue);
    expect(excBikes.exceptMotorcars(), isFalse);
    expect(
      TurnRestriction.isTurnForbidden(excBikes, 10, 10, 30, 20, true, false),
      isFalse,
    );
    expect(
      TurnRestriction.isTurnForbidden(excBikes, 10, 10, 30, 20, false, true),
      isTrue,
    );
    // chained: a positive elsewhere plus a matching positive
    pos.next = tr(true, 0, 31);
    expect(
      TurnRestriction.isTurnForbidden(pos, 10, 10, 31, 20, false, false),
      isFalse,
    );
    expect(
      TurnRestriction.isTurnForbidden(null, 10, 10, 31, 20, false, false),
      isFalse,
    );
    expect(neg.toString(), 'pos=false fromLon=10 fromLat=10 toLon=30 toLat=20');
  });

  test('OsmNode: ids, hollow state, distance, toString', () {
    final n = OsmNode(163136958, 122646756);
    expect(n.getIdFromPos(), 700667899501572324);
    final m = OsmNode.fromId(700667899501572324);
    expect([m.ilon, m.ilat], [163136958, 122646756]);
    expect(m.isHollow(), isFalse);
    m.setHollow();
    expect(m.isHollow(), isTrue);
    expect(m.selev, -12345);
    expect(OsmNode().selev, -32768);
    expect(n.calcDistance(n), 1, reason: 'never below 1 m');
    expect(n.calcDistance(OsmNode(163136958 + 1000, 122646756)), 94);
    expect(n.toString(), 'n_-16863042_32646756');
    expect(n.getElev(), 122646756 == 0 ? 0 : n.selev / 4.0);
    expect(OsmNode.posHashCode(n), i32(163136958 + 122646756));
    expect(OsmNode.posEquals(n, m), isTrue);
    expect(n == m, isFalse, reason: '== stays identity, like Java ==');
  });

  test('OsmNode/OsmLink: a hollow proxy is its own first link, unlink, vanish', () {
    final hollow = OsmNodesMap();
    final a = OsmNode(100, 100)..selev = 1;
    // an external link from a to (200, 200): the proxy node is the link object
    a.addLinkTo(200, 200, Uint8List.fromList([1, 2]), null, hollow, false);
    final b = hollow.get(200, 200)!;
    expect(b.isHollow(), isTrue);
    expect(identical(a.firstlink, b), isTrue, reason: 'technical inheritance');
    expect(a.firstlink!.getTarget(a), same(b));
    expect(b.firstlink!.getTarget(b), same(a));
    expect(a.firstlink!.isReverse(a), isFalse);
    expect(b.firstlink!.isReverse(b), isTrue);
    expect(a.firstlink!.isBidirectional(), isTrue);
    expect(a.firstlink!.descriptionBitmap, [1, 2]);
    // the reverse side of the same way, decoded later at b, reuses the link
    b.addLinkTo(100, 100, null, null, hollow, true);
    expect(b.firstlink!.getNext(b), isNull, reason: 'no duplicate link');
    // self references are skipped
    a.addLinkTo(100, 100, null, null, hollow, false);
    expect(a.firstlink!.getNext(a), isNull);
    // a second, plain link
    final c = OsmNode(300, 300)..selev = 3;
    a.addLink(OsmLink(), false, c);
    expect(a.firstlink!.getTarget(a), same(c));
    expect(a.firstlink!.getNext(a)!.getTarget(a), same(b));
    // vanish removes links to non-hollow targets only
    a.vanish();
    expect(a.firstlink!.getTarget(a), same(b));
    expect(a.firstlink!.getNext(a), isNull);
    expect(c.firstlink, isNull);
    // unlinking the last link clears the way data
    a.unlinkLink(a.firstlink!);
    expect(a.firstlink, isNull);
    b.unlinkLink(b.firstlink!);
    expect(b.isLinkUnused(), isTrue);
    expect(b.descriptionBitmap, isNull);
  });

  test('OsmLink holders and error paths', () {
    final n1 = OsmNode(1, 1);
    final n2 = OsmNode(2, 2);
    final link = OsmLink(n1, n2);
    final h1 = _Holder();
    final h2 = _Holder();
    link.addLinkHolder(h1, n1);
    link.addLinkHolder(h2, n1);
    expect(link.getFirstLinkHolder(n1), same(h2));
    expect(h2.getNextForLink(), same(h1));
    expect(link.getFirstLinkHolder(n2), isNull);
    expect(
      () => link.getFirstLinkHolder(OsmNode(3, 3)),
      returnsNormally,
      reason: 'an unknown source reads as the forward side',
    );
    final startLink = OsmLink(null, n1);
    startLink.addLinkHolder(h1, null);
    expect(startLink.getTarget(null), same(n1));
    expect(() => OsmLink().clear(n1), throwsArgumentError);
  });

  test('GeometryDecoder: chaining, reverse order, result cache and pool', () {
    final w = ByteDataWriter(Uint8List(64));
    // three transfer nodes as (dlon, dlat, dele) deltas
    for (final d in [
      [10, 20, 4],
      [-5, 5, -2],
      [1, 1, 0],
    ]) {
      w.writeVarLengthSigned(d[0]);
      w.writeVarLengthSigned(d[1]);
      w.writeVarLengthSigned(d[2]);
    }
    final g = w.toByteArray();
    final src = OsmNode(1000, 2000)..selev = 100;
    final dst = OsmNode(1006, 2026)..selev = 102;
    final gd = GeometryDecoder();
    final f = gd.decodeGeometry(g, src, dst, false)!;
    expect([f.ilon, f.ilat, f.selev], [1010, 2020, 104]);
    expect([f.next!.ilon, f.next!.ilat, f.next!.selev], [1005, 2025, 102]);
    expect([f.next!.next!.ilon, f.next!.next!.selev], [1006, 102]);
    expect(f.next!.next!.next, isNull);
    expect(gd.decodeGeometry(g, src, dst, false), same(f), reason: 'cached');
    // reverse: decoded from the target, chained backwards
    final r = gd.decodeGeometry(g, src, dst, true)!;
    expect([r.ilon, r.ilat], [1012, 2052]);
    expect([r.next!.ilon, r.next!.ilat], [1011, 2051]);
    expect([r.next!.next!.ilon, r.next!.next!.ilat], [1016, 2046]);
    expect(r.next!.next!.next, isNull);
    // the pool is reused: the forward result is overwritten by the next call
    expect(f.ilon, isNot(1010));
    expect(gd.decodeGeometry(Uint8List(0), src, dst, false), isNull);
  });

  test('JavaHashMap iterates in java.util.HashMap order', () {
    final m = JavaHashMap<int, int>(16, (k) => k, (a, b) => a == b);
    // 1, 17, 33 share bucket 1 of 16; 2 and 18 bucket 2
    for (final k in [17, 1, 33, 2, 18]) {
      expect(m.put(k, k), isNull);
    }
    expect(m.values.toList(), [17, 1, 33, 2, 18]);
    expect(m.put(1, 100), 1, reason: 'previous value');
    expect(m.get(1), 100);
    expect(m.values.toList(), [17, 100, 33, 2, 18], reason: 'order kept');
    // the 13th entry triggers the resize to 32 buckets: chains are split
    // into lo (bit 16 clear) and hi (bit 16 set) lists, order preserved:
    // bucket 1 [17, 1, 33, 65] -> bucket 1 [1, 33, 65] + bucket 17 [17]
    for (var k = 64; k < 72; k++) {
      m.put(k, k);
    }
    expect(m.length, 13);
    expect(m.values.toList(), [
      64,
      100,
      33,
      65,
      2,
      66,
      67,
      68,
      69,
      70,
      71,
      17,
      18,
    ]);
    expect(m.remove(33), 33);
    expect(m.remove(33), isNull);
    expect(m.get(33), isNull);
    expect(m.values.toList(), [64, 100, 65, 2, 66, 67, 68, 69, 70, 71, 17, 18]);
    expect(m.length, 12);
    // negative hash codes are spread like Java ints
    final neg = JavaHashMap<int, int>(4, (k) => k, (a, b) => a == b);
    neg.put(-1, 1);
    neg.put(3, 3);
    expect(neg.values.toList(), [-1, 3].map((k) => neg.get(k)).toList());
  });

  test('OsmNodesMap: get/put/remove by position, endnodes are kept', () {
    final map = OsmNodesMap();
    final a = OsmNode(5, 6);
    expect(map.put(a), isNull);
    expect(map.get(5, 6), same(a));
    final a2 = OsmNode(5, 6);
    expect(map.put(a2), same(a), reason: 'previous node for that position');
    expect(map.get(5, 6), same(a2));
    map.endNode1 = a2;
    map.remove(a2);
    expect(map.get(5, 6), same(a2), reason: 'end nodes stay in the map');
    map.endNode1 = null;
    map.remove(a2);
    expect(map.get(5, 6), isNull);
    expect(map.isInMemoryBounds(0, false), isTrue);
    map.nodesCreated = 100000;
    expect(map.isInMemoryBounds(0, false), isFalse, reason: '9.5 MB > 4 MB');
    map.maxmem = 64 << 20;
    expect(map.isInMemoryBounds(0, true), isTrue, reason: 'extended');
  });

  test('OsmNodePairSet', () {
    final s = OsmNodePairSet(2);
    s.addTempPair(1, 2);
    s.addTempPair(3, 4);
    s.addTempPair(5, 6); // beyond maxTempNodes: dropped
    expect(s.tempSize(), 2);
    expect(s.hasPair(1, 2), isFalse);
    s.freezeTempPairs();
    expect(s.getFreezeCount(), 1);
    expect(s.size(), 2);
    expect(s.hasPair(1, 2), isTrue);
    expect(s.hasPair(2, 1), isTrue, reason: 'either direction');
    expect(s.hasPair(3, 4), isTrue);
    expect(s.hasPair(5, 6), isFalse);
    s.addTempPair(1, 7);
    s.freezeTempPairs();
    expect(s.hasPair(1, 7), isTrue);
    expect(s.hasPair(1, 2), isTrue);
    expect(s.getMaxTmpNodes(), 2);
    s.addTempPair(9, 9);
    s.clearTempPairs();
    expect(s.tempSize(), 0);
  });

  test('Rd5DiffTool is a stub for track R5', () {
    expect(
      () => Rd5DiffTool.recoverFromDelta(
        File('a'),
        File('b'),
        File('c'),
        _NoProgress(),
      ),
      throwsUnimplementedError,
    );
  });
}

class _Holder implements OsmLinkHolder {
  OsmLinkHolder? _next;

  @override
  OsmLinkHolder? getNextForLink() => _next;

  @override
  void setNextForLink(OsmLinkHolder? holder) => _next = holder;
}

class _NoProgress implements ProgressListener {
  @override
  bool isCanceled() => false;

  @override
  void updateProgress(String task, int progress) {}
}
