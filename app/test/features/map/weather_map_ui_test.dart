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
  SharedPreferences.setMockInitialValues(<String, Object>{
    ...mapLayersOff,
    ...prefs,
  });
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

    testWidgets('an opacity slider under the rain and the clouds while each '
        'is on, at 75 % at first, remembered', (tester) async {
      final (prefs, container) = await _pump(tester, const LayersSheet());
      Finder slider(Key key) =>
          find.descendant(of: find.byKey(key), matching: find.byType(Slider));
      expect(find.byType(Slider), findsNothing);
      expect(container.read(weatherMapOpacityProvider), const WeatherOpacity());
      expect(const WeatherOpacity().radar, 0.75);
      expect(const WeatherOpacity().clouds, 0.75);

      await tester.tap(_switch(l10n.mapLayersRainRadar));
      await tester.pumpAndSettle();
      expect(slider(radarOpacityKey), findsOneWidget);
      expect(slider(cloudsOpacityKey), findsNothing);
      expect(tester.widget<Slider>(slider(radarOpacityKey)).value, 0.75);
      expect(find.text(l10n.mapLayersOpacity), findsOneWidget);
      expect(find.text(l10n.mapLayersOpacityValue(75)), findsOneWidget);
      // Under the rain's switch, over the clouds'.
      final rainY = tester.getCenter(_switch(l10n.mapLayersRainRadar)).dy;
      final cloudsY = tester.getCenter(_switch(l10n.mapLayersClouds)).dy;
      final sliderY = tester.getCenter(slider(radarOpacityKey)).dy;
      expect(sliderY, greaterThan(rainY));
      expect(sliderY, lessThan(cloudsY));

      // All the way down: the least, live and then remembered.
      await tester.drag(slider(radarOpacityKey), const Offset(-400, 0));
      await tester.pumpAndSettle();
      expect(container.read(weatherMapOpacityProvider).radar, 0.2);
      expect(container.read(weatherMapOpacityProvider).clouds, 0.75);
      expect(prefs.getDouble('map.weather.radarOpacity'), 0.2);
      expect(find.text(l10n.mapLayersOpacityValue(20)), findsOneWidget);

      await tester.tap(_switch(l10n.mapLayersClouds));
      await tester.pumpAndSettle();
      expect(slider(cloudsOpacityKey), findsOneWidget);
      expect(tester.widget<Slider>(slider(cloudsOpacityKey)).value, 0.75);

      // Off, its slider goes; the share is kept.
      await tester.tap(_switch(l10n.mapLayersRainRadar));
      await tester.pumpAndSettle();
      expect(slider(radarOpacityKey), findsNothing);
      expect(slider(cloudsOpacityKey), findsOneWidget);

      final again = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(again.dispose);
      expect(
        again.read(weatherMapOpacityProvider),
        const WeatherOpacity(radar: 0.2),
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
            {'id': 'radar_knmi', 'enabled': false},
            {'id': 'radar_fmi', 'enabled': false},
            {'id': 'radar_noaa', 'enabled': false},
            {'id': 'rain_hsaf', 'enabled': false},
            {'id': 'rain_icon_eu', 'enabled': false},
            {'id': 'rain_hrrr', 'enabled': false},
            {'id': 'rain_icon', 'enabled': false},
          ])!,
        },
      );
      expect(_switch(l10n.mapLayersRainRadar), findsNothing);
      expect(_switch(l10n.mapLayersClouds), findsOneWidget);
    });
  });

  group('Layers sheet, wind', () {
    testWidgets('off at first and remembered', (tester) async {
      final (prefs, container) = await _pump(tester, const LayersSheet());
      expect(_switch(l10n.mapLayersWind), findsOneWidget);
      expect(find.text(l10n.mapLayersWindSubtitle), findsOneWidget);
      expect(container.read(weatherMapPreferencesProvider).wind, isFalse);
      expect(
        tester.widget<SwitchListTile>(_switch(l10n.mapLayersWind)).value,
        isFalse,
      );
      await tester.tap(_switch(l10n.mapLayersWind));
      await tester.pumpAndSettle();
      expect(container.read(weatherMapPreferencesProvider).wind, isTrue);
      expect(prefs.getBool('map.weather.wind'), isTrue);
      // The rain and the clouds stay as they were.
      expect(container.read(weatherMapPreferencesProvider).radar, isFalse);
      final again = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(again.dispose);
      expect(
        again.read(weatherMapPreferencesProvider),
        const WeatherMapSettings(wind: true),
      );
    });

    testWidgets('not offered when the mirror turns its source off', (
      tester,
    ) async {
      await _pump(
        tester,
        const LayersSheet(),
        prefs: <String, Object>{
          'map.weather.override': encodeWeatherOverride([
            {'id': 'wind_icon', 'enabled': false},
          ])!,
        },
      );
      expect(_switch(l10n.mapLayersWind), findsNothing);
      expect(_switch(l10n.mapLayersRainRadar), findsOneWidget);
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

    // The clock always leads; the drop with the rain on, the wind's sign
    // with the wind on, in that order, each as large, a little apart.
    for (final (name, prefs, icons)
        in <(String, Map<String, Object>, List<IconData>)>[
          ('neither', <String, Object>{}, [Icons.schedule]),
          (
            'the rain',
            <String, Object>{'map.weather.radar': true},
            [Icons.schedule, Icons.water_drop_outlined],
          ),
          (
            'the wind',
            <String, Object>{'map.weather.wind': true},
            [Icons.schedule, Icons.air],
          ),
          (
            'the rain and the wind',
            <String, Object>{
              'map.weather.radar': true,
              'map.weather.wind': true,
            },
            [Icons.schedule, Icons.water_drop_outlined, Icons.air],
          ),
        ]) {
      testWidgets('the leading icons with $name on', (tester) async {
        final (_, container) = await _pump(
          tester,
          // Shown with both off too, as the Plan tab's departure.
          const WeatherTimeRow(leave: true, shown: true),
          prefs: prefs,
        );
        container.read(sharedWeatherMapStatusProvider.notifier).set(berlin);
        await tester.pump();
        final found = tester
            .widgetList<Icon>(
              find.descendant(
                of: find.byType(WeatherTimeRow),
                matching: find.byType(Icon),
              ),
            )
            .toList();
        expect(found.map((i) => i.icon), icons);
        expect(found.map((i) => i.size), everyElement(18));
        final rects = [
          for (final icon in icons) tester.getRect(find.byIcon(icon)),
        ];
        for (var i = 1; i < rects.length; i++) {
          expect(rects[i].left - rects[i - 1].right, moreOrLessEquals(4));
          expect(rects[i].center.dy, moreOrLessEquals(rects[0].center.dy));
        }
        // The label after the last icon; the slider after it, or under it
        // where the row stacks.
        final text = tester.getRect(find.byKey(weatherTimeLabelKey));
        expect(text.left, moreOrLessEquals(rects.last.right + 8, epsilon: 1));
        final slider = tester.getRect(find.byType(Slider));
        expect(
          slider.left >= text.right - 1 || slider.top >= text.bottom - 1,
          isTrue,
        );
      });
    }

    testWidgets('with the wind alone too: its hour, a forecast ahead', (
      tester,
    ) async {
      final (_, container) = await _pump(
        tester,
        const WeatherTimeRow(),
        prefs: <String, Object>{'map.weather.wind': true},
      );
      expect(find.byType(Slider), findsOneWidget);
      expect(find.byIcon(Icons.air), findsOneWidget);
      expect(find.byIcon(Icons.water_drop_outlined), findsNothing);
      expect(
        tester.getSemantics(find.byType(Slider)).label,
        contains(l10n.mapWeatherWindTime),
      );
      container.read(sharedWeatherMapStatusProvider.notifier).set(berlin);
      await tester.pump();
      // Now: the hour now falls in.
      expect(
        label(tester),
        '${l10n.mapWeatherNow} · '
        '${clock(tester, DateTime.utc(2026, 10, 10, 14))}',
      );
      container.read(weatherRadarOffsetProvider.notifier).set(180);
      await tester.pump();
      expect(
        label(tester),
        '${l10n.mapWeatherHoursAhead(3)} · '
        '${clock(tester, DateTime.utc(2026, 10, 10, 17))} · '
        '${l10n.mapWeatherForecast}',
      );
      // With the rain on as well, the label tells the rain's.
      await container
          .read(weatherMapPreferencesProvider.notifier)
          .setRadar(true);
      await tester.pump();
      expect(find.byIcon(Icons.water_drop_outlined), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
      // Both off: no control.
      final prefs = container.read(weatherMapPreferencesProvider.notifier);
      await prefs.setRadar(false);
      await prefs.setWind(false);
      await tester.pump();
      expect(find.byType(Slider), findsNothing);
    });

    testWidgets('the wind that did not answer says so', (tester) async {
      final (_, container) = await _pump(
        tester,
        const WeatherMapHints(),
        prefs: <String, Object>{'map.weather.wind': true},
      );
      expect(find.byType(WeatherMapChip), findsNothing);
      container
          .read(sharedWeatherMapStatusProvider.notifier)
          .set(const WeatherMapStatus(failed: <WeatherKind>{WeatherKind.wind}));
      await tester.pump();
      expect(find.text(l10n.mapWeatherWindUnavailable), findsOneWidget);
      // Switched off, no word of it.
      await container
          .read(weatherMapPreferencesProvider.notifier)
          .setWind(false);
      await tester.pump();
      expect(find.text(l10n.mapWeatherWindUnavailable), findsNothing);
    });

    /// The time control in a sheet [width] wide, its sides padded as the
    /// sheets pad them, over Berlin at [offset].
    Future<ProviderContainer> sheetRow(
      WidgetTester tester,
      double width, {
      int offset = 105,
    }) async {
      final (_, container) = await _pump(
        tester,
        const Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: WeatherTimeRow(),
          ),
        ),
        prefs: <String, Object>{'map.weather.radar': true},
      );
      await tester.binding.setSurfaceSize(Size(width, 1400));
      container.read(sharedWeatherMapStatusProvider.notifier).set(berlin);
      container.read(weatherRadarOffsetProvider.notifier).set(offset);
      await tester.pump();
      return container;
    }

    double measured(WidgetTester tester, ProviderContainer container) =>
        weatherTimeLabelWidth(
          tester.element(find.byType(Slider)),
          container.read(weatherMapSourcesProvider),
          berlin,
        );

    for (final width in <double>[360, 430]) {
      testWidgets('$width dp wide: the slider gets most of the row, and '
          'keeps its place whatever the step', (tester) async {
        final container = await sheetRow(tester, width);
        final row = width - 40;
        final labelWidth = measured(tester, container);
        final slider = tester.getRect(find.byType(Slider));
        final text = tester.getRect(find.byKey(weatherTimeLabelKey));
        // The clock and the drop lead it.
        if (weatherTimeRowStacks(row, labelWidth, icons: 2)) {
          // The label on its own line, over a slider as wide as the row.
          expect(slider.width, moreOrLessEquals(row, epsilon: 0.5));
          expect(text.bottom, lessThanOrEqualTo(slider.top + 1));
          expect(
            tester.getSize(find.byType(WeatherTimeRow)).height,
            weatherTimeRowStackedHeight,
          );
        } else {
          expect(text.right, lessThanOrEqualTo(slider.left + 1));
          expect((text.center.dy - slider.center.dy).abs(), lessThan(2));
          expect(slider.width, greaterThanOrEqualTo(row * 0.55));
          expect(slider.right, moreOrLessEquals(width - 20, epsilon: 0.5));
        }
        expect(slider.width, greaterThanOrEqualTo(row * 0.55));
        // Every step's label fits the room measured for the widest; the
        // slider does not move.
        for (final offset in weatherRadarOffsets) {
          container.read(weatherRadarOffsetProvider.notifier).set(offset);
          await tester.pump();
          expect(tester.getRect(find.byType(Slider)), slider);
          expect(
            tester.getSize(find.byKey(weatherTimeLabelKey)).width,
            lessThanOrEqualTo(labelWidth),
          );
        }
      });
    }

    testWidgets('with room, one line: the label as wide as the widest it '
        'gets, the slider all the rest', (tester) async {
      const width = 1400.0;
      final container = await sheetRow(tester, width);
      final labelWidth = measured(tester, container);
      expect(weatherTimeRowStacks(width - 40, labelWidth, icons: 2), isFalse);
      final slider = tester.getRect(find.byType(Slider));
      final text = tester.getRect(find.byKey(weatherTimeLabelKey));
      expect(text.right, lessThanOrEqualTo(slider.left + 1));
      expect((text.center.dy - slider.center.dy).abs(), lessThan(2));
      // The clock and the drop, 18 each and 4 apart, and 8 before the label.
      expect(
        slider.left,
        moreOrLessEquals(20 + 18 + 4 + 18 + 8 + labelWidth, epsilon: 1),
      );
      expect(slider.right, moreOrLessEquals(width - 20, epsilon: 0.5));
      expect(
        tester.getSize(find.byType(WeatherTimeRow)).height,
        weatherTimeRowHeight,
      );
      // Dragged from Now to the last step, the slider stays put.
      container.read(weatherRadarOffsetProvider.notifier).set(0);
      await tester.pump();
      expect(tester.getRect(find.byType(Slider)), slider);
      container
          .read(weatherRadarOffsetProvider.notifier)
          .set(weatherRadarOffsets.last);
      await tester.pump();
      expect(tester.getRect(find.byType(Slider)), slider);
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

    testWidgets('as a planned route\'s departure each step says so and '
        'tells the departure\'s time; without a route the label is the '
        'map\'s', (tester) async {
      final (_, container) = await _pump(
        tester,
        const WeatherTimeRow(leave: true),
        prefs: <String, Object>{'map.weather.radar': true},
      );
      container.read(sharedWeatherMapStatusProvider.notifier).set(berlin);
      await tester.pump();
      // The rain shows its 14:35 frame; the rider leaves at the map's now.
      expect(
        label(tester),
        '${l10n.mapWeatherLeaveNow} · ${clock(tester, at)}',
      );
      expect(
        tester.getSemantics(find.byType(Slider)).label,
        contains(l10n.mapWeatherDepartureTime),
      );
      container.read(weatherRadarOffsetProvider.notifier).set(45);
      await tester.pump();
      expect(
        label(tester),
        '${l10n.mapWeatherLeaveAhead(l10n.mapWeatherMinutesAhead(45))} · '
        '${clock(tester, at.add(const Duration(minutes: 45)))}',
      );

      // No route: the same moment, as the map's.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: testApp(home: const Scaffold(body: WeatherTimeRow())),
        ),
      );
      await tester.pump();
      expect(
        label(tester),
        '${l10n.mapWeatherMinutesAhead(45)} · '
        '${clock(tester, DateTime.utc(2026, 10, 10, 15, 20))} · '
        '${l10n.mapWeatherNowcast}',
      );
    });

    testWidgets('shown for a route\'s weather with the rain and the wind off: '
        'the departure and its time', (tester) async {
      final (_, container) = await _pump(
        tester,
        const WeatherTimeRow(leave: true, shown: true),
      );
      container.read(sharedWeatherMapStatusProvider.notifier).set(berlin);
      await tester.pump();
      expect(find.byType(Slider), findsOneWidget);
      expect(find.byIcon(Icons.schedule), findsOneWidget);
      expect(
        label(tester),
        '${l10n.mapWeatherLeaveNow} · ${clock(tester, at)}',
      );
      container.read(weatherRadarOffsetProvider.notifier).set(60);
      await tester.pump();
      expect(
        label(tester),
        '${l10n.mapWeatherLeaveAhead(l10n.mapWeatherHoursAhead(1))} · '
        '${clock(tester, at.add(const Duration(hours: 1)))}',
      );
    });

    group('loading', () {
      Finder spinner() => find.byKey(weatherTimeLoadingKey);

      testWidgets('while the step\'s weather is fetched: a spinner in the '
          'clock\'s place after a moment, said to a screen reader, gone when '
          'it is in; the drop stays and nothing moves', (tester) async {
        final handle = tester.ensureSemantics();
        final (_, container) = await _pump(
          tester,
          const WeatherTimeRow(),
          prefs: <String, Object>{'map.weather.radar': true},
        );
        final status = container.read(sharedWeatherMapStatusProvider.notifier)
          ..set(berlin);
        await tester.pump();
        final row = tester.getRect(find.byType(WeatherTimeRow));
        final labelRect = tester.getRect(find.byKey(weatherTimeLabelKey));
        final sliderRect = tester.getRect(find.byType(Slider));
        final clockRect = tester.getRect(find.byIcon(Icons.schedule));
        final dropRect = tester.getRect(find.byIcon(Icons.water_drop_outlined));
        status.set(
          WeatherMapStatus(centre: berlin.centre, at: at, loading: true),
        );
        await tester.pump();
        await tester.pump(
          weatherLoadingDelay - const Duration(milliseconds: 1),
        );
        expect(spinner(), findsNothing);
        await tester.pump(const Duration(milliseconds: 1));
        expect(spinner(), findsOneWidget);
        expect(find.byIcon(Icons.schedule), findsNothing);
        expect(find.bySemanticsLabel(l10n.mapWeatherLoading), findsOneWidget);
        // In the clock's place, the drop where it was, the row as it was.
        expect(
          tester.getRect(spinner()).center,
          offsetMoreOrLessEquals(clockRect.center),
        );
        expect(
          tester.getRect(find.byIcon(Icons.water_drop_outlined)),
          dropRect,
        );
        expect(tester.getRect(find.byType(WeatherTimeRow)), row);
        expect(tester.getRect(find.byKey(weatherTimeLabelKey)), labelRect);
        expect(tester.getRect(find.byType(Slider)), sliderRect);
        status.set(berlin);
        await tester.pump();
        expect(spinner(), findsNothing);
        expect(find.byIcon(Icons.schedule), findsOneWidget);
        expect(find.byIcon(Icons.water_drop_outlined), findsOneWidget);
        expect(tester.getRect(find.byType(WeatherTimeRow)), row);
        handle.dispose();
      });

      testWidgets('a quick answer shows none', (tester) async {
        final (_, container) = await _pump(
          tester,
          const WeatherTimeRow(),
          prefs: <String, Object>{'map.weather.radar': true},
        );
        final status = container.read(sharedWeatherMapStatusProvider.notifier)
          ..set(WeatherMapStatus(centre: berlin.centre, at: at, loading: true));
        await tester.pump(const Duration(milliseconds: 100));
        status.set(berlin);
        await tester.pump(weatherLoadingDelay * 2);
        expect(spinner(), findsNothing);
      });

      testWidgets('with the rain and the wind off, only the route\'s '
          'forecast counts', (tester) async {
        final (_, container) = await _pump(
          tester,
          const WeatherTimeRow(leave: true, shown: true),
        );
        // The clouds over the map have nothing to do with the departure.
        container
            .read(sharedWeatherMapStatusProvider.notifier)
            .set(
              WeatherMapStatus(centre: berlin.centre, at: at, loading: true),
            );
        await tester.pump(weatherLoadingDelay * 2);
        expect(spinner(), findsNothing);
        final row = tester.getRect(find.byType(WeatherTimeRow));
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: testApp(
              home: const Scaffold(
                body: WeatherTimeRow(
                  leave: true,
                  shown: true,
                  forecastLoading: true,
                ),
              ),
            ),
          ),
        );
        await tester.pump(weatherLoadingDelay);
        expect(spinner(), findsOneWidget);
        expect(find.byIcon(Icons.schedule), findsNothing);
        expect(tester.getRect(find.byType(WeatherTimeRow)), row);
      });
    });

    testWidgets('where the model stands in for the satellite, "Now" says it '
        'is a forecast', (tester) async {
      final (_, container) = await _pump(
        tester,
        const WeatherTimeRow(),
        prefs: <String, Object>{'map.weather.radar': true},
      );
      const paris = LatLng(48.85, 2.35);
      final status = container.read(sharedWeatherMapStatusProvider.notifier)
        ..set(WeatherMapStatus(centre: paris, at: at));
      await tester.pump();
      expect(
        label(tester),
        '${l10n.mapWeatherNow} · '
        '${clock(tester, DateTime.utc(2026, 10, 10, 14, 10))}',
      );
      status.set(
        WeatherMapStatus(
          centre: paris,
          at: at,
          missing: const <String>{'rain_hsaf'},
        ),
      );
      await tester.pump();
      expect(
        label(tester),
        '${l10n.mapWeatherNow} · '
        '${clock(tester, DateTime.utc(2026, 10, 10, 14))} · '
        '${l10n.mapWeatherForecast}',
      );
    });

    testWidgets('dragged, the map is told the step under the finger at once, '
        'and the label says the step it shows', (tester) async {
      final (_, container) = await _pump(
        tester,
        const WeatherTimeRow(),
        prefs: <String, Object>{'map.weather.radar': true},
      );
      final status = container.read(sharedWeatherMapStatusProvider.notifier)
        ..set(berlin);
      await tester.pump();
      final slider = tester.getRect(find.byType(Slider));
      final step = (slider.width - 2 * 14) / (weatherRadarOffsets.length - 1);
      final gesture = await tester.startGesture(
        Offset(slider.left + 14, slider.center.dy),
      );
      await gesture.moveBy(Offset(step * 3, 0));
      await tester.pump();
      // The map is asked for +45 min before the finger lets go.
      expect(container.read(weatherRadarPreviewProvider), 45);
      expect(container.read(weatherRadarOffsetProvider), 0);
      // It has only +15 min loaded so far: the label says so.
      status.set(
        WeatherMapStatus(centre: berlin.centre, at: berlin.at, shownOffset: 15),
      );
      await tester.pump();
      expect(
        label(tester),
        '${l10n.mapWeatherMinutesAhead(15)} · '
        '${clock(tester, DateTime.utc(2026, 10, 10, 14, 50))} · '
        '${l10n.mapWeatherNowcast}',
      );
      // Then +45 is in.
      status.set(
        WeatherMapStatus(centre: berlin.centre, at: berlin.at, shownOffset: 45),
      );
      await tester.pump();
      expect(label(tester), startsWith(l10n.mapWeatherMinutesAhead(45)));
      await gesture.up();
      await tester.pump();
      expect(container.read(weatherRadarOffsetProvider), 45);
      expect(container.read(weatherRadarPreviewProvider), isNull);
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

    testWidgets('the clouds\' time is in the Layers sheet, not over the '
        'map, and only while they are on', (tester) async {
      final (_, container) = await _pump(
        tester,
        const Column(
          children: [
            WeatherMapHints(),
            Expanded(child: LayersSheet()),
          ],
        ),
        prefs: <String, Object>{'map.weather.clouds': true},
      );
      expect(find.byKey(cloudsImageTimeKey), findsNothing);
      final frame = DateTime.utc(2026, 10, 10, 14);
      container
          .read(sharedWeatherMapStatusProvider.notifier)
          .set(WeatherMapStatus(cloudsFrame: frame));
      await tester.pump();
      final caption = l10n.mapWeatherCloudsAt(
        weatherClockTime(tester.element(find.byType(LayersSheet)), frame),
      );
      // In the Clouds row, under its subtitle; no chip over the map.
      expect(find.byType(WeatherMapChip), findsNothing);
      expect(
        find.descendant(
          of: _switch(l10n.mapLayersClouds),
          matching: find.text(caption),
        ),
        findsOneWidget,
      );
      expect(find.text(l10n.mapLayersCloudsSubtitle), findsOneWidget);
      // Switched off: the time goes.
      await container
          .read(weatherMapPreferencesProvider.notifier)
          .setClouds(false);
      await tester.pump();
      expect(find.text(caption), findsNothing);
      expect(find.text(l10n.mapLayersCloudsSubtitle), findsOneWidget);
    });

    testWidgets('the rain\'s moment is in the Layers sheet, not over the map', (
      tester,
    ) async {
      final (_, container) = await _pump(
        tester,
        const Column(
          children: [
            WeatherMapHints(),
            Expanded(child: LayersSheet()),
          ],
        ),
        prefs: <String, Object>{'map.weather.radar': true},
      );
      container.read(sharedWeatherMapStatusProvider.notifier).set(berlin);
      await tester.pump();
      final context = tester.element(find.byType(LayersSheet));
      expect(find.byType(WeatherMapChip), findsNothing);
      expect(
        find.descendant(
          of: _switch(l10n.mapLayersRainRadar),
          matching: find.text(
            '${l10n.mapWeatherNow} · '
            '${weatherClockTime(context, DateTime.utc(2026, 10, 10, 14, 35))}',
          ),
        ),
        findsOneWidget,
      );
      container.read(weatherRadarOffsetProvider.notifier).set(180);
      await tester.pump();
      expect(
        find.text(
          '${l10n.mapWeatherHoursAhead(3)} · '
          '${weatherClockTime(context, DateTime.utc(2026, 10, 10, 17))} · '
          '${l10n.mapWeatherForecast}',
        ),
        findsOneWidget,
      );
      // The rain off: no moment.
      await container
          .read(weatherMapPreferencesProvider.notifier)
          .setRadar(false);
      await tester.pump();
      expect(find.byKey(rainImageTimeKey), findsNothing);
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
