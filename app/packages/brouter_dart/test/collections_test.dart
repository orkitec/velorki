import 'dart:typed_data';

import 'package:brouter_dart/brouter_dart.dart';
import 'package:test/test.dart';

import 'vectors.dart';

class _LruNode extends LruMapNode {
  _LruNode(this.key) {
    hash = i32(key ^ (key >>> 32));
  }

  final int key;

  @override
  int get hashCode => hash;

  @override
  bool operator ==(Object other) => other is _LruNode && other.key == key;
}

void main() {
  final vec = loadVector('collections.json');

  List<List<dynamic>> ops(String section) =>
      ((vec[section] as Map<String, dynamic>)['ops'] as List<dynamic>)
          .cast<List<dynamic>>();
  List<dynamic> results(String section) =>
      (vec[section] as Map<String, dynamic>)['results'] as List<dynamic>;

  test('SortedHeap: pop order, extract and sizes', () {
    final heap = SortedHeap<int>();
    final out = <Object?>[];
    for (final op in ops('sortedheap')) {
      switch (op[0] as String) {
        case 'add':
          heap.add(op[1] as int, op[2] as int);
          out.add(null);
        case 'pop':
          out.add(heap.popLowestKeyValue());
        case 'extract':
          final t = List<int?>.filled(op[1] as int, null);
          final cnt = heap.getExtract(t);
          out.add([cnt, t.sublist(0, cnt)]);
        case 'size':
          out.add(heap.getSize());
        case 'peak':
          out.add(heap.getPeakSize());
        default:
          fail('unknown op ${op[0]}');
      }
    }
    expect(out, results('sortedheap'));
  });

  test('CompactLongMap / FrozenLongMap', () {
    var map = CompactLongMap<int>();
    final out = <Object?>[];
    for (final op in ops('compactlongmap')) {
      switch (op[0] as String) {
        case 'put':
          Object? res;
          try {
            res = map.put(op[1] as int, op[2] as int);
          } on StateError {
            res = 'error';
          }
          out.add(res);
        case 'fastput':
          map.fastPut(op[1] as int, op[2] as int);
          out.add(null);
        case 'get':
          out.add(map.get(op[1] as int));
        case 'contains':
          out.add(map.contains(op[1] as int));
        case 'size':
          out.add(map.size());
        case 'freeze':
          map = FrozenLongMap<int>(map);
          out.add(map.size());
        case 'keys':
          out.add((map as FrozenLongMap<int>).getKeyArray().toList());
        case 'values':
          out.add(
            (map as FrozenLongMap<int>).getValueList().toList(),
          ); // a copy: later put()s replace values
        default:
          fail('unknown op ${op[0]}');
      }
    }
    expect(out, results('compactlongmap'));
  });

  test('CompactLongSet / FrozenLongSet', () {
    var set = CompactLongSet();
    final out = <Object?>[];
    for (final op in ops('compactlongset')) {
      switch (op[0] as String) {
        case 'add':
          out.add(set.add(op[1] as int));
        case 'fastadd':
          set.fastAdd(op[1] as int);
          out.add(null);
        case 'contains':
          out.add(set.contains(op[1] as int));
        case 'size':
          out.add(set.size());
        case 'freeze':
          set = FrozenLongSet(set);
          out.add(set.size());
        default:
          fail('unknown op ${op[0]}');
      }
    }
    expect(out, results('compactlongset'));
  });

  for (final section in ['denselongmap', 'tinydenselongmap']) {
    test('$section put/getInt', () {
      final map = section == 'denselongmap'
          ? DenseLongMap()
          : TinyDenseLongMap();
      final out = <Object?>[];
      for (final op in ops(section)) {
        switch (op[0] as String) {
          case 'put':
            map.put(op[1] as int, op[2] as int);
            out.add(null);
          case 'get':
            out.add(map.getInt(op[1] as int));
          default:
            fail('unknown op ${op[0]}');
        }
      }
      expect(out, results(section));
    });
  }

  test('LinkedListContainer', () {
    final c = LinkedListContainer(10, Int32List(8));
    final out = <Object?>[];
    for (final op in ops('linkedlistcontainer')) {
      switch (op[0] as String) {
        case 'add':
          c.addDataElement(op[1] as int, op[2] as int);
          out.add(null);
        case 'init':
          out.add(c.initList(op[1] as int));
        case 'get':
          Object? res;
          try {
            res = c.getDataElement();
          } on ArgumentError {
            res = 'error';
          }
          out.add(res);
        default:
          fail('unknown op ${op[0]}');
      }
    }
    expect(out, results('linkedlistcontainer'));
  });

  test('ByteArrayUnifier: instance reuse and content', () {
    final u = ByteArrayUnifier(16, true);
    final seen = <Uint8List>[];
    final out = <Object?>[];
    for (final op in ops('bytearrayunifier')) {
      final input = unhex('ff${op[1]}ee');
      final res = u.unify(input, 1, input.length - 2);
      var same = -1;
      for (var j = 0; j < seen.length; j++) {
        if (identical(seen[j], res)) {
          same = j;
          break;
        }
      }
      seen.add(res);
      out.add([same, hex(res)]);
    }
    expect(out, results('bytearrayunifier'));
  });

  test('LruMap', () {
    final lru = LruMap(7, 10);
    final out = <Object?>[];
    for (final op in ops('lrumap')) {
      switch (op[0] as String) {
        case 'put':
          lru.put(_LruNode(op[1] as int));
          out.add(null);
        case 'get':
          out.add(lru.get(_LruNode(op[1] as int)) != null);
        case 'touch':
          final e = lru.get(_LruNode(op[1] as int));
          if (e != null) lru.touch(e);
          out.add(e != null);
        case 'removelru':
          final removed = lru.removeLru();
          out.add(removed == null ? null : (removed as _LruNode).key);
        default:
          fail('unknown op ${op[0]}');
      }
    }
    expect(out, results('lrumap'));
  });

  test('IntegerFifo3Pass', () {
    final f = IntegerFifo3Pass(2);
    f.init();
    expect(f.getNext(), 1);
    f.add(5);
    f.init();
    for (final v in [3, 7, 11, 13, 17]) {
      f.add(v);
    }
    expect(f.getNext(), 1);
    f.init();
    expect([for (var i = 0; i < 5; i++) f.getNext()], [3, 7, 11, 13, 17]);
    expect(() => f.getNext(), throwsRangeError);
  });

  test(
    'LazyArrayOfLists, LongList, StringUtils, ReducedMedianFilter smoke',
    () {
      final l = LazyArrayOfLists<String>(3);
      expect(l.getSize(1), 0);
      l.getList(1).add('a');
      expect(l.getSize(1), 1);
      l.trimAll();

      final ll = LongList(1);
      for (var i = 0; i < 10; i++) {
        ll.add(i * 1000000000000);
      }
      expect(ll.size(), 10);
      expect(ll.get(9), 9000000000000);
      expect(() => ll.get(10), throwsRangeError);

      expect(StringUtils.escapeJson('a"b\\c/d\'e'), 'a\\"b\\\\c\\/d\\\'e');
      expect(
        StringUtils.escapeXml10('<a&b>\'"\t\n\r'),
        '&lt;a&amp;b&gt;&apos;&quot;&#x9;&#xA;&#xD;',
      );
      expect(StringUtils.escapeXml10('plain'), 'plain');

      final f = ReducedMedianFilter(10);
      f.addSample(1.0, 10);
      f.addSample(1.0, 20);
      f.addSample(1.0, 30);
      f.addSample(1.0, 1000);
      // 0.25 weight cut from each edge: (0.75*10 + 20 + 30 + 0.75*1000) / 3.5
      expect(f.calcEdgeReducedMedian(0.5), closeTo(230.71428571428572, 1e-12));
    },
  );
}
