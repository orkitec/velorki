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
import 'package:velorki/features/map/presentation/weather_time_row.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../support/app.dart';

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
            {'id': 'rain_hsaf', 'enabled': false},
            {'id': 'rain_icon_eu', 'enabled': false},
            {'id': 'rain_icon', 'enabled': false},
          ])!,
        },
      );
      expect(_switch(l10n.mapLayersRainRadar), findsNothing);
      expect(_switch(l10n.mapLayersClouds), findsOneWidget);
    });
  });

  group('time control', () {
    // 14:42 UTC, the view over Berlin.
    final at = DateTime.utc(2026, 10, 10, 14, 42);
    final berlin = WeatherMapStatus(centre: const LatLng(52.5, 13.4), at: at);
    final newYork = WeatherMapStatus(centre: const LatLng(40.7, -74), at: at);

    String label(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(weatherTimeLabelKey)).data!;

    String clock(WidgetTester tester, DateTime utc) =>
        weatherClockTime(tester.element(find.byType(Slider)), utc);

    testWidgets('only while the rain is on', (tester) async {
      final (_, container) = await _pump(tester, const WeatherTimeRow());
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

    testWidgets('one line: the label and the slider side by side', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      final (_, container) = await _pump(
        tester,
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: WeatherTimeRow(),
        ),
        prefs: <String, Object>{'map.weather.radar': true},
      );
      container.read(sharedWeatherMapStatusProvider.notifier).set(berlin);
      container.read(weatherRadarOffsetProvider.notifier).set(105);
      await tester.pump();
      final text = tester.getRect(find.byKey(weatherTimeLabelKey));
      final slider = tester.getRect(find.byType(Slider));
      expect(text.right, lessThanOrEqualTo(slider.left + 1));
      expect((text.center.dy - slider.center.dy).abs(), lessThan(2));
      expect(slider.width, greaterThan(120));
    });

    testWidgets('the label says the step, the frame over the view\'s middle '
        'and what it is', (tester) async {
      final (_, container) = await _pump(
        tester,
        const WeatherTimeRow(),
        prefs: <String, Object>{'map.weather.radar': true},
      );
      final status = container.read(sharedWeatherMapStatusProvider.notifier)
        ..set(berlin);
      await tester.pump();
      // The DWD's frame over Berlin.
      expect(
        label(tester),
        '${l10n.mapWeatherNow} · '
        '${clock(tester, DateTime.utc(2026, 10, 10, 14, 35))}',
      );
      // Over New York, NOAA's, twenty minutes back: not the DWD's time.
      status.set(newYork);
      await tester.pump();
      expect(
        label(tester),
        '${l10n.mapWeatherNow} · '
        '${clock(tester, DateTime.utc(2026, 10, 10, 14, 20))}',
      );

      // Moved three steps on: the label follows the finger, the step is
      // shared once let go.
      status.set(berlin);
      await tester.pump();
      final slider = tester.getRect(find.byType(Slider));
      final step = (slider.width - 2 * 14) / (weatherRadarOffsets.length - 1);
      final gesture = await tester.startGesture(
        Offset(slider.left + 14, slider.center.dy),
      );
      await gesture.moveBy(Offset(step * 3, 0));
      await tester.pump();
      expect(
        label(tester),
        '${l10n.mapWeatherMinutesAhead(45)} · '
        '${clock(tester, DateTime.utc(2026, 10, 10, 15, 20))} · '
        '${l10n.mapWeatherNowcast}',
      );
      expect(container.read(weatherRadarOffsetProvider), 0);
      await gesture.up();
      await tester.pump();
      expect(container.read(weatherRadarOffsetProvider), 45);

      // Over New York ahead: the model, for the hour the step falls in.
      status.set(newYork);
      await tester.pump();
      expect(
        label(tester),
        '${l10n.mapWeatherMinutesAhead(45)} · '
        '${clock(tester, DateTime.utc(2026, 10, 10, 15))} · '
        '${l10n.mapWeatherForecast}',
      );
      container.read(weatherRadarOffsetProvider.notifier).set(180);
      status.set(berlin);
      await tester.pump();
      expect(
        label(tester),
        '${l10n.mapWeatherHoursAhead(3)} · '
        '${clock(tester, DateTime.utc(2026, 10, 10, 17))} · '
        '${l10n.mapWeatherForecast}',
      );
    });

    testWidgets('a source that did not answer says so until it does', (
      tester,
    ) async {
      final (_, container) = await _pump(
        tester,
        const WeatherMapHints(),
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
          failedRain: <RainRole>{
            RainRole.radar,
            RainRole.satellite,
            RainRole.model,
          },
        ),
      );
      await tester.pump();
      expect(find.text(l10n.mapWeatherRadarUnavailable), findsOneWidget);
      expect(find.text(l10n.mapWeatherSatelliteUnavailable), findsOneWidget);
      expect(find.text(l10n.mapWeatherForecastUnavailable), findsOneWidget);
      expect(find.text(l10n.mapWeatherCloudsUnavailable), findsOneWidget);
      // No slider on the map.
      expect(find.byType(Slider), findsNothing);
      status.set(const WeatherMapStatus());
      await tester.pump();
      expect(find.byType(WeatherMapChip), findsNothing);
    });

    testWidgets('the clouds show their time, with the rain on or off', (
      tester,
    ) async {
      final (_, container) = await _pump(
        tester,
        const WeatherMapHints(),
        prefs: <String, Object>{'map.weather.clouds': true},
      );
      expect(find.byType(WeatherMapChip), findsNothing);
      final frame = DateTime.utc(2026, 10, 10, 14);
      container
          .read(sharedWeatherMapStatusProvider.notifier)
          .set(WeatherMapStatus(cloudsFrame: frame));
      await tester.pump();
      final caption = l10n.mapWeatherCloudsAt(
        weatherClockTime(tester.element(find.byType(WeatherMapHints)), frame),
      );
      expect(find.text(caption), findsOneWidget);
      await container
          .read(weatherMapPreferencesProvider.notifier)
          .setRadar(true);
      await tester.pump();
      expect(find.text(caption), findsOneWidget);
    });

    testWidgets('the Library\'s chip: the rain\'s moment, no slider', (
      tester,
    ) async {
      final (_, container) = await _pump(
        tester,
        const WeatherMapHints(rainTime: true),
        prefs: <String, Object>{'map.weather.radar': true},
      );
      container.read(sharedWeatherMapStatusProvider.notifier).set(berlin);
      await tester.pump();
      final context = tester.element(find.byType(WeatherMapHints));
      expect(
        find.text(
          '${l10n.mapLayersRainRadar} · '
          '${weatherClockTime(context, DateTime.utc(2026, 10, 10, 14, 35))}',
        ),
        findsOneWidget,
      );
      expect(find.byType(Slider), findsNothing);
      container.read(weatherRadarOffsetProvider.notifier).set(180);
      await tester.pump();
      expect(
        find.text(
          '${l10n.mapLayersRainRadar} · ${l10n.mapWeatherHoursAhead(3)} · '
          '${weatherClockTime(context, DateTime.utc(2026, 10, 10, 17))} · '
          '${l10n.mapWeatherForecast}',
        ),
        findsOneWidget,
      );
      // The rain off: no chip.
      await container
          .read(weatherMapPreferencesProvider.notifier)
          .setRadar(false);
      await tester.pump();
      expect(find.byType(WeatherMapChip), findsNothing);
    });
  });

  group('the shared step', () {
    test('kept until the app is away more than half an hour', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final step = container.read(weatherRadarOffsetProvider.notifier)..set(60);
      final t = DateTime.utc(2026, 10, 10, 14);
      step
        ..hidden(t)
        ..shown(t.add(const Duration(minutes: 29)));
      expect(container.read(weatherRadarOffsetProvider), 60);
      step
        ..hidden(t)
        ..shown(t.add(const Duration(minutes: 31)));
      expect(container.read(weatherRadarOffsetProvider), 0);
      // Shown without having been hidden: nothing.
      step
        ..set(30)
        ..shown(t.add(const Duration(hours: 5)));
      expect(container.read(weatherRadarOffsetProvider), 30);
    });

    test('snapped to the steps', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(weatherRadarOffsetProvider.notifier).set(200);
      expect(container.read(weatherRadarOffsetProvider), 180);
    });
  });
}
