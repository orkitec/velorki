import 'dart:io';

import 'package:test/test.dart';
import 'package:velorki_cycle_map/velorki_cycle_map.dart';

void main() {
  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync('cell_store');
    addTearDown(() => root.deleteSync(recursive: true));
  });

  test('a cell comes back as it was written', () {
    final store = CellStore(root);
    final cell =
        (CellWaysBuilder()
              ..addLine([1, 2, 3, 4, 5, 6], 7)
              ..addLine([8, 9, 10, 11], 12)
              ..addBarrier(13, 14, 2))
            .build();
    store.write('v', 3, 4, cell);
    final back = store.read('v', 3, 4)!;
    expect(back.coords, cell.coords);
    expect(back.starts, cell.starts);
    expect(back.attrs, cell.attrs);
    expect(back.barriers, cell.barriers);
    expect(store.read('v', 3, 5), isNull);
    expect(store.read('w', 3, 4), isNull);
  });

  test('an empty cell too', () {
    final store = CellStore(root)..write('v', 0, 0, CellWays.empty());
    final back = store.read('v', 0, 0)!;
    expect(back.lineCount, 0);
    expect(back.barrierCount, 0);
  });

  test('a damaged file is no cell', () {
    final store = CellStore(root)..write('v', 1, 1, CellWays.empty());
    final file = File('${root.path}/v/1_1.bin');
    file.writeAsBytesSync(file.readAsBytesSync().sublist(0, 12));
    expect(store.read('v', 1, 1), isNull);
    file.writeAsBytesSync(List.filled(24, 0));
    expect(store.read('v', 1, 1), isNull);
  });

  test('prune keeps only the current versions', () {
    final store = CellStore(root)
      ..write('a', 0, 0, CellWays.empty())
      ..write('b', 0, 0, CellWays.empty());
    store.prune({'a'});
    expect(store.read('a', 0, 0), isNotNull);
    expect(Directory('${root.path}/b').existsSync(), isFalse);
  });
}
