// L3 parity: every case of tools/brouter-oracle/corpus routed with the Dart
// engine on the same tiles, profiles and parameters, compared byte for byte
// with the recorded GeoJSON body of the real 1.7.10 server (and, so that a
// partial mismatch is readable, field by field).

import 'dart:convert';
import 'dart:io';

import 'package:brouter_dart/brouter_dart.dart';
import 'package:test/test.dart';

import 'corpus_support.dart';
import 'mapaccess_support.dart';

void main() {
  final skip = tilesMissing;
  final cases = loadCorpus();
  if (cases.length != 200) {
    throw StateError('expected 200 cases, got ${cases.length}');
  }
  final only = Platform.environment['BROUTER_CORPUS_ONLY'];

  final router = oracleRouter();

  for (final c in cases) {
    if (only != null && !c.id.startsWith(only)) continue;
    test('${c.id} (${c.kind}, ${c.profile})', () async {
      final expectedBytes = c.responseFile.readAsBytesSync();
      final expectedText = utf8.decode(expectedBytes);
      final actualText = await router.routeQuery(c.query);
      final actualBytes = utf8.encode(actualText);
      final diff = firstDifference(actualBytes, expectedBytes);
      if (diff != null) {
        // structural comparison first, so the failure names the field
        final e = RoutingResult.parse(expectedText);
        final a = RoutingResult.parse(actualText);
        expect(
          a.coordinates.length,
          e.coordinates.length,
          reason: 'coordinate count',
        );
        expect(a.coordinates, e.coordinates, reason: 'coordinates');
        expect(a.trackLength, e.trackLength, reason: 'track-length');
        expect(a.filteredAscend, e.filteredAscend, reason: 'filtered ascend');
        expect(a.plainAscend, e.plainAscend, reason: 'plain-ascend');
        expect(a.cost, e.cost, reason: 'cost');
        expect(a.messages, e.messages, reason: 'messages');
        expect(a.times, e.times, reason: 'times');
        expect(a.totalTimeSeconds, e.totalTimeSeconds, reason: 'total-time');
        expect(a.totalEnergy, e.totalEnergy, reason: 'total-energy');
        fail(diff);
      }
    }, skip: skip);
  }
}
