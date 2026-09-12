// The decoders with the real BExpressionContextWay: `dump-microcache` with
// `--profile trekking` (inaccessible ways drop out, unused tags are filtered,
// 8 779 -> 8 627 nodes) and the way-tag strings of the two raw dumps, both
// committed samples of the oracle.

import 'dart:convert';
import 'dart:io';

import 'package:brouter_dart/brouter_dart.dart';
import 'package:test/test.dart';

import 'mapaccess_support.dart';
import 'vectors.dart';

Map<String, dynamic> loadSample(String name) => jsonDecode(
  File('../../../tools/brouter-oracle/dump/samples/$name').readAsStringSync(),
) as Map<String, dynamic>;

/// `Dump.dumpMicroCache`: decode the cell, walk it like AreaReader, compare
/// the first `limit` nodes with the sample (incl. the way tag strings).
void compareDump(
  Map<String, dynamic> sample,
  String cell,
  BExpressionContextWay ctxWay,
  TagValueValidator? validator,
) {
  final listing = loadVector('$cell.listing.json');
  final raw = loadBinary('$cell.bin');
  final lonIdx = listing['lonIdx'] as int;
  final latIdx = listing['latIdx'] as int;
  final divisor = listing['divisor'] as int;
  expect(sample['lonIdx'], lonIdx);
  expect(sample['latIdx'], latIdx);
  final segment = MicroCache2.decode(
    StatCoderContext(raw),
    DataBuffers(),
    lonIdx,
    latIdx,
    divisor,
    validator,
    null,
  );
  expect(segment.getSize(), sample['microcacheNodes']);
  expect(segment.getDataSize(), sample['microcacheDataSize']);
  final nodes = (sample['nodes'] as List).cast<Map<String, dynamic>>();
  final limit = sample['limit'] as int;
  expect(nodes.length, limit);
  final nodesMap = OsmNodesMap();
  final size = segment.getSize();
  var emitted = 0;
  for (var i = 0; i < size; i++) {
    if (limit >= 0 && emitted >= limit) break;
    final id = segment.getIdForIndex(i);
    final node = OsmNode.fromId(id);
    if (!segment.getAndClear(id)) continue;
    node.parseNodeBody(segment, nodesMap, ctxWay);
    final exp = nodes[emitted++];
    expect(id, exp['id64']);
    expect(node.ilon, exp['ilon']);
    expect(node.ilat, exp['ilat']);
    expect(node.selev, exp['selev'], reason: 'node $id selev');
    expect(
      node.nodeDescription == null ? null : hex(node.nodeDescription!),
      exp['nodeDescription'],
    );
    final links = <Map<String, Object?>>[];
    for (
      OsmLink? link = node.firstlink;
      link != null;
      link = link.getNext(node)
    ) {
      final target = link.getTarget(node);
      final reverse = link.isReverse(node);
      final d = link.descriptionBitmap;
      final g = link.geometry;
      links.add({
        'targetIlon': target.ilon,
        'targetIlat': target.ilat,
        'reverse': reverse,
        'bidirectional': link.isBidirectional(),
        'descriptionBitmap': d == null ? null : hex(d),
        'wayTags': d == null ? null : ctxWay.getKeyValueDescription(reverse, d),
        'geometryBytes': g == null ? null : hex(g),
      });
    }
    final expLinks = (exp['links'] as List).cast<Map<String, dynamic>>();
    expect(links.length, expLinks.length, reason: 'node $id link count');
    for (var k = 0; k < links.length; k++) {
      for (final key in links[k].keys) {
        expect(
          links[k][key],
          expLinks[k][key],
          reason: 'node $id link $k $key',
        );
      }
    }
  }
  expect(emitted, limit);
}

void main() {
  test('dump-microcache --profile trekking: Funchal filtered through the real profile', () {
    final sample = loadSample('microcache-W20_N30-funchal-trekking.json');
    expect(sample['profile'], 'trekking.brf');
    final ctxWay = profileWayContext('trekking');
    ctxWay.setDecodeForbidden(true); // "detailed" mode of the dump
    compareDump(sample, 'microcache-W20_N30-funchal', ctxWay, ctxWay);
    expect(sample['microcacheNodes'], 8627);
  });

  for (final (name, cell) in [
    ('microcache-W20_N30-funchal.json', 'microcache-W20_N30-funchal'),
    ('microcache-W25_N60-reykjavik.json', 'microcache-W25_N60-reykjavik'),
  ]) {
    test(
      '$name: way tag strings of the raw dump (lookups.dat only, no validator)',
      () {
        final sample = loadSample(name);
        expect(sample['profile'], isNull);
        // dump-microcache without --profile: readMetaData plus finishMetaParsing
        final meta = BExpressionMetaData();
        final ctxWay = BExpressionContextWay(meta);
        meta.readMetaData(lookupsFile);
        ctxWay.finishMetaParsing();
        ctxWay.setDecodeForbidden(true);
        compareDump(sample, cell, ctxWay, null);
      },
    );
  }
}
