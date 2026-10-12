import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../../core/http/user_agent.dart';
import '../../map/domain/wind_field.dart';

part 'dwd_route_forecast.g.dart';

// The free forecast a route is coloured by without Velorki Plus: the DWD's
// open model data (CC BY 4.0), asked for straight from the phone off the
// same WCS the wind map uses, one box at one hour per request as a
// plain-text grid ([parseWcsGrid]).
//
// What the service serves, as checked against it (October 2026):
//
// - Every coverage holds several runs at once (`REFERENCE_TIME`, the last
//   day and a half of them, every six hours). A GetCoverage that names no
//   run is answered from the *oldest* run that has the hour, a day or more
//   behind the newest; so every request here names the newest run, read
//   off the coverage's DescribeCoverage ([parseNewestRun]).
// - `Icon_reg025_fd_sl_UV10M`: the wind 10 m up, u (east) and v (north) in
//   m/s, at the hour, global on a 0.25° grid.
// - `Icon-eu_reg00625_fd_sl_TOTPREC01H`: ICON-EU's rain in the hour up to
//   the time asked for (kg/m², i.e. mm), on a 0.0625° grid over Europe.
// - `Icon_reg025_fd_sl_TOTPREC` ("Niederschlag akkumuliert"): the global
//   model's rain summed from the start of its run, 0 at the run's own hour
//   and only growing; there is no hourly rain for the global model. The rain
//   of an hour is the difference of the sums at its two ends, from the same
//   run (`hourlyRain`). Its time axis is hourly too.

/// The DWD's WCS, the one the wind map asks too.
const String dwdWcsUrl = 'https://maps.dwd.de/geoserver/ows';

/// The global wind, u and v at 10 m, 0.25°, hourly.
const String dwdWindCoverage = 'dwd__Icon_reg025_fd_sl_UV10M';

/// ICON-EU's rain of each hour, 0.0625°, over [dwdRainEuArea].
const String dwdRainEuCoverage = 'dwd__Icon-eu_reg00625_fd_sl_TOTPREC01H';

/// The global model's rain summed from its run's start, 0.25°.
const String dwdRainGlobalCoverage = 'dwd__Icon_reg025_fd_sl_TOTPREC';

/// Where ICON-EU has rain: its grid's points, as DescribeCoverage gives
/// them (70.5° N to 29.5° N, 23.5° W to 62.5° E).
const BoundingBox dwdRainEuArea = BoundingBox(
  south: 29.5,
  west: -23.5,
  north: 70.5,
  east: 62.5,
);

/// How long a request may take.
const Duration dwdRouteForecastTimeout = Duration(seconds: 15);

/// How long the newest run read off a coverage is believed: a new run
/// comes every six hours, some hours after its time.
const Duration dwdRunCacheAge = Duration(minutes: 30);

/// How many grids are kept in memory, the oldest asked for going first.
const int dwdGridCacheSize = 200;

/// How many requests run at once.
const int dwdMaxConcurrent = 4;

/// [time] as the WCS reads it.
String _dwdTime(DateTime time) =>
    '${time.toUtc().toIso8601String().substring(0, 19)}.000Z';

/// The GetCoverage of [coverageId] over [box] at [time] from [run], as
/// plain text.
String dwdCoverageUrl(
  String coverageId,
  BoundingBox box,
  DateTime time,
  DateTime run,
) {
  String f(double v) => v.toStringAsFixed(3);
  return '$dwdWcsUrl?service=WCS&version=2.0.1&request=GetCoverage'
      '&coverageId=$coverageId&format=text/plain'
      '&subset=Lat(${f(box.south)},${f(box.north)})'
      '&subset=Long(${f(box.west)},${f(box.east)})'
      '&subset=time(%22${_dwdTime(time)}%22)'
      '&subset=REFERENCE_TIME(%22${_dwdTime(run)}%22)';
}

/// The DescribeCoverage of [coverageId].
String dwdDescribeUrl(String coverageId) =>
    '$dwdWcsUrl?service=WCS&version=2.0.1&request=DescribeCoverage'
    '&coverageId=$coverageId';

/// What the free route forecast asks of the network.
abstract class DwdForecastClient {
  /// The newest run of [coverageId]; `null` when it cannot be had.
  Future<DateTime?> newestRun(String coverageId);

  /// [coverageId]'s grid of [bands] bands over [box] at [time] from [run];
  /// `null` when it cannot be had.
  Future<WcsGrid?> grid(
    String coverageId,
    BoundingBox box,
    DateTime time,
    DateTime run, {
    int bands = 1,
  });

  /// The newest run of [coverageId] as last read, without asking; `null`
  /// while it is not known.
  DateTime? knownRun(String coverageId);

  /// [grid]'s answer if it has come, without asking; `null` while it has
  /// not been asked for, is on its way, or could not be had.
  WcsGrid? loadedGrid(
    String coverageId,
    BoundingBox box,
    DateTime time,
    DateTime run,
  );
}

