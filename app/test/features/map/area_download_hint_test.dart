import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/map/application/area_download_hint.dart';
import 'package:velorki/features/map/testing/testing.dart';
import 'package:velorki_geo/velorki_geo.dart';

BoundingBox around(double lon, double lat) => BoundingBox(
  south: lat - 0.01,
  west: lon - 0.01,
  north: lat + 0.01,
  east: lon + 0.01,
);

void main() {
  late FakeMapController map;
  late FakeStopsCoverage coverage;
  late AreaDownloadHint hint;

  setUp(() {
    map = FakeMapController()
      ..zoom = 13
      ..visibleBounds = around(8.5, 47.4);
    coverage = FakeStopsCoverage();
    hint = AreaDownloadHint(coverage);
    addTearDown(hint.dispose);
  });

  test('over a downloaded area there is no hint', () {
    hint.attach(map);
    expect(hint.needed, isFalse);
  });

  test('over an area not downloaded the hint shows, and goes once it is', () {
    coverage.covered = (_) => false;
    hint.attach(map);
    expect(hint.needed, isTrue);
    coverage.changed(null);
    expect(hint.needed, isFalse);
  });

  test('it follows the camera', () {
    hint.attach(map);
    coverage.covered = (_) => false;
    map.emitCameraIdle();
    expect(hint.needed, isTrue);
  });

  test('zoomed out past the hint zoom there is none', () {
    coverage.covered = (_) => false;
    map.zoom = 9;
    hint.attach(map);
    expect(hint.needed, isFalse);
  });

  test('detach takes the hint away', () {
    coverage.covered = (_) => false;
    hint.attach(map);
    hint.detach();
    expect(hint.needed, isFalse);
    expect(map.cameraIdleListeners, isEmpty);
  });
}
