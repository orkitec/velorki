import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// What a weather layer shows: where it rains now, or the clouds.
enum WeatherKind { radar, clouds }

/// How a source's tile URL names the moment it shows.
enum WeatherTimeFormat {
  /// The URL names no moment: the service serves its latest image.
  none,

  /// `{time}` as `YYYY-MM-DDTHH:MM:00.000Z`, in UTC.
  iso,

  /// `{timeMs}` as milliseconds since the epoch.
  epochMs,
}

/// A frame the map can ask a source for: [time] in UTC, or `null` for the
/// service's latest image, which names no moment.
@immutable
class WeatherFrame {
  /// Creates the frame.
  const WeatherFrame(this.time);

  /// The moment shown, UTC; `null` for "the latest".
  final DateTime? time;

  @override
  bool operator ==(Object other) => other is WeatherFrame && other.time == time;

  @override
  int get hashCode => time.hashCode;

  @override
  String toString() => 'WeatherFrame(${time?.toIso8601String() ?? 'latest'})';
}

/// One public service the map loads radar or cloud tiles from, straight
/// from the phone.
///
/// Radar comes as tiles: the URL is a MapLibre tile template, `{z}`/`{x}`/
/// `{y}` for a tile pyramid, `{bbox-epsg-3857}` for a WMS or ArcGIS service
/// that renders a box. Clouds come as one image per [coverage] box: the URL
/// is a WMS GetMap with `{bbox-epsg-3857}`, `{width}` and `{height}`, which
/// the app fetches itself and turns into white cloud on a clear ground
/// (see `weather_cloud_images.dart`). Either names its moment with
/// `{time}` or `{timeMs}` ([timeFormat]).
@immutable
class WeatherMapSource {
  /// Creates a source.
  const WeatherMapSource({
    required this.id,
    required this.kind,
    required this.urlTemplate,
    required this.coverage,
    required this.attribution,
    this.tileSize = 256,
    this.minZoom = 0,
    this.maxZoom = 10,
    this.timeFormat = WeatherTimeFormat.none,
    this.stepMinutes = 5,
    this.delayMinutes = 5,
    this.historyMinutes = 120,
    this.forecastMinutes = 0,
    this.opacity,
    this.enabled = true,
  });

  /// Stable name, which the mirror's override refers to.
  final String id;

  /// Radar or clouds.
  final WeatherKind kind;

  /// The tile URL template.
  final String urlTemplate;

  /// Tile size in pixels.
  final int tileSize;

  /// Where the service has data, as lon/lat boxes; the layer is only added
  /// while the view meets one of them.
  final List<BoundingBox> coverage;

  /// The zooms the service serves; MapLibre overzooms beyond [maxZoom].
  final int minZoom;
  final int maxZoom;

  /// How the URL names the moment.
  final WeatherTimeFormat timeFormat;

  /// The grid the service's images lie on, in minutes.
  final int stepMinutes;

  /// How old an image has to be before it is asked for, in minutes: the
  /// newest one is still being made, or not ours to take (see
  /// [eumetsatClouds]).
  final int delayMinutes;

  /// How far back the service keeps images, in minutes.
  final int historyMinutes;

  /// How far ahead it forecasts, in minutes; 0 for none.
  final int forecastMinutes;

  /// The credit shown while the layer is drawn; `{year}` is the year of the
  /// image.
  final String attribution;

  /// The layer's opacity, overriding the kind's default.
  final double? opacity;

  /// Whether the source is used at all; a fork or the mirror can switch one
  /// off.
  final bool enabled;

