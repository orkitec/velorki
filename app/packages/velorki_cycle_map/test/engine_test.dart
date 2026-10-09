import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:velorki_cycle_map/velorki_cycle_map.dart';

import 'support/paths.dart';

/// Funchal's middle, on the oracle's Madeira tile.
const funchal = CycleMapRequest(
  south: 32.63,
  west: -16.95,
  north: 32.67,
  east: -16.88,
  zoom: 16,
);

void main() {
  late Directory segments;
  late Directory cache;
  late Rd5CellReader reader;

  setUpAll(() => reader = Rd5CellReader(lookupsLines()));

  setUp(() {
    final temp = Directory.systemTemp.createTempSync('cycle_map');
    segments = Directory('${temp.path}/segments')..createSync();
    cache = Directory('${temp.path}/cache');
    File('${oracleTiles.path}/W20_N30.rd5')
        .copySync('${segments.path}/W20_N30.rd5');
    addTearDown(() => temp.deleteSync(recursive: true));
  });

  CycleMapEngine engine() =>
      CycleMapEngine(reader: reader, segmentsDir: segments, cacheDir: cache);

  List<Map<String, dynamic>> features(CycleMapResult r) => [
    for (final f in (jsonDecode(r.geojson) as Map)['features'] as List)
      f as Map<String, dynamic>,
  ];

  test('reads Funchal: cycleways, routes, rough streets and barriers', () {
    final e = engine();
    addTearDown(e.close);
    final result = e.render(funchal);
    expect(result.cellsWithoutTile, 0);
    expect(result.truncated, isFalse);
    final fs = features(result);
    bool any(bool Function(Map<String, dynamic> p) test) =>
        fs.any((f) => test(f['properties'] as Map<String, dynamic>));
    expect(any((p) => p['k'] == CycleKind.cycleway.index), isTrue);
    expect(any((p) => p['r'] == 1), isTrue);
    expect(any((p) => p['nn'] == 1 || p['nr'] == 1 || p['nl'] == 1), isTrue);
    expect(any((p) => p.containsKey('b')), isTrue);
    // Every line is a real line inside the cells around the box.
    for (final f in fs) {
      final g = f['geometry'] as Map;
      if (g['type'] != 'LineString') continue;
      final coords = g['coordinates'] as List;
      expect(coords.length, greaterThanOrEqualTo(2));
      for (final p in coords) {
        final lon = (p as List)[0] as num;
        final lat = p[1] as num;
        expect(lon, inInclusiveRange(-17.1, -16.7));
        expect(lat, inInclusiveRange(32.5, 32.8));
      }
    }
  });

  test('the same view a second time comes from memory', () {
    final e = engine();
    addTearDown(e.close);
    final first = e.render(funchal);
    expect(first.decodedCells, greaterThan(0));
    final second = e.render(funchal);
    expect(second.decodedCells, 0);
    expect(second.geojson, first.geojson);
  });

  test('a new engine reads the cells from disk, not from the tile', () {
    final first = engine();
    final a = first.render(funchal);
    first.close();
    final second = engine();
    addTearDown(second.close);
    final b = second.render(funchal);
    expect(b.decodedCells, 0);
    expect(b.geojson, a.geojson);
  });

  test('another zoom simplifies the lines', () {
    final e = engine();
    addTearDown(e.close);
    final near = e.render(funchal);
    final far = e.render(
      const CycleMapRequest(
        south: 32.63,
        west: -16.95,
        north: 32.67,
        east: -16.88,
        zoom: 13,
      ),
    );
    expect(far.decodedCells, 0);
    expect(far.geojson.length, lessThan(near.geojson.length));
  });

  test('only the wanted content', () {
    final e = engine();
    addTearDown(e.close);
    final barriers = features(
      e.render(
        const CycleMapRequest(
          south: 32.63,
          west: -16.95,
          north: 32.67,
          east: -16.88,
          zoom: 16,
          wanted: CycleContent.barriers,
        ),
      ),
    );
    expect(barriers, isNotEmpty);
    expect(
      barriers.every((f) => (f['properties'] as Map).containsKey('b')),
      isTrue,
    );
  });

  test('cells without a tile are counted, not drawn', () {
    final e = engine();
    addTearDown(e.close);
    final result = e.render(
      const CycleMapRequest(
        south: 46.0,
        west: 7.0,
        north: 46.05,
        east: 7.05,
        zoom: 14,
      ),
    );
    expect(result.cellsWithoutTile, result.cells);
    expect(features(result), isEmpty);
  });

  test('a size limit keeps the cells nearest the middle', () {
    final e = engine();
    addTearDown(e.close);
    final all = e.render(funchal);
    final cut = e.render(
      CycleMapRequest(
        south: funchal.south,
        west: funchal.west,
        north: funchal.north,
        east: funchal.east,
        zoom: 16,
        maxChars: all.geojson.length ~/ 3,
      ),
    );
    expect(cut.truncated, isTrue);
    expect(cut.geojson.length, lessThan(all.geojson.length));
    expect(features(cut), isNotEmpty);
    // The middle cell is kept even when it alone is over the limit.
    final tiny = e.render(
      CycleMapRequest(
        south: funchal.south,
        west: funchal.west,
        north: funchal.north,
        east: funchal.east,
        zoom: 16,
        maxChars: 1,
      ),
    );
    expect(features(tiny), isNotEmpty);
  });

  test('a tile downloaded later is picked up after tilesChanged', () {
    final tile = File('${segments.path}/W20_N30.rd5');
    final bytes = tile.readAsBytesSync();
    tile.deleteSync();
    final e = engine();
    addTearDown(e.close);
    expect(e.render(funchal).cellsWithoutTile, greaterThan(0));
    tile.writeAsBytesSync(bytes);
    expect(e.render(funchal).cellsWithoutTile, greaterThan(0));
    e.tilesChanged();
    final result = e.render(funchal);
    expect(result.cellsWithoutTile, 0);
    expect(features(result), isNotEmpty);
  });

  test('pruning drops the stored cells of tiles that changed', () {
    final e = engine();
    e.render(funchal);
    e.close();
    expect(cache.listSync(), hasLength(1));
    final tile = File('${segments.path}/W20_N30.rd5');
    tile.setLastModifiedSync(DateTime(2020));
    engine().pruneStore();
    expect(cache.listSync(), isEmpty);
  });
}
