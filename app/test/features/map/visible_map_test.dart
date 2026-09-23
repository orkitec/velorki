import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/map/domain/visible_map.dart';
import 'package:velorki_geo/velorki_geo.dart';

void main() {
  group('visibleMapInsets', () {
    test('adds up the chrome, the sheet and the column, with air', () {
      final insets = visibleMapInsets(
        size: const Size(400, 800),
        topInset: 50,
        chromeTop: 130,
        sheetExtent: 0.5,
        columnWidth: 62,
      );
      expect(insets, const EdgeInsets.fromLTRB(24, 204, 86, 424));
    });

    test('a sheet cannot cover more than the screen', () {
      final insets = visibleMapInsets(
        size: const Size(400, 800),
        topInset: 0,
        chromeTop: 0,
        sheetExtent: 1.4,
        columnWidth: 0,
      );
      expect(insets.bottom, 824);
    });
  });

  group('offsetCenter', () {
    const target = LatLng(0, 0);
    const size = Size(512, 512);

    test('leaves the target alone without or with symmetric padding', () {
      expect(
        offsetCenter(target, size: size, padding: EdgeInsets.zero, zoom: 3),
        target,
      );
      expect(
        offsetCenter(
          target,
          size: size,
          padding: const EdgeInsets.all(40),
          zoom: 3,
        ),
        target,
      );
    });

    test('a sheet at the bottom puts the camera south of the target', () {
      // Half the world is the sheet: the visible middle is a quarter world
      // above the map's middle, so the camera aims that far south. At zoom
      // 0 the world is 512 px, 128 px down from the equator is y = 384.
      final center = offsetCenter(
        target,
        size: size,
        padding: const EdgeInsets.only(bottom: 256),
        zoom: 0,
      );
      expect(center.lon, closeTo(0, 1e-9));
      expect(center.lat, closeTo(-66.513, 0.01));
    });

    test('the offset shrinks with the zoom', () {
      final near = offsetCenter(
        target,
        size: size,
        padding: const EdgeInsets.only(bottom: 256),
        zoom: 10,
      );
      final far = offsetCenter(
        target,
        size: size,
        padding: const EdgeInsets.only(bottom: 256),
        zoom: 9,
      );
      expect(near.lat, lessThan(0));
      expect(far.lat, closeTo(near.lat * 2, 1e-3));
    });

    test('a column at the right puts the camera east of the target', () {
      final center = offsetCenter(
        target,
        size: size,
        padding: const EdgeInsets.only(right: 128),
        zoom: 2,
      );
      expect(center.lat, closeTo(0, 1e-9));
      expect(center.lon, greaterThan(0));
    });

    test('follows the map when it is turned', () {
      // Turned 90° clockwise, north is at the right and screen-up is west:
      // a sheet at the bottom now wants the camera east of the target.
      final center = offsetCenter(
        target,
        size: size,
        padding: const EdgeInsets.only(bottom: 256),
        zoom: 0,
        bearing: 90,
      );
      expect(center.lat, closeTo(0, 1e-6));
      expect(center.lon, closeTo(90, 1e-6));
    });

    test('wraps at the antimeridian', () {
      final center = offsetCenter(
        const LatLng(0, 179.9),
        size: size,
        padding: const EdgeInsets.only(right: 256),
        zoom: 0,
      );
      expect(center.lon, closeTo(-90.1, 1e-6));
    });
  });
}
