import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/features/map/data/map_preferences.dart';
import 'package:velorki_geo/velorki_geo.dart';

const String _latKey = 'map.camera.lat';
const String _lonKey = 'map.camera.lon';
const String _zoomKey = 'map.camera.zoom';
const String _cyclosmKey = 'map.cyclosm_overlay';

Future<(ProviderContainer, SharedPreferences)> _container([
  Map<String, Object> stored = const <String, Object>{},
]) async {
  SharedPreferences.setMockInitialValues(stored);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  return (container, prefs);
}

void main() {
  group('MapCamera', () {
    test('two cameras on the same spot are the same camera', () {
      const camera = MapCamera(center: LatLng(48.0, 11.0), zoom: 12.5);

      expect(camera, const MapCamera(center: LatLng(48.0, 11.0), zoom: 12.5));
      expect(
        camera.hashCode,
        const MapCamera(center: LatLng(48.0, 11.0), zoom: 12.5).hashCode,
      );
      expect(
        camera,
        isNot(const MapCamera(center: LatLng(48.0, 11.0), zoom: 12.6)),
      );
      expect(
        camera,
        isNot(const MapCamera(center: LatLng(48.1, 11.0), zoom: 12.5)),
      );
    });

    test('toString names the centre and the zoom', () {
      expect(
        const MapCamera(center: LatLng(48.0, 11.0), zoom: 12.5).toString(),
        'MapCamera(LatLng(48.0, 11.0), zoom: 12.5)',
      );
    });

    test('the default view is central Europe at a country zoom', () {
      expect(defaultMapCamera.center, const LatLng(50.0, 10.0));
      expect(defaultMapCamera.zoom, 4.5);
    });
  });

  group('LastMapCamera', () {
    test('a fresh install opens on the default view', () async {
      final (container, _) = await _container();

      expect(container.read(lastMapCameraProvider), defaultMapCamera);
    });

    test('the camera the map was left at is where it opens', () async {
      final (container, _) = await _container(<String, Object>{
        _latKey: 48.1374,
        _lonKey: 11.5755,
        _zoomKey: 13.25,
      });

      expect(
        container.read(lastMapCameraProvider),
        const MapCamera(center: LatLng(48.1374, 11.5755), zoom: 13.25),
      );
    });

    test('a half-written camera falls back to the default', () async {
      // All three values or none: a centre without a zoom is not a camera.
      final (withoutZoom, _) = await _container(<String, Object>{
        _latKey: 48.1374,
        _lonKey: 11.5755,
      });
      expect(withoutZoom.read(lastMapCameraProvider), defaultMapCamera);

      final (withoutLon, _) = await _container(<String, Object>{
        _latKey: 48.1374,
        _zoomKey: 13.25,
      });
      expect(withoutLon.read(lastMapCameraProvider), defaultMapCamera);

      final (withoutLat, _) = await _container(<String, Object>{
        _lonKey: 11.5755,
        _zoomKey: 13.25,
      });
      expect(withoutLat.read(lastMapCameraProvider), defaultMapCamera);
    });

    test('saving a camera stores all three values', () async {
      final (container, prefs) = await _container();

      await container
          .read(lastMapCameraProvider.notifier)
          .save(const MapCamera(center: LatLng(48.1374, 11.5755), zoom: 13.25));

      expect(prefs.getDouble(_latKey), 48.1374);
      expect(prefs.getDouble(_lonKey), 11.5755);
      expect(prefs.getDouble(_zoomKey), 13.25);
    });

    test('saving a camera tells the listeners at once', () async {
      final (container, _) = await _container();
      final seen = <MapCamera>[];
      container.listen(
        lastMapCameraProvider,
        (_, next) => seen.add(next),
        fireImmediately: true,
      );

      const moved = MapCamera(center: LatLng(52.52, 13.405), zoom: 11.0);
      await container.read(lastMapCameraProvider.notifier).save(moved);

      expect(seen, [defaultMapCamera, moved]);
      expect(container.read(lastMapCameraProvider), moved);
    });

    test('the camera saved last is the one read back', () async {
      final (first, prefs) = await _container();
      await first
          .read(lastMapCameraProvider.notifier)
          .save(const MapCamera(center: LatLng(52.52, 13.405), zoom: 11.0));

      final reopened = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(reopened.dispose);

      expect(
        reopened.read(lastMapCameraProvider),
        const MapCamera(center: LatLng(52.52, 13.405), zoom: 11.0),
      );
    });
  });

  group('CyclosmOverlay', () {
    test('the overlay is off on a fresh install', () async {
      final (container, _) = await _container();

      expect(container.read(cyclosmOverlayProvider), isFalse);
    });

    test('an overlay left switched on comes back on', () async {
      final (container, _) = await _container(<String, Object>{
        _cyclosmKey: true,
      });

      expect(container.read(cyclosmOverlayProvider), isTrue);
    });

    test('switching the overlay on stores it and notifies', () async {
      final (container, prefs) = await _container();
      final seen = <bool>[];
      container.listen(
        cyclosmOverlayProvider,
        (_, next) => seen.add(next),
        fireImmediately: true,
      );

      await container.read(cyclosmOverlayProvider.notifier).set(true);

      expect(prefs.getBool(_cyclosmKey), isTrue);
      expect(container.read(cyclosmOverlayProvider), isTrue);
      expect(seen, [false, true]);
    });

    test('switching it off again stores the false', () async {
      final (container, prefs) = await _container(<String, Object>{
        _cyclosmKey: true,
      });

      await container.read(cyclosmOverlayProvider.notifier).set(false);

      expect(prefs.getBool(_cyclosmKey), isFalse);
      expect(container.read(cyclosmOverlayProvider), isFalse);
    });

    test('toggling flips the overlay and keeps the choice', () async {
      final (container, prefs) = await _container();
      final notifier = container.read(cyclosmOverlayProvider.notifier);

      await notifier.toggle();
      expect(container.read(cyclosmOverlayProvider), isTrue);
      expect(prefs.getBool(_cyclosmKey), isTrue);

      await notifier.toggle();
      expect(container.read(cyclosmOverlayProvider), isFalse);
      expect(prefs.getBool(_cyclosmKey), isFalse);
    });
  });
}