  /// The frame shown [offsetMinutes] from now: the latest image on the
  /// source's grid at least [delayMinutes] old, moved by the offset; `null`
  /// where the source has nothing for that moment (a forecast it does not
  /// make, a past it does not keep).
  ///
  /// A source that names no moment shows its latest image, now only.
  WeatherFrame? frameAt(DateTime now, {int offsetMinutes = 0}) {
    if (offsetMinutes > forecastMinutes) return null;
    if (-offsetMinutes > historyMinutes) return null;
    if (timeFormat == WeatherTimeFormat.none) {
      return offsetMinutes == 0 ? const WeatherFrame(null) : null;
    }
    return WeatherFrame(
      latestFrameTime(
        now,
        stepMinutes: stepMinutes,
        delayMinutes: delayMinutes,
      ).add(Duration(minutes: offsetMinutes)),
    );
  }

  /// The tile URL template with [frame]'s moment filled in; `{z}`, `{x}`,
  /// `{y}` and `{bbox-epsg-3857}` stay for MapLibre.
  String tileUrl(WeatherFrame frame) {
    final time = frame.time;
    if (time == null) return urlTemplate;
    return urlTemplate
        .replaceAll('{time}', formatWeatherTime(time))
        .replaceAll('{timeMs}', '${time.toUtc().millisecondsSinceEpoch}');
  }

  /// One concrete tile URL: the tile at [zoom] holding [point], for a probe
  /// of whether the service answers.
  String probeUrl(WeatherFrame frame, LatLng point, int zoom) {
    final z = zoom.clamp(minZoom, maxZoom);
    final (x, y) = tileOf(point, z);
    return tileUrl(frame)
        .replaceAll('{z}', '$z')
        .replaceAll('{x}', '$x')
        .replaceAll('{y}', '$y')
        .replaceAll('{bbox-epsg-3857}', tileBboxEpsg3857(x, y, z));
  }

  /// The GetMap URL of coverage box [region] as one image at [frame]: the
  /// box in Web Mercator, about [cloudMetresPerPixel] a pixel, at most
  /// [cloudImageMaxSide] pixels on its long side.
  String regionImageUrl(WeatherFrame frame, int region) {
    final box = coverage[region];
    final (width, height) = cloudImageSize(box);
    return tileUrl(frame)
        .replaceAll('{bbox-epsg-3857}', mercatorBboxString(box))
        .replaceAll('{width}', '$width')
        .replaceAll('{height}', '$height');
  }

  /// The credit for [frame].
  String attributionFor(WeatherFrame frame, DateTime now) =>
      attribution.replaceAll('{year}', '${(frame.time ?? now).toUtc().year}');

  /// Whether [view] meets the source's coverage. A view across the
  /// antimeridian (west east of east) is taken as its two halves.
  bool covers(BoundingBox view) {
    final parts = view.west <= view.east
        ? <BoundingBox>[view]
        : <BoundingBox>[
            BoundingBox(
              south: view.south,
              west: view.west,
              north: view.north,
              east: 180,
            ),
            BoundingBox(
              south: view.south,
              west: -180,
              north: view.north,
              east: view.east,
            ),
          ];
    return coverage.any((box) => parts.any(box.intersects));
  }

  /// The box MapLibre is told to keep its requests in: the coverage's
  /// union, or `null` (no limit) when that would span most of the world.
  List<double>? get requestBounds {
    if (coverage.isEmpty) return null;
    final all = coverage.reduce((a, b) => a.union(b));
    if (all.lonSpan > 300) return null;
    return <double>[
      all.west,
      math.max(all.south, -85.051129),
      all.east,
      math.min(all.north, 85.051129),
    ];
  }

  /// A copy with the fields an override names replaced.
  WeatherMapSource copyWith({
    WeatherKind? kind,
    String? urlTemplate,
    int? tileSize,
    List<BoundingBox>? coverage,
    int? minZoom,
    int? maxZoom,
    WeatherTimeFormat? timeFormat,
    int? stepMinutes,
    int? delayMinutes,
    int? historyMinutes,
    int? forecastMinutes,
    String? attribution,
    double? opacity,
    bool? enabled,
  }) => WeatherMapSource(
    id: id,
    kind: kind ?? this.kind,
    urlTemplate: urlTemplate ?? this.urlTemplate,
    tileSize: tileSize ?? this.tileSize,
    coverage: coverage ?? this.coverage,
    minZoom: minZoom ?? this.minZoom,
    maxZoom: maxZoom ?? this.maxZoom,
    timeFormat: timeFormat ?? this.timeFormat,
    stepMinutes: stepMinutes ?? this.stepMinutes,
    delayMinutes: delayMinutes ?? this.delayMinutes,
    historyMinutes: historyMinutes ?? this.historyMinutes,
    forecastMinutes: forecastMinutes ?? this.forecastMinutes,
    attribution: attribution ?? this.attribution,
    opacity: opacity ?? this.opacity,
    enabled: enabled ?? this.enabled,
  );

