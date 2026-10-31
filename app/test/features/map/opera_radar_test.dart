import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/features/integrations/common/data/relay_client_provider.dart';
import 'package:velorki/features/map/data/weather_fetcher.dart';
import 'package:velorki/features/map/data/weather_map_preferences.dart';
import 'package:velorki/features/map/domain/weather_map.dart';
import 'package:velorki/features/map/presentation/layers_sheet.dart';
import 'package:velorki/features/map/presentation/rain_radar_dialog.dart';
import 'package:velorki/features/subscription/application/plus_access.dart';
import 'package:velorki_api/velorki_api.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../support/app.dart';

const String _relayBase = 'https://api.velorki.test';
const String _rider = 'rider-42';

/// [text] inside the dialog, not under the Layers sheet's switch of the
/// same name.
Finder _inDialog(String text) =>
    find.descendant(of: find.byType(Dialog), matching: find.text(text));

RelayClient _relay() {
  final relay = RelayClient(_relayBase, appUserId: _rider);
  addTearDown(relay.close);
  return relay;
}

const LatLng _paris = LatLng(48.85, 2.35);
const LatLng _madrid = LatLng(40.42, -3.70);
const LatLng _berlin = LatLng(52.52, 13.40);

BoundingBox _around(LatLng p) => BoundingBox(
  south: p.lat - 0.2,
  west: p.lon - 0.3,
  north: p.lat + 0.2,
  east: p.lon + 0.3,
);

/// The sources a rider gets: with Plus, the OPERA radar besides the rest.
List<WeatherMapSource> _sources({required bool plus}) =>
    (plus
            ? withOperaRadar(defaultWeatherMapSources, _relayBase)
            : defaultWeatherMapSources)
        .where((s) => s.enabled && s.kind == WeatherKind.radar)
        .toList();

