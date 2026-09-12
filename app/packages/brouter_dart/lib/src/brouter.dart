/// The public routing API of the port: [BRouter] runs the ported
/// `RoutingEngine` the way upstream's `RouteServer`/`ServerHandler` do for an
/// HTTP request, either from a query string ([BRouter.routeQuery], the
/// oracle's contract) or from a typed [RoutingRequest] ([BRouter.route]).
library;

import 'dart:convert';
import 'dart:io';

import 'core/format_csv.dart';
import 'core/format_gpx.dart';
import 'core/format_json.dart';
import 'core/format_kml.dart';
import 'core/osm_track.dart';
import 'core/routing_context.dart';
import 'core/routing_engine.dart';
import 'core/routing_param_collector.dart';
import 'expressions/profile_cache.dart';
import 'jfloat.dart';
import 'jvm.dart';

/// A waypoint in degrees.
class LonLat {
  const LonLat(this.lon, this.lat);

  final double lon;
  final double lat;

  @override
  String toString() => '$lon,$lat';
}

/// A circular nogo area (`nogos=lon,lat,radius[,weight]`).
class NogoCircle {
  const NogoCircle(this.center, this.radiusMeters, {this.weight});

  final LonLat center;
  final int radiusMeters;

  /// Null: the area is forbidden; otherwise a cost per metre inside.
  final double? weight;
}

/// The parameters of one routing request, named like the 1.7.10 URL
/// parameters (`RoutingParamCollector.setParams`).
class RoutingRequest {
  const RoutingRequest({
    required this.points,
    required this.profile,
    this.alternativeIdx = 0,
    this.roundTrip = false,
    this.roundTripDistance,
    this.direction,
    this.roundTripDirectionAdd,
    this.roundTripPoints,
    this.allowSamewayback = false,
    this.nogos = const <NogoCircle>[],
    this.maxRunningTimeMillis = 0,
    this.turnInstructionMode,
    this.profileParams = const <String, String>{},
  });

  /// Waypoints (two or more; one for a round trip).
  final List<LonLat> points;

  /// Profile name without `.brf` (a file of `BRouter.profilesDir`).
  final String profile;

  /// `alternativeidx` 0..3.
  final int alternativeIdx;

  /// `engineMode=4`: a loop from `points[0]`.
  final bool roundTrip;

  /// `roundTripDistance`: the radius in metres to the generated circle points.
  final int? roundTripDistance;

  /// `direction`: the start bearing in degrees. Always set it for round
  /// trips: without it upstream picks a random bearing (`Math.random`).
  final int? direction;
  final int? roundTripDirectionAdd;

  /// `roundTripPoints` (3..20, default 5).
  final int? roundTripPoints;
  final bool allowSamewayback;
  final List<NogoCircle> nogos;

  /// `maxRunningTime` in milliseconds; 0 disables the timeout (the oracle's
  /// setting).
  final int maxRunningTimeMillis;

  /// `timode` (0 = none).
  final int? turnInstructionMode;

  /// `profile:<name>=<value>` overrides.
  final Map<String, String> profileParams;

  /// The query string upstream's server would receive for this request.
  String toQuery() {
    final sb = StringBuffer();
    sb.write('lonlats=');
    sb.write(points.map((p) => '${p.lon},${p.lat}').join('|'));
    if (nogos.isNotEmpty) {
      sb.write('&nogos=');
      sb.write(
        nogos
            .map(
              (n) =>
                  '${n.center.lon},${n.center.lat},${n.radiusMeters}${n.weight == null ? '' : ',${n.weight}'}',
            )
            .join('|'),
      );
    }
    sb.write('&profile=$profile');
    sb.write('&alternativeidx=$alternativeIdx');
    sb.write('&format=geojson');
    if (roundTrip) sb.write('&engineMode=4');
    if (roundTripDistance != null) {
      sb.write('&roundTripDistance=$roundTripDistance');
    }
    if (direction != null) sb.write('&direction=$direction');
    if (roundTripDirectionAdd != null) {
      sb.write('&roundTripDirectionAdd=$roundTripDirectionAdd');
    }
    if (roundTripPoints != null) sb.write('&roundTripPoints=$roundTripPoints');
    if (allowSamewayback) sb.write('&allowSamewayback=1');
    if (turnInstructionMode != null) sb.write('&timode=$turnInstructionMode');
    for (final e in profileParams.entries) {
      sb.write('&profile:${e.key}=${e.value}');
    }
    return sb.toString();
  }
}

/// A routing failure: the message upstream's server would return with
/// `400 Bad Request` (`RoutingEngine.getErrorMessage()`).
class RoutingException implements Exception {
  RoutingException(this.message);

  final String message;

  @override
  String toString() => 'RoutingException: $message';
}

/// The result of a routing request: the GeoJSON body byte-identical to
/// upstream's `format=geojson` response plus the parsed essentials.
class RoutingResult {
  RoutingResult._(this.geojson, this._props, this.coordinates);

  /// The `FormatJson` output.
  final String geojson;
  final Map<String, dynamic> _props;

  /// `[lon, lat, elevation?]` per track point.
  final List<List<double>> coordinates;

  int get trackLength => int.parse(_props['track-length'] as String);
  int get filteredAscend => int.parse(_props['filtered ascend'] as String);
  int get plainAscend => int.parse(_props['plain-ascend'] as String);
  int get totalTimeSeconds => int.parse(_props['total-time'] as String);
  int get totalEnergy => int.parse(_props['total-energy'] as String);
  int get cost => int.parse(_props['cost'] as String);