  @override
  bool operator ==(Object other) =>
      other is WeatherMapSource &&
      other.id == id &&
      other.kind == kind &&
      other.urlTemplate == urlTemplate &&
      other.tileSize == tileSize &&
      listEquals(other.coverage, coverage) &&
      other.minZoom == minZoom &&
      other.maxZoom == maxZoom &&
      other.timeFormat == timeFormat &&
      other.stepMinutes == stepMinutes &&
      other.delayMinutes == delayMinutes &&
      other.historyMinutes == historyMinutes &&
      other.forecastMinutes == forecastMinutes &&
      other.attribution == attribution &&
      other.opacity == opacity &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    urlTemplate,
    tileSize,
    Object.hashAll(coverage),
    minZoom,
    maxZoom,
    timeFormat,
    stepMinutes,
    delayMinutes,
    historyMinutes,
    forecastMinutes,
    attribution,
    opacity,
    enabled,
  );

  @override
  String toString() => 'WeatherMapSource($id, ${kind.name}, enabled: $enabled)';
}

/// The newest moment on a [stepMinutes] grid that is at least
/// [delayMinutes] before [now], in UTC.
DateTime latestFrameTime(
  DateTime now, {
  required int stepMinutes,
  required int delayMinutes,
}) {
  final step = math.max(1, stepMinutes) * Duration.millisecondsPerMinute;
  final ms =
      now.toUtc().millisecondsSinceEpoch -
      delayMinutes * Duration.millisecondsPerMinute;
  return DateTime.fromMillisecondsSinceEpoch(ms - ms % step, isUtc: true);
}

/// [time] as the services want it: `YYYY-MM-DDTHH:MM:00.000Z`.
String formatWeatherTime(DateTime time) {
  final t = time.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year.toString().padLeft(4, '0')}-${two(t.month)}-${two(t.day)}'
      'T${two(t.hour)}:${two(t.minute)}:00.000Z';
}

/// The slippy-map tile at [zoom] that holds [point].
(int, int) tileOf(LatLng point, int zoom) {
  final n = 1 << zoom;
  final lat = point.lat.clamp(-85.0511, 85.0511) * math.pi / 180;
  final x = ((point.lon + 180) / 360 * n).floor().clamp(0, n - 1);
  final y =
      ((1 - math.log(math.tan(lat) + 1 / math.cos(lat)) / math.pi) / 2 * n)
          .floor()
          .clamp(0, n - 1);
  return (x, y);
}

/// The Web Mercator box of tile [x]/[y] at [zoom], `minx,miny,maxx,maxy`,
/// as MapLibre fills `{bbox-epsg-3857}`.
String tileBboxEpsg3857(int x, int y, int zoom) {
  const origin = 20037508.342789244;
  final size = 2 * origin / (1 << zoom);
  final minX = -origin + x * size;
  final maxY = origin - y * size;
  String f(double v) => v.toStringAsFixed(6);
  return '${f(minX)},${f(maxY - size)},${f(minX + size)},${f(maxY)}';
}

/// How many Web Mercator metres one pixel of a cloud image spans.
const double cloudMetresPerPixel = 3000;

/// The longest side of a cloud image, in pixels.
const int cloudImageMaxSide = 2048;

/// The Web Mercator x of [lon] and y of [lat], in metres.
double mercatorX(double lon) => lon * 20037508.342789244 / 180;

