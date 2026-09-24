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

  group('fitCamera', () {
    const size = Size(512, 512);

    test('picks the zoom at which the bounds just fill the visible map', () {
      // Half the world wide at zoom 0 (256 px): one zoom in fills 512 px.
      const wide = BoundingBox(south: 0, west: -90, north: 0, east: 90);
      final fit = fitCamera(wide, size: size, padding: EdgeInsets.zero);
      expect(fit.zoom, closeTo(1, 1e-9));
      expect(fit.center.lat, closeTo(0, 1e-9));
      expect(fit.center.lon, closeTo(0, 1e-9));
    });

    test('a column at the right leaves less room, and aims east of the '
        'middle', () {
      const wide = BoundingBox(south: 0, west: -90, north: 0, east: 90);
      final fit = fitCamera(
        wide,
        size: size,
        padding: const EdgeInsets.only(right: 256),
      );
      expect(fit.zoom, closeTo(0, 1e-9));
      // The visible middle is left of the map's, so the camera sits east of
      // the bounds' middle to put it there.
      expect(fit.center.lon, greaterThan(0));
    });

    test('the tighter side decides, and the middle is Mercator\'s', () {
      // North of the equator up to where y = 128 px at zoom 0: 128 px tall
      // and next to nothing wide, so the height decides: 512 / 128 = zoom 2.
      const tall = BoundingBox(
        south: 0,
        west: 0,
        north: 66.51326,
        east: 0.0001,
      );
      final fit = fitCamera(tall, size: size, padding: EdgeInsets.zero);
      expect(fit.zoom, closeTo(2, 1e-3));
      // The middle in world pixels (y = 192) is further north than the
      // arithmetic middle of the latitudes (33.26°).
      expect(fit.center.lat, closeTo(40.98, 0.05));
    });

    test('a sheet at the bottom aims the camera south of the bounds', () {
      const box = BoundingBox(south: 47, west: 8, north: 48, east: 9);
      final fit = fitCamera(
        box,
        size: size,
        padding: const EdgeInsets.only(bottom: 256),
      );
      final plain = fitCamera(box, size: size, padding: EdgeInsets.zero);
      expect(fit.zoom, lessThan(plain.zoom));
      expect(fit.center.lat, lessThan(plain.center.lat));
    });

    test('never zooms past the cap on a tiny box', () {
      const dot = BoundingBox(south: 47, west: 8, north: 47.0001, east: 8.0001);
      expect(fitCamera(dot, size: size, padding: EdgeInsets.zero).zoom, 18);
      expect(
        fitCamera(dot, size: size, padding: EdgeInsets.zero, maxZoom: 15).zoom,
        15,
      );
    });

    test('crosses the antimeridian the short way', () {
      const across = BoundingBox(south: 0, west: 170, north: 0, east: -170);
      final fit = fitCamera(across, size: size, padding: EdgeInsets.zero);
      // 20° of longitude, not 340°.
      expect(fit.zoom, greaterThan(4));
      expect(fit.center.lon.abs(), closeTo(180, 1e-6));
    });
  });
}
