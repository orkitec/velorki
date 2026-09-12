// L2-mapaccess parity: NodesCache / OsmFile / PhysicalFile / DirectWeaver /
// MicroCache2 / OsmNode / OsmNodesMap / WaypointMatcherImpl / GeometryDecoder
// against the oracle's `nodes-cache-walk` on the two real tiles (see
// tools/brouter-oracle/README.md). Every walk JSON carries its parameters.

import 'dart:io';

import 'package:test/test.dart';

import 'mapaccess_support.dart';

void main() {
  final skip = tilesMissing;
  final files =
      Directory('test/vectors/mapaccess')
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => n.startsWith('walk-') && n.endsWith('.json'))
          .toList()
        ..sort();
  if (files.length < 12) {
    throw StateError('expected at least 12 walk vectors, found $files');
  }

  for (final name in files) {
    group(name, () {
      final expected = loadMapaccessVector(name);
      late Map<String, Object?> actual;

      setUpAll(() {
        actual = runWalk(expected);
      });

      test('matchWaypointsToNodes: crosspoints, nodes, radii, wayNearest', () {
        expectJson(actual['match'], expected['match'], r'$.match');
      });

      test(
        'graph nodes obtained and expanded: links, geometry, restrictions',
        () {
          expectJson(actual['expand'], expected['expand'], r'$.expand');
        },
      );

      test('breadth-first walk over ${expected['steps']} nodes', () {
        expectJson(actual['walk'], expected['walk'], r'$.walk');
      });

      test('collectOutreachers / canEscape (vanish, HashMap order)', () {
        expectJson(actual['collect'], expected['collect'], r'$.collect');
      });

      test('getStartNode after a reset (ghost state)', () {
        expectJson(actual['startNode'], expected['startNode'], r'$.startNode');
      });
    }, skip: skip);
  }
}