double mercatorY(double lat) {
  final clamped = lat.clamp(-85.051129, 85.051129) * math.pi / 180;
  return math.log(math.tan(math.pi / 4 + clamped / 2)) * 6378137.0;
}

/// [box] in Web Mercator, `minx,miny,maxx,maxy`.
String mercatorBboxString(BoundingBox box) {
  String f(double v) => v.toStringAsFixed(1);
  return '${f(mercatorX(box.west))},${f(mercatorY(box.south))},'
      '${f(mercatorX(box.east))},${f(mercatorY(box.north))}';
}

/// The pixel size of the image of [box]: [metresPerPixel] Web Mercator
/// metres a pixel, scaled down to [maxSide] on the long side, the box's
/// aspect kept.
(int, int) cloudImageSize(
  BoundingBox box, {
  double metresPerPixel = cloudMetresPerPixel,
  int maxSide = cloudImageMaxSide,
}) {
  final w = (mercatorX(box.east) - mercatorX(box.west)) / metresPerPixel;
  final h = (mercatorY(box.north) - mercatorY(box.south)) / metresPerPixel;
  final scale = math.min(1.0, maxSide / math.max(w, h));
  return (math.max(1, (w * scale).round()), math.max(1, (h * scale).round()));
}

BoundingBox _box(double west, double south, double east, double north) =>
    BoundingBox(south: south, west: west, north: north, east: east);

/// Rain radar over Germany and its borders, from the Deutscher
/// Wetterdienst: five-minute frames from about three days back to two
/// hours ahead (the nowcast).
final WeatherMapSource dwdRadar = WeatherMapSource(
  id: 'radar_dwd',
  kind: WeatherKind.radar,
  urlTemplate:
      'https://maps.dwd.de/geoserver/dwd/wms?service=WMS&version=1.3.0'
      '&request=GetMap&layers=dwd:Niederschlagsradar&styles=&crs=EPSG:3857'
      '&bbox={bbox-epsg-3857}&width=256&height=256&format=image/png'
      '&transparent=true&time={time}',
  coverage: <BoundingBox>[_box(1.5, 45, 19, 56.5)],
  maxZoom: 10,
  timeFormat: WeatherTimeFormat.iso,
  forecastMinutes: 120,
  attribution: 'Radar: Deutscher Wetterdienst (CC BY 4.0)',
);

/// Base reflectivity over the US from the National Weather Service: the
/// past two hours, no forecast.
final WeatherMapSource noaaRadar = WeatherMapSource(
  id: 'radar_noaa',
  kind: WeatherKind.radar,
  urlTemplate:
      'https://mapservices.weather.noaa.gov/eventdriven/rest/services/radar/'
      'radar_base_reflectivity_time/ImageServer/exportImage'
      '?bbox={bbox-epsg-3857}&bboxSR=3857&imageSR=3857&size=256,256'
      '&format=png&transparent=true&time={timeMs}&f=image',
  coverage: <BoundingBox>[
    _box(-126, 24, -66, 50), // the contiguous US
    _box(-170, 51, -129, 72), // Alaska
    _box(-161, 18.5, -154, 22.5), // Hawaii
    _box(-67.5, 17.8, -65.2, 18.6), // Puerto Rico
  ],
  maxZoom: 10,
  timeFormat: WeatherTimeFormat.epochMs,
  attribution: 'Radar: NOAA National Weather Service',
);

/// The NASA GIBS map service the GOES clouds come from: one GetMap for a
/// whole region. `TIME=default` is the latest image, which the URL cannot
/// name, so a region is fetched again with every refresh.
String _gibsGoes(String layer) =>
    'https://gibs.earthdata.nasa.gov/wms/epsg3857/best/wms.cgi?SERVICE=WMS'
    '&REQUEST=GetMap&VERSION=1.3.0&LAYERS=$layer&STYLES=&FORMAT=image/png'
    '&TRANSPARENT=TRUE&CRS=EPSG:3857&BBOX={bbox-epsg-3857}'
    '&WIDTH={width}&HEIGHT={height}&TIME=default';

