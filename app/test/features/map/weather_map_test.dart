import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/map/domain/weather_map.dart';
import 'package:velorki/features/map/presentation/weather_time_row.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../support/app.dart';

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
      // Twenty minutes behind (NOAA's newest frame is some 14 old), then
      // fifteen back.
      expect(url, contains('time=${utc(14, 5).millisecondsSinceEpoch}&'));
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
    test('now, then quarter hours to two hours, then hours to a day', () {
      expect(weatherRadarOffsets, hasLength(31));
      expect(weatherRadarOffsets.first, 0);
      expect(weatherRadarOffsets.sublist(1, 9), <int>[
        15, 30, 45, 60, 75, 90, 105, 120, //
      ]);
      expect(weatherRadarOffsets[9], 180);
      expect(weatherRadarOffsets.last, 1440);
      for (var i = 10; i < weatherRadarOffsets.length; i++) {
        expect(weatherRadarOffsets[i] - weatherRadarOffsets[i - 1], 60);
      }
      expect(weatherSliderIndexOf(0), 0);
      expect(weatherSliderIndexOf(45), 3);
      expect(weatherSliderIndexOf(180), 9);
      expect(weatherOffsetOfSliderIndex(30), 1440);
      for (final offset in weatherRadarOffsets) {
        expect(
          weatherOffsetOfSliderIndex(weatherSliderIndexOf(offset)),
          offset,
        );
      }
      // Anything else to the nearest step; the past to now.
      expect(snapWeatherOffset(-45), 0);
      expect(snapWeatherOffset(50), 45);
      expect(snapWeatherOffset(200), 180);
      expect(snapWeatherOffset(5000), 1440);
    });

    test('the step\'s text', () {
      expect(weatherStepText(l10n, 0), l10n.mapWeatherNow);
      expect(weatherStepText(l10n, 30), l10n.mapWeatherMinutesAhead(30));
      expect(weatherStepText(l10n, 105), l10n.mapWeatherMinutesAhead(105));
      expect(weatherStepText(l10n, 60), l10n.mapWeatherHoursAhead(1));
      expect(weatherStepText(l10n, 120), l10n.mapWeatherHoursAhead(2));
      expect(weatherStepText(l10n, 1440), l10n.mapWeatherHoursAhead(24));
    });
  });

  group('rain sources', () {
    // 14:42 UTC.
    final now = utc(14, 42);
    final strasbourg = const BoundingBox(
      south: 48.2,
      west: 6.0,
      north: 48.9,
      east: 7.8,
    );
    List<String> ids(int offset, BoundingBox at) => <String>[
      for (final part in rainPartsAt(
        defaultWeatherMapSources,
        now,
        offset,
        view: at,
      ))
        part.source.id,
    ];

    test('now: the radars where they reach, the satellite around them', () {
      // Inside the DWD's reach: the radar alone.
      expect(ids(0, view(13.4, 52.5)), <String>['radar_dwd']);
      // At its edge: the satellite too, masked by the radar.
      expect(ids(0, strasbourg), <String>['radar_dwd', 'rain_hsaf']);
      final hsaf = rainPartsAt(
        defaultWeatherMapSources,
        now,
        0,
        view: strasbourg,
      ).last;
      expect(hsaf.maskedBy, <String>['radar_dwd']);
      expect(hsaf.masks, <List<LatLng>>[dwdRadarReach]);
      expect(hsaf.maskKey, '-radar_dwd');
      // Spain, Africa: the satellite alone.
      expect(ids(0, view(-3.7, 40.4)), <String>['rain_hsaf']);
      expect(ids(0, view(36.8, -1.3)), <String>['rain_hsaf']);
      // The US: NOAA, out of the satellite's disk.
      expect(ids(0, view(-74, 40.7)), <String>['radar_noaa']);
      // Asia: nothing measures the rain there.
      expect(ids(0, view(100, 10)), isEmpty);
    });

    test('ahead: the nowcast in the DWD\'s reach for two hours, ICON-EU '
        'over Europe, the global ICON elsewhere', () {
      expect(ids(30, view(13.4, 52.5)), <String>['radar_dwd']);
      expect(ids(30, strasbourg), <String>['radar_dwd', 'rain_icon_eu']);
      expect(
        rainPartsAt(
          defaultWeatherMapSources,
          now,
          30,
          view: strasbourg,
        ).last.maskedBy,
        <String>['radar_dwd'],
      );
      // Past the nowcast: the model over Germany too.
      expect(ids(180, view(13.4, 52.5)), <String>['rain_icon_eu']);
      expect(ids(30, view(-3.7, 40.4)), <String>['rain_icon_eu']);
      // Africa south of ICON-EU, the US, Asia: the global model.
      expect(ids(30, view(36.8, -1.3)), <String>['rain_icon']);
      expect(ids(30, view(-74, 40.7)), <String>['rain_icon']);
      expect(ids(1440, view(100, 10)), <String>['rain_icon']);
      // Across ICON-EU's edge: both, the global one masked by the other.
      final edge = rainPartsAt(
        defaultWeatherMapSources,
        now,
        180,
        view: const BoundingBox(south: 27, west: 10, north: 32, east: 15),
      );
      expect(edge.map((p) => p.source.id), <String>[
        'rain_icon_eu',
        'rain_icon',
      ]);
      expect(edge.last.maskedBy, <String>['rain_icon_eu']);
    });

    test('the satellite: the newest ten-minute frame at least 25 minutes '
        'old, now only', () {
      expect(hsafRain.frameAt(utc(14, 42))!.time, utc(14, 10));
      expect(hsafRain.frameAt(utc(14, 45))!.time, utc(14, 20));
      expect(hsafRain.frameAt(utc(14, 42), offsetMinutes: 15), isNull);
      final url = hsafRain.softImageUrl(
        hsafRain.frameAt(utc(14, 45))!,
        view(10, 45),
      )!;
      expect(url, startsWith('https://view.eumetsat.int/geoserver/ows?'));
      expect(url, contains('layers=mtg_fd:h40b'));
      expect(timeOf(url), '2026-10-10T14:20:00.000Z');
      expect(
        hsafRain.attributionFor(hsafRain.frameAt(utc(14, 45))!, now),
        'Satellite rain: Contains modified EUMETSAT H SAF data 2026',
      );
    });

    test('the licence rule for EUMETSAT\'s images leaves H SAF be', () {
      final enforced = enforceWeatherLicences(defaultWeatherMapSources);
      final hsaf = enforced.firstWhere((s) => s.id == 'rain_hsaf');
      expect(hsaf.stepMinutes, 10);
      expect(hsaf.delayMinutes, 25);
      expect(hsaf.enabled, isTrue);
      // A Meteosat image under another name is still held to the hour.
      final sneaky = enforceWeatherLicences(<WeatherMapSource>[
        hsafRain.copyWith(
          urlTemplate: hsafRain.urlTemplate.replaceAll(
            'mtg_fd:h40b',
            'mtg_fd:ir105_hrfi',
          ),
          imageUrlTemplate: hsafRain.urlTemplate.replaceAll(
            'mtg_fd:h40b',
            'mtg_fd:ir105_hrfi',
          ),
        ),
      ]).single;
      expect(sneaky.stepMinutes, 60);
      expect(sneaky.delayMinutes, greaterThanOrEqualTo(20));
    });

    test('a model shows the hour the step falls in, never now', () {
      // 14:42 + 15 min = 14:57: the hour to 15:00.
      expect(iconEuRain.frameAt(now, offsetMinutes: 15)!.time, utc(15, 0));
      // + 45 min = 15:27: the hour to 16:00.
      expect(iconEuRain.frameAt(now, offsetMinutes: 45)!.time, utc(16, 0));
      expect(iconEuRain.frameAt(now, offsetMinutes: 180)!.time, utc(18, 0));
      expect(iconEuRain.frameAt(now), isNull);
      // The global model's six hours up to 18, 00, … UTC.
      expect(iconGlobalRain.frameAt(now, offsetMinutes: 15)!.time, utc(18, 0));
      expect(iconGlobalRain.frameAt(now, offsetMinutes: 180)!.time, utc(18, 0));
      expect(
        iconGlobalRain.frameAt(now, offsetMinutes: 300)!.time,
        DateTime.utc(2026, 10, 11),
      );
      expect(
        iconGlobalRain.frameAt(now, offsetMinutes: 1440)!.time,
        DateTime.utc(2026, 10, 11, 18),
      );
    });

    test('a model\'s moment is clamped to the frames it has', () {
      final short = iconEuRain.copyWith(forecastMinutes: 180);
      // 14:42 + 3 h: 17:42, its last frame 17:00.
      expect(short.frameAt(now, offsetMinutes: 600)!.time, utc(17, 0));
      expect(short.modelFrameTime(now, 15), utc(15, 0));
      // Nothing ahead at all: no frame.
      expect(
        iconEuRain
            .copyWith(forecastMinutes: 10)
            .frameAt(now, offsetMinutes: 60),
        isNull,
      );
      // The global model clamped to its last six-hour frame.
      expect(
        iconGlobalRain.copyWith(forecastMinutes: 600).modelFrameTime(now, 1440),
        DateTime.utc(2026, 10, 11),
      );
    });

    test('the model requests: ICON-EU hourly in the radar\'s style, the '
        'global ICON\'s six hours in its own', () {
      final box = view(10, 50);
      final eu = Uri.parse(
        iconEuRain.softImageUrl(WeatherFrame(utc(16, 0)), box)!,
      );
      expect(eu.host, 'maps.dwd.de');
      expect(
        eu.queryParameters['layers'],
        'dwd:Icon-eu_reg00625_fd_sl_TOTPREC01H',
      );
      expect(eu.queryParameters['styles'], 'niederschlagsradar');
      expect(eu.queryParameters['time'], '2026-10-10T16:00:00.000Z');
      expect(eu.queryParameters['bbox'], mercatorBboxString(box));
      // At the model's own 7 km, no minimum size.
      expect(
        eu.queryParameters['width'],
        '${((mercatorX(box.east) - mercatorX(box.west)) / 7000).round()}',
      );
      final global = Uri.parse(
        iconGlobalRain.softImageUrl(
          WeatherFrame(utc(18, 0)),
          const BoundingBox(south: 20, west: -130, north: 55, east: -60),
        )!,
      );
      expect(
        global.queryParameters['layers'],
        'dwd:Icon_reg025_fd_sl_TOTPREC06H',
      );
      expect(global.queryParameters['styles'], '');
      final (w, _) = radarSoftImageSize(
        iconGlobalRain,
        const BoundingBox(south: 20, west: -130, north: 55, east: -60),
      );
      expect(global.queryParameters['width'], '$w');
      expect(w, ((mercatorX(-60) - mercatorX(-130)) / 28000).round());
      expect(
        iconEuRain.attributionFor(WeatherFrame(utc(16, 0)), now),
        'Forecast: Deutscher Wetterdienst (CC BY 4.0)',
      );
    });

    test('the label\'s source is the one over the view\'s middle', () {
      final berlin = LatLng(52.5, 13.4);
      final paris = LatLng(48.86, 2.35); // in the DWD's box, beyond its reach
      final newYork = LatLng(40.7, -74);
      expect(rainAtPoint(defaultWeatherMapSources, berlin, now, 0), (
        role: RainRole.radar,
        time: utc(14, 35),
      ));
      expect(rainAtPoint(defaultWeatherMapSources, paris, now, 0), (
        role: RainRole.satellite,
        time: utc(14, 10),
      ));
      // NOAA's frame, twenty minutes back: not the DWD's.
      expect(rainAtPoint(defaultWeatherMapSources, newYork, now, 0), (
        role: RainRole.radar,
        time: utc(14, 20),
      ));
      expect(rainAtPoint(defaultWeatherMapSources, berlin, now, 45), (
        role: RainRole.radar,
        time: utc(15, 20),
      ));
      // A model: the hour the step falls in.
      expect(rainAtPoint(defaultWeatherMapSources, paris, now, 45), (
        role: RainRole.model,
        time: utc(15, 0),
      ));
      expect(rainAtPoint(defaultWeatherMapSources, newYork, now, 45), (
        role: RainRole.model,
        time: utc(15, 0),
      ));
      expect(rainAtPoint(defaultWeatherMapSources, berlin, now, 180), (
        role: RainRole.model,
        time: utc(17, 0),
      ));
      expect(
        rainAtPoint(defaultWeatherMapSources, LatLng(10, 100), now, 0),
        isNull,
      );
    });

    test('the DWD\'s reach: Germany in, Paris and the North Sea\'s far side '
        'out', () {
      expect(dwdRadar.reaches(LatLng(52.5, 13.4)), isTrue);
      expect(dwdRadar.reaches(LatLng(48.1, 11.6)), isTrue);
      expect(dwdRadar.reaches(LatLng(54.3, 10.1)), isTrue);
      expect(dwdRadar.reaches(LatLng(48.86, 2.35)), isFalse);
      expect(dwdRadar.reaches(LatLng(56, 3)), isFalse);
      // Its coverage box still holds them all.
      expect(dwdRadar.coverage.single.contains(LatLng(48.86, 2.35)), isTrue);
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

  group('soft radar', () {
    double mercatorWidth(BoundingBox b) =>
        mercatorX(b.east) - mercatorX(b.west);

    BoundingBox berlinBox() =>
        dwdRadar.softBox(cloudDetailArea(view(13.4, 52.5), 8)!)!;

    test('the DWD: a GetMap of the box at its size and the frame, the tile '
        'template kept for As measured', () {
      final box = berlinBox();
      final frame = dwdRadar.frameAt(utc(14, 42))!;
      final url = dwdRadar.softImageUrl(frame, box)!;
      final query = Uri.parse(url).queryParameters;
      final (w, h) = radarSoftImageSize(dwdRadar, box);
      expect(query['request'], 'GetMap');
      expect(query['layers'], 'dwd:Niederschlagsradar');
      expect(query['bbox'], mercatorBboxString(box));
      expect(query['width'], '$w');
      expect(query['height'], '$h');
      expect(query['time'], '2026-10-10T14:35:00.000Z');
      expect(dwdRadar.tileUrl(frame), contains('width=256&height=256'));
      expect(dwdRadar.tileUrl(frame), contains('{bbox-epsg-3857}'));
    });

    test('NOAA: exportImage of the box at its size, the time in epoch '
        'milliseconds', () {
      final box = noaaRadar.softBox(cloudDetailArea(view(-74, 40.7), 8)!)!;
      final frame = noaaRadar.frameAt(utc(14, 42), offsetMinutes: -30)!;
      final url = noaaRadar.softImageUrl(frame, box)!;
      final query = Uri.parse(url).queryParameters;
      final (w, h) = radarSoftImageSize(noaaRadar, box);
      expect(url, contains('/exportImage?'));
      expect(query['bbox'], mercatorBboxString(box));
      expect(query['bboxSR'], '3857');
      expect(query['imageSR'], '3857');
      expect(query['size'], '$w,$h');
      expect(query['time'], '${utc(13, 50).millisecondsSinceEpoch}');
      expect(query['f'], 'image');
    });

    test('at the radar\'s own kilometre, each side between 64 and 1536', () {
      expect(dwdRadar.nativeMetresPerPixel, 1000);
      expect(noaaRadar.nativeMetresPerPixel, 1000);
      const box = BoundingBox(south: 50, west: 10, north: 52, east: 13);
      final (w, _) = radarSoftImageSize(dwdRadar, box);
      expect(w, (mercatorWidth(box) / 1000).round());
      expect(radarSoftCapped(dwdRadar, box), isFalse);
      const tiny = BoundingBox(south: 50, west: 10, north: 50.05, east: 10.1);
      expect(radarSoftImageSize(dwdRadar, tiny), (64, 64));
      final (cw, ch) = radarSoftImageSize(dwdRadar, dwdRadar.coverage.single);
      expect(ch, radarSoftMaxSide);
      expect(cw, lessThanOrEqualTo(radarSoftMaxSide));
      expect(radarSoftCapped(dwdRadar, dwdRadar.coverage.single), isTrue);
    });

    group('a model\'s image', () {
      double mercatorHeight(BoundingBox b) =>
          mercatorY(b.north) - mercatorY(b.south);

      // A city's view at zoom 12, as the driver asks for it.
      BoundingBox cityBox(WeatherMapSource source, double lon, double lat) =>
          source.softBox(
            modelImageArea(source, cloudDetailArea(view(lon, lat, 0.03), 12)!),
          )!;

      for (final (source, lon, lat) in <(WeatherMapSource, double, double)>[
        (iconEuRain, 13.4, 52.5),
        (iconGlobalRain, -74, 40.7),
      ]) {
        test('${source.id} at city zoom: at least $modelMinCells cells a '
            'side, a pixel a cell', () {
          final cell = source.nativeMetresPerPixel;
          final box = cityBox(source, lon, lat);
          expect(
            mercatorWidth(box),
            greaterThanOrEqualTo(modelMinCells * cell),
          );
          expect(
            mercatorHeight(box),
            greaterThanOrEqualTo(modelMinCells * cell),
          );
          // Centred on the view, within the snap of its middle (an eighth
          // of the minimum) and the view's own rounding.
          expect(
            ((mercatorX(box.west) + mercatorX(box.east)) / 2 - mercatorX(lon))
                .abs(),
            lessThanOrEqualTo(cell * modelMinCells / 8 + 5000),
          );
          final (w, h) = radarSoftImageSize(source, box);
          expect(w, greaterThanOrEqualTo(modelMinCells));
          expect(h, greaterThanOrEqualTo(modelMinCells));
          expect(w, lessThan(radarSoftMinSide));
          expect(mercatorWidth(box) / w, closeTo(cell, cell * 0.01));
          expect(mercatorHeight(box) / h, closeTo(cell, cell * 0.05));
          expect(radarSoftCapped(source, box), isFalse);
        });

        test('${source.id}: a small pan asks for the same box', () {
          // From a point of the grid the box's middle snaps to, a pan of a
          // kilometre or two, either way.
          final snap = source.nativeMetresPerPixel * modelMinCells / 4;
          double onGrid(double v) => (v / snap).roundToDouble() * snap;
          final x = lonOfMercatorX(onGrid(mercatorX(lon)));
          final y = latOfMercatorY(onGrid(mercatorY(lat)));
          final key = cloudDetailKey(cityBox(source, x, y));
          for (final (dx, dy) in <(double, double)>[
            (0.015, 0),
            (-0.015, 0),
            (0, 0.01),
            (0, -0.01),
            (0.01, 0.01),
          ]) {
            expect(
              cloudDetailKey(cityBox(source, x + dx, y + dy)),
              key,
              reason: '($dx, $dy)',
            );
          }
          // A pan of half the minimum is a box of its own.
          final far = lonOfMercatorX(
            mercatorX(x) + source.nativeMetresPerPixel * modelMinCells / 2,
          );
          expect(cloudDetailKey(cityBox(source, far, y)), isNot(key));
        });

        test('${source.id} zoomed out: the coverage, at most '
            '$radarSoftMaxSide pixels a side', () {
          final whole = source.softBox(
            modelImageArea(
              source,
              const BoundingBox(south: -80, west: -179, north: 80, east: 179),
            ),
          )!;
          final (w, h) = radarSoftImageSize(source, whole);
          expect(w, lessThanOrEqualTo(radarSoftMaxSide));
          expect(h, lessThanOrEqualTo(radarSoftMaxSide));
          // A finer model would be capped, its pixels coarser than cells.
          final fine = source.copyWith(nativeMetresPerPixel: 2000);
          final (fw, fh) = radarSoftImageSize(fine, whole);
          expect(math.max(fw, fh), radarSoftMaxSide);
          expect(radarSoftCapped(fine, whole), isTrue);
        });
      }

      test('a view larger than the minimum is kept, put on the grid', () {
        final area = cloudDetailArea(view(10, 50, 3), 6)!;
        final grown = modelImageArea(iconEuRain, area);
        expect(grown.west, lessThanOrEqualTo(area.west));
        expect(grown.east, greaterThanOrEqualTo(area.east));
        expect(grown.south, lessThanOrEqualTo(area.south));
        expect(grown.north, greaterThanOrEqualTo(area.north));
        // By the snap of its middle and a cell on each side, at most.
        expect(
          mercatorWidth(grown),
          lessThanOrEqualTo(
            mercatorWidth(area) + (modelMinCells / 4 + 2) * 7000 + 1,
          ),
        );
      });

      test('the radars keep their 64-pixel minimum', () {
        const tiny = BoundingBox(south: 50, west: 10, north: 50.05, east: 10.1);
        expect(radarSoftImageSize(dwdRadar, tiny), (64, 64));
        expect(radarSoftImageSize(hsafRain, tiny), (64, 64));
      });
    });

    test('the box: every coverage box the area meets, clipped', () {
      // Zoomed out over North America: the contiguous US and Alaska.
      const area = BoundingBox(south: 10, west: -175, north: 75, east: -60);
      final box = noaaRadar.softBox(area)!;
      expect(box.west, -170);
      expect(box.east, -65.2);
      expect(box.south, 17.8);
      expect(box.north, 72);
      // Over Germany, the view's own area.
      final berlin = cloudDetailArea(view(13.4, 52.5), 8)!;
      expect(dwdRadar.softBox(berlin), berlin);
      expect(noaaRadar.softBox(berlin), isNull);
    });

    test('the cache stamp: the moment, and for one ahead also the newest '
        'measured', () {
      final now = utc(14, 42);
      final past = dwdRadar.frameAt(now, offsetMinutes: -15)!;
      expect(
        radarImageStamp(dwdRadar, past, now),
        '${utc(14, 20).millisecondsSinceEpoch}',
      );
      final ahead = dwdRadar.frameAt(now, offsetMinutes: 30)!;
      final stamp = radarImageStamp(dwdRadar, ahead, now);
      expect(
        stamp,
        '${utc(15, 5).millisecondsSinceEpoch}f'
        '${utc(14, 35).millisecondsSinceEpoch}',
      );
      // Five minutes on, the same moment ahead is a new forecast.
      final later = utc(14, 47);
      expect(radarImageStamp(dwdRadar, ahead, later), isNot(stamp));
      // The past stays the same moment.
      expect(
        radarImageStamp(dwdRadar, past, later),
        radarImageStamp(dwdRadar, past, now),
      );
    });

    test('the mirror can set the image request, https only', () {
      final sources = applyWeatherOverride(defaultWeatherMapSources, [
        {
          'id': 'radar_dwd',
          'imageUrl':
              'https://radar.example/wms?bbox={bbox-epsg-3857}'
              '&width={width}&height={height}&time={time}',
          'metresPerPixel': 500,
        },
        {'id': 'radar_noaa', 'imageUrl': 'http://radar.example/x'},
      ]);
      final dwd = sources.firstWhere((s) => s.id == 'radar_dwd');
      expect(dwd.imageUrlTemplate, startsWith('https://radar.example/'));
      expect(dwd.nativeMetresPerPixel, 500);
      // Not https: the entry is left out, the built-in source stays.
      expect(sources.firstWhere((s) => s.id == 'radar_noaa'), noaaRadar);
    });
  });

  test('NOAA asks for png32: its plain png is RGB with a colour key, which '
      'the map cannot decode', () {
    final frame = noaaRadar.frameAt(utc(14, 42))!;
    final box = noaaRadar.coverage.first;
    for (final url in <String>[
      noaaRadar.tileUrl(frame),
      noaaRadar.softImageUrl(frame, box)!,
    ]) {
      expect(Uri.parse(url).queryParameters['format'], 'png32');
    }
  });
  group('image boxes MapLibre can draw', () {
    BoundingBox box(double w, double s, double e, double n) =>
        BoundingBox(south: s, west: w, north: n, east: e);

    test('an ordinary box passes', () {
      expect(safeImageBox(box(13, 52, 14, 53)), isTrue);
      expect(safeImageBox(box(-180, -85.05, 0, 85.05)), isTrue);
      expect(safeImageBox(box(0, 0, 180, 1)), isTrue);
    });

    test('no width or no height fails, and too little of either', () {
      expect(safeImageBox(box(13, 52, 13, 53)), isFalse);
      expect(safeImageBox(box(13, 52, 14, 52)), isFalse);
      expect(safeImageBox(box(13, 52, 13.005, 53)), isFalse);
      expect(safeImageBox(box(13, 52, 14, 52.005)), isFalse);
      expect(safeImageBox(box(13, 52, 13.02, 52.02)), isTrue);
    });

    test('inverted fails', () {
      expect(safeImageBox(box(14, 52, 13, 53)), isFalse);
      expect(safeImageBox(box(13, 53, 14, 52)), isFalse);
      // Across the antimeridian, as a view can be.
      expect(safeImageBox(box(170, 52, -170, 53)), isFalse);
    });

    test('beyond the Web Mercator latitudes fails', () {
      expect(safeImageBox(box(0, 80, 10, 85.0511)), isTrue);
      expect(safeImageBox(box(0, -85.0511, 10, -80)), isTrue);
      expect(safeImageBox(box(0, 80, 10, 85.06)), isFalse);
      expect(safeImageBox(box(0, -85.06, 10, -80)), isFalse);
      expect(safeImageBox(box(0, 86, 10, 89)), isFalse);
      expect(safeImageBox(box(0, -90, 10, 90)), isFalse);
    });

    test('beyond ±180° or wider than 180° fails', () {
      expect(safeImageBox(box(-181, 0, -170, 10)), isFalse);
      expect(safeImageBox(box(170, 0, 181, 10)), isFalse);
      expect(safeImageBox(box(-540, -85, 540, 85)), isFalse);
      expect(safeImageBox(box(-90, 0, 90.5, 10)), isFalse);
      expect(safeImageBox(box(-180, -85, 180, 85)), isFalse);
    });

    test('a number that is not one fails', () {
      expect(safeImageBox(box(double.nan, 0, 10, 10)), isFalse);
      expect(safeImageBox(box(0, double.nan, 10, 10)), isFalse);
      expect(safeImageBox(box(0, 0, double.infinity, 10)), isFalse);
      expect(safeImageBox(box(0, 0, 10, double.nan)), isFalse);
    });

    test('clipped to the world an image can show', () {
      final world = clipToImageWorld(box(-540, -90, 540, 90))!;
      expect(world.west, -180);
      expect(world.east, 180);
      expect(world.south, -weatherImageMaxLat);
      expect(world.north, weatherImageMaxLat);
      expect(clipToImageWorld(box(190, 0, 200, 10)), isNull);
      expect(clipToImageWorld(box(0, 86, 10, 89)), isNull);
      expect(clipToImageWorld(box(double.nan, 0, 10, 10)), isNull);
    });

    test('every region image of the clouds passes', () {
      for (final source in defaultWeatherMapSources) {
        if (source.kind != WeatherKind.clouds) continue;
        for (final region in source.coverage) {
          expect(safeImageBox(region), isTrue, reason: '${source.id} $region');
        }
      }
    });

    test('an image asked for beyond the world is clipped before it is '
        'sized', () {
      final soft = iconGlobalRain.softBox(box(-540, -90, -100, 90))!;
      expect(soft.west, -180);
      expect(soft.south, greaterThanOrEqualTo(-weatherImageMaxLat));
      expect(soft.north, lessThanOrEqualTo(weatherImageMaxLat));
      final detail = eumetsatClouds.detailBox(box(-540, -90, 540, 90))!;
      expect(detail.west, greaterThanOrEqualTo(-180));
      expect(detail.east, lessThanOrEqualTo(180));
      expect(iconGlobalRain.softBox(box(190, 0, 200, 10)), isNull);
    });
  });
}