/// Records each request and its headers; answers [body] as [contentType].
class _Adapter implements HttpClientAdapter {
  String contentType = 'image/png';
  Uint8List body = Uint8List.fromList(<int>[1, 2, 3]);
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromBytes(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [contentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  final now = DateTime.utc(2026, 10, 12, 21, 7, 30);

  group('the OPERA source', () {
    test('comes after the free radars and before the satellite, served by '
        'the relay', () {
      final ids = withOperaRadar(
        defaultWeatherMapSources,
        '$_relayBase/',
      ).map((s) => s.id).toList();
      expect(ids.indexOf(operaRadarId), ids.indexOf('radar_noaa') + 1);
      expect(ids.indexOf(operaRadarId), lessThan(ids.indexOf('rain_hsaf')));
      expect(ids.indexOf(operaRadarId), greaterThan(ids.indexOf('radar_fmi')));
      expect(ids.where((id) => id == operaRadarId), hasLength(1));

      final opera = operaRadar('$_relayBase/');
      expect(opera.role, RainRole.radar);
      expect(opera.palette, RainPalette.dwd);
      expect(opera.servesTiles, isFalse);
      expect(dwdRadar.servesTiles, isTrue);
      expect(opera.timesUrl, '$_relayBase/weather/radar/opera/frames');
      final url = opera.softImageUrl(opera.frameAt(now)!, _around(_paris))!;
      expect(
        url,
        startsWith(
          '$_relayBase/weather/radar/opera/image?time=2026-10-12T21:00:00.000Z'
          '&bbox=',
        ),
      );
      expect(opera.attribution, 'Radar: EUMETNET OPERA (CC BY 4.0)');
    });

    test('a frame list names its newest frame', () {
      expect(
        parseFramesNewest(
          '{"frames": ["2026-10-12T21:00:00.000Z", '
          '"2026-10-12T21:05:00.000Z"], "newest": "2026-10-12T21:05:00.000Z", '
          '"stepMinutes": 5}',
        ),
        DateTime.utc(2026, 10, 12, 21, 5),
      );
      expect(parseFramesNewest('{"frames": [], "newest": null}'), isNull);
      expect(parseFramesNewest('<xml/>'), isNull);
      // Never past the newest frame the relay listed.
      final opera = operaRadar(_relayBase);
      expect(
        opera.frameAt(now, newest: DateTime.utc(2026, 10, 12, 20, 55))!.time,
        DateTime.utc(2026, 10, 12, 20, 55),
      );
    });

    test('with Plus, France and Spain are OPERA radar, not the satellite', () {
      for (final place in [_paris, _madrid]) {
        final parts = rainPartsAt(
          _sources(plus: true),
          now,
          0,
          view: _around(place),
        );
        final ids = parts.map((p) => p.source.id).toList();
        expect(ids, contains(operaRadarId));
        // The satellite only around it, cut where OPERA's frame measures.
        final satellite = parts.firstWhere((p) => p.source.id == 'rain_hsaf');
        expect(satellite.cutBy.map((s) => s.id), contains(operaRadarId));
        expect(
          rainAtPoint(_sources(plus: true), place, now, 0)?.role,
          RainRole.radar,
        );
      }
    });

    test('without Plus, France is the satellite', () {
      final parts = rainPartsAt(
        _sources(plus: false),
        now,
        0,
        view: _around(_paris),
      );
      expect(parts.map((p) => p.source.id), isNot(contains(operaRadarId)));
      expect(
        rainAtPoint(_sources(plus: false), _madrid, now, 0)?.role,
        RainRole.satellite,
      );
    });

    test('Germany keeps the DWD radar first, OPERA only around it', () {
      final parts = rainPartsAt(
        _sources(plus: true),
        now,
        0,
        view: _around(_berlin),
      );
      expect(parts.first.source.id, 'radar_dwd');
      final opera = parts.firstWhere((p) => p.source.id == operaRadarId);
      expect(opera.maskedBy, contains('radar_dwd'));
      expect(opera.cutBy.map((s) => s.id), contains('radar_dwd'));
    });

    test('the forecast steps keep the models', () {
      for (final offset in [15, 60, 180]) {
        final parts = rainPartsAt(
          _sources(plus: true),
          now,
          offset,
          view: _around(_paris),
        );
        expect(parts.map((p) => p.source.id), isNot(contains(operaRadarId)));
        expect(parts.map((p) => p.source.role), contains(RainRole.model));
      }
    });

    test('the sources in force carry OPERA only with Plus granted and a '
        'relay', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final relay = _relay();
      bool opera({required RelayClient? relay, required PlusAccess access}) {
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            relayClientProvider.overrideWithValue(relay),
            plusAccessProvider.overrideWith((ref, feature) => access),
          ],
        );
        addTearDown(container.dispose);
        return container
            .read(weatherMapSourcesProvider)
            .any((s) => s.id == operaRadarId);
      }

      expect(opera(relay: relay, access: PlusAccess.granted), isTrue);
      expect(opera(relay: relay, access: PlusAccess.missing), isFalse);
      expect(opera(relay: relay, access: PlusAccess.unknown), isFalse);
      expect(opera(relay: null, access: PlusAccess.granted), isFalse);

      // The mirror can switch it off by its id.
      await prefs.setString(
        'map.weather.override',
        '[{"id": "$operaRadarId", "enabled": false}]',
      );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          relayClientProvider.overrideWithValue(relay),
          plusAccessProvider.overrideWith((ref, feature) => PlusAccess.granted),
        ],
      );
      addTearDown(container.dispose);
      expect(
        container
            .read(weatherMapSourcesProvider)
            .firstWhere((s) => s.id == operaRadarId)
            .enabled,
        isFalse,
      );
    });
  });

  group('the relay\'s credentials', () {
    test('go to the relay\'s OPERA radar and nowhere else', () {
      final relay = _relay();
      final headers = relayAuthFor(
        relay,
        '$_relayBase/weather/radar/opera/image?time=x',
      );
      expect(headers['Authorization'], 'Bearer $_rider');
      expect(
        relayAuthFor(relay, '$_relayBase/weather/radar/opera/frames'),
        isNotEmpty,
      );
      for (final url in [
        'https://maps.dwd.de/geoserver/dwd/wms?layers=dwd:Niederschlagsradar',
        'https://view.eumetsat.int/geoserver/ows?layers=mtg_fd:h40b',
        '$_relayBase/share',
        '$_relayBase/weather/radar/operas/image',
        'http://api.velorki.test/weather/radar/opera/image',
        'https://api.velorki.test.evil.example/weather/radar/opera/image',
        'https://api.velorki.test:8443/weather/radar/opera/image',
        'https://user@api.velorki.test/weather/radar/opera/image',
        'not a url at all',
      ]) {
        expect(relayAuthFor(relay, url), isEmpty, reason: url);
      }
      expect(relayAuthFor(null, '$_relayBase/weather/radar/opera/x'), isEmpty);
    });

    test('ride on the OPERA requests the fetcher makes, and only on '
        'them', () async {
      final relay = _relay();
      final adapter = _Adapter();
      final dir = Directory.systemTemp.createTempSync('opera');
      addTearDown(() => dir.deleteSync(recursive: true));
      final fetcher = HttpWeatherFetcher(
        dio: Dio()..httpClientAdapter = adapter,
        cacheDir: () async => dir,
        processRadar: (png, job) async => png,
        headersFor: (url) => relayAuthFor(relay, url),
      );
      final opera = operaRadar(_relayBase);
      final box = _around(_paris);
      await fetcher.radarImage(opera, box, opera.frameAt(now)!, now);
      await fetcher.radarImage(dwdRadar, box, dwdRadar.frameAt(now)!, now);
      await fetcher.radarImage(hsafRain, box, hsafRain.frameAt(now)!, now);
      adapter
        ..contentType = 'application/json'
        ..body = Uint8List.fromList(
          '{"frames": [], "newest": "2026-10-12T21:05:00.000Z"}'.codeUnits,
        );
      expect(
        await fetcher.newestFrame(opera),
        DateTime.utc(2026, 10, 12, 21, 5),
      );

      expect(adapter.requests, hasLength(4));
      String? auth(RequestOptions r) => r.headers['Authorization'] as String?;
      final toRelay = adapter.requests.where(
        (r) => r.uri.host == 'api.velorki.test',
      );
      expect(toRelay, hasLength(2));
      for (final r in toRelay) {
        expect(auth(r), 'Bearer $_rider');
      }
      for (final r in adapter.requests.where(
        (r) => r.uri.host != 'api.velorki.test',
      )) {
        expect(auth(r), isNull, reason: '${r.uri}');
        expect(
          r.headers.keys.map((k) => k.toLowerCase()),
          isNot(contains('authorization')),
        );
      }
    });
  });

  group('the Layers sheet\'s rain radar switch', () {
    Future<ProviderContainer> pump(
      WidgetTester tester, {
      required PlusAccess access,
      bool relay = true,
      Size size = const Size(411, 1400),
    }) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues(mapLayersOff);
      final prefs = await SharedPreferences.getInstance();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: LayersSheet()),
          ),
          GoRoute(
            path: paywallRoute,
            builder: (_, _) => const Scaffold(body: Text('paywall')),
          ),
        ],
      );
      addTearDown(router.dispose);
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          relayClientProvider.overrideWithValue(relay ? _relay() : null),
          plusAccessProvider.overrideWith((ref, feature) => access),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: testRouterApp(routerConfig: router),
        ),
      );
      await tester.pump();
      return container;
    }

    Finder switchOf(String title) => find.widgetWithText(SwitchListTile, title);
    final rain = switchOf(l10n.mapLayersRainRadar);
    bool radarOn(ProviderContainer c) =>
        c.read(weatherMapPreferencesProvider).radar;

    testWidgets('without Plus, every switch-on asks: the free radar comes on '
        'only when chosen', (tester) async {
      final container = await pump(tester, access: PlusAccess.missing);

      await tester.tap(rain);
      await tester.pumpAndSettle();
      expect(_inDialog(l10n.mapRainRadarPlusTitle), findsOneWidget);
      expect(_inDialog(l10n.mapRainRadarPlusBody), findsOneWidget);
      expect(radarOn(container), isFalse);
      await tester.tap(find.text(l10n.mapRainRadarPlusUseFree));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(radarOn(container), isTrue);

      // Off asks nothing.
      await tester.tap(rain);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(radarOn(container), isFalse);

      // On again asks again; Cancel leaves it off.
      await tester.tap(rain);
      await tester.pumpAndSettle();
      expect(_inDialog(l10n.mapRainRadarPlusTitle), findsOneWidget);
      await tester.tap(find.text(l10n.commonCancel));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(radarOn(container), isFalse);

      // "See Plus" opens the Plus page, the radar still off.
      await tester.tap(rain);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.mapRainRadarPlusSeePlus));
      await tester.pumpAndSettle();
      expect(find.text('paywall'), findsOneWidget);
      expect(radarOn(container), isFalse);
    });

    testWidgets('with Plus, while the store has not answered, and without '
        'the relay, it comes on at once', (tester) async {
      for (final (access, relay) in [
        (PlusAccess.granted, true),
        (PlusAccess.unknown, true),
        (PlusAccess.missing, false),
      ]) {
        final container = await pump(tester, access: access, relay: relay);
        await tester.tap(rain);
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing, reason: '$access $relay');
        expect(radarOn(container), isTrue, reason: '$access $relay');
      }
    });

    testWidgets('the clouds and the wind ask nothing', (tester) async {
      final container = await pump(tester, access: PlusAccess.missing);
      await tester.tap(switchOf(l10n.mapLayersClouds));
      await tester.pumpAndSettle();
      await tester.tap(switchOf(l10n.mapLayersWind));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      final settings = container.read(weatherMapPreferencesProvider);
      expect(settings.clouds, isTrue);
      expect(settings.wind, isTrue);
    });
  });

  for (final size in const [Size(667, 375), Size(402, 874)]) {
    testWidgets('the dialog fits at ${size.width.round()} × '
        '${size.height.round()}', (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      RainRadarAnswer? answer;
      await tester.pumpWidget(
        testApp(
          home: Builder(
            builder: (context) => Center(
              child: IconButton(
                icon: const Icon(Icons.water_drop_outlined),
                onPressed: () async =>
                    answer = await showRainRadarDialog(context),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final dialog = tester.getRect(find.byType(Dialog));
      final buttons = find.descendant(
        of: find.byType(Dialog),
        matching: find.byWidgetPredicate(
          (w) => w is TextButton || w is FilledButton,
        ),
      );
      expect(buttons, findsNWidgets(3));
      for (final button in tester.widgetList<Widget>(buttons)) {
        final rect = tester.getRect(find.byWidget(button));
        expect(rect.bottom, lessThanOrEqualTo(dialog.bottom + 0.5));
        expect(rect.top, greaterThanOrEqualTo(dialog.top - 0.5));
      }
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(answer, RainRadarAnswer.useFree);
    });
  }
}
