import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/map/domain/weather_map.dart';
import 'package:velorki/features/map/presentation/weather_map_overlay.dart';
import 'package:velorki/l10n/generated/app_localizations.dart';
import 'package:velorki_geo/velorki_geo.dart';

BoundingBox view(double lon, double lat, [double half = 0.2]) => BoundingBox(
  south: lat - half,
  west: lon - half,
  north: lat + half,
  east: lon + half,
);

DateTime utc(int h, int m, [int s = 0]) => DateTime.utc(2026, 10, 10, h, m, s);

/// The `time=` value of [url].
String? timeOf(String url) => RegExp(r'[?&]time=([^&]+)').firstMatch(url)?[1];

void main() {
  group('time', () {
    test(
      'the DWD radar is on a five-minute grid at least five minutes old',
      () {
        expect(dwdRadar.frameAt(utc(14, 39, 59))!.time, utc(14, 30));
        expect(dwdRadar.frameAt(utc(14, 40))!.time, utc(14, 35));
        expect(
          dwdRadar.frameAt(utc(14, 40), offsetMinutes: -45)!.time,
          utc(13, 50),
        );
        expect(
          dwdRadar.frameAt(utc(14, 40), offsetMinutes: 120)!.time,
          utc(16, 35),
        );
        expect(dwdRadar.frameAt(utc(14, 40), offsetMinutes: 135), isNull);
      },
    );

    test('the DWD URL carries the frame in its own format', () {
      final url = dwdRadar.tileUrl(dwdRadar.frameAt(utc(14, 40))!);
      expect(timeOf(url), '2026-10-10T14:35:00.000Z');
      expect(url, contains('{bbox-epsg-3857}'));
      expect(url, isNot(contains('{time}')));
    });

    test('the NOAA radar is epoch milliseconds, the past only', () {
      final frame = noaaRadar.frameAt(utc(14, 40), offsetMinutes: -15)!;
      final url = noaaRadar.tileUrl(frame);
      expect(url, contains('time=${utc(14, 20).millisecondsSinceEpoch}&'));
      expect(noaaRadar.frameAt(utc(14, 40), offsetMinutes: 15), isNull);
      expect(noaaRadar.frameAt(utc(14, 40), offsetMinutes: -120), isNotNull);
    });

    test('EUMETSAT: the latest full hour at least twenty minutes old', () {
      expect(eumetsatClouds.frameAt(utc(14, 19, 59))!.time, utc(13, 0));
      expect(eumetsatClouds.frameAt(utc(14, 20))!.time, utc(14, 0));
      expect(eumetsatClouds.frameAt(utc(14, 59))!.time, utc(14, 0));
      expect(
        eumetsatClouds.frameAt(utc(0, 5))!.time,
        DateTime.utc(2026, 10, 9, 23),
      );
    });

    test('an EUMETSAT request never lacks a full-hour time', () {
      for (var minute = 0; minute < 24 * 60; minute += 7) {
        final now = utc(0, 0).add(Duration(minutes: minute));
        final frame = eumetsatClouds.frameAt(now)!;
        final url = eumetsatClouds.regionImageUrl(frame, 0);
        final time = timeOf(url);
        expect(time, isNotNull, reason: url);
        expect(time, matches(RegExp(r'^\d{4}-\d\d-\d\dT\d\d:00:00\.000Z$')));
        final shown = DateTime.parse(time!);
        expect(now.difference(shown).inMinutes, greaterThanOrEqualTo(20));
        expect(now.difference(shown).inMinutes, lessThan(80));
      }
    });

    test('an override cannot take the full hours away from EUMETSAT', () {
      final sources = applyWeatherOverride(defaultWeatherMapSources, [
        {'id': 'clouds_eumetsat', 'delayMinutes': 0, 'stepMinutes': 10},
      ]);
      final eumetsat = sources.firstWhere((s) => s.id == 'clouds_eumetsat');
      expect(eumetsat.enabled, isTrue);
      expect(eumetsat.frameAt(utc(14, 10))!.time, utc(13, 0));
      final timeless = applyWeatherOverride(defaultWeatherMapSources, [
        {
          'id': 'clouds_eumetsat',
          'url':
              'https://view.eumetsat.int/geoserver/ows?bbox={bbox-epsg-3857}',
        },
      ]);
      expect(
        timeless.firstWhere((s) => s.id == 'clouds_eumetsat').enabled,
        isFalse,
      );
    });

    test('the attribution names the image year', () {
      final frame = eumetsatClouds.frameAt(DateTime.utc(2027, 1, 1, 0, 10))!;
      expect(
        eumetsatClouds.attributionFor(frame, DateTime.utc(2027, 1, 1, 0, 10)),
        'Clouds: Contains modified EUMETSAT Meteosat data 2026',
      );
    });

    test('GOES names no moment: the latest image, now only', () {
      expect(goesEastClouds.frameAt(utc(14, 0)), const WeatherFrame(null));
      expect(goesEastClouds.frameAt(utc(14, 0), offsetMinutes: -15), isNull);
      final url = goesEastClouds.regionImageUrl(const WeatherFrame(null), 0);
      expect(url, contains('TIME=default'));
      expect(url, isNot(contains('{')));
    });
  });

  group('urls', () {
    test('a probe fills in one tile', () {
      final frame = dwdRadar.frameAt(utc(14, 40))!;
      final url = dwdRadar.probeUrl(frame, const LatLng(52.5, 13.4), 5);
      expect(url, isNot(contains('{')));
      final (x, y) = tileOf(const LatLng(52.5, 13.4), 5);
      expect((x, y), (17, 10));
      expect(url, contains('bbox=${tileBboxEpsg3857(17, 10, 5)}&'));
    });

    test('tile 0/0/0 is the whole Web Mercator world', () {
      expect(
        tileBboxEpsg3857(0, 0, 0),
        '-20037508.342789,-20037508.342789,20037508.342789,20037508.342789',
      );
    });

    test('a cloud region is one image about 3 km a pixel, at most 2048', () {
      final box = eumetsatClouds.coverage.single;
      final (w, h) = cloudImageSize(box);
      expect(h, 2048);
      final mw = mercatorX(box.east) - mercatorX(box.west);
      final mh = mercatorY(box.north) - mercatorY(box.south);
      expect(w / h, closeTo(mw / mh, 0.01));
      // A small box keeps 3 km a pixel.
      final (sw, _) = cloudImageSize(
        const BoundingBox(south: 0, west: 0, north: 1, east: 1),
      );
      expect(sw, (mercatorX(1) / 3000).round());
      expect(
        mercatorBboxString(box),
        '${mercatorX(-30).toStringAsFixed(1)},'
        '${mercatorY(25).toStringAsFixed(1)},'
        '${mercatorX(45).toStringAsFixed(1)},'
        '${mercatorY(75).toStringAsFixed(1)}',
      );
      final url = eumetsatClouds.regionImageUrl(
        eumetsatClouds.frameAt(utc(14, 30))!,
        0,
      );
      expect(url, contains('width=$w&height=$h'));
      expect(url, contains('bbox=${mercatorBboxString(box)}&'));
    });
  });

  group('coverage', () {
    test('a view over Germany meets the DWD radar, not the NOAA one', () {
      expect(dwdRadar.covers(view(13.4, 52.5)), isTrue);
      expect(noaaRadar.covers(view(13.4, 52.5)), isFalse);
      expect(noaaRadar.covers(view(-74, 40.7)), isTrue);
      expect(noaaRadar.covers(view(-157.9, 21.3)), isTrue); // Honolulu
      expect(dwdRadar.covers(view(-74, 40.7)), isFalse);
    });

    test('a view across the antimeridian meets GOES-West', () {
      const across = BoundingBox(south: 0, west: 170, north: 10, east: -170);
      expect(goesWestClouds.covers(across), isTrue);
      expect(goesEastClouds.covers(across), isFalse);
    });

    test('requests are kept inside the coverage', () {
      expect(dwdRadar.requestBounds, <double>[1.5, 45, 19, 56.5]);
      expect(goesWestClouds.requestBounds, isNull);
    });
  });

  group('override', () {
    test('missing or not a list: the defaults', () {
      expect(
        applyWeatherOverride(defaultWeatherMapSources, null),
        defaultWeatherMapSources,
      );
      expect(
        applyWeatherOverride(defaultWeatherMapSources, {'id': 'radar_dwd'}),
        defaultWeatherMapSources,
      );
      expect(decodeWeatherOverride('{not json'), isNull);
    });

    test('an entry replaces the fields it names', () {
      final sources = applyWeatherOverride(defaultWeatherMapSources, [
        {
          'id': 'radar_dwd',
          'url': 'https://example.org/wms?bbox={bbox-epsg-3857}&t={time}',
          'opacity': 0.5,
          'coverage': [
            [5, 47, 15, 55],
          ],
        },
      ]);
      final dwd = sources.firstWhere((s) => s.id == 'radar_dwd');
      expect(dwd.urlTemplate, startsWith('https://example.org/'));
      expect(dwd.opacity, 0.5);
      expect(dwd.coverage.single.west, 5);
      expect(dwd.forecastMinutes, 120);
      expect(dwd.attribution, dwdRadar.attribution);
    });

    test('enabled false switches a source off', () {
      final sources = applyWeatherOverride(defaultWeatherMapSources, [
        {'id': 'radar_noaa', 'enabled': false},
      ]);
      expect(sources.firstWhere((s) => s.id == 'radar_noaa').enabled, isFalse);
      expect(sources.firstWhere((s) => s.id == 'radar_dwd').enabled, isTrue);
    });

    test('unreadable entries are skipped, the rest applies', () {
      final sources = applyWeatherOverride(defaultWeatherMapSources, [
        'nonsense',
        {'enabled': false},
        {'id': 'radar_dwd', 'url': 'http://insecure.example/{z}/{x}/{y}'},
        {
          'id': 'radar_noaa',
          'coverage': [
            [1, 2, 3],
          ],
        },
        {'id': 'clouds_goes_east', 'enabled': false},
        {'id': 'new_without_fields', 'kind': 'radar'},
      ]);
      expect(sources.firstWhere((s) => s.id == 'radar_dwd'), dwdRadar);
      expect(sources.firstWhere((s) => s.id == 'radar_noaa'), noaaRadar);
      expect(
        sources.firstWhere((s) => s.id == 'clouds_goes_east').enabled,
        isFalse,
      );
      expect(sources.map((s) => s.id), isNot(contains('new_without_fields')));
    });

    test('a full entry with a new id adds a source', () {
      final sources = applyWeatherOverride(defaultWeatherMapSources, [
        {
          'id': 'radar_elsewhere',
          'kind': 'radar',
          'url': 'https://radar.example/{z}/{x}/{y}.png?t={timeMs}',
          'time': 'epochMs',
          'coverage': [
            [0, 0, 10, 10],
          ],
          'attribution': 'Radar: Example',
        },
      ]);
      final added = sources.firstWhere((s) => s.id == 'radar_elsewhere');
      expect(added.kind, WeatherKind.radar);
      expect(added.timeFormat, WeatherTimeFormat.epochMs);
    });

    test('stored and read back', () {
      final override = [
        {'id': 'radar_noaa', 'enabled': false},
      ];
      final stored = encodeWeatherOverride(override);
      expect(
        applyWeatherOverride(
          defaultWeatherMapSources,
          decodeWeatherOverride(stored),
        ).firstWhere((s) => s.id == 'radar_noaa').enabled,
        isFalse,
      );
      expect(encodeWeatherOverride({'not': 'a list'}), isNull);
    });
  });

  group('time control', () {
    test('steps of a quarter hour from two hours back to two ahead', () {
      expect(weatherRadarOffsets, hasLength(17));
      expect(weatherRadarOffsets.first, -120);
      expect(weatherRadarOffsets.last, 120);
      expect(weatherSliderIndexOf(0), 8);
      expect(weatherSliderIndexOf(-120), 0);
      expect(weatherSliderIndexOf(45), 11);
      expect(weatherOffsetOfSliderIndex(11), 45);
      for (final offset in weatherRadarOffsets) {
        expect(
          weatherOffsetOfSliderIndex(weatherSliderIndexOf(offset)),
          offset,
        );
      }
    });

    test('labels', () {
      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(weatherOffsetLabel(l10n, 0), 'Now');
      expect(weatherOffsetLabel(l10n, -45), '−45 min');
      expect(weatherOffsetLabel(l10n, 30), '+30 min');
    });
  });

  group('cloud detail', () {
    double mercatorWidth(BoundingBox b) =>
        mercatorX(b.east) - mercatorX(b.west);
    double mercatorHeight(BoundingBox b) =>
        mercatorY(b.north) - mercatorY(b.south);

    test('each service at its own resolution: 1 km EUMETSAT, 2 km GOES', () {
      expect(eumetsatClouds.nativeMetresPerPixel, 1000);
      expect(goesEastClouds.nativeMetresPerPixel, 2000);
      expect(goesWestClouds.nativeMetresPerPixel, 2000);
      const box = BoundingBox(south: 50, west: 10, north: 53, east: 15);
      final (w, h) = cloudDetailImageSize(eumetsatClouds, box);
      expect(w, (mercatorWidth(box) / 1000).round());
      expect(h, (mercatorHeight(box) / 1000).round());
      final (gw, _) = cloudDetailImageSize(goesEastClouds, box);
      expect(gw, (mercatorWidth(box) / 2000).round());
    });

    test('each side between 64 and 1536 pixels', () {
      const tiny = BoundingBox(south: 50, west: 10, north: 50.05, east: 10.1);
      expect(cloudDetailImageSize(eumetsatClouds, tiny), (64, 64));
      final (w, h) = cloudDetailImageSize(
        eumetsatClouds,
        eumetsatClouds.coverage.single,
      );
      expect(h, cloudDetailMaxSide);
      expect(w, lessThanOrEqualTo(cloudDetailMaxSide));
      expect(w, greaterThanOrEqualTo(cloudDetailMinSide));
    });

    test('the area: the view, a quarter around it, on the grid', () {
      final v = view(13.4, 52.5);
      final area = cloudDetailArea(v, 8)!;
      final mw = mercatorWidth(v);
      expect(
        mercatorX(area.west),
        lessThanOrEqualTo(mercatorX(v.west) - mw / 4),
      );
      expect(
        mercatorX(area.east),
        greaterThanOrEqualTo(mercatorX(v.east) + mw / 4),
      );
      final mh = mercatorHeight(v);
      expect(
        mercatorY(area.south),
        lessThanOrEqualTo(mercatorY(v.south) - mh / 4 + 0.01),
      );
      expect(
        mercatorY(area.north),
        greaterThanOrEqualTo(mercatorY(v.north) + mh / 4 - 0.01),
      );
      // On the zoom-9 tile grid.
      const origin = 20037508.342789244;
      const cell = 2 * origin / 512;
      final x = (mercatorX(area.west) + origin) / cell;
      expect(x, closeTo(x.roundToDouble(), 1e-6));
      // A small pan finds the same box, so the same cache entry.
      final panned = cloudDetailArea(view(13.401, 52.501), 8)!;
      expect(cloudDetailKey(panned), cloudDetailKey(area));
      // A big one does not.
      expect(
        cloudDetailKey(cloudDetailArea(view(14, 52.5), 8)!),
        isNot(cloudDetailKey(area)),
      );
    });

    test('across the antimeridian there is no detail', () {
      const across = BoundingBox(south: 0, west: 179, north: 1, east: -179);
      expect(cloudDetailArea(across, 8), isNull);
    });

    test('the box is clipped to the coverage', () {
      // Over the Atlantic's edge of the EUMETSAT box.
      final area = cloudDetailArea(view(-30, 50, 1), 7)!;
      expect(area.west, lessThan(-30));
      final box = eumetsatClouds.detailBox(area)!;
      expect(box.west, -30);
      expect(box.east, area.east);
      expect(
        eumetsatClouds.detailBox(cloudDetailArea(view(-80, 40), 8)!),
        isNull,
      );
      // GOES-West: the larger of its two boxes.
      final pacific = goesWestClouds.detailBox(
        const BoundingBox(south: 0, west: 160, north: 10, east: 180),
      )!;
      expect(pacific.west, 165);
    });

    test('the cache key is the box to the kilometre', () {
      const box = BoundingBox(south: 0, west: 0, north: 1, east: 1);
      expect(
        cloudDetailKey(box),
        '0_0_${(mercatorX(1) / 1000).round()}_${(mercatorY(1) / 1000).round()}',
      );
    });

    test('an EUMETSAT detail never lacks a full-hour time', () {
      final box = eumetsatClouds.detailBox(
        cloudDetailArea(view(13.4, 52.5), 8)!,
      )!;
      for (var minute = 0; minute < 24 * 60; minute += 7) {
        final now = utc(0, 0).add(Duration(minutes: minute));
        final url = eumetsatClouds.detailImageUrl(
          eumetsatClouds.frameAt(now)!,
          box,
        );
        final time = timeOf(url);
        expect(time, matches(RegExp(r'^\d{4}-\d\d-\d\dT\d\d:00:00\.000Z$')));
        final shown = DateTime.parse(time!);
        expect(now.difference(shown).inMinutes, greaterThanOrEqualTo(20));
        final (w, h) = cloudDetailImageSize(eumetsatClouds, box);
        expect(url, contains('width=$w&height=$h'));
        expect(url, contains('bbox=${mercatorBboxString(box)}&'));
      }
    });

    test('the mirror can set the resolution', () {
      final sources = applyWeatherOverride(defaultWeatherMapSources, [
        {'id': 'clouds_goes_east', 'metresPerPixel': 4000},
        {'id': 'clouds_goes_west', 'metresPerPixel': -1},
      ]);
      expect(
        sources
            .firstWhere((s) => s.id == 'clouds_goes_east')
            .nativeMetresPerPixel,
        4000,
      );
      expect(
        sources
            .firstWhere((s) => s.id == 'clouds_goes_west')
            .nativeMetresPerPixel,
        2000,
      );
    });
  });
}