/// Infrared clouds over the eastern Americas, GOES-East through NASA GIBS:
/// the latest image only.
final WeatherMapSource goesEastClouds = WeatherMapSource(
  id: 'clouds_goes_east',
  kind: WeatherKind.clouds,
  urlTemplate: _gibsGoes('GOES-East_ABI_Band13_Clean_Infrared'),
  coverage: <BoundingBox>[_box(-115, -60, -20, 60)],
  maxZoom: 6,
  attribution: 'Clouds: NOAA GOES via NASA GIBS',
);

/// The same over the western Americas and the Pacific, GOES-West.
final WeatherMapSource goesWestClouds = WeatherMapSource(
  id: 'clouds_goes_west',
  kind: WeatherKind.clouds,
  urlTemplate: _gibsGoes('GOES-West_ABI_Band13_Clean_Infrared'),
  coverage: <BoundingBox>[_box(-180, -60, -115, 60), _box(165, -60, 180, 60)],
  maxZoom: 6,
  attribution: 'Clouds: NOAA GOES via NASA GIBS',
);

/// Infrared clouds over Europe, Africa and around from Meteosat
/// (EUMETSAT), hourly.
///
/// Full hours only, and never the newest image: under the EUMETSAT Data
/// Policy the hourly Level 1 images are Core data, free under CC BY 4.0,
/// while the images between the hours and any image under an hour old are
/// a paid licence. So the URL always names a full UTC hour at least 20
/// minutes old (a step of 60 and a delay of 20 below), and never leaves
/// `time` out: without it the service hands out its newest ten-minute
/// image. [enforceWeatherLicences] keeps an override from undoing this.
final WeatherMapSource eumetsatClouds = WeatherMapSource(
  id: 'clouds_eumetsat',
  kind: WeatherKind.clouds,
  urlTemplate:
      'https://view.eumetsat.int/geoserver/ows?service=WMS&version=1.3.0'
      '&request=GetMap&layers=mtg_fd:ir105_hrfi&styles=&crs=EPSG:3857'
      '&bbox={bbox-epsg-3857}&width={width}&height={height}'
      '&format=image/png&transparent=true&time={time}',
  coverage: <BoundingBox>[_box(-30, 25, 45, 75)],
  maxZoom: 8,
  timeFormat: WeatherTimeFormat.iso,
  stepMinutes: 60,
  delayMinutes: 20,
  historyMinutes: 0,
  attribution: 'Clouds: Contains modified EUMETSAT Meteosat data {year}',
);

/// The sources a build ships with, before the mirror's override.
final List<WeatherMapSource> defaultWeatherMapSources = <WeatherMapSource>[
  dwdRadar,
  noaaRadar,
  goesEastClouds,
  goesWestClouds,
  eumetsatClouds,
];

/// The host whose images may only be taken on the full hour; see
/// [eumetsatClouds].
const String _eumetsatHost = 'view.eumetsat.int';

/// [sources] with every source on the EUMETSAT host held to full hours at
/// least 20 minutes old with the moment in the URL; one whose URL names no
/// moment is switched off.
List<WeatherMapSource> enforceWeatherLicences(List<WeatherMapSource> sources) =>
    <WeatherMapSource>[
      for (final source in sources)
        if (Uri.tryParse(source.urlTemplate)?.host != _eumetsatHost)
          source
        else if (!source.urlTemplate.contains('{time}'))
          source.copyWith(enabled: false)
        else
          source.copyWith(
            timeFormat: WeatherTimeFormat.iso,
            stepMinutes: 60,
            delayMinutes: math.max(20, source.delayMinutes),
            historyMinutes: 0,
            forecastMinutes: 0,
          ),
    ];

