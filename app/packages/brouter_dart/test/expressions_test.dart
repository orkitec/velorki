// The expressions module: lookups.dat parsing, encode/decode round trips,
// profile parsing (constant folding, injected key/values, foreign variables,
// v: lookups, noStartWay comments) and the evaluation samples of the oracle
// (`eval-profile`, both in the committed Float.toString format and in the
// float-bits format).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:brouter_dart/brouter_dart.dart';
import 'package:test/test.dart';

import 'mapaccess_support.dart';
import 'vectors.dart';

final File fixturesLookups = File('test/fixtures/lookups_test.dat');

String hex8(int bits) => bits.toUnsigned(32).toRadixString(16).padLeft(8, '0');

/// `Dump.tagsToLookupData`: one line of `key=value` tokens into lookup data.
Int32List tagsToLookupData(
  BExpressionContext ctx,
  String line,
  List<String> unknown,
) {
  final ld = ctx.createNewLookupData()!;
  for (final tok in line.split(RegExp(r'\s+'))) {
    final eq = tok.indexOf('=');
    if (eq <= 0) continue;
    final k = tok.substring(0, eq);
    final v = tok.substring(eq + 1);
    if (ctx.getLookupNameIdx(k) < 0) {
      unknown.add(k);
      continue;
    }
    ctx.addLookupValue(k, v, ld);
  }
  return ld;
}

/// Replays one `eval-profile --bits` vector against [ctx] (already parsed).
void replayBitsVector(Map<String, dynamic> v, BExpressionContext ctx) {
  final vars = (v['variables'] as List).cast<String>();
  expect(ctx.usedTagList(), v['usedTags']);
  for (final name in vars) {
    expect(
      ctx.getVariableValue(name, 0.0) == 0.0 &&
          ctx.getVariableValue(name, 1.0) == 1.0,
      isFalse,
      reason: 'variable $name exists',
    );
  }
  for (final c in (v['cases'] as List).cast<Map<String, dynamic>>()) {
    final tags = c['tags'] as String;
    final unknown = <String>[];
    final ld = tagsToLookupData(ctx, tags, unknown);
    expect(unknown, c['unknownKeys'], reason: '$tags: unknown keys');
    final ab = ctx.encodeLookupData(ld);
    if (c['encoded'] == null) {
      expect(ab, isNull, reason: tags);
      continue;
    }
    expect(hex(ab!), c['encoded'], reason: '$tags: encoded');
    expect(
      ctx.getKeyValueDescription(false, ab),
      c['decoded'],
      reason: '$tags: decoded',
    );
    for (final dir in ['forward', 'reverse']) {
      ctx.evaluate(dir == 'reverse', ab);
      final expected = (c[dir] as Map).cast<String, String>();
      for (final name in vars) {
        expect(
          hex8(floatToIntBits(ctx.getVariableValue(name, double.nan))),
          expected[name],
          reason: '$tags $dir: $name',
        );
      }
    }
  }
}