/// [DwdForecastClient] over HTTP: the newest runs kept for
/// [dwdRunCacheAge], the grids in memory by their URL (which names the
/// coverage, the box, the hour and the run) for as long as they are among
/// the [dwdGridCacheSize] last asked for, at most [dwdMaxConcurrent]
/// requests at once. A grid asked for again while on its way waits for the
/// same request.
class HttpDwdForecastClient implements DwdForecastClient {
  /// A client on [dio], [now] the clock the runs' age is told by.
  HttpDwdForecastClient({
    required this.dio,
    required this.now,
    this.timeout = dwdRouteForecastTimeout,
    this.parse = _parseInBackground,
  });

  final Dio dio;
  final DateTime Function() now;
  final Duration timeout;

  /// Reads a grid of so many bands from the service's text.
  final Future<WcsGrid?> Function(String text, int bands) parse;

  final Map<String, (DateTime, DateTime)> _runs =
      <String, (DateTime, DateTime)>{};
  final LinkedHashMap<String, Future<WcsGrid?>> _grids =
      LinkedHashMap<String, Future<WcsGrid?>>();

  /// The grids of [_grids] that have come.
  final Map<String, WcsGrid> _loaded = <String, WcsGrid>{};
  int _running = 0;
  final Queue<Completer<void>> _waiting = Queue<Completer<void>>();

  /// The URLs asked for, newest last; for tests.
  @visibleForTesting
  final List<String> requests = <String>[];

  @override
  Future<DateTime?> newestRun(String coverageId) async {
    final at = now();
    final known = _runs[coverageId];
    if (known != null && at.difference(known.$1) < dwdRunCacheAge) {
      return known.$2;
    }
    final text = await _get(dwdDescribeUrl(coverageId), xml: true);
    final run = text == null ? null : parseNewestRun(text);
    if (run != null) _runs[coverageId] = (at, run);
    return run ?? known?.$2;
  }

  @override
  Future<WcsGrid?> grid(
    String coverageId,
    BoundingBox box,
    DateTime time,
    DateTime run, {
    int bands = 1,
  }) {
    final url = dwdCoverageUrl(coverageId, box, time, run);
    final hit = _grids.remove(url);
    if (hit != null) return _grids[url] = hit;
    final future = _fetchGrid(url, bands);
    _grids[url] = future;
    while (_grids.length > dwdGridCacheSize) {
      _loaded.remove(_grids.keys.first);
      _grids.remove(_grids.keys.first);
    }
    // A failure is not kept: it is asked again next time.
    unawaited(
      future.then((grid) {
        if (grid == null) {
          _grids.remove(url);
        } else if (identical(_grids[url], future)) {
          _loaded[url] = grid;
        }
      }),
    );
    return future;
  }

  @override
  DateTime? knownRun(String coverageId) {
    final known = _runs[coverageId];
    if (known == null || now().difference(known.$1) >= dwdRunCacheAge) {
      return null;
    }
    return known.$2;
  }

  @override
  WcsGrid? loadedGrid(
    String coverageId,
    BoundingBox box,
    DateTime time,
    DateTime run,
  ) => _loaded[dwdCoverageUrl(coverageId, box, time, run)];

  Future<WcsGrid?> _fetchGrid(String url, int bands) async {
    final text = await _get(url);
    if (text == null) return null;
    try {
      return await parse(text, bands);
    } on Object catch (error) {
      debugPrint('velorki: free forecast not read: $error');
      return null;
    }
  }

  /// The body of [url]: plain text (or XML for [xml]); `null` on anything
  /// else, as the service answers a request it cannot serve with an XML
  /// error under status 200.
  Future<String?> _get(String url, {bool xml = false}) async {
    await _acquire();
    requests.add(url);
    try {
      final response = await dio
          .get<String>(
            url,
            options: Options(
              responseType: ResponseType.plain,
              sendTimeout: timeout,
              receiveTimeout: timeout,
            ),
          )
          .timeout(timeout);
      final status = response.statusCode ?? 0;
      final type = (response.headers.value(Headers.contentTypeHeader) ?? '')
          .toLowerCase();
      final data = response.data;
      if (status < 200 || status >= 300) return null;
      if (data == null || data.isEmpty) return null;
      if (xml ? !type.contains('xml') : !type.startsWith('text/plain')) {
        return null;
      }
      return data;
    } on Object catch (error) {
      debugPrint('velorki: free forecast not fetched: $error');
      return null;
    } finally {
      _release();
    }
  }

  Future<void> _acquire() async {
    if (_running < dwdMaxConcurrent) {
      _running++;
      return;
    }
    final turn = Completer<void>();
    _waiting.add(turn);
    await turn.future;
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeFirst().complete();
    } else {
      _running--;
    }
  }
}

Future<WcsGrid?> _parseInBackground(String text, int bands) =>
    Isolate.run(() => parseWcsGrid(text, bands: bands));

/// The one [DwdForecastClient].
@Riverpod(keepAlive: true)
DwdForecastClient dwdForecastClient(Ref ref) {
  final dio = velorkiDio();
  ref.onDispose(dio.close);
  return HttpDwdForecastClient(dio: dio, now: DateTime.now);
}