/// The sources after the mirror's `weatherLayers` [override]: an entry
/// with a known `id` replaces the fields it names (`enabled: false` turns
/// that source off); a full entry with a new `id` adds a source. Entries
/// that cannot be read are skipped; an [override] that is not a list
/// leaves [defaults] as they are.
List<WeatherMapSource> applyWeatherOverride(
  List<WeatherMapSource> defaults,
  Object? override,
) {
  if (override is! List) return enforceWeatherLicences(defaults);
  final out = <String, WeatherMapSource>{
    for (final source in defaults) source.id: source,
  };
  for (final row in override) {
    if (row is! Map) continue;
    final id = row['id'];
    if (id is! String || id.isEmpty) continue;
    try {
      final known = out[id];
      final parsed = known == null
          ? _parseNew(id, row)
          : _parseOver(known, row);
      if (parsed != null) out[id] = parsed;
    } on Object {
      // A malformed entry is left out; the rest still applies.
    }
  }
  return enforceWeatherLicences(out.values.toList());
}

/// The override as stored: the list itself, encoded, or `null` when
/// [pointer] carries none that reads.
String? encodeWeatherOverride(Object? override) =>
    override is List ? jsonEncode(override) : null;

/// The stored override back, `null` when it does not decode.
Object? decodeWeatherOverride(String? stored) {
  if (stored == null) return null;
  try {
    return jsonDecode(stored);
  } on FormatException {
    return null;
  }
}

WeatherMapSource? _parseNew(String id, Map<Object?, Object?> row) {
  final kind = _kind(row['kind']);
  final url = _str(row['url']);
  final coverage = _coverage(row['coverage']);
  final attribution = _str(row['attribution']);
  if (kind == null || url == null || coverage == null || attribution == null) {
    return null;
  }
  return _parseOver(
    WeatherMapSource(
      id: id,
      kind: kind,
      urlTemplate: url,
      coverage: coverage,
      attribution: attribution,
    ),
    row,
  );
}

WeatherMapSource? _parseOver(WeatherMapSource base, Map<Object?, Object?> row) {
  final url = _str(row['url']);
  if (url != null && !url.startsWith('https://')) return null;
  return base.copyWith(
    kind: _kind(row['kind']),
    urlTemplate: url,
    tileSize: _int(row['tileSize']),
    coverage: _coverage(row['coverage']),
    minZoom: _int(row['minzoom']),
    maxZoom: _int(row['maxzoom']),
    timeFormat: _timeFormat(row['time']),
    stepMinutes: _int(row['stepMinutes']),
    delayMinutes: _int(row['delayMinutes']),
    historyMinutes: _int(row['historyMinutes']),
    forecastMinutes: _int(row['forecastMinutes']),
    attribution: _str(row['attribution']),
    opacity: _num(row['opacity'])?.clamp(0.0, 1.0),
    enabled: row['enabled'] is bool ? row['enabled']! as bool : null,
  );
}

String? _str(Object? v) => v is String && v.trim().isNotEmpty ? v : null;

int? _int(Object? v) => v is num && v >= 0 ? v.toInt() : null;

double? _num(Object? v) => v is num ? v.toDouble() : null;

WeatherKind? _kind(Object? v) => switch (v) {
  'radar' => WeatherKind.radar,
  'clouds' => WeatherKind.clouds,
  _ => null,
};

WeatherTimeFormat? _timeFormat(Object? v) => switch (v) {
  'none' => WeatherTimeFormat.none,
  'iso' => WeatherTimeFormat.iso,
  'epochMs' => WeatherTimeFormat.epochMs,
  _ => null,
};

/// `[[west, south, east, north], ...]`.
List<BoundingBox>? _coverage(Object? v) {
  if (v is! List || v.isEmpty) return null;
  final out = <BoundingBox>[];
  for (final row in v) {
    if (row is! List || row.length != 4 || row.any((e) => e is! num)) {
      return null;
    }
    final [w, s, e, n] = <double>[for (final c in row) (c as num).toDouble()];
    if (w > e || s > n) return null;
    out.add(_box(w, s, e, n));
  }
  return out;
}