void main() {
  group('lookups.dat', () {
    test('parses version 11.2 into way and node contexts', () {
      final meta = BExpressionMetaData();
      final way = BExpressionContextWay(meta);
      final node = BExpressionContextNode(meta);
      meta.readMetaData(lookupsFile);
      expect(meta.lookupVersion, 11);
      expect(meta.lookupMinorVersion, 2);
      expect(meta.minAppVersion, -1);
      expect(way.lookupName(0), 'reversedirection');
      expect(way.lookupValueNames(0), ['', 'unknown', 'yes']);
      expect(way.lookupName(1), 'highway');
      expect(way.lookupValueNames(1).take(4), [
        '',
        'unknown',
        'residential',
        'service',
      ]);
      expect(node.lookupName(0), 'nodeaccessgranted');
      expect(node.lookupName(1), 'highway');
      expect(node.lookupValueNames(1).take(3), ['', 'unknown', 'bus_stop']);
      expect(way.lookupCount, greaterThan(100));
      expect(node.lookupCount, greaterThan(20));
      expect(way.isLookupIdxUsed(1), isFalse);
      expect(way.createNewLookupData()!.length, way.lookupCount);
    });

    test('aliases resolve to the primary value; unknown values become 1', () {
      final meta = BExpressionMetaData();
      final way = BExpressionContextWay(meta);
      meta.readMetaData(lookupsFile);
      final ld = way.createNewLookupData()!;
      way.addLookupValue('highway', 'yes', ld); // alias of "road"
      expect(way.lookupValueNames(1)[ld[1]], 'road');
      way.addLookupValue('highway', 'no_such_value', ld);
      expect(ld[1], 1);
      way.addLookupValue('surface', 'cobblestone:flattened', ld);
      expect(
        way.lookupValueNames(way.getLookupNameIdx('surface'))[ld[way
            .getLookupNameIdx('surface')]],
        'cobblestone',
      );
      way.addLookupValue(
        'nonexistent_key',
        'x',
        ld,
      ); // ignored for external arrays
      expect(way.getLookupNameIdx('nonexistent_key'), -1);
      expect(way.getLookupKey('highway'), 1);
      expect(way.getLookupKey('nonexistent_key'), -1);
    });

    test('a context without data for it is rejected', () {
      final meta = BExpressionMetaData();
      final way = BExpressionContextWay(meta);
      expect(() => way.finishMetaParsing(), throwsA(isA<ArgumentError>()));
      expect(meta.lookupVersion, -1);
    });

    test(
      'every shipped profile parses in both contexts (IntegrityCheckProfile)',
      () {
        final lines = IntegrityCheckProfile().integrityTestProfiles(
          lookupsFile,
          profilesDir,
        );
        expect(lines.length, 7);
        for (final l in lines) {
          expect(l, startsWith('test 11.2 '));
        }
      },
    );
  });

  group('encode / decode', () {
    late BExpressionContextWay way;
    setUpAll(() => way = profileWayContext('trekking'));

    test('round trips every line of samples/tags.txt', () {
      final lines = File('../../../tools/brouter-oracle/dump/samples/tags.txt')
          .readAsLinesSync()
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('#'))
          .toList();
      expect(lines.length, 20);
      for (final line in lines) {
        final unknown = <String>[];
        final ld = tagsToLookupData(way, line, unknown);
        expect(unknown, isEmpty, reason: line);
        final ab = way.encodeLookupData(ld)!;
        // the description lists the tags in lookup order
        final decoded = way.getKeyValueDescription(false, ab);
        expect(decoded.split(' ')..sort(), line.split(' ')..sort());
        expect(
          way.getKeyValueDescription(true, ab),
          'reversedirection=yes $decoded',
        );
        final list = way.getKeyValueList(false, ab);
        expect(list.length.isEven, isTrue);
        final ld2 = Int32List(way.lookupCount);
        way.decodeInto(ld2, false, ab);
        expect(ld2, ld);
        final ld3 = Int32List(way.lookupCount);
        way.decodeInto(ld3, true, ab);
        expect(ld3[0], 2);
        expect(ld3.sublist(1), ld.sublist(1));
      }
    });

    test('encode() needs decoded data; an empty tag set encodes to null', () {
      expect(() => way.encode(), throwsA(isA<ArgumentError>()));
      expect(way.encodeLookupData(way.createNewLookupData()!), isNull);
      final ld = way.createNewLookupData()!;
      way.addLookupValue('highway', 'residential', ld);
      final ab = way.encodeLookupData(ld)!;
      way.decode(ab);
      expect(way.encode(), ab);
      expect(way.getBooleanLookupValue('highway'), isTrue); // value index 2
      expect(way.getBooleanLookupValue('surface'), isFalse);
    });

    test('a description with a lookup beyond this table is cut off (higher minor version)', () {
      final ld = way.createNewLookupData()!;
      way.addLookupValue('highway', 'residential', ld);
      way.addLookupValue('surface', 'asphalt', ld);
      final ab = way.encodeLookupData(ld)!;
      final short = Int32List(3); // reversedirection, highway, surface
      way.decodeInto(short, false, ab);
      expect(short, [0, ld[1], ld[2]]);
      final tiny = Int32List(2);
      way.decodeInto(tiny, false, ab);
      expect(tiny, [0, ld[1]]);
    });
  });

  group('eval-profile samples (Float.toString format)', () {
    for (final (profile, file) in [
      ('trekking', 'eval-trekking.json'),
      ('gravel', 'eval-gravel.json'),
    ]) {
      test('$file reproduces bit-exactly', () {
        final sample = jsonDecode(
          File('../../../tools/brouter-oracle/dump/samples/$file')
              .readAsStringSync(),
        ) as Map<String, dynamic>;
        expect(sample['lookupVersion'], 11);
        final ctx = profileWayContext(profile);
        final cases = (sample['cases'] as List).cast<Map<String, dynamic>>();
        expect(cases.length, 20);
        for (final c in cases) {
          final tags = c['tags'] as String;
          final unknown = <String>[];
          final ab = ctx.encodeLookupData(
            tagsToLookupData(ctx, tags, unknown),
          )!;
          expect(unknown, c['unknownKeys']);
          expect(hex(ab), c['encoded'], reason: tags);
          expect(
            ctx.getKeyValueDescription(false, ab),
            c['decoded'],
            reason: tags,
          );
          for (final dir in ['forward', 'reverse']) {
            ctx.evaluate(dir == 'reverse', ab);
            final expected = (c[dir] as Map).cast<String, Object?>();
            expect(expected, isNotEmpty);
            for (final e in expected.entries) {
              final actual = ctx.getVariableValue(e.key, double.nan);
              final exp = e.value;
              // the sample prints Float.toString (or null for NaN, 1e999 for infinity);
              // a Float.toString string parses back to the same float, so the
              // comparison is exact
              if (exp == null) {
                expect(actual.isNaN, isTrue, reason: '$tags $dir ${e.key}');
              } else {
                final d = (exp as num).toDouble();
                expect(
                  hex8(floatToIntBits(actual)),
                  hex8(
                    floatToIntBits(
                      d.abs() > 1e308
                          ? (d > 0 ? double.infinity : double.negativeInfinity)
                          : javaParseFloat('$d'),
                    ),
                  ),
                  reason:
                      '$tags $dir ${e.key}: got ${javaFloatToString(actual)}, expected $exp',
                );
              }
            }
            // and every variable the profile has is in the sample (unless NaN)
            for (final name in ctx.variableNames()) {
              if (!expected.containsKey(name)) {
                expect(
                  ctx.getVariableValue(name, double.nan).isNaN,
                  isTrue,
                  reason: '$name missing from the sample',
                );
              }
            }
          }
        }
      });
    }
  });

  group('eval-profile --bits vectors', () {
    test('trekking on samples/tags.txt', () {
      final v = loadExpressionsVector('eval-trekking-bits.json');
      replayBitsVector(v, profileWayContext('trekking'));
    });

    test(
      'profile_test.brf (constant folding, global calcs) with lookups_test.dat',
      () {
        final v = loadExpressionsVector('eval-profile_test-bits.json');
        final meta = BExpressionMetaData();
        final ctx = BExpressionContextWay(meta);
        meta.readMetaData(fixturesLookups);
        expect(meta.lookupMinorVersion, 1);
        ctx.parseFile(File('test/fixtures/profile_test.brf'), 'global');
        replayBitsVector(v, ctx);
      },
    );

    test('soft_test.brf: unit conversion of "*" lookups, v:maxspeed, Float.toString of numeric values', () {
      final v = loadExpressionsVector('eval-soft_test-units.json');
      final meta = BExpressionMetaData();
      final ctx = BExpressionContextWay(meta);
      meta.readMetaData(fixturesLookups);
      ctx.parseFile(File('test/fixtures/soft_test.brf'), 'global');
      final cases = (v['cases'] as List).cast<Map<String, dynamic>>();
      expect(cases.length, greaterThan(70));
      // the decoded strings carry the converted numbers, e.g. "maxheight=3.5"
      expect(
        cases
            .map((c) => c['decoded'])
            .where((d) => (d as String).contains('maxheight=3.8')),
        isNotEmpty,
      );
      replayBitsVector(v, ctx);
    });

    test('node context of soft_test.brf (no cache, hashSize 0)', () {
      final v = loadExpressionsVector('eval-soft_test-node.json');
      final meta = BExpressionMetaData();
      final way = BExpressionContextWay(meta);
      final node = BExpressionContextNode(meta, 0);
      node.setForeignContext(way);
      meta.readMetaData(fixturesLookups);
      way.parseFile(File('test/fixtures/soft_test.brf'), 'global');
      node.parseFile(File('test/fixtures/soft_test.brf'), 'global');
      final unknown = <String>[];
      final wayAb = way.encodeLookupData(
        tagsToLookupData(way, v['wayTags'] as String, unknown),
      )!;
      expect(hex(wayAb), v['wayEncoded']);
      way.evaluate(false, wayAb);
      expect(hex8(floatToIntBits(way.getCostfactor())), v['wayCostfactor']);
      replayBitsVector(v, node);
    });
  });

  group('parser', () {
    test('constant optimizer: optimised and unoptimised profiles agree (upstream ConstantOptimizerTest)', () {
      final meta1 = BExpressionMetaData();
      final meta2 = BExpressionMetaData();
      final expctx1 = BExpressionContextWay(meta1);
      final expctx2 = BExpressionContextWay(meta2);
      expctx2.skipConstantExpressionOptimizations = true;
      final keyValue = {
        'global_inject1': '5',
        'global_inject2': '6',
        'global_inject3': '7',
      };
      meta1.readMetaData(fixturesLookups);
      meta2.readMetaData(fixturesLookups);
      final profile = File('test/fixtures/profile_test.brf');
      expctx1.parseFile(profile, 'global', keyValue);
      expctx2.parseFile(profile, 'global', keyValue);
      expect(expctx1.getVariableValue('global_inject1', 0), 5);
      expect(
        expctx1.getVariableValue('global_inject2', 0),
        9,
      ); // modified in the 2nd assign
      expect(expctx1.getVariableValue('global_inject3', 0), 7);
      expect(expctx1.getVariableValue('global_inject4', 3), 3); // un-assigned
      expect(
        expctx2.expressionNodeCount - expctx1.expressionNodeCount,
        greaterThanOrEqualTo(311 - 144),
      );
      expect(expctx1.expressionNodeCount, 144);
      expect(expctx2.expressionNodeCount, 311);
      final rnd = JavaRandom(17464);
      for (var i = 0; i < 10000; i++) {
        final data = expctx1.generateRandomValues(rnd);
        expctx1.evaluateLookupData(data);
        expctx2.evaluateLookupData(data);
        expctx1.assertAllVariablesEqual(expctx2);
      }
    });

    test('ProfileComparator on the shipped profiles, both contexts', () {
      for (final nodeContext in [false, true]) {
        final lines = ProfileComparator.testContext(
          lookupsFile,
          profileFile('trekking'),
          profileFile('trekking'),
          2000,
          nodeContext,
          rnd: JavaRandom(20260912),
        );
        expect(lines[2], startsWith('nodeContext=$nodeContext nodeCount1='));
      }
    });

    test('injected key/values are protected once and overridable', () {
      final meta = BExpressionMetaData();
      final ctx = BExpressionContextWay(meta);
      meta.readMetaData(lookupsFile);
      ctx.parseProfile(
        'inject.brf',
        '''
---context:global
assign a = 1
assign b = add a 1
assign b = add b 1
---context:way
assign costfactor = add a b
''',
        'global',
        {'a': '10', 'b': '100'},
      );
      // "a" keeps the injected 10 (the profile's assign is ignored once), "b"
      // is injected as 100, then the second assign in the file changes it
      expect(ctx.getVariableValue('a', -1), 10);
      expect(ctx.getVariableValue('b', -1), 101);
      final ab = ctx.encodeLookupData(
        tagsToLookupData(ctx, 'highway=residential', []),
      )!;
      ctx.evaluate(false, ab);
      expect(ctx.getCostfactor(), 111);
    });

    test('model tag, foreign variables and v: lookups', () {
      final meta = BExpressionMetaData();
      final way = BExpressionContextWay(meta);
      final node = BExpressionContextNode(meta);
      node.setForeignContext(way);
      meta.readMetaData(fixturesLookups);
      const profile = '''
---model:btools.router.StdModel
---context:global
assign my_height = 3.2
---context:way
assign no_height = switch and not maxheight= lesser v:maxheight my_height true false
assign costfactor = if no_height then 2 else 1
assign turncost = 0
---context:node
assign initialcost = if way:costfactor then 100 else 0
assign height_seen = way:no_height
''';
      way.parseProfile('p.brf', profile, 'global');
      node.parseProfile('p.brf', profile, 'global');
      expect(way.modelClass, 'btools.router.StdModel');
      final ld = way.createNewLookupData()!;
      way.addLookupValue('highway', 'residential', ld);
      way.addLookupValue('maxheight', '2.5', ld);
      final ab = way.encodeLookupData(ld)!;
      expect(
        way.getKeyValueDescription(false, ab),
        'highway=residential maxheight=2.5',
      );
      way.evaluate(false, ab);
      expect(way.getCostfactor(), 2);
      expect(way.getVariableValue('no_height', -1), 1);
      // the node context reads the way's build-in and output variables
      final nab = node.encodeLookupData(node.createNewLookupData()!..[1] = 2)!;
      node.evaluate(false, nab);
      expect(node.getInitialcost(), 100);
      expect(node.getVariableValue('height_seen', -1), 1);
      // no maxheight: v:maxheight is NaN, lesser is false
      final ld2 = way.createNewLookupData()!;
      way.addLookupValue('highway', 'residential', ld2);
      way.evaluate(false, way.encodeLookupData(ld2)!);
      expect(way.getCostfactor(), 1);
      expect(
        way.getLookupValue(way.getLookupNameIdx('maxheight')).isNaN,
        isTrue,
      );
      expect(
        way.getLookupValueOf(false, ab, way.getLookupNameIdx('maxheight')),
        2.5,
      );
      expect(
        way.getLookupValueOf(false, ab, way.getLookupNameIdx('highway')),
        f32((2 - 1000) / 100),
      );
      expect(
        () => node.getForeignVariableIdx('global', 'x'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('noStartWay comments feed checkStartWay', () {
      final meta = BExpressionMetaData();
      final way = BExpressionContextWay(meta);
      meta.readMetaData(lookupsFile);
      way.parseProfile('p.brf', '''
---context:way
assign check_start_way = true
# noStartWay | 1 | 2 | ways=highway,motorway;highway,trunk
assign costfactor = 1
''', 'global');
      expect(way.noStartWays, [
        1,
        way.getLookupValueIdx(1, 'motorway'),
        1,
        way.getLookupValueIdx(1, 'trunk'),
      ]);
      Uint8List enc(String tags) =>
          way.encodeLookupData(tagsToLookupData(way, tags, []))!;
      expect(way.checkStartWay(enc('highway=motorway')), isFalse);
      expect(way.checkStartWay(enc('highway=trunk surface=asphalt')), isFalse);
      expect(way.checkStartWay(enc('highway=residential')), isTrue);
      expect(way.checkStartWay(null), isTrue);
      way.freeNoWays();
      expect(way.checkStartWay(enc('highway=motorway')), isTrue);
    });

    test('parse errors carry the file name and line', () {
      BExpressionContextWay fresh() {
        final meta = BExpressionMetaData();
        final way = BExpressionContextWay(meta);
        meta.readMetaData(lookupsFile);
        return way;
      }

      // the token ending at the newline of line 4 is reported at line 5, as upstream
      expect(
        () => fresh().parseProfile(
          'bad.brf',
          '---context:way\nassign costfactor = 1\n\nassign x = highway=nosuchvalue\n',
          'global',
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            'ParseException bad.brf at line 5: unknown lookup value: nosuchvalue',
          ),
        ),
      );
      expect(
        () => fresh().parseProfile(
          'bad.brf',
          '---context:way\nassign costfactor = divide 1 0\n',
          'global',
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('div by zero'),
          ),
        ),
      );
      expect(
        () => fresh().parseProfile(
          'empty.brf',
          '---context:node\nassign initialcost = 0\n',
          'global',
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('does not contain expressions for context way'),
          ),
        ),
      );
      expect(
        () => fresh().parseFile(File('/nonexistent.brf'), 'global'),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => fresh().parseProfile(
          'bad.brf',
          '---context:way\nassign costfactor = if true 1 else 2\n',
          'global',
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('expected: then'),
          ),
        ),
      );
      // a global variable cannot be assigned in the way context
      expect(
        () => fresh().parseProfile(
          'bad.brf',
          '---context:global\nassign a = 1\n---context:way\nassign a = 2\nassign costfactor = 1\n',
          'global',
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('cannot assign to readonly variable a'),
          ),
        ),
      );
    });

    test('accessType and the inverse variables', () {
      final way = profileWayContext('trekking');
      Uint8List enc(String tags) =>
          way.encodeLookupData(tagsToLookupData(way, tags, []))!;
      expect(way.accessType(enc('highway=residential')), 2);
      expect(
        way.accessType(enc('highway=motorway')),
        0,
      ); // costfactor 100000 (> 10000)
      way.setDecodeForbidden(true);
      expect(
        way.accessType(enc('highway=residential access=no')),
        1,
      ); // 9999 <= costfactor < 10000
      way.setDecodeForbidden(false);
      expect(way.accessType(enc('highway=residential access=no')), 0);
      // a oneway: penalised backwards, so the minimum over both directions passes
      expect(way.accessType(enc('highway=residential oneway=yes')), 2);
      way.evaluate(true, enc('highway=residential oneway=yes'));
      final reverse = way.getCostfactor();
      way.evaluate(false, enc('highway=residential oneway=yes'));
      expect(way.getCostfactor(), lessThan(reverse));
      // the inverse variables of the same cached evaluation
      way.setInverseVars();
      expect(way.getCostfactor(), reverse);
      expect(way.cacheStats(), startsWith('requests='));
    });

    test('unify returns the cached instance of an equal description', () {
      final way = profileWayContext('trekking');
      final ab = way.encodeLookupData(
        tagsToLookupData(way, 'highway=residential surface=asphalt', []),
      )!;
      final fresh = way.unify(ab, 0, ab.length);
      expect(identical(fresh, ab), isFalse); // not yet cached: a copy
      way.evaluate(false, ab); // now ab is the cached instance
      final padded = Uint8List(ab.length + 2)..setRange(1, 1 + ab.length, ab);
      expect(identical(way.unify(padded, 1, ab.length), ab), isTrue);
    });

    test('setVariableValue, addLookupValueIndex, addSmallestLookupValue, dumpStatistics', () {
      final way = profileWayContext('trekking');
      way.setVariableValue('costfactor', 2.5, false);
      expect(way.getVariableValue('costfactor', 0), 2.5);
      // creating a variable after parseFile NPEs upstream (lastAssignedExpression
      // is null by then); the port throws too
      expect(
        () => way.setVariableValue('brand_new', 0.1, true),
        throwsA(isA<Error>()),
      );
      way.setVariableValue('never', 1, false);
      expect(way.getVariableValue('never', -1), -1);
      way.addLookupValueIndex('highway', 3);
      way.addLookupValueIndex('no_such', 3);
      expect(
        () => way.addLookupValueIndex('highway', 9999),
        throwsA(isA<ArgumentError>()),
      );
      way.addSmallestLookupValue('highway', 2);
      way.addSmallestLookupValue('highway', 5); // keeps 2
      way.addSmallestLookupValue('surface', 99999); // clamps to the last value
      way.addSmallestLookupValue('no_such', 1);
      expect(way.getBooleanLookupValue('highway'), isTrue);
      final stats = way.dumpStatistics();
      expect(stats, isNotEmpty);
      expect(stats.first, startsWith('highway;'));
      expect(() => way.variableName(-1), throwsA(isA<StateError>()));
      expect(
        way.variableName(way.getVariableIdx('costfactor', false)),
        'costfactor',
      );
    });
  });
}