  /// The `messages` rows (the first row is the header).
  List<List<String>> get messages => (_props['messages'] as List)
      .map((r) => (r as List).cast<String>())
      .toList();

  /// Cumulative travel time per track point (absent when the total is 0).
  List<double> get times => ((_props['times'] as List?) ?? const [])
      .map((t) => (t as num).toDouble())
      .toList();

  static RoutingResult parse(String geojson) {
    final doc = jsonDecode(geojson) as Map<String, dynamic>;
    final feature = (doc['features'] as List).first as Map<String, dynamic>;
    final props = feature['properties'] as Map<String, dynamic>;
    final coords =
        ((feature['geometry'] as Map<String, dynamic>)['coordinates'] as List)
            .map((c) => (c as List).map((v) => (v as num).toDouble()).toList())
            .toList();
    return RoutingResult._(geojson, props, coords);
  }
}

/// The ported BRouter: rd5 tiles from [segmentsDir], `.brf` profiles and
/// `lookups.dat` from [profilesDir].
class BRouter {
  BRouter({required this.segmentsDir, required this.profilesDir});

  final Directory segmentsDir;
  final Directory profilesDir;

  /// `RouteServer.getMaxRunningTime()` for [routeQuery]: 0 disables the
  /// timeout like the oracle's `-DmaxRunningTime=0`.
  int maxRunningTimeMillis = 0;

  /// `RoutingContext.memoryclass` of the server handler.
  int memoryclass = 128;

  /// Awaited every ~2000 node expansions of a search when set (see
  /// `RoutingEngine.yieldHook`).
  Future<void> Function()? yieldHook;

  /// Node expansions between two calls of [yieldHook]/[progressListener].
  int yieldInterval = 2000;
  void Function(int linksProcessed, int openSetSize)? progressListener;

  /// The engine of the request in progress (for `terminate()`).
  RoutingEngine? currentEngine;

  Future<RoutingResult> route(RoutingRequest request) async {
    final body = await routeQuery(
      request.toQuery(),
      maxRunningTimeMillis: request.maxRunningTimeMillis,
    );
    return RoutingResult.parse(body);
  }

  /// Runs a request exactly like `RouteServer.run` + `ServerHandler`: the
  /// query string (`lonlats=...&profile=...&format=geojson...`, URL-encoded
  /// or not) is parsed with `RoutingParamCollector`, the profile is loaded
  /// through `ProfileCache` with `profileBaseDir` = [profilesDir], and the
  /// track is formatted in the requested `format` (geojson, gpx, kml, csv).
  /// Throws [RoutingException] with the engine's error message.
  Future<String> routeQuery(String query, {int? maxRunningTimeMillis}) async {
    final url = query.startsWith('/') ? query : '/brouter?$query';
    final routingParamCollector = RoutingParamCollector();
    final params = routingParamCollector.getUrlParams(url);
    if (!params.containsKey('lonlats') || !params.containsKey('profile')) {
      throw RoutingException('lonlats and profile parameters are required');
    }

    ProfileCache.profileBaseDir = profilesDir.path;

    // ServerHandler.readRoutingContext
    final rc = RoutingContext();
    rc.memoryclass = memoryclass;
    rc.localFunction = params.get('profile')!;

    final wplist = routingParamCollector.getWayPointList(params.get('lonlats'));
    params.remove('profile');
    var engineMode = 0;
    if (params.containsKey('engineMode')) {
      engineMode = javaParseInt(params.get('engineMode')!);
    }
    routingParamCollector.setParams(rc, wplist, params);

    final cr = RoutingEngine(null, null, segmentsDir, wplist, rc, engineMode);
    cr.quite = true;
    cr.yieldHook = yieldHook;
    cr.yieldInterval = yieldInterval;
    cr.progressListener = progressListener;
    currentEngine = cr;
    try {
      await cr.doRun(maxRunningTimeMillis ?? this.maxRunningTimeMillis);
    } finally {
      currentEngine = null;
    }

    if (cr.getErrorMessage() != null) {
      throw RoutingException(cr.getErrorMessage()!);
    }
    if (engineMode == RoutingEngine.brouterEngineModeGetElev ||
        engineMode == RoutingEngine.brouterEngineModeGetInfo) {
      return cr.getFoundInfo() ?? '';
    }
    final track = cr.getFoundTrack();
    return _formatTrack(rc, params, track);
  }

  /// `ServerHandler.formatTrack`.
  static String _formatTrack(
    RoutingContext rc,
    JavaHashMap<String, String> params,
    OsmTrack track,
  ) {
    final format = params.get('format');
    final trackName = _trackName(params.get('trackname'));
    if (trackName != null) {
      track.name = trackName;
    }
    var exportWaypointsStr = params.get('exportWaypoints');
    if (exportWaypointsStr != null && javaParseInt(exportWaypointsStr) != 0) {
      track.exportWaypoints = true;
    }
    exportWaypointsStr = params.get('exportCorrectedWaypoints');
    if (exportWaypointsStr != null && javaParseInt(exportWaypointsStr) != 0) {
      track.exportCorrectedWaypoints = true;
    }

    if (format == null || 'gpx' == format) {
      return FormatGpx(rc).format(track);
    } else if ('kml' == format) {
      return FormatKml(rc).format(track);
    } else if ('geojson' == format) {
      return FormatJson(rc).format(track);
    } else if ('csv' == format) {
      return FormatCsv(rc).format(track);
    } else {
      // unknown track format, using default
      return FormatGpx(rc).format(track);
    }
  }

  static String? _trackName(String? s) =>
      s?.replaceAll(RegExp(r'[^a-zA-Z0-9 \._\-]+'), '');
}
