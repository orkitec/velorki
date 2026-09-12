// L2 parity of the expressions module: every shipped profile evaluated on the
// full way-tag corpus of the two oracle tiles (35 099 distinct tag sets, both
// directions) and on the node-tag corpus (772 sets, both nodeaccessgranted
// states), compared float-bit for float-bit with `eval-profile --compact`.

import 'dart:io';
import 'dart:typed_data';

import 'package:brouter_dart/brouter_dart.dart';
import 'package:test/test.dart';

import 'expressions_test.dart' show tagsToLookupData;
import 'mapaccess_support.dart';
import 'vectors.dart';

const profiles = [
  'trekking',
  'fastbike',
  'fastbike-lowtraffic',
  'fastbike-verylowtraffic',
  'gravel',
  'mtb',
  'shortest',
];

List<String> corpusLines(String name) =>
    File('../../../tools/brouter-oracle/dump/samples/$name')
        .readAsLinesSync()
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('#'))
        .toList();

List<Int32List> parseVectors(Map<String, dynamic> v) => [
  for (final s in (v['vectors'] as List).cast<String>())
    Int32List.fromList([
      for (final h in s.split(' ')) int.parse(h, radix: 16).toSigned(32),
    ]),
];

String hex8(int bits) => bits.toUnsigned(32).toRadixString(16).padLeft(8, '0');

/// Evaluates every line of [lines] in [ctx] and compares all variables of the
/// vector; returns the mismatch descriptions (empty = parity).
List<String> replayCompact(
  Map<String, dynamic> v,
  BExpressionContext ctx,
  List<String> lines,
) {
  final vars = (v['variables'] as List).cast<String>();
  final vectors = parseVectors(v);
  final cases = (v['cases'] as List).cast<List>();
  final encoded = v['encoded'] as List?;
  expect(
    cases.length,
    lines.length,
    reason: 'case count of ${v['profile']} ${v['context']}',
  );
  expect(
    ctx.usedTagList(),
    v['usedTags'],
    reason: 'usedTagList of ${v['profile']} ${v['context']}',
  );
  final failures = <String>[];
  final unknown = <String>[];
  var evaluated = 0;
  for (var i = 0; i < cases.length; i++) {
    final line = lines[i];
    unknown.clear();
    final ab = ctx.encodeLookupData(tagsToLookupData(ctx, line, unknown));
    if (encoded != null) {
      final e = encoded[i];
      if (e == null) {
        if (ab != null) failures.add('$line: expected an empty encoding');
      } else if (e is String) {
        if (ab == null || hex(ab) != e) {
          failures.add(
            '$line: encoded ${ab == null ? null : hex(ab)}, expected $e',
          );
        }
        if (ab != null && ctx.getKeyValueDescription(false, ab) != line) {
          failures.add(
            '$line: decoded "${ctx.getKeyValueDescription(false, ab)}"',
          );
        }
        if (unknown.isNotEmpty) failures.add('$line: unknown keys $unknown');
      } else {
        final l = (e as List).cast<String>();
        if (ab == null || hex(ab) != l[0]) {
          failures.add(
            '$line: encoded ${ab == null ? null : hex(ab)}, expected ${l[0]}',
          );
        }
        if (ab != null && ctx.getKeyValueDescription(false, ab) != l[1]) {
          failures.add(
            '$line: decoded "${ctx.getKeyValueDescription(false, ab)}", expected "${l[1]}"',
          );
        }
        if (unknown.join(',') != l.sublist(2).join(',')) {
          failures.add(
            '$line: unknown keys $unknown, expected ${l.sublist(2)}',
          );
        }
      }
    }
    final fr = cases[i];
    if (ab == null) {
      if (fr[0] != null || fr[1] != null) {
        failures.add('$line: Java evaluated it, the port could not encode it');
      }
      continue;
    }
    for (var dir = 0; dir < 2; dir++) {
      final expected = vectors[fr[dir] as int];
      ctx.evaluate(dir == 1, ab);
      evaluated++;
      for (var k = 0; k < vars.length; k++) {
        final actual = floatToIntBits(
          ctx.getVariableValue(vars[k], double.nan),
        );
        if (actual != floatToIntBits(intBitsToFloat(expected[k]))) {
          failures.add(
            '$line ${dir == 0 ? 'forward' : 'reverse'} ${vars[k]}: got ${hex8(actual)} (${javaFloatToString(intBitsToFloat(actual))}), expected ${hex8(expected[k])} (${javaFloatToString(intBitsToFloat(expected[k]))})',
          );
        }
      }
    }
    if (failures.length > 50) break;
  }
  expect(evaluated, greaterThan(0));
  return failures;
}

