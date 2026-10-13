import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/features/integrations/common/data/relay_client_provider.dart';
import 'package:velorki/features/map/data/weather_fetcher.dart';
import 'package:velorki/features/map/data/weather_map_preferences.dart';
import 'package:velorki/features/map/domain/weather_map.dart';
import 'package:velorki/features/subscription/application/plus_access.dart';
import 'package:velorki_api/velorki_api.dart';
import 'package:velorki_geo/velorki_geo.dart';

const String _relayBase = 'https://api.velorki.test';
const String _rider = 'rider-42';

RelayClient _relay() {
  final relay = RelayClient(_relayBase, appUserId: _rider);
  addTearDown(relay.close);
  return relay;
}

const LatLng _rome = LatLng(41.9, 12.5);
const LatLng _palermo = LatLng(38.12, 13.36);
const LatLng _cagliari = LatLng(39.22, 9.12);
const LatLng _paris = LatLng(48.85, 2.35);
const LatLng _munich = LatLng(48.14, 11.58);

BoundingBox _around(LatLng p) => BoundingBox(
  south: p.lat - 0.2,
  west: p.lon - 0.3,
  north: p.lat + 0.2,
  east: p.lon + 0.3,
);

/// The rain radars a rider gets: with Plus, the relay's besides the rest,
/// composed as the sources in force are.
List<WeatherMapSource> _sources({required bool plus}) =>
    (plus
            ? withDpcRadar(
                withOperaRadar(defaultWeatherMapSources, _relayBase),
                _relayBase,
              )
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

  group('the DPC source', () {
    test('comes with the national radars, before OPERA and the satellite, '
        'served by the relay', () {
      final ids = withDpcRadar(
        withOperaRadar(defaultWeatherMapSources, '$_relayBase/'),
        '$_relayBase/',
      ).map((s) => s.id).toList();
      expect(ids.indexOf(dpcRadarId), ids.indexOf('radar_noaa') + 1);
      expect(ids.indexOf(dpcRadarId) + 1, ids.indexOf(operaRadarId));
      expect(ids.indexOf(dpcRadarId), lessThan(ids.indexOf('rain_hsaf')));
      expect(ids.where((id) => id == dpcRadarId), hasLength(1));
      // Without OPERA, still before the satellite.
      final alone = withDpcRadar(
        defaultWeatherMapSources,
        _relayBase,
      ).map((s) => s.id).toList();
      expect(alone.indexOf(dpcRadarId) + 1, alone.indexOf('rain_hsaf'));

      final dpc = dpcRadar('$_relayBase/');
      expect(dpc.role, RainRole.radar);
      expect(dpc.palette, RainPalette.dwd);
      expect(dpc.servesTiles, isFalse);
      expect(dpc.nativeMetresPerPixel, 1000);
      expect(dpc.timesUrl, '$_relayBase/weather/radar/dpc/frames');
      final url = dpc.softImageUrl(dpc.frameAt(now)!, _around(_rome))!;
      expect(
        url,
        startsWith(
          '$_relayBase/weather/radar/dpc/image?time=2026-10-12T21:00:00.000Z'
          '&bbox=',
        ),
      );
      expect(
        dpc.attribution,
        'Radar: Radar-DPC, Dipartimento della Protezione Civile '
        '(CC BY-SA 4.0)',
      );
    });

    test('reaches the mainland and the islands, not France or Bavaria', () {
      final dpc = dpcRadar(_relayBase);
      for (final place in [_rome, _palermo, _cagliari]) {
        expect(dpc.reaches(place), isTrue, reason: '$place');
        expect(ringContains(dpc.extent!, place), isTrue, reason: '$place');
      }
      for (final place in [_paris, _munich]) {
        expect(dpc.reaches(place), isFalse, reason: '$place');
      }
    });

    test('with Plus, Italy is the DPC\'s radar, OPERA and the satellite '
        'only around it', () {
      for (final place in [_rome, _palermo, _cagliari]) {
        final parts = rainPartsAt(
          _sources(plus: true),
          now,
          0,
          view: _around(place),
        );
        expect(parts.first.source.id, dpcRadarId, reason: '$place');
        final opera = parts.firstWhere((p) => p.source.id == operaRadarId);
        expect(opera.maskedBy, contains(dpcRadarId));
        expect(opera.cutBy.map((s) => s.id), contains(dpcRadarId));
        expect(
          rainAtPoint(_sources(plus: true), place, now, 0)?.role,
          RainRole.radar,
        );
      }
    });

    test('France stays OPERA\'s, and without Plus Italy is the '
        'satellite', () {
      final paris = rainPartsAt(
        _sources(plus: true),
        now,
        0,
        view: _around(_paris),
      );
      expect(paris.map((p) => p.source.id), isNot(contains(dpcRadarId)));
      expect(paris.map((p) => p.source.id), contains(operaRadarId));
      expect(
        rainAtPoint(_sources(plus: false), _rome, now, 0)?.role,
        RainRole.satellite,
      );
    });

    test('the forecast steps keep the models', () {
      for (final offset in [15, 60, 180]) {
        final parts = rainPartsAt(
          _sources(plus: true),
          now,
          offset,
          view: _around(_rome),
        );
        expect(parts.map((p) => p.source.id), isNot(contains(dpcRadarId)));
        expect(parts.map((p) => p.source.role), contains(RainRole.model));
      }
    });

    test('the sources in force carry it only with Plus granted and a '
        'relay', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final relay = _relay();
      List<String> ids({
        required RelayClient? relay,
        required PlusAccess access,
      }) {
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
            .map((s) => s.id)
            .toList();
      }

      final granted = ids(relay: relay, access: PlusAccess.granted);
      expect(granted.indexOf(dpcRadarId) + 1, granted.indexOf(operaRadarId));
      for (final (relay, access) in [
        (relay, PlusAccess.missing),
        (relay, PlusAccess.unknown),
        (null, PlusAccess.granted),
      ]) {
        expect(
          ids(relay: relay, access: access),
          isNot(contains(dpcRadarId)),
          reason: '$access',
        );
      }

      // The mirror can switch it off by its id, OPERA staying on.
      await prefs.setString(
        'map.weather.override',
        '[{"id": "$dpcRadarId", "enabled": false}]',
      );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          relayClientProvider.overrideWithValue(relay),
          plusAccessProvider.overrideWith((ref, feature) => PlusAccess.granted),
        ],
      );
      addTearDown(container.dispose);
      final sources = container.read(weatherMapSourcesProvider);
      expect(sources.firstWhere((s) => s.id == dpcRadarId).enabled, isFalse);
      expect(sources.firstWhere((s) => s.id == operaRadarId).enabled, isTrue);
    });
  });

  group('the relay\'s credentials', () {
    test('go to the relay\'s DPC radar as to its OPERA radar, nowhere '
        'else', () {
      final relay = _relay();
      expect(
        relayAuthFor(
          relay,
          '$_relayBase/weather/radar/dpc/image?time=x',
        )['Authorization'],
        'Bearer $_rider',
      );
      expect(
        relayAuthFor(relay, '$_relayBase/weather/radar/dpc/frames'),
        isNotEmpty,
      );
      for (final url in [
        '$_relayBase/weather/radar/dpcs/image',
        '$_relayBase/weather/radar/dpc',
        '$_relayBase/weather/radar/image',
        'https://radar-api.protezionecivile.it/downloadProduct',
        'https://s3-prod-dpc-radar.s3.eu-south-1.amazonaws.com/SRI/x.tif',
        'http://api.velorki.test/weather/radar/dpc/image',
        'https://api.velorki.test:8443/weather/radar/dpc/image',
        'https://user@api.velorki.test/weather/radar/dpc/image',
      ]) {
        expect(relayAuthFor(relay, url), isEmpty, reason: url);
      }
    });

    test('ride on the DPC requests the fetcher makes', () async {
      final relay = _relay();
      final adapter = _Adapter();
      final dir = Directory.systemTemp.createTempSync('dpc');
      addTearDown(() => dir.deleteSync(recursive: true));
      final fetcher = HttpWeatherFetcher(
        dio: Dio()..httpClientAdapter = adapter,
        cacheDir: () async => dir,
        processRadar: (png, job) async => png,
        headersFor: (url) => relayAuthFor(relay, url),
      );
      final dpc = dpcRadar(_relayBase);
      final box = _around(_rome);
      await fetcher.radarImage(dpc, box, dpc.frameAt(now)!, now);
      await fetcher.radarImage(hsafRain, box, hsafRain.frameAt(now)!, now);
      adapter
        ..contentType = 'application/json'
        ..body = Uint8List.fromList(
          '{"frames": [], "newest": "2026-10-12T21:00:00.000Z"}'.codeUnits,
        );
      expect(await fetcher.newestFrame(dpc), DateTime.utc(2026, 10, 12, 21));

      expect(adapter.requests, hasLength(3));
      for (final r in adapter.requests) {
        final auth = r.headers['Authorization'] as String?;
        if (r.uri.host == 'api.velorki.test') {
          expect(r.uri.path, startsWith('/weather/radar/dpc/'));
          expect(auth, 'Bearer $_rider');
        } else {
          expect(auth, isNull, reason: '${r.uri}');
        }
      }
    });
  });
}
