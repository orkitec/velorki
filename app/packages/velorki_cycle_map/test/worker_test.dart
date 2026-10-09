import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:velorki_cycle_map/velorki_cycle_map.dart';

import 'support/paths.dart';

CycleMapRequest around(double lon, double lat, {double zoom = 15}) =>
    CycleMapRequest(
      south: lat - 0.01,
      west: lon - 0.01,
      north: lat + 0.01,
      east: lon + 0.01,
      zoom: zoom,
    );

void main() {
  late Directory temp;
  late CycleMapWorker worker;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('cycle_worker');
    final segments = Directory('${temp.path}/segments')..createSync();
    File('${oracleTiles.path}/W20_N30.rd5')
        .copySync('${segments.path}/W20_N30.rd5');
    worker = await CycleMapWorker.spawn(
      segmentsDir: segments.path,
      lookupsPath: File('../../assets/brouter/profiles/lookups.dat').path,
      cacheDir: '${temp.path}/cache',
      outputDir: '${temp.path}/out',
    );
    addTearDown(() {
      worker.dispose();
      temp.deleteSync(recursive: true);
    });
  });

  test('writes the map to a file', () async {
    final file = (await worker.render(around(-16.91, 32.65)))!;
    final json = jsonDecode(File(file.path).readAsStringSync()) as Map;
    expect(json['type'], 'FeatureCollection');
    expect(json['features'], isNotEmpty);
    expect(file.result.cellsWithoutTile, 0);
  });

  test('a request made while one runs replaces the one waiting', () async {
    final first = worker.render(around(-16.91, 32.65));
    final replaced = worker.render(around(-16.95, 32.66));
    final last = worker.render(around(-16.90, 32.64));
    expect(await first, isNotNull);
    expect(await replaced, isNull);
    expect(await last, isNotNull);
  });

  test('clients do not replace each other', () async {
    final busy = worker.render(around(-16.91, 32.65), client: 'a');
    final a = worker.render(around(-16.95, 32.66), client: 'a');
    final b = worker.render(around(-16.90, 32.64), client: 'b');
    expect(await busy, isNotNull);
    expect(await a, isNotNull);
    expect(await b, isNotNull);
  });

  test('a released client gets null', () async {
    final busy = worker.render(around(-16.91, 32.65), client: 'a');
    final waiting = worker.render(around(-16.95, 32.66), client: 'a');
    worker.release('a');
    expect(await busy, isNotNull);
    expect(await waiting, isNull);
  });

  test('keeps only the two newest files', () async {
    final paths = <String>[];
    for (var i = 0; i < 4; i++) {
      paths.add((await worker.render(around(-16.91 + i * 0.01, 32.65)))!.path);
    }
    expect(File(paths[0]).existsSync(), isFalse);
    expect(File(paths[1]).existsSync(), isFalse);
    expect(File(paths[2]).existsSync(), isTrue);
    expect(File(paths[3]).existsSync(), isTrue);
    // Another client's files are its own.
    final other = (await worker.render(around(-16.9, 32.65), client: 'b'))!;
    expect(File(paths[2]).existsSync(), isTrue);
    expect(File(other.path).existsSync(), isTrue);
  });

  test('after dispose a request gets null', () async {
    worker.dispose();
    expect(await worker.render(around(-16.91, 32.65)), isNull);
  });
}