void main() {
  final wayLines = corpusLines('tags-large.txt');
  final nodeLines = corpusLines('node-tags-large.txt');

  test('the corpus is the real one: thousands of way tag sets, hundreds of node tag sets', () {
    expect(wayLines.length, greaterThan(30000));
    expect(nodeLines.length, greaterThan(700));
    expect(wayLines.toSet().length, wayLines.length);
  });

  for (final profile in profiles) {
    group(profile, () {
      test(
        'way context: ${wayLines.length} tag sets x 2 directions, every variable bit-identical',
        () {
          final v = loadExpressionsVector('eval-$profile-way.json');
          expect(v['profile'], '$profile.brf');
          expect(v['context'], 'way');
          final ctx = profileWayContext(profile);
          final failures = replayCompact(v, ctx, wayLines);
          expect(
            failures,
            isEmpty,
            reason:
                '${failures.length}+ mismatches, first:\n${failures.take(10).join('\n')}',
          );
        },
      );

      test(
        'node context: ${nodeLines.length} tag sets x nodeaccessgranted no/yes, every variable bit-identical',
        () {
          final v = loadExpressionsVector('eval-$profile-node.json');
          expect(v['context'], 'node');
          final meta = BExpressionMetaData();
          final way = BExpressionContextWay(meta);
          final node = BExpressionContextNode(
            meta,
            0,
          ); // no cache, like ProfileCache
          node.setForeignContext(way);
          meta.readMetaData(lookupsFile);
          way.parseFile(profileFile(profile), 'global');
          node.parseFile(profileFile(profile), 'global');
          final unknown = <String>[];
          final wayAb = way.encodeLookupData(
            tagsToLookupData(way, v['wayTags'] as String, unknown),
          )!;
          expect(unknown, v['wayUnknownKeys']);
          expect(hex(wayAb), v['wayEncoded']);
          expect(way.getKeyValueDescription(false, wayAb), v['wayDecoded']);
          expect(way.usedTagList(), v['wayUsedTags']);
          way.evaluate(false, wayAb);
          expect(hex8(floatToIntBits(way.getCostfactor())), v['wayCostfactor']);
          final failures = replayCompact(v, node, nodeLines);
          expect(
            failures,
            isEmpty,
            reason:
                '${failures.length}+ mismatches, first:\n${failures.take(10).join('\n')}',
          );
        },
      );
    });
  }

  test('trekking node context after a motorway (way costfactor >= 10000)', () {
    final v = loadExpressionsVector('eval-trekking-node-motorway.json');
    final meta = BExpressionMetaData();
    final way = BExpressionContextWay(meta);
    final node = BExpressionContextNode(meta, 0);
    node.setForeignContext(way);
    meta.readMetaData(lookupsFile);
    way.parseFile(profileFile('trekking'), 'global');
    node.parseFile(profileFile('trekking'), 'global');
    final wayAb = way.encodeLookupData(
      tagsToLookupData(way, v['wayTags'] as String, []),
    )!;
    way.evaluate(false, wayAb);
    expect(hex8(floatToIntBits(way.getCostfactor())), v['wayCostfactor']);
    expect(way.getCostfactor(), greaterThanOrEqualTo(10000));
    final failures = replayCompact(v, node, nodeLines);
    expect(failures, isEmpty, reason: failures.take(10).join('\n'));
  });
}
