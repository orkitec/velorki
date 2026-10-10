import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/features/map/application/weather_map_binding.dart';
import 'package:velorki/features/map/application/weather_map_driver.dart';
import 'package:velorki/features/map/data/weather_map_preferences.dart';
import 'package:velorki/features/map/domain/weather_map.dart';
import 'package:velorki/features/map/presentation/layers_sheet.dart';
import 'package:velorki/features/map/presentation/weather_map_overlay.dart';
import 'package:velorki/l10n/generated/app_localizations.dart';

import '../../support/app.dart';

final AppLocalizations l10n = lookupAppLocalizations(const Locale('en'));

Future<(SharedPreferences, ProviderContainer)> _pump(
  WidgetTester tester,
  Widget child, {
  Map<String, Object> prefs = const <String, Object>{},
}) async {
  await tester.binding.setSurfaceSize(const Size(411, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues(prefs);
  final preferences = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: testApp(home: Scaffold(body: child)),
    ),
  );
  await tester.pump();
  return (preferences, container);
}

Finder _switch(String title) => find.widgetWithText(SwitchListTile, title);

void main() {
  test(
    'the mirror\'s override is kept for offline and dropped with it',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      ProviderContainer open() {
        final container = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        );
        addTearDown(container.dispose);
        return container;
      }

      final container = open();
      bool dwd(ProviderContainer c) => c
          .read(weatherMapSourcesProvider)
          .firstWhere((s) => s.id == 'radar_dwd')
          .enabled;
      expect(dwd(container), isTrue);
      await container.read(weatherMapSourcesProvider.notifier).applyPointer([
        {'id': 'radar_dwd', 'enabled': false},
      ]);
      expect(dwd(container), isFalse);
      // Read back on the next start, with no network.
      expect(dwd(open()), isFalse);
      // A pointer without one: the defaults again.
      await container
          .read(weatherMapSourcesProvider.notifier)
          .applyPointer(null);
      expect(dwd(container), isTrue);
      expect(prefs.getString('map.weather.override'), isNull);
    },
  );

  group('Layers sheet', () {
    testWidgets('rain radar and clouds are off at first and remembered', (
      tester,
    ) async {
      final (prefs, container) = await _pump(tester, const LayersSheet());
      expect(_switch(l10n.mapLayersRainRadar), findsOneWidget);
      expect(find.text(l10n.mapLayersRainRadarSubtitle), findsOneWidget);
      expect(_switch(l10n.mapLayersClouds), findsOneWidget);
      expect(find.text(l10n.mapLayersCloudsSubtitle), findsOneWidget);
      expect(container.read(weatherMapPreferencesProvider).any, isFalse);

      await tester.tap(_switch(l10n.mapLayersRainRadar));
      await tester.pumpAndSettle();
      expect(container.read(weatherMapPreferencesProvider).radar, isTrue);
      expect(prefs.getBool('map.weather.radar'), isTrue);

      await tester.tap(_switch(l10n.mapLayersClouds));
      await tester.pumpAndSettle();
      expect(prefs.getBool('map.weather.clouds'), isTrue);

      // A fresh start reads them back.
      final again = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(again.dispose);
      expect(
        again.read(weatherMapPreferencesProvider),
        const WeatherMapSettings(radar: true, clouds: true),
      );
    });

    testWidgets('a switch whose sources are all off is not offered', (
      tester,
    ) async {
      await _pump(
        tester,
        const LayersSheet(),
        prefs: <String, Object>{
          'map.weather.override': encodeWeatherOverride([
            {'id': 'radar_dwd', 'enabled': false},
            {'id': 'radar_noaa', 'enabled': false},
          ])!,
        },
      );
      expect(_switch(l10n.mapLayersRainRadar), findsNothing);
      expect(_switch(l10n.mapLayersClouds), findsOneWidget);
    });
  });

  group('time control', () {
    testWidgets('only while the radar is on', (tester) async {
      final (_, container) = await _pump(
        tester,
        const Align(alignment: Alignment.topRight, child: WeatherMapOverlay()),
      );
      expect(find.byType(Slider), findsNothing);
      await container
          .read(weatherMapPreferencesProvider.notifier)
          .setClouds(true);
      await tester.pump();
      expect(find.byType(Slider), findsNothing);
      await container
          .read(weatherMapPreferencesProvider.notifier)
          .setRadar(true);
      await tester.pump();
      expect(find.byType(Slider), findsOneWidget);
      await container
          .read(weatherMapPreferencesProvider.notifier)
          .setRadar(false);
      await tester.pump();
      expect(find.byType(Slider), findsNothing);
    });

    testWidgets('the label says the offset and the frame in local time', (
      tester,
    ) async {
      final (_, container) = await _pump(
        tester,
        const Align(alignment: Alignment.topRight, child: WeatherMapOverlay()),
        prefs: <String, Object>{'map.weather.radar': true},
      );
      final frame = DateTime.utc(2026, 10, 10, 14, 35);
      container
          .read(sharedWeatherMapStatusProvider.notifier)
          .set(WeatherMapStatus(radarFrame: frame));
      await tester.pump();
      String label() => tester
          .widget<Text>(find.byKey(const ValueKey('weather-time-label')))
          .data!;
      final context = tester.element(find.byType(Slider));
      expect(label(), 'Now · ${weatherClockTime(context, frame)}');

      // Moved a step back: the label follows the finger.
      final slider = tester.getRect(find.byType(Slider));
      final step = (slider.width - 2 * 14) / 16;
      await tester.dragFrom(slider.center, Offset(-step * 3, 0));
      await tester.pump();
      expect(container.read(weatherRadarOffsetProvider), -45);
      container
          .read(sharedWeatherMapStatusProvider.notifier)
          .set(
            WeatherMapStatus(
              radarFrame: frame.subtract(const Duration(minutes: 45)),
            ),
          );
      await tester.pump();
      expect(
        label(),
        '−45 min · '
        '${weatherClockTime(context, frame.subtract(const Duration(minutes: 45)))}',
      );
    });

    testWidgets('a moment ahead elsewhere says forecast is Germany only', (
      tester,
    ) async {
      final (_, container) = await _pump(
        tester,
        const Align(alignment: Alignment.topRight, child: WeatherMapOverlay()),
        prefs: <String, Object>{'map.weather.radar': true},
      );
      container
          .read(sharedWeatherMapStatusProvider.notifier)
          .set(const WeatherMapStatus(forecastElsewhere: true));
      await tester.pump();
      expect(find.text(l10n.mapWeatherForecastGermanyOnly), findsOneWidget);
    });

    testWidgets('a layer that did not answer says so until it does', (
      tester,
    ) async {
      final (_, container) = await _pump(
        tester,
        const Align(alignment: Alignment.topRight, child: WeatherMapOverlay()),
        prefs: <String, Object>{
          'map.weather.radar': true,
          'map.weather.clouds': true,
        },
      );
      final status = container.read(sharedWeatherMapStatusProvider.notifier);
      expect(find.text(l10n.mapWeatherRadarUnavailable), findsNothing);
      status.set(
        const WeatherMapStatus(
          failed: <WeatherKind>{WeatherKind.radar, WeatherKind.clouds},
        ),
      );
      await tester.pump();
      expect(find.text(l10n.mapWeatherRadarUnavailable), findsOneWidget);
      expect(find.text(l10n.mapWeatherCloudsUnavailable), findsOneWidget);
      status.set(const WeatherMapStatus());
      await tester.pump();
      expect(find.text(l10n.mapWeatherRadarUnavailable), findsNothing);
      expect(find.text(l10n.mapWeatherCloudsUnavailable), findsNothing);
    });

    testWidgets('clouds alone show their time', (tester) async {
      final (_, container) = await _pump(
        tester,
        const Align(alignment: Alignment.topRight, child: WeatherMapOverlay()),
        prefs: <String, Object>{'map.weather.clouds': true},
      );
      expect(find.textContaining('Clouds'), findsNothing);
      container
          .read(sharedWeatherMapStatusProvider.notifier)
          .set(WeatherMapStatus(cloudsFrame: DateTime.utc(2026, 10, 10, 14)));
      await tester.pump();
      expect(find.textContaining('Clouds '), findsOneWidget);
      expect(find.byType(Slider), findsNothing);
    });
  });
}
