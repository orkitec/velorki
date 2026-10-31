import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/features/map/data/country_map_views.dart';
import 'package:velorki/features/map/data/map_preferences.dart';
import 'package:velorki/features/settings/data/units.dart';
import 'package:velorki/features/map/domain/cycle_map.dart';
import 'package:velorki_geo/velorki_geo.dart';

const String _latKey = 'map.camera.lat';
const String _lonKey = 'map.camera.lon';
const String _zoomKey = 'map.camera.zoom';
const String _cyclosmKey = 'map.cyclosm_overlay';

Future<(ProviderContainer, SharedPreferences)> _container([
  Map<String, Object> stored = const <String, Object>{},
  String? country,
]) async {
  SharedPreferences.setMockInitialValues(stored);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      localeCountryProvider.overrideWithValue(country),
    ],
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

    test('toString names the centre, the zoom and the bearing', () {
      expect(
        const MapCamera(center: LatLng(48.0, 11.0), zoom: 12.5).toString(),
        'MapCamera(LatLng(48.0, 11.0), zoom: 12.5, bearing: 0.0)',
      );
    });

    test('a turned map is another camera', () {
      const north = MapCamera(center: LatLng(48.0, 11.0), zoom: 12.5);
      const east = MapCamera(
        center: LatLng(48.0, 11.0),
        zoom: 12.5,
        bearing: 90,
      );
      expect(north, isNot(east));
      expect(north.hashCode, isNot(east.hashCode));
    });

    test('the default view is central Europe at a country zoom', () {
      expect(defaultMapCamera.center, const LatLng(50.0, 10.0));
      expect(defaultMapCamera.zoom, 4.5);
    });
  });

  group('countryMapViews', () {
    test('every entry is a real place and a phone-sized zoom', () {
      expect(countryMapViews.length, greaterThanOrEqualTo(249));
      countryMapViews.forEach((code, view) {
        expect(code, matches(RegExp(r'^[A-Z]{2}$')));
        expect(view.lat, inInclusiveRange(-90, 90), reason: code);
        expect(view.lon, inInclusiveRange(-180, 180), reason: code);
        expect(view.zoom, inInclusiveRange(1.5, 12.5), reason: code);
      });
    });

    test('the common countries are all there', () {
      const common = [
        // The EU.
        'AT', 'BE', 'BG', 'HR', 'CY', 'CZ', 'DK', 'EE', 'FI', 'FR', 'DE',
        'GR', 'HU', 'IE', 'IT', 'LV', 'LT', 'LU', 'MT', 'NL', 'PL', 'PT',
        'RO', 'SK', 'SI', 'ES', 'SE',
        'US', 'CA', 'GB', 'CH', 'NO', 'AU', 'NZ', 'JP', 'BR',
      ];
      for (final code in common) {
        expect(countryMapViews, contains(code));
      }
    });

    test('small countries are closer than big ones', () {
      expect(
        countryMapViews['LU']!.zoom,
        greaterThan(countryMapViews['DE']!.zoom),
      );
      expect(
        countryMapViews['DE']!.zoom,
        greaterThan(countryMapViews['US']!.zoom),
      );
      expect(
        countryMapViews['US']!.zoom,
        greaterThan(countryMapViews['RU']!.zoom),
      );
    });
  });

  group('LastMapCamera', () {
    test(
      'a fresh install with no known country opens on the default view',
      () async {
        final (container, _) = await _container();

        expect(container.read(lastMapCameraProvider), defaultMapCamera);
        expect(
          hasStoredMapCamera(container.read(sharedPreferencesProvider)),
          isFalse,
        );
      },
    );

    test('a fresh install opens over the phone\'s country', () async {
      for (final code in ['DE', 'US', 'LU']) {
        final (container, _) = await _container(const <String, Object>{}, code);
        final view = countryMapViews[code]!;

        expect(
          container.read(lastMapCameraProvider),
          MapCamera(center: LatLng(view.lat, view.lon), zoom: view.zoom),
          reason: code,
        );
      }
    });

    test('a country without an entry opens on the default view', () async {
      final (container, _) = await _container(const <String, Object>{}, 'ZZ');

      expect(container.read(lastMapCameraProvider), defaultMapCamera);
    });

    test('the camera the map was left at wins over the country', () async {
      final (container, prefs) = await _container(<String, Object>{
        _latKey: 48.1374,
        _lonKey: 11.5755,
        _zoomKey: 13.25,
      }, 'US');

      expect(
        container.read(lastMapCameraProvider),
        const MapCamera(center: LatLng(48.1374, 11.5755), zoom: 13.25),
      );
      expect(hasStoredMapCamera(prefs), isTrue);
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

    test(
      'saving a camera stores the centre and the zoom, not the bearing',
      () async {
        final (container, prefs) = await _container();

        const camera = MapCamera(
          center: LatLng(48.1374, 11.5755),
          zoom: 13.25,
          bearing: 45,
        );
        await container.read(lastMapCameraProvider.notifier).save(camera);

        expect(prefs.getDouble(_latKey), 48.1374);
        expect(prefs.getDouble(_lonKey), 11.5755);
        expect(prefs.getDouble(_zoomKey), 13.25);
        // In memory the bearing is kept, for the other maps of this launch;
        // the next launch opens north up.
        expect(container.read(lastMapCameraProvider), camera);
        expect(prefs.getKeys(), isNot(contains(contains('bearing'))));
        final (relaunched, _) = await _container(<String, Object>{
          _latKey: 48.1374,
          _lonKey: 11.5755,
          _zoomKey: 13.25,
        });
        expect(relaunched.read(lastMapCameraProvider).bearing, 0);
      },
    );

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

  group('MapStopsPreferences', () {
    test('on, the five everyday kinds, along the route, until set', () async {
      final (container, _) = await _container();

      final stops = container.read(mapStopsPreferencesProvider);

      expect(stops.shown, isTrue);
      expect(stops.kinds, <String>{
        'drinking_water',
        'cafe',
        'bakery',
        'toilets',
        'bicycle_repair_station',
      });
      expect(stops.alongRoute, isTrue);
    });

    test('a rider who switched the stops off keeps them off', () async {
      final (container, _) = await _container(<String, Object>{
        'map.stops.shown': false,
      });

      expect(container.read(mapStopsPreferencesProvider).shown, isFalse);
    });

    test('every choice is stored and read back on the next launch', () async {
      final (container, prefs) = await _container();
      final notifier = container.read(mapStopsPreferencesProvider.notifier);

      await notifier.setShown(true);
      await notifier.setKind('cafe', shown: false);
      await notifier.setKind('camp_site', shown: true);
      await notifier.setAlongRoute(false);

      expect(prefs.getBool('map.stops.shown'), isTrue);
      expect(prefs.getBool('map.stops.alongRoute'), isFalse);
      expect(
        prefs.getStringList('map.stops.kinds'),
        unorderedEquals(<String>[
          'drinking_water',
          'bakery',
          'toilets',
          'bicycle_repair_station',
          'camp_site',
        ]),
      );

      // A fresh container over the same storage is the next launch.
      final next = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(next.dispose);
      final stops = next.read(mapStopsPreferencesProvider);
      expect(stops.shown, isTrue);
      expect(stops.alongRoute, isFalse);
      expect(stops.kinds, contains('camp_site'));
      expect(stops.kinds, isNot(contains('cafe')));
    });

    test('a rider who switched every kind off keeps none', () async {
      final (container, prefs) = await _container(<String, Object>{
        'map.stops.kinds': <String>[],
      });

      expect(container.read(mapStopsPreferencesProvider).kinds, isEmpty);
      expect(prefs.getStringList('map.stops.kinds'), isEmpty);
    });
  });

  group('CycleMapPreferences', () {
    test('on with the default parts on a fresh install', () async {
      final (container, _) = await _container();
      final settings = container.read(cycleMapPreferencesProvider);
      expect(settings.shown, isTrue);
      expect(settings.parts, defaultCycleMapParts);
    });

    test('a rider who switched it off keeps it off', () async {
      final (container, _) = await _container(<String, Object>{
        'map.cycle_map.shown': false,
      });
      expect(container.read(cycleMapPreferencesProvider).shown, isFalse);
    });

    test('a rider on the CyclOSM overlay does not get both', () async {
      final (container, _) = await _container(<String, Object>{
        _cyclosmKey: true,
      });
      expect(container.read(cycleMapPreferencesProvider).shown, isFalse);
    });

    test('a part switched off stays off', () async {
      final (container, _) = await _container();
      await container
          .read(cycleMapPreferencesProvider.notifier)
          .setPart(CycleMapPart.directions, shown: false);
      container.invalidate(cycleMapPreferencesProvider);
      expect(
        container.read(cycleMapPreferencesProvider).parts,
        isNot(contains(CycleMapPart.directions)),
      );
    });

    test('a part added since the last choice starts as its default', () async {
      // Saved by a build that knew neither one-way part.
      final (container, _) = await _container(<String, Object>{
        'map.cycle_map.parts': <String>['infrastructure'],
        'map.cycle_map.known': <String>['infrastructure', 'paths'],
      });
      final parts = container.read(cycleMapPreferencesProvider).parts;
      expect(parts, contains(CycleMapPart.infrastructure));
      expect(parts, isNot(contains(CycleMapPart.paths)));
      expect(parts, contains(CycleMapPart.directions));
      expect(parts, isNot(contains(CycleMapPart.onewayStreets)));
    });
  });
}