/// How far the radar's time control reaches back and ahead, in minutes,
/// and its step.
const int weatherRadarRangeMinutes = 120;
const int weatherRadarStepMinutes = 15;

/// The offsets the time control offers, from two hours back to two ahead.
List<int> get weatherRadarOffsets => <int>[
  for (
    var m = -weatherRadarRangeMinutes;
    m <= weatherRadarRangeMinutes;
    m += weatherRadarStepMinutes
  )
    m,
];

/// The control's slider position for [offsetMinutes] and back.
int weatherSliderIndexOf(int offsetMinutes) =>
    (offsetMinutes.clamp(-weatherRadarRangeMinutes, weatherRadarRangeMinutes) +
        weatherRadarRangeMinutes) ~/
    weatherRadarStepMinutes;

int weatherOffsetOfSliderIndex(int index) =>
    index * weatherRadarStepMinutes - weatherRadarRangeMinutes;

/// One weather layer the map is asked to draw: a source's radar tiles for
/// one frame ([tiles]), or one region of a source's clouds as one image
/// ([image] over [imageBox]). A new [frameKey] under the same [id] is a new
/// frame, which the map swaps in without a gap.
@immutable
class WeatherLayer {
  /// A layer of tiles.
  const WeatherLayer.tiles({
    required this.id,
    required this.kind,
    required String this.tiles,
    required this.attribution,
    this.tileSize = 256,
    this.minZoom = 0,
    this.maxZoom = 10,
    this.bounds,
    this.opacity,
  }) : image = null,
       imageBox = null,
       frameKey = tiles;

  /// A layer of one image over [imageBox].
  const WeatherLayer.image({
    required this.id,
    required this.kind,
    required Uint8List this.image,
    required BoundingBox this.imageBox,
    required this.frameKey,
    required this.attribution,
    this.opacity,
  }) : tiles = null,
       tileSize = 256,
       minZoom = 0,
       maxZoom = 22,
       bounds = null;

  /// Radar [source] at [frame], as tiles.
  factory WeatherLayer.ofRadar(
    WeatherMapSource source,
    WeatherFrame frame,
    DateTime now,
  ) => WeatherLayer.tiles(
    id: source.id,
    kind: source.kind,
    tiles: source.tileUrl(frame),
    attribution: source.attributionFor(frame, now),
    tileSize: source.tileSize,
    minZoom: source.minZoom,
    maxZoom: source.maxZoom,
    bounds: source.requestBounds,
    opacity: source.opacity,
  );

  /// Which layer this is: the source's id, with the region's number for an
  /// image.
  final String id;
  final WeatherKind kind;

  /// What tells one frame from the next: the tile URL, or the source,
  /// region and moment of an image.
  final String frameKey;

  /// The tile URL template, for tiles.
  final String? tiles;

  /// The PNG, for an image.
  final Uint8List? image;

  /// Where the image lies.
  final BoundingBox? imageBox;

  /// The credit shown while the layer is drawn.
  final String attribution;
  final int tileSize;
  final int minZoom;
  final int maxZoom;

  /// `[west, south, east, north]` MapLibre keeps its tile requests in.
  final List<double>? bounds;

  /// The opacity, overriding the kind's default.
  final double? opacity;

  @override
  bool operator ==(Object other) =>
      other is WeatherLayer &&
      other.id == id &&
      other.kind == kind &&
      other.frameKey == frameKey &&
      other.attribution == attribution &&
      other.tileSize == tileSize &&
      other.minZoom == minZoom &&
      other.maxZoom == maxZoom &&
      other.imageBox == imageBox &&
      listEquals(other.bounds, bounds) &&
      other.opacity == opacity;

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    frameKey,
    attribution,
    tileSize,
    minZoom,
    maxZoom,
    imageBox,
    bounds == null ? null : Object.hashAll(bounds!),
    opacity,
  );

  @override
  String toString() => 'WeatherLayer($id, $frameKey)';
}
