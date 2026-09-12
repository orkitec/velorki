// The R5 byte-level cell cache: bounded, LRU, copies; and routing with it
// on/off produces the same bytes.

import 'dart:typed_data';

import 'package:brouter_dart/brouter_dart.dart';
import 'package:test/test.dart';

import 'corpus_support.dart';
import 'mapaccess_support.dart';

void main() {
  group('RawCellCache', () {
    Uint8List cell(int size, int fill) =>
        Uint8List(size)..fillRange(0, size, fill);

    test('hit copies the bytes, miss counts', () {
      final c = RawCellCache(maxBytes: 100);
      final key = RawCellCache.key(c.fileId('W20_N30.rd5'), 12345);
      final target = Uint8List(64);
      expect(c.copyInto(key, target, 10), isFalse);
      expect(c.misses, 1);

      final src = cell(64, 7);
      c.put(key, src, 10);
      src[0] = 9; // the cache holds a copy
      expect(c.copyInto(key, target, 10), isTrue);
      expect(target.sublist(0, 10), everyElement(7));
      expect(c.hits, 1);
      expect(c.bytes, 10);
      expect(c.length, 1);
    });

    test('is bounded and evicts the least recently used cell', () {
      final c = RawCellCache(maxBytes: 30);
      final f = c.fileId('a');
      c.put(RawCellCache.key(f, 0), cell(10, 1), 10);
      c.put(RawCellCache.key(f, 1), cell(10, 2), 10);
      c.put(RawCellCache.key(f, 2), cell(10, 3), 10);
      expect(c.bytes, 30);
      // touch key 0, then key 1 is the LRU
      final t = Uint8List(10);
      expect(c.copyInto(RawCellCache.key(f, 0), t, 10), isTrue);
      c.put(RawCellCache.key(f, 3), cell(10, 4), 10);
      expect(c.bytes, 30);
      expect(c.copyInto(RawCellCache.key(f, 1), t, 10), isFalse);
      expect(c.copyInto(RawCellCache.key(f, 0), t, 10), isTrue);
      expect(c.copyInto(RawCellCache.key(f, 2), t, 10), isTrue);
      expect(c.copyInto(RawCellCache.key(f, 3), t, 10), isTrue);
      // a cell larger than the bound is not cached
      c.put(RawCellCache.key(f, 4), cell(40, 5), 40);
      expect(c.bytes, 30);
      c.clear();
      expect(c.bytes, 0);
      expect(c.length, 0);
    });

    test('file ids are stable per name', () {
      final c = RawCellCache();
      expect(c.fileId('x'), 0);
      expect(c.fileId('y'), 1);
      expect(c.fileId('x'), 0);
    });
  });

  group('routing with the cell cache', () {
    final skip = tilesMissing;

    test('produces the same bytes with and without it', () async {
      final cases = loadCorpus();
      final c = cases.firstWhere((c) => c.id == 'pair-000');
      final with_ = oracleRouter();
      final without = oracleRouter()..rawCache = RawCellCache(maxBytes: 0);
      final a = await with_.routeQuery(c.query);
      final b = await without.routeQuery(c.query);
      expect(a, b);
      expect(a, c.responseFile.readAsStringSync());
      expect(with_.rawCache.hits, greaterThan(0));
      expect(with_.rawCache.bytes, 0, reason: 'released after the route');
      expect(without.rawCache.hits, 0);
    }, skip: skip);

    test('is retained across routes when asked', () async {
      final cases = loadCorpus();
      final c = cases.firstWhere((c) => c.id == 'pair-000');
      final r = oracleRouter()..retainRawCache = true;
      await r.routeQuery(c.query);
      expect(r.rawCache.bytes, greaterThan(0));
      final misses = r.rawCache.misses;
      await r.routeQuery(c.query);
      expect(r.rawCache.misses, misses, reason: 'second route: all hits');
      expect(r.rawCache.bytes, lessThanOrEqualTo(r.rawCache.maxBytes));
    }, skip: skip);
  });
}
