import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/map/application/area_download_hint.dart';
import 'package:velorki/features/map/testing/testing.dart';
import 'package:velorki_brouter/velorki_brouter.dart' show TileName;
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

  test('the hint names the tile under the middle of the map', () {
    coverage.covered = (_) => false;
    hint.attach(map);
    expect(hint.missingArea, const TileName(5, 45));
    map.visibleBounds = around(11.5, 48.1);
    map.emitCameraIdle();
    expect(hint.missingArea, const TileName(10, 45));
    coverage.changed(null);
    expect(hint.missingArea, isNull);
  });

  test('closed over an area, it stays away while the map is over that area '
      'and comes back over another', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    coverage.covered = (_) => false;
    hint.attach(map);
    Set<TileName> dismissed() => container.read(areaHintDismissalsProvider);
    expect(hint.shownDespite(dismissed()), isTrue);

    container
        .read(areaHintDismissalsProvider.notifier)
        .dismiss(hint.missingArea!);
    expect(hint.shownDespite(dismissed()), isFalse);

    // Panned within the same tile.
    map.visibleBounds = around(9.6, 48.9);
    map.emitCameraIdle();
    expect(hint.shownDespite(dismissed()), isFalse);

    // Into the tile beside it.
    map.visibleBounds = around(10.4, 47.4);
    map.emitCameraIdle();
    expect(hint.shownDespite(dismissed()), isTrue);
  });
}
