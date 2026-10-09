import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/map/application/cycle_map_driver.dart';
import 'package:velorki/features/map/domain/cycle_map.dart';
import 'package:velorki/features/map/testing/testing.dart';
import 'package:velorki_cycle_map/velorki_cycle_map.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// Answers every request with a file named after its serial, when told to.
class FakeRenderer implements CycleMapRenderer {
  final List<(CycleMapRequest, Completer<CycleMapFile?>)> pending = [];
  final List<CycleMapRequest> requests = [];
  int released = 0;
  int tilesChangedCalls = 0;
  int _serial = 0;

  @override
  Future<CycleMapFile?> render(CycleMapRequest request, {Object client = 0}) {
    final completer = Completer<CycleMapFile?>();
    requests.add(request);
    pending.add((request, completer));
    return completer.future;
  }

  /// Answers every pending request, in order.
  Future<void> answerAll() async {
    final now = List.of(pending);
    pending.clear();
    for (final (_, completer) in now) {
      completer.complete(
        CycleMapFile(
          path: '/out/${_serial++}.geojson',
          result: const CycleMapResult(
            geojson: '',
            cells: 4,
            cellsWithoutTile: 0,
            truncated: false,
            decodedCells: 0,
          ),
        ),
      );
    }
    await Future<void>.delayed(Duration.zero);
  }

  @override
  void release(Object client) => released++;

  @override
  void tilesChanged() => tilesChangedCalls++;
}

const shown = CycleMapSettings(shown: true);

BoundingBox box(double lon, double lat, [double half = 0.01]) => BoundingBox(
  south: lat - half,
  west: lon - half,
  north: lat + half,
  east: lon + half,
);

void main() {
  late FakeMapController map;
  late FakeRenderer renderer;
  late CycleMapDriver driver;
  var covered = true;

  setUp(() {
    covered = true;
    map = FakeMapController()
      ..zoom = 14.2
      ..visibleBounds = box(-16.91, 32.65);
    renderer = FakeRenderer();
    driver = CycleMapDriver(renderer: renderer, covers: (_) => covered);
    addTearDown(driver.dispose);
  });

  test('off, it asks for nothing and draws nothing', () async {
    driver.attach(map);
    map.emitCameraIdle();
    expect(renderer.requests, isEmpty);
    expect(map.cycleMapCalls, isEmpty);
  });

  test('on, it draws the view and a margin around it', () async {
    driver
      ..attach(map)
      ..configure(shown);
    expect(renderer.requests, hasLength(1));
    final request = renderer.requests.single;
    expect(request.south, closeTo(32.63, 1e-9));
    expect(request.north, closeTo(32.67, 1e-9));
    expect(request.west, closeTo(-16.93, 1e-9));
    expect(request.east, closeTo(-16.89, 1e-9));
    expect(request.zoom, 14.2);
    expect(request.wanted, cycleContentOf(defaultCycleMapParts));
    await renderer.answerAll();
    expect(map.cycleMap, '/out/0.geojson');
    expect(map.cycleMapParts, defaultCycleMapParts);
  });

  test('panning inside the drawn area asks for nothing new', () async {
    driver
      ..attach(map)
      ..configure(shown);
    await renderer.answerAll();
    map.visibleBounds = box(-16.905, 32.655);
    map.emitCameraIdle();
    expect(renderer.requests, hasLength(1));
    map.visibleBounds = box(-16.88, 32.65);
    map.emitCameraIdle();
    expect(renderer.requests, hasLength(2));
  });

  test('a new zoom step asks again, within one it does not', () async {
    driver
      ..attach(map)
      ..configure(shown);
    await renderer.answerAll();
    map.zoom = 14.9;
    map.visibleBounds = box(-16.91, 32.65, 0.005);
    map.emitCameraIdle();
    expect(renderer.requests, hasLength(1));
    map.zoom = 15.1;
    map.emitCameraIdle();
    expect(renderer.requests, hasLength(2));
    expect(CycleMapDriver.zoomStep(17.5), 16);
  });

  test('zoomed out past the cycle map it keeps what it has', () async {
    driver
      ..attach(map)
      ..configure(shown);
    await renderer.answerAll();
    map
      ..zoom = 12.4
      ..visibleBounds = box(-16.91, 32.65, 0.3);
    map.emitCameraIdle();
    expect(renderer.requests, hasLength(1));
    expect(map.cycleMap, '/out/0.geojson');
  });

  test('other parts show at once and ask for a new map', () async {
    driver
      ..attach(map)
      ..configure(shown);
    await renderer.answerAll();
    const parts = {CycleMapPart.surface, CycleMapPart.barriers};
    driver.configure(const CycleMapSettings(shown: true, parts: parts));
    expect(map.cycleMapParts, parts);
    expect(renderer.requests, hasLength(2));
    expect(renderer.requests.last.wanted, cycleContentOf(parts));
  });

  test('only the newest answer is drawn', () async {
    driver
      ..attach(map)
      ..configure(shown);
    map.visibleBounds = box(-16.5, 32.65);
    map.emitCameraIdle();
    await renderer.answerAll();
    expect(map.cycleMapCalls, ['/out/1.geojson']);
  });

  test('switched off, it takes the map away', () async {
    driver
      ..attach(map)
      ..configure(shown);
    await renderer.answerAll();
    driver.configure(const CycleMapSettings());
    expect(map.cycleMap, isNull);
    expect(renderer.released, greaterThan(0));
  });

  test('new tiles: a new map, and the hint follows coverage', () async {
    covered = false;
    driver
      ..attach(map)
      ..configure(shown);
    expect(driver.needsDownload.value, isTrue);
    await renderer.answerAll();
    driver.tilesChanged((_) => true);
    expect(renderer.tilesChangedCalls, 1);
    expect(renderer.requests, hasLength(2));
    expect(driver.needsDownload.value, isFalse);
  });

  test('no hint while the cycle map is off', () {
    covered = false;
    driver.attach(map);
    map.emitCameraIdle();
    expect(driver.needsDownload.value, isFalse);
  });

  test('detach takes the map away and stops listening', () async {
    driver
      ..attach(map)
      ..configure(shown);
    await renderer.answerAll();
    driver.detach();
    expect(map.cycleMap, isNull);
    expect(map.cameraIdleListeners, isEmpty);
  });

  test('an answer for a map let go of is dropped', () async {
    driver
      ..attach(map)
      ..configure(shown);
    driver.detach(clear: false);
    await renderer.answerAll();
    expect(map.cycleMapCalls, isEmpty);
  });

  test('halfway into the fade a new area is drawn already', () async {
    map.zoom = 12.6;
    driver
      ..attach(map)
      ..configure(shown);
    expect(renderer.requests, hasLength(1));
  });
}
