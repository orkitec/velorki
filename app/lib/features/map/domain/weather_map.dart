import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'wind_field.dart';

/// What a weather layer shows: the rain (measured, estimated or
/// forecast; the "Rain radar" switch), the clouds, or the wind (a model's,
/// drawn as arrows; see `wind_field.dart`).
enum WeatherKind { radar, clouds, wind }

/// Where a rain source's picture of the rain comes from.
enum RainRole {
  /// A weather radar: measured, and for the DWD also its two-hour nowcast.
  radar,

  /// A satellite's estimate, where no radar reaches; the present only.
  satellite,

  /// A weather model's forecast, for the moments ahead.
  model,
}

/// Which legend the colours of a rain image are read by when it is drawn
/// soft (see `rainLegendOf`), and what of it is no rain at all.
enum RainPalette {
  /// The DWD radar's legend, mm an hour from cyan through green, yellow and
  /// red to purple and blue, grey for no data. It serves the DWD's nowcast.
  dwd,

  /// NOAA's reflectivity ramp: grey-blue, cyan, green, yellow, red.
  noaa,

  /// The H SAF satellite rain: light green, greens, blues, purples.
  hsaf,

  /// The DWD's six-hour precipitation scale for the global ICON forecast,
  /// recoloured into the DWD radar's legend at the mean rate per hour.
  dwdModel6h,

  /// ICON-EU's hourly rain drawn in the radar's style, whose thresholds
  /// are mm in ten minutes, recoloured into the radar's legend at the rate
  /// the model actually gives.
  dwdModel1h,

  /// The Iowa Environmental Mesonet's NEXRAD reflectivity ramp (N0Q), half
  /// a dBZ a colour, which its HRRR forecast is drawn in.
  n0q,

  /// The KNMI radar's blue ramp, white-blue for 0.1 mm an hour to violet
  /// for 100, on a log scale.
  knmi,

  /// The FMI radar's rain rate ramp: cyan, greens, yellow, orange, red,
  /// purple; grey for no data.
  fmi,
}

/// How the rain radar is drawn, chosen under Settings → Appearance.
enum RadarStyle {
  /// One image of the view, smoothed on the phone: soft edges, light rain
  /// fainter than heavy (see `softenRainPixels`).
  soft,

  /// The service's tiles as delivered, its cells sharp.
  measured;

  /// The style named [name], or [soft] when the name is unknown.
  static RadarStyle fromName(String? name) =>
      RadarStyle.values.firstWhere((s) => s.name == name, orElse: () => soft);
}

/// How a source's tile URL names the moment it shows.
enum WeatherTimeFormat {
  /// The URL names no moment: the service serves its latest image.
  none,

  /// `{time}` as `YYYY-MM-DDTHH:MM:00.000Z`, in UTC.
  iso,

  /// `{timeMs}` as milliseconds since the epoch.
  epochMs,

  /// A model's run and the minutes from it: `{run}` as `YYYYMMDDHHMI` and
  /// `{runMinute}` as four digits, in UTC. The run is the newest the
  /// service names ([WeatherMapSource.timesUrl], [parseModelRunTime]);
  /// without it the source has no frame.
  modelRun,
}

/// A frame the map can ask a source for: [time] in UTC, or `null` for the
/// service's latest image, which names no moment; for a model named by its
/// run ([WeatherTimeFormat.modelRun]) also the [run] it comes from.
@immutable
class WeatherFrame {
  /// Creates the frame.
  const WeatherFrame(this.time, {this.run});

  /// The moment shown, UTC; `null` for "the latest".
  final DateTime? time;

  /// The model run the frame is from, UTC; `null` where the URL names none.
  final DateTime? run;

  @override
  bool operator ==(Object other) =>
      other is WeatherFrame && other.time == time && other.run == run;

  @override
  int get hashCode => Object.hash(time, run);

  @override
  String toString() =>
      'WeatherFrame(${time?.toIso8601String() ?? 'latest'}'
      '${run == null ? '' : ', run ${run!.toIso8601String()}'})';
}

/// One public service the map loads radar or cloud tiles from, straight
/// from the phone.
///
/// Radar comes as tiles: the URL is a MapLibre tile template, `{z}`/`{x}`/
/// `{y}` for a tile pyramid, `{bbox-epsg-3857}` for a WMS or ArcGIS service
/// that renders a box. Clouds come as one image per [coverage] box, and
/// zoomed in a second, finer image of the view's surroundings
/// ([detailImageUrl]): the URL is a WMS GetMap with `{bbox-epsg-3857}`,
/// `{width}` and `{height}`, which the app fetches itself and turns into
/// white cloud on a clear ground (see `weather_fetcher.dart`). Either names
/// its moment with `{time}` or `{timeMs}` ([timeFormat]).
///
/// A radar drawn soft ([RadarStyle.soft]) is one image of the view as
/// well, from [imageUrlTemplate]; a radar without one stays on its tiles.
/// Where that names `{z}`, `{x}` and `{y}` ([imageFromTiles]) the image is
/// put together on the phone from the service's tiles ([tileMosaicOf]).
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
    this.nativeMetresPerPixel = 2000,
    this.cloudLuminance = defaultCloudLuminance,
    this.imageUrlTemplate,
    this.enabled = true,
    this.role = RainRole.radar,
    this.palette = RainPalette.dwd,
    this.reach,
    this.extent,
    this.timesUrl,
  });

  /// Stable name, which the mirror's override refers to.
  final String id;

  /// Radar or clouds.
  final WeatherKind kind;

  /// For rain: a radar, a satellite or a model. Rain sources are listed
  /// from the most trusted down; each leaves the [reachRings] of those
  /// before it that show the same moment to them (see [rainPartsAt]).
  final RainRole role;

  /// How the soft look reads the rain image's colours.
  final RainPalette palette;

  /// Where the source actually has data, as lon/lat rings, finer than its
  /// [coverage] boxes: a radar's reach. `null` for the coverage boxes.
  final List<List<LatLng>>? reach;

  /// The ring the service's image is drawn in, where it has one inside its
  /// [coverage] box: inside it a transparent pixel is measured dry, beyond
  /// it nothing is measured. A source with one tells where it measures by
  /// each frame it draws (its "no data" colour inside the ring), and the
  /// sources after it are cut by that frame (see `RainCoverage`) instead of
  /// by its fixed [reach], which stands in only where the frame cannot be
  /// had. `null` for none.
  final List<LatLng>? extent;

  /// Where the service tells the moments it has frames of: a WMS
  /// GetCapabilities request for the source's layer alone, whose time
  /// dimension names its newest frame ([parseWmsNewestTime]). The frames
  /// asked for are never newer than that ([frameAt]'s `newest`), since the
  /// service answers a moment past it with an error. `null` where the
  /// service is not asked: the frames follow the clock alone.
  final String? timesUrl;

  /// [reach], or the [coverage] boxes as rings.
  List<List<LatLng>> get reachRings =>
      reach ??
      <List<LatLng>>[
        for (final box in coverage)
          <LatLng>[
            LatLng(box.south, box.west),
            LatLng(box.south, box.east),
            LatLng(box.north, box.east),
            LatLng(box.north, box.west),
          ],
      ];

  /// Whether [point] lies where the source has data ([reachRings]).
  bool reaches(LatLng point) =>
      reachRings.any((ring) => ringContains(ring, point));

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

  /// How far ahead it forecasts, in minutes; 0 for none. For a model named
  /// by its run ([WeatherTimeFormat.modelRun]), from the run.
  final int forecastMinutes;

  /// The credit shown while the layer is drawn; `{year}` is the year of the
  /// image.
  final String attribution;

  /// The layer's opacity, overriding the kind's default.
  final double? opacity;

  /// How many Web Mercator metres one pixel of the service's own imagery
  /// spans, about: a cloud detail image is asked for at this resolution,
  /// not the screen's, so the service sends what it has and the map
  /// smooths it, instead of the service blowing its pixels up into blocks.
  final double nativeMetresPerPixel;

  /// For clouds, the luminance (0..255) of the service's grey at and below
  /// which a pixel is clear, and at and above which it is full cloud. Each
  /// satellite's service draws the same cold in its own grey, so each has
  /// its own: the same cloud comes out the same on either side of a seam.
  final ({double clear, double full}) cloudLuminance;

  /// A radar's request for one image of a box, for the soft look: like
  /// [urlTemplate], with `{bbox-epsg-3857}`, `{width}` and `{height}` to
  /// fill, or a tile template (`{z}`, `{x}`, `{y}`) the image is put
  /// together from ([imageFromTiles]); `null` where the service only serves
  /// tiles to the map.
  final String? imageUrlTemplate;

  /// Whether the image of a box is put together from tiles: an
  /// [imageUrlTemplate] with `{z}`, `{x}` and `{y}` (see [tileMosaicOf]).
  bool get imageFromTiles {
    final template = imageUrlTemplate;
    return template != null &&
        template.contains('{z}') &&
        template.contains('{x}') &&
        template.contains('{y}');
  }

  /// Whether the service serves tiles MapLibre can load itself: a tile
  /// template, not an image of a box of any size (`{width}` and
  /// `{height}`). A radar without them is drawn as an image in either look.
  bool get servesTiles =>
      !(urlTemplate.contains('{width}') && urlTemplate.contains('{height}'));

  /// Whether the source is used at all; a fork or the mirror can switch one
  /// off.
  final bool enabled;

  /// The frame shown [offsetMinutes] from now: the latest image on the
  /// source's grid at least [delayMinutes] old, moved by the offset; `null`
  /// where the source has nothing for that moment (a forecast it does not
  /// make, a past it does not keep).
  ///
  /// A source that names no moment shows its latest image, now only. A
  /// satellite shows the present only, and a model only the moments ahead
  /// ([modelFrameTime]).
  ///
  /// [newest] is the newest frame the service has, where it said
  /// ([timesUrl]): no frame is asked for past it, moved back onto the
  /// source's grid (for the Meteosat images the full hour). Without it the
  /// clock alone decides. For a model named by its run
  /// ([WeatherTimeFormat.modelRun]) it is the run, without which there is
  /// no frame ([runFrameAt]).
  WeatherFrame? frameAt(
    DateTime now, {
    int offsetMinutes = 0,
    DateTime? newest,
  }) {
    if (kind == WeatherKind.wind) {
      // The model's hourly frames: the hour the step falls in. With
      // [timesUrl], of the newest run, which [newest] is then (the frame
      // names no run before it is known, and the map asks for none).
      if (offsetMinutes < 0 || offsetMinutes > forecastMinutes) return null;
      return WeatherFrame(
        windFrameTime(now, offsetMinutes, forecastMinutes: forecastMinutes),
        run: timesUrl == null ? null : newest,
      );
    }
    if (timeFormat == WeatherTimeFormat.modelRun) {
      if (role == RainRole.model && offsetMinutes <= 0) return null;
      if (newest == null) return null;
      return runFrameAt(
        newest,
        now.add(Duration(minutes: offsetMinutes)),
        stepMinutes: stepMinutes,
        lastMinute: forecastMinutes,
      );
    }
    if (kind == WeatherKind.radar && role == RainRole.model) {
      if (offsetMinutes <= 0) return null;
      final time = modelFrameTime(now, offsetMinutes);
      return time == null ? null : WeatherFrame(time);
    }
    if (kind == WeatherKind.radar &&
        role == RainRole.satellite &&
        offsetMinutes != 0) {
      return null;
    }
    if (offsetMinutes > forecastMinutes) return null;
    if (-offsetMinutes > historyMinutes) return null;
    if (timeFormat == WeatherTimeFormat.none) {
      return offsetMinutes == 0 ? const WeatherFrame(null) : null;
    }
    final time = latestFrameTime(
      now,
      stepMinutes: stepMinutes,
      delayMinutes: delayMinutes,
    ).add(Duration(minutes: offsetMinutes));
    if (newest == null) return WeatherFrame(time);
    final cap = floorToStep(newest, stepMinutes);
    return WeatherFrame(time.isAfter(cap) ? cap : time);
  }

  /// A model's frame for the moment [offsetMinutes] from [now]: the hour
  /// that moment falls in, as the model names it.
  ///
  /// A model's frame is the rain summed over the [stepMinutes] up to its
  /// time: an hour for ICON-EU, six for the global ICON. So the hour the
  /// moment falls in, which ends on the next full hour, is the frame whose
  /// span holds that end. Clamped to the frames there are: none before the
  /// one holding the present hour, none beyond [forecastMinutes] from now;
  /// `null` where that leaves none.
  DateTime? modelFrameTime(DateTime now, int offsetMinutes) {
    final step = math.max(1, stepMinutes) * Duration.millisecondsPerMinute;
    int ceilStep(int ms) => ms % step == 0 ? ms : ms - ms % step + step;
    const hour = Duration.millisecondsPerHour;
    int hourEnd(DateTime t) {
      final ms = t.toUtc().millisecondsSinceEpoch;
      return ms - ms % hour + hour;
    }

    final first = ceilStep(hourEnd(now));
    final lastMs =
        now.toUtc().millisecondsSinceEpoch +
        forecastMinutes * Duration.millisecondsPerMinute;
    final last = lastMs - lastMs % step;
    if (last < first) return null;
    final wanted = ceilStep(hourEnd(now.add(Duration(minutes: offsetMinutes))))
        .clamp(first, last);
    return DateTime.fromMillisecondsSinceEpoch(wanted, isUtc: true);
  }

  /// The tile URL template with [frame]'s moment filled in; `{z}`, `{x}`,
  /// `{y}` and `{bbox-epsg-3857}` stay for MapLibre.
  String tileUrl(WeatherFrame frame) => _withTime(urlTemplate, frame);

  static String _withTime(String template, WeatherFrame frame) {
    final time = frame.time;
    if (time == null) return template;
    final run = frame.run;
    return template
        .replaceAll('{time}', formatWeatherTime(time))
        .replaceAll('{timeMs}', '${time.toUtc().millisecondsSinceEpoch}')
        .replaceAll('{run}', run == null ? '' : formatModelRun(run))
        .replaceAll('{runTime}', run == null ? '' : formatWeatherTime(run))
        .replaceAll(
          '{runMinute}',
          run == null
              ? ''
              : '${time.difference(run).inMinutes}'.padLeft(4, '0'),
        );
  }

  /// The URL of tile [x]/[y] at [zoom] of the image at [frame], for an
  /// image put together from tiles ([imageFromTiles]).
  String imageTileUrl(WeatherFrame frame, int zoom, int x, int y) => _withTime(
    imageUrlTemplate ?? urlTemplate,
    frame,
  ).replaceAll('{z}', '$zoom').replaceAll('{x}', '$x').replaceAll('{y}', '$y');

  /// The request for the soft radar's image of [box] at [frame]: the
  /// service's own [nativeMetresPerPixel], each side within
  /// [radarSoftMinSide] and [radarSoftMaxSide] pixels (see
  /// [radarSoftImageSize]); `null` without an [imageUrlTemplate].
  String? softImageUrl(WeatherFrame frame, BoundingBox box) {
    final template = imageUrlTemplate;
    if (template == null) return null;
    final (width, height) = radarSoftImageSize(this, box);
    return _withTime(template, frame)
        .replaceAll('{bbox-epsg-3857}', mercatorBboxString(box))
        .replaceAll('{width}', '$width')
        .replaceAll('{height}', '$height');
  }

  /// The part of [wanted] the soft radar's image shows: the box around its
  /// overlaps with every coverage box, clipped to the world an image can
  /// show ([clipToImageWorld]) before its size is worked out; `null` where
  /// it meets none. Unlike
  /// [detailBox] it keeps them all, so a view of the US zoomed out still
  /// shows Alaska's radar beside the contiguous states'.
  BoundingBox? softBox(BoundingBox wanted) {
    final area = clipToImageWorld(wanted);
    if (area == null) return null;
    BoundingBox? out;
    for (final box in coverage) {
      final south = math.max(box.south, area.south);
      final north = math.min(box.north, area.north);
      final west = math.max(box.west, area.west);
      final east = math.min(box.east, area.east);
      if (south >= north || west >= east) continue;
      final part = _box(west, south, east, north);
      out = out == null ? part : out.union(part);
    }
    return out;
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
    return imageUrl(frame, box, width, height);
  }

  /// The GetMap URL of the detail image of [box] at [frame]: the service's
  /// own [nativeMetresPerPixel], each side kept within [cloudDetailMinSide]
  /// and [cloudDetailMaxSide] pixels.
  String detailImageUrl(WeatherFrame frame, BoundingBox box) {
    final (width, height) = cloudDetailImageSize(this, box);
    return imageUrl(frame, box, width, height);
  }

  /// The GetMap URL of [box] at [frame] as an image of [width] × [height].
  String imageUrl(WeatherFrame frame, BoundingBox box, int width, int height) =>
      tileUrl(frame)
          .replaceAll('{bbox-epsg-3857}', mercatorBboxString(box))
          .replaceAll('{width}', '$width')
          .replaceAll('{height}', '$height');

  /// The part of [wanted] the detail image shows: its overlap with the
  /// coverage box it overlaps most, clipped to the world an image can show
  /// ([clipToImageWorld]); `null` where it meets none.
  BoundingBox? detailBox(BoundingBox wanted) {
    final area = clipToImageWorld(wanted);
    if (area == null) return null;
    BoundingBox? best;
    var bestSize = 0.0;
    for (final box in coverage) {
      final south = math.max(box.south, area.south);
      final north = math.min(box.north, area.north);
      final west = math.max(box.west, area.west);
      final east = math.min(box.east, area.east);
      if (south >= north || west >= east) continue;
      final size =
          (mercatorX(east) - mercatorX(west)) *
          (mercatorY(north) - mercatorY(south));
      if (size > bestSize) {
        bestSize = size;
        best = _box(west, south, east, north);
      }
    }
    return best;
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
    double? nativeMetresPerPixel,
    ({double clear, double full})? cloudLuminance,
    String? imageUrlTemplate,
    bool? enabled,
    RainRole? role,
    RainPalette? palette,
    String? timesUrl,
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
    nativeMetresPerPixel: nativeMetresPerPixel ?? this.nativeMetresPerPixel,
    cloudLuminance: cloudLuminance ?? this.cloudLuminance,
    imageUrlTemplate: imageUrlTemplate ?? this.imageUrlTemplate,
    enabled: enabled ?? this.enabled,
    role: role ?? this.role,
    palette: palette ?? this.palette,
    reach: reach,
    extent: extent,
    timesUrl: timesUrl ?? this.timesUrl,
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
      other.nativeMetresPerPixel == nativeMetresPerPixel &&
      other.cloudLuminance == cloudLuminance &&
      other.imageUrlTemplate == imageUrlTemplate &&
      other.enabled == enabled &&
      other.role == role &&
      other.palette == palette &&
      identical(other.reach, reach) &&
      identical(other.extent, extent) &&
      other.timesUrl == timesUrl;

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
    nativeMetresPerPixel,
    imageUrlTemplate,
    enabled,
    role,
    palette,
    Object.hash(
      identityHashCode(reach),
      identityHashCode(extent),
      timesUrl,
      cloudLuminance,
    ),
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

/// [time] moved back onto a [stepMinutes] grid, in UTC.
DateTime floorToStep(DateTime time, int stepMinutes) {
  final step = math.max(1, stepMinutes) * Duration.millisecondsPerMinute;
  final ms = time.toUtc().millisecondsSinceEpoch;
  return DateTime.fromMillisecondsSinceEpoch(ms - ms % step, isUtc: true);
}

/// A time dimension in a WMS capabilities document: `Dimension` (1.3.0) or
/// `Extent` (1.1.1), its attributes and, unless it closes itself, its text.
final RegExp _wmsDimension = RegExp(
  r'<(?:[\w.-]+:)?(?:Dimension|Extent)\b([^>]*?)(/?)>([^<]*)',
);

final RegExp _wmsTimeName = RegExp(r'''\bname\s*=\s*["']time["']''');

final RegExp _wmsDefault = RegExp(r'''\bdefault\s*=\s*["']([^"']*)["']''');

/// The newest moment a WMS capabilities document ([xml]) names in its time
/// dimensions, UTC: the latest of the values listed (`a,b,c`) and of the
/// ends of the intervals (`start/end/period`), else the dimension's
/// `default`; `null` where there is none that reads (an error report, a
/// layer without time, `current`).
DateTime? parseWmsNewestTime(String xml) {
  DateTime? newest;
  DateTime? fallback;
  for (final match in _wmsDimension.allMatches(xml)) {
    final attributes = match.group(1)!;
    if (!_wmsTimeName.hasMatch(attributes)) continue;
    final text = match.group(2)!.isEmpty ? match.group(3)! : '';
    for (final item in text.split(',')) {
      final parts = item.trim().split('/');
      final value = parts.length >= 2 ? parts[1] : parts[0];
      final time = DateTime.tryParse(value.trim())?.toUtc();
      if (time != null && (newest == null || time.isAfter(newest))) {
        newest = time;
      }
    }
    final stated = _wmsDefault.firstMatch(attributes)?.group(1);
    final time = stated == null ? null : DateTime.tryParse(stated.trim());
    if (time != null && (fallback == null || time.isAfter(fallback))) {
      fallback = time.toUtc();
    }
  }
  return newest ?? fallback;
}

/// The frame of a model's [run] for [moment] ([WeatherTimeFormat.modelRun]):
/// the moment's minutes from the run, rounded to its [stepMinutes] grid;
/// `null` where that falls before the run or past its [lastMinute].
WeatherFrame? runFrameAt(
  DateTime run,
  DateTime moment, {
  required int stepMinutes,
  required int lastMinute,
}) {
  final step = math.max(1, stepMinutes);
  final minutes =
      moment.difference(run).inMilliseconds / Duration.millisecondsPerMinute;
  final minute = (minutes / step).round() * step;
  if (minute < 0 || minute > lastMinute) return null;
  final start = run.toUtc();
  return WeatherFrame(start.add(Duration(minutes: minute)), run: start);
}

/// The run a model's latest-run document names, UTC: the
/// `model_init_utc` of the Iowa Environmental Mesonet's JSON, e.g.
/// `{"model_init_utc": "2026-10-11T17:00:00Z", ...}`; `null` where [json]
/// does not read as one.
DateTime? parseModelRunTime(String json) {
  try {
    final data = jsonDecode(json);
    if (data is! Map) return null;
    final value = data['model_init_utc'];
    if (value is! String) return null;
    return DateTime.tryParse(value)?.toUtc();
  } on FormatException {
    return null;
  }
}

/// The newest frame a frame list names, UTC: the `newest` of the relay's
/// `GET /weather/radar/opera/frames`, e.g. `{"frames": [...], "newest":
/// "2026-10-12T21:05:00.000Z", ...}`; `null` where [json] does not read as
/// one, or names none.
DateTime? parseFramesNewest(String json) {
  try {
    final data = jsonDecode(json);
    if (data is! Map) return null;
    final value = data['newest'];
    if (value is! String) return null;
    return DateTime.tryParse(value)?.toUtc();
  } on FormatException {
    return null;
  }
}

/// [run] as a model's run is named in a URL: `YYYYMMDDHHMI`, UTC.
String formatModelRun(DateTime run) {
  final t = run.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year.toString().padLeft(4, '0')}${two(t.month)}${two(t.day)}'
      '${two(t.hour)}${two(t.minute)}';
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

/// The GOES images' clear and full-cloud luminance, every cloud source's
/// unless it names its own ([WeatherMapSource.cloudLuminance]).
const ({double clear, double full}) defaultCloudLuminance = (
  clear: 110,
  full: 220,
);

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

/// The longitude of Web Mercator x [x] and the latitude of y [y], in
/// degrees: [mercatorX] and [mercatorY] the other way.
double lonOfMercatorX(double x) => x * 180 / 20037508.342789244;

double latOfMercatorY(double y) =>
    (2 * math.atan(math.exp(y / 6378137.0)) - math.pi / 2) * 180 / math.pi;

/// [box] in Web Mercator, `minx,miny,maxx,maxy`.
String mercatorBboxString(BoundingBox box) {
  String f(double v) => v.toStringAsFixed(1);
  return '${f(mercatorX(box.west))},${f(mercatorY(box.south))},'
      '${f(mercatorX(box.east))},${f(mercatorY(box.north))}';
}

/// The pixel size of the image of [box]: [metresPerPixel] Web Mercator
/// metres a pixel, scaled down to [maxSide] on the long side, the box's
/// aspect kept, and no side under [minSide].
(int, int) cloudImageSize(
  BoundingBox box, {
  double metresPerPixel = cloudMetresPerPixel,
  int maxSide = cloudImageMaxSide,
  int minSide = 1,
}) {
  final w = (mercatorX(box.east) - mercatorX(box.west)) / metresPerPixel;
  final h = (mercatorY(box.north) - mercatorY(box.south)) / metresPerPixel;
  final scale = math.min(1.0, maxSide / math.max(w, h));
  return (
    math.max(minSide, (w * scale).round()),
    math.max(minSide, (h * scale).round()),
  );
}

// Zoomed in, the region's image alone is blocky: a few kilometres a pixel,
// blown up. So from [cloudDetailMinZoom] the clouds get a second image over
// the view and a margin around it, at the service's own resolution, drawn
// over the region's, which still covers a pan beyond it and the view
// zoomed out.

/// The zoom from which the clouds get a detail image.
const double cloudDetailMinZoom = 6;

/// How far the detail image reaches beyond the view on each side, as a
/// share of the view's width and height.
const double cloudDetailMargin = 0.25;

/// The fewest pixels a side of a detail image has: zoomed far in the box
/// is only a few of the service's pixels, which the map then smooths.
const int cloudDetailMinSide = 64;

/// The most pixels a side of a detail image has.
const int cloudDetailMaxSide = 1536;

/// How far the zoom moves from the detail image's before it is fetched
/// anew, finer or coarser.
const double cloudDetailRezoom = 1.5;

/// The pixel size of [source]'s detail image of [box]: the service's own
/// resolution, each side within [cloudDetailMinSide] and
/// [cloudDetailMaxSide].
(int, int) cloudDetailImageSize(WeatherMapSource source, BoundingBox box) =>
    cloudImageSize(
      box,
      metresPerPixel: source.nativeMetresPerPixel,
      maxSide: cloudDetailMaxSide,
      minSide: cloudDetailMinSide,
    );

/// The area a detail image of [view] at [zoom] covers: the view and
/// [cloudDetailMargin] around it, rounded outward to the tile grid one zoom
/// finer than [zoom], so a small pan asks for the same box (and finds it in
/// the cache). `null` for a view across the antimeridian, which keeps the
/// region's image only.
BoundingBox? cloudDetailArea(BoundingBox view, double zoom) {
  if (view.west > view.east) return null;
  const origin = 20037508.342789244;
  final x0 = mercatorX(view.west);
  final x1 = mercatorX(view.east);
  final y0 = mercatorY(view.south);
  final y1 = mercatorY(view.north);
  final dx = (x1 - x0) * cloudDetailMargin;
  final dy = (y1 - y0) * cloudDetailMargin;
  final grid = 2 * origin / (1 << (zoom.floor() + 1).clamp(0, 22));
  double down(double v) =>
      ((v + origin) / grid).floorToDouble() * grid - origin;
  double up(double v) => ((v + origin) / grid).ceilToDouble() * grid - origin;
  final west = down(x0 - dx).clamp(-origin, origin);
  final east = up(x1 + dx).clamp(-origin, origin);
  final south = down(y0 - dy).clamp(-origin, origin);
  final north = up(y1 + dy).clamp(-origin, origin);
  return _box(
    lonOfMercatorX(west),
    latOfMercatorY(south),
    lonOfMercatorX(east),
    latOfMercatorY(north),
  );
}

/// What names a detail box in the cache: its Web Mercator corners to the
/// kilometre.
String cloudDetailKey(BoundingBox box) => <double>[
  mercatorX(box.west),
  mercatorY(box.south),
  mercatorX(box.east),
  mercatorY(box.north),
].map((v) => (v / 1000).round()).join('_');

// The soft radar: one image of the view and the same margin as a cloud
// detail ([cloudDetailArea]), at the radar's own resolution, at every zoom.
// Zoomed out the box grows and the image coarsens at [radarSoftMaxSide],
// still finer than the screen's pixels there; there is no region-wide
// image under it, since rain is local and a coverage box is large.

/// The fewest pixels a side of a soft radar image has.
const int radarSoftMinSide = 64;

/// The most pixels a side of a soft radar image has.
const int radarSoftMaxSide = 1536;

/// The pixel size of [source]'s soft radar image of [box]: the radar's
/// own resolution, each side within [radarSoftMinSide] and
/// [radarSoftMaxSide]. A model's has no minimum: its box is already at
/// least [modelMinCells] of its cells a side ([modelImageArea]), and one
/// pixel a cell is what lets the map blend the cells into each other. An
/// image put together from tiles is the size of its mosaic
/// ([tileMosaicOf]).
(int, int) radarSoftImageSize(WeatherMapSource source, BoundingBox box) {
  if (source.imageFromTiles) {
    final mosaic = tileMosaicOf(source, box);
    return (mosaic.width, mosaic.height);
  }
  return cloudImageSize(
    box,
    metresPerPixel: source.nativeMetresPerPixel,
    maxSide: radarSoftMaxSide,
    minSide: source.role == RainRole.model ? 1 : radarSoftMinSide,
  );
}

/// How many tiles one image put together from tiles takes at most.
const int weatherMosaicMaxTiles = 16;

/// The tiles an image of a box is put together from ([tileMosaicOf]): a
/// [columns] × [rows] block from tile [x0]/[y0] at [zoom], and where the
/// box lies on it, in its pixels from the block's north-west corner
/// ([left], [top], [right], [bottom]); the image is [width] × [height].
@immutable
class TileMosaic {
  /// Creates the mosaic.
  const TileMosaic({
    required this.zoom,
    required this.tileSize,
    required this.x0,
    required this.y0,
    required this.columns,
    required this.rows,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.width,
    required this.height,
  });

  final int zoom;
  final int tileSize;
  final int x0;
  final int y0;
  final int columns;
  final int rows;
  final double left;
  final double top;
  final double right;
  final double bottom;
  final int width;
  final int height;

  /// The tiles, row by row from the north-west: (x, y).
  List<(int, int)> get tiles => <(int, int)>[
    for (var y = y0; y < y0 + rows; y++)
      for (var x = x0; x < x0 + columns; x++) (x, y),
  ];

  @override
  String toString() =>
      'TileMosaic(z$zoom, $x0/$y0 ${columns}x$rows, ${width}x$height)';
}

/// The tiles [source]'s image of [box] is put together from: at the
/// finest zoom from its `maxZoom` down whose block of tiles is at most
/// [weatherMosaicMaxTiles] and whose image is at most [radarSoftMaxSide]
/// a side, never under its `minZoom`. The image is [box] at that zoom's
/// resolution.
TileMosaic tileMosaicOf(WeatherMapSource source, BoundingBox box) {
  const origin = 20037508.342789244;
  final size = source.tileSize;
  final lowest = math.max(0, math.min(source.minZoom, source.maxZoom));
  for (var zoom = math.max(lowest, source.maxZoom); ; zoom--) {
    final n = 1 << zoom;
    final world = n * size.toDouble();
    double px(double mx) => (mx + origin) / (2 * origin) * world;
    double py(double my) => (origin - my) / (2 * origin) * world;
    final left = px(mercatorX(box.west));
    final right = px(mercatorX(box.east));
    final top = py(mercatorY(box.north));
    final bottom = py(mercatorY(box.south));
    final x0 = (left / size).floor().clamp(0, n - 1);
    final x1 = math.max(x0, ((right / size).ceil() - 1).clamp(0, n - 1));
    final y0 = (top / size).floor().clamp(0, n - 1);
    final y1 = math.max(y0, ((bottom / size).ceil() - 1).clamp(0, n - 1));
    final width = math.max(1, (right - left).round());
    final height = math.max(1, (bottom - top).round());
    final columns = x1 - x0 + 1;
    final rows = y1 - y0 + 1;
    if (zoom <= lowest ||
        (columns * rows <= weatherMosaicMaxTiles &&
            math.max(width, height) <= radarSoftMaxSide)) {
      return TileMosaic(
        zoom: zoom,
        tileSize: size,
        x0: x0,
        y0: y0,
        columns: columns,
        rows: rows,
        left: left - x0 * size,
        top: top - y0 * size,
        right: right - x0 * size,
        bottom: bottom - y0 * size,
        width: width,
        height: height,
      );
    }
  }
}

// A model's cells are kilometres wide (7 for ICON-EU, 28 for the global
// ICON). An image of a city's view at the model's own resolution would be
// a few pixels, which the service then draws larger, each cell a hard
// block that the map's smoothing cannot undo. So a model's image covers at
// least [modelMinCells] cells a side, one pixel a cell, and the map's
// linear resampling turns the cells into gradients.

/// The fewest of a model's own cells each side of its image spans.
const int modelMinCells = 24;

/// The area [source]'s (a model's) image of [area] covers: [area] grown
/// to at least [modelMinCells] of the model's cells a side, about its
/// middle put on a grid a quarter of that wide, its edges on the cells: so
/// a pan of less than an eighth asks for the same box. The coverage clips
/// it later ([WeatherMapSource.softBox]).
BoundingBox modelImageArea(WeatherMapSource source, BoundingBox area) {
  const origin = 20037508.342789244;
  final cell = source.nativeMetresPerPixel;
  final snap = cell * modelMinCells / 4;
  (double, double) grow(double a, double b) {
    final mid = ((a + b) / 2 / snap).roundToDouble() * snap;
    final need = math.max(b - a, modelMinCells * cell) / 2 + snap / 2;
    final half = (need / cell).ceilToDouble() * cell;
    return (
      (mid - half).clamp(-origin, origin),
      (mid + half).clamp(-origin, origin),
    );
  }

  final (west, east) = grow(mercatorX(area.west), mercatorX(area.east));
  final (south, north) = grow(mercatorY(area.south), mercatorY(area.north));
  return _box(
    lonOfMercatorX(west),
    latOfMercatorY(south),
    lonOfMercatorX(east),
    latOfMercatorY(north),
  );
}

/// Whether the soft image of [box] is coarser than [source]'s own
/// resolution: capped at [radarSoftMaxSide], so zooming in is worth a new,
/// finer one.
bool radarSoftCapped(WeatherMapSource source, BoundingBox box) {
  final (width, _) = radarSoftImageSize(source, box);
  final metres = mercatorX(box.east) - mercatorX(box.west);
  return metres / width > source.nativeMetresPerPixel * 1.01;
}

/// What tells one soft radar image of [frame] from the next, besides its
/// box: the moment, and for a moment still ahead also the newest frame
/// measured, since each new measurement makes a new forecast of it; for a
/// model named by its run, the run.
String radarImageStamp(
  WeatherMapSource source,
  WeatherFrame frame,
  DateTime now,
) {
  final time = frame.time;
  final run = frame.run;
  if (time != null && run != null) {
    return '${time.millisecondsSinceEpoch}r${run.millisecondsSinceEpoch}';
  }
  if (time == null) {
    // The latest image, which the URL cannot name: one per step.
    final step = math.max(1, source.stepMinutes) * 60000;
    final ms = now.millisecondsSinceEpoch;
    return 'latest${ms - ms % step}';
  }
  final latest = latestFrameTime(
    now,
    stepMinutes: source.stepMinutes,
    delayMinutes: source.delayMinutes,
  );
  final ms = time.millisecondsSinceEpoch;
  if (!time.isAfter(latest)) return '$ms';
  return '${ms}f${latest.millisecondsSinceEpoch}';
}

BoundingBox _box(double west, double south, double east, double north) =>
    BoundingBox(south: south, west: west, north: north, east: east);

// MapLibre draws an image source by covering its corners with tiles and
// takes the first of them without asking whether there is one: a box that
// is empty, has no width or height, or lies beyond the latitudes Web
// Mercator reaches has none, and the renderer crashes on it (seen on iOS,
// zoomed out to the whole world and panned). So no image reaches the map
// unless [safeImageBox] passes it, and a view wider than half the world or
// across the antimeridian is asked for in at most two boxes that each pass
// ([weatherImageAreas]).

/// The latitude an image's box is clipped to before it is asked for: just
/// inside the ±85.0511° Web Mercator ends.
const double weatherImageMaxLat = 85.05;

/// The latitude beyond which MapLibre has no tiles to cover an image with.
const double weatherImageLatLimit = 85.0511;

/// The narrowest an image's box may be, either way, in degrees.
const double weatherImageMinSpan = 0.01;

/// The widest an image's box may be, in degrees of longitude: a wider image
/// shows nothing worth the risk.
const double weatherImageMaxLonSpan = 180;

/// Whether MapLibre can draw an image over [b] without crashing (see
/// above): finite edges, west before east within ±180°, south before north
/// within ±[weatherImageLatLimit], each side at least [weatherImageMinSpan]
/// and at most [weatherImageMaxLonSpan] wide.
bool safeImageBox(BoundingBox b) {
  final edges = <double>[b.west, b.south, b.east, b.north];
  if (edges.any((v) => !v.isFinite)) return false;
  if (b.west < -180 || b.east > 180) return false;
  if (b.south < -weatherImageLatLimit || b.north > weatherImageLatLimit) {
    return false;
  }
  final width = b.east - b.west;
  final height = b.north - b.south;
  return width >= weatherImageMinSpan &&
      width <= weatherImageMaxLonSpan &&
      height >= weatherImageMinSpan;
}

// MapLibre also misdraws an image whose box ends on the antimeridian: with
// a copy of the world beside the one in view (zoomed out further than the
// map is wide, as sideways it can be), the image of 165° to 180° east was
// smeared westward over the Pacific in streaks, each of its rows stretched
// across tens of degrees. Pulled in from ±180° by a hair, it is drawn where
// it belongs. The image itself is unchanged; the strip it loses is
// [weatherImageAntimeridianInset] wide, about eleven metres at the equator,
// far under a pixel at any zoom the image is drawn at.

/// How far an image's box is pulled in from the antimeridian before it is
/// drawn ([drawnImageBox]), in degrees.
const double weatherImageAntimeridianInset = 1e-4;

/// [b] as an image source is put on the map: a west edge on −180° or an
/// east edge on +180° pulled in by [weatherImageAntimeridianInset] (see
/// above), the rest as it is.
BoundingBox drawnImageBox(BoundingBox b) {
  const edge = 180 - weatherImageAntimeridianInset;
  if (b.west > -edge && b.east < edge) return b;
  return _box(
    math.max(b.west, -edge),
    b.south,
    math.min(b.east, edge),
    b.north,
  );
}

/// The areas the rain's images of [view] at [zoom] are asked for: the
/// view and [cloudDetailMargin] around it, on the grid of
/// [cloudDetailArea], as at most two boxes each within ±180°, at most
/// [weatherImageMaxLonSpan] wide and within ±[weatherImageMaxLat]: one
/// box, or two split at the antimeridian where it runs across, or where it
/// is wider than half the world (zoomed far out), the world's two halves.
/// Empty where nothing of it is left.
List<BoundingBox> weatherImageAreas(BoundingBox view, double zoom) {
  final edges = <double>[view.west, view.south, view.east, view.north];
  if (edges.any((v) => !v.isFinite)) return const <BoundingBox>[];
  const origin = 20037508.342789244;
  final west = view.west;
  final east = view.west <= view.east ? view.east : view.east + 360;
  final x0 = west * origin / 180;
  final x1 = east * origin / 180;
  final y0 = mercatorY(view.south);
  final y1 = mercatorY(view.north);
  final dx = (x1 - x0) * cloudDetailMargin;
  final dy = (y1 - y0) * cloudDetailMargin;
  final grid = 2 * origin / (1 << (zoom.floor() + 1).clamp(0, 22));
  double down(double v) =>
      ((v + origin) / grid).floorToDouble() * grid - origin;
  double up(double v) => ((v + origin) / grid).ceilToDouble() * grid - origin;
  final south = math.max(
    -weatherImageMaxLat,
    latOfMercatorY(down(y0 - dy).clamp(-origin, origin)),
  );
  final north = math.min(
    weatherImageMaxLat,
    latOfMercatorY(up(y1 + dy).clamp(-origin, origin)),
  );
  if (!(north - south >= weatherImageMinSpan)) return const <BoundingBox>[];
  var w = down(x0 - dx) * 180 / origin;
  var e = up(x1 + dx) * 180 / origin;
  BoundingBox box(double w, double e) => _box(w, south, e, north);
  if (e - w > weatherImageMaxLonSpan) {
    return <BoundingBox>[box(-180, 0), box(0, 180)];
  }
  while (w < -180) {
    w += 360;
    e += 360;
  }
  while (w >= 180) {
    w -= 360;
    e -= 360;
  }
  if (e <= 180) return <BoundingBox>[box(w, e)];
  return <BoundingBox>[
    if (180 - w >= weatherImageMinSpan) box(w, 180),
    if (e - 180 >= weatherImageMinSpan) box(-180, e - 360),
  ];
}

/// Whether images asked for over [areas] (see [weatherImageAreas]) still
/// serve [view]: its latitudes within theirs, and each longitude of it
/// inside one of them, or theirs a whole turn of the globe.
bool weatherAreasServe(List<BoundingBox> areas, BoundingBox view) {
  if (areas.isEmpty) return false;
  final edges = <double>[view.west, view.south, view.east, view.north];
  if (edges.any((v) => !v.isFinite)) return false;
  final south = math.max(view.south, -weatherImageMaxLat);
  final north = math.min(view.north, weatherImageMaxLat);
  for (final a in areas) {
    if (south < a.south - 1e-9 || north > a.north + 1e-9) return false;
  }
  final width = areas.fold<double>(0, (sum, a) => sum + a.east - a.west);
  if (width >= 360 - 1e-6) return true;
  var w = view.west;
  var e = view.west <= view.east ? view.east : view.east + 360;
  if (e - w >= 360) return false;
  while (w < -180) {
    w += 360;
    e += 360;
  }
  while (w >= 180) {
    w -= 360;
    e -= 360;
  }
  final pieces = e <= 180
      ? <(double, double)>[(w, e)]
      : <(double, double)>[(w, 180), (-180, e - 360)];
  return pieces.every(
    (p) => areas.any((a) => p.$1 >= a.west - 1e-9 && p.$2 <= a.east + 1e-9),
  );
}

/// [b] clipped to the world an image can show, ±180° by
/// ±[weatherImageMaxLat]; `null` where nothing of it is left.
BoundingBox? clipToImageWorld(BoundingBox b) {
  final edges = <double>[b.west, b.south, b.east, b.north];
  if (edges.any((v) => v.isNaN)) return null;
  final west = math.max(b.west, -180.0);
  final east = math.min(b.east, 180.0);
  final south = math.max(b.south, -weatherImageMaxLat);
  final north = math.min(b.north, weatherImageMaxLat);
  if (west >= east || south >= north) return null;
  return _box(west, south, east, north);
}

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
  imageUrlTemplate:
      'https://maps.dwd.de/geoserver/dwd/wms?service=WMS&version=1.3.0'
      '&request=GetMap&layers=dwd:Niederschlagsradar&styles=&crs=EPSG:3857'
      '&bbox={bbox-epsg-3857}&width={width}&height={height}'
      '&format=image/png&transparent=true&time={time}',
  coverage: <BoundingBox>[_box(1.5, 45, 19, 56.5)],
  reach: const <List<LatLng>>[dwdRadarReach],
  extent: dwdRadarExtent,
  maxZoom: 10,
  timeFormat: WeatherTimeFormat.iso,
  forecastMinutes: 120,
  // The radar composite's cells are a kilometre square.
  nativeMetresPerPixel: 1000,
  attribution: 'Radar: Deutscher Wetterdienst (CC BY 4.0)',
);

/// Where the DWD's radars reach: the ring inside the magenta line its
/// composite draws around them, some 4 km in, traced from an image of its
/// coverage box (2 km a pixel) and simplified to within 6 km. Beyond it the
/// composite is grey, "no data", inside its box; the satellite and the
/// models draw there instead.
///
/// The reach of each frame differs (the nowcast's shrinks the further
/// ahead it looks), so drawn soft the sources after the DWD are cut by the
/// frame itself (see [WeatherMapSource.extent]); this ring stands in where
/// that frame cannot be had, drawn as measured, and for what the time
/// control says about the middle of the view.
const List<LatLng> dwdRadarReach = <LatLng>[
  LatLng(51.34, 15.90),
  LatLng(51.59, 15.81),
  LatLng(51.82, 15.61),
  LatLng(52.14, 15.90),
  LatLng(52.61, 16.07),
  LatLng(52.96, 16.04),
  LatLng(53.32, 15.83),
  LatLng(53.56, 15.52),
  LatLng(53.79, 15.08),
  LatLng(53.97, 14.30),
  LatLng(54.55, 14.28),
  LatLng(54.82, 14.10),
  LatLng(55.14, 13.71),
  LatLng(55.43, 12.95),
  LatLng(55.52, 12.12),
  LatLng(55.46, 11.39),
  LatLng(55.27, 10.74),
  LatLng(55.34, 10.34),
  LatLng(55.34, 9.76),
  LatLng(55.24, 9.19),
  LatLng(55.08, 8.67),
  LatLng(54.67, 8.04),
  LatLng(54.85, 7.38),
  LatLng(54.90, 6.48),
  LatLng(54.81, 5.91),
  LatLng(54.58, 5.27),
  LatLng(54.24, 4.78),
  LatLng(53.68, 4.51),
  LatLng(53.26, 4.57),
  LatLng(52.93, 4.80),
  LatLng(52.69, 5.08),
  LatLng(52.42, 5.56),
  LatLng(51.93, 4.98),
  LatLng(51.51, 4.84),
  LatLng(51.34, 4.85),
  LatLng(50.97, 4.96),
  LatLng(50.64, 4.63),
  LatLng(50.33, 4.50),
  LatLng(50.08, 4.48),
  LatLng(49.61, 4.64),
  LatLng(49.31, 4.91),
  LatLng(49.06, 5.29),
  LatLng(48.87, 5.82),
  LatLng(48.76, 6.49),
  LatLng(48.45, 6.20),
  LatLng(48.11, 6.06),
  LatLng(47.71, 6.04),
  LatLng(47.39, 6.17),
  LatLng(47.08, 6.42),
  LatLng(46.82, 6.81),
  LatLng(46.61, 7.41),
  LatLng(46.55, 7.88),
  LatLng(46.64, 8.72),
  LatLng(46.78, 9.13),
  LatLng(46.91, 9.22),
  LatLng(46.73, 9.93),
  LatLng(46.73, 10.54),
  LatLng(46.96, 11.35),
  LatLng(46.86, 11.95),
  LatLng(46.88, 12.53),
  LatLng(46.97, 12.95),
  LatLng(47.18, 13.44),
  LatLng(47.48, 13.82),
  LatLng(47.83, 14.05),
  LatLng(48.25, 14.14),
  LatLng(48.70, 14.01),
  LatLng(49.20, 14.41),
  LatLng(49.56, 14.50),
  LatLng(49.85, 14.44),
  LatLng(50.09, 15.13),
  LatLng(50.33, 15.50),
  LatLng(50.80, 15.84),
];

/// The DWD composite's grid: the ring its images are drawn in (rain, dry
/// and the grey of "no data" beyond the radars' reach), transparent beyond.
/// Traced from an image of the layer's whole box (`dwd:Niederschlagsradar`,
/// 1.4 km a pixel, 2026-10-11), kept some 3 km inside the grid's edge and
/// simplified to within 1.5 km: next to the edge the composite is grey
/// anyway. The grid is the same for every frame, the nowcast's too.
const List<LatLng> dwdRadarExtent = <LatLng>[
  LatLng(55.779, 1.500),
  LatLng(55.834, 1.506),
  LatLng(55.841, 1.531),
  LatLng(55.945, 2.869),
  LatLng(56.048, 4.538),
  LatLng(56.144, 6.797),
  LatLng(56.178, 8.209),
  LatLng(56.191, 9.351),
  LatLng(56.191, 10.652),
  LatLng(56.178, 11.794),
  LatLng(56.116, 13.979),
  LatLng(56.048, 15.465),
  LatLng(55.979, 16.619),
  LatLng(55.821, 18.682),
  LatLng(55.682, 18.682),
  LatLng(53.360, 18.092),
  LatLng(50.763, 17.515),
  LatLng(48.522, 17.073),
  LatLng(45.715, 16.582),
  LatLng(45.809, 15.281),
  LatLng(45.886, 13.906),
  LatLng(45.937, 12.629),
  LatLng(45.971, 11.131),
  LatLng(45.971, 8.860),
  LatLng(45.937, 7.374),
  LatLng(45.860, 5.582),
  LatLng(45.723, 3.569),
  LatLng(48.578, 3.077),
  LatLng(51.104, 2.586),
  LatLng(53.557, 2.046),
  LatLng(55.724, 1.506),
];

/// Rain radar over the Netherlands and the sea and land around them, from
/// the KNMI: the composite of its radars (`RAD_NL25_PCP_CM`), a kilometre
/// a cell, every five minutes; no forecast. After the DWD's in the list, so
/// over Germany the DWD's radar draws and the KNMI's fills in to its west.
///
/// Drawn in the style `precip-blue-transparent/nearest`, a fixed ramp over
/// 0.1 to 100 mm an hour that the phone reads back as rates
/// ([RainPalette.knmi]). The style draws dry and beyond the radars' reach
/// alike, transparent, so where it measures is its fixed reach
/// ([knmiRadarReach]), which the sources after it fade in across as beside
/// the DWD's radar ([WeatherMapSource.extent]). The service answers a
/// moment past its newest frame, some five to ten minutes behind the clock,
/// with an error: the newest is read off its capabilities, which name the
/// composite's frames from 2024 on as one interval.
final WeatherMapSource knmiRadar = WeatherMapSource(
  id: 'radar_knmi',
  kind: WeatherKind.radar,
  palette: RainPalette.knmi,
  urlTemplate: _knmiUrl('256', '256'),
  imageUrlTemplate: _knmiUrl('{width}', '{height}'),
  // Its reach's box: the composite's own box reaches south to 48.9°, where
  // its radars no longer do.
  coverage: <BoundingBox>[_box(0, 49.1, 9.8, 55.85)],
  reach: const <List<LatLng>>[knmiRadarReach],
  extent: knmiRadarReach,
  maxZoom: 10,
  timeFormat: WeatherTimeFormat.iso,
  delayMinutes: 10,
  // The composite's cells are a kilometre square.
  nativeMetresPerPixel: 1000,
  attribution: 'Radar: KNMI (CC BY 4.0)',
  timesUrl:
      'https://geoservices.knmi.nl/adagucserver?dataset=RADAR'
      '&service=WMS&version=1.3.0&request=GetCapabilities',
);

String _knmiUrl(String width, String height) =>
    'https://geoservices.knmi.nl/adagucserver?dataset=RADAR&service=WMS'
    '&version=1.3.0&request=GetMap&layers=RAD_NL25_PCP_CM'
    '&styles=precip-blue-transparent/nearest&crs=EPSG:3857'
    '&bbox={bbox-epsg-3857}&width=$width&height=$height'
    '&format=image/png&transparent=true&time={time}';

/// Where the KNMI's radars reach: the edge of what its composite measures
/// (in the style `precip-blue/nearest`, which draws dry white and beyond
/// the reach nothing), the same in frames of March, August and October
/// 2026; traced from an image of the composite's box (0.8 km a pixel), kept
/// some 3 km inside and simplified to within 1.5 km. From the English coast
/// to Hamburg and from Denmark's west coast to Luxembourg.
const List<LatLng> knmiRadarReach = <LatLng>[
  LatLng(52.58, 9.62),
  LatLng(52.82, 9.51),
  LatLng(53.10, 9.53),
  LatLng(53.49, 9.48),
  LatLng(53.89, 9.32),
  LatLng(54.36, 8.99),
  LatLng(54.58, 8.76),
  LatLng(54.86, 8.41),
  LatLng(55.21, 7.78),
  LatLng(55.47, 7.08),
  LatLng(55.69, 6.17),
  LatLng(55.77, 5.56),
  LatLng(55.81, 4.99),
  LatLng(55.78, 4.07),
  LatLng(55.64, 3.14),
  LatLng(55.52, 2.65),
  LatLng(55.33, 2.08),
  LatLng(55.11, 1.59),
  LatLng(54.95, 1.32),
  LatLng(54.72, 1.00),
  LatLng(54.36, 0.59),
  LatLng(53.86, 0.25),
  LatLng(53.60, 0.14),
  LatLng(53.26, 0.05),
  LatLng(52.76, 0.07),
  LatLng(52.58, 0.13),
  LatLng(52.48, 0.14),
  LatLng(52.04, 0.34),
  LatLng(51.83, 0.51),
  LatLng(51.29, 0.63),
  LatLng(50.82, 0.86),
  LatLng(50.43, 1.17),
  LatLng(50.07, 1.57),
  LatLng(49.83, 1.92),
  LatLng(49.63, 2.27),
  LatLng(49.46, 2.62),
  LatLng(49.34, 2.96),
  LatLng(49.28, 4.48),
  LatLng(49.14, 6.61),
  LatLng(49.36, 7.38),
  LatLng(49.52, 7.76),
  LatLng(49.75, 8.23),
  LatLng(50.09, 8.73),
  LatLng(50.57, 9.23),
  LatLng(50.96, 9.49),
  LatLng(51.93, 9.75),
  LatLng(52.25, 9.73),
];

/// Rain radar over Finland and the Baltic around it, from the Finnish
/// Meteorological Institute: the rain rate of its radars' composite
/// (`Radar:suomi_rr_eureffin`), every five minutes, the past week; no
/// forecast.
///
/// Its colours are a ramp the phone reads back as rates
/// ([RainPalette.fmi]). Like the DWD's, the composite draws "no data" in
/// grey (`#CCCCCC` at 15 %) inside its grid ([fmiRadarExtent]) beyond its
/// radars' reach, so the sources after it are cut by each frame's own
/// reach; [fmiRadarReach] stands in where a frame cannot be had. The
/// service answers a moment past its newest frame, some five minutes behind
/// the clock, with an XML error: the newest is read off the layer's own
/// capabilities.
final WeatherMapSource fmiRadar = WeatherMapSource(
  id: 'radar_fmi',
  kind: WeatherKind.radar,
  palette: RainPalette.fmi,
  urlTemplate: _fmiUrl('256', '256'),
  imageUrlTemplate: _fmiUrl('{width}', '{height}'),
  coverage: <BoundingBox>[_box(17.3, 57.6, 34, 69.6)],
  reach: const <List<LatLng>>[fmiRadarReach],
  extent: fmiRadarExtent,
  maxZoom: 10,
  timeFormat: WeatherTimeFormat.iso,
  delayMinutes: 10,
  nativeMetresPerPixel: 1000,
  attribution: 'Radar: Finnish Meteorological Institute (CC BY 4.0)',
  timesUrl:
      'https://openwms.fmi.fi/geoserver/Radar/suomi_rr_eureffin/ows'
      '?service=WMS&version=1.3.0&request=GetCapabilities',
);

String _fmiUrl(String width, String height) =>
    'https://openwms.fmi.fi/geoserver/Radar/wms?service=WMS&version=1.3.0'
    '&request=GetMap&layers=Radar:suomi_rr_eureffin&styles=&crs=EPSG:3857'
    '&bbox={bbox-epsg-3857}&width=$width&height=$height'
    '&format=image/png&transparent=true&time={time}';

/// Where the FMI's radars reach: the edge of the grey "no data" its
/// composite draws inside its grid, traced from a frame of 2026-10-11 (some
/// 2 km a pixel), kept some 4 km inside and simplified to within 5 km.
/// Finland, the Gulf of Bothnia to the Swedish coast, the Gulf of Finland
/// and the north of Estonia.
const List<LatLng> fmiRadarReach = <LatLng>[
  LatLng(69.28, 23.20),
  LatLng(69.20, 30.55),
  LatLng(69.09, 33.06),
  LatLng(68.93, 33.40),
  LatLng(68.44, 33.47),
  LatLng(67.93, 33.27),
  LatLng(67.35, 32.55),
  LatLng(66.91, 32.55),
  LatLng(66.48, 32.28),
  LatLng(65.89, 31.50),
  LatLng(65.60, 32.62),
  LatLng(65.33, 33.27),
  LatLng(59.92, 31.74),
  LatLng(59.80, 30.99),
  LatLng(59.32, 30.21),
  LatLng(59.02, 29.43),
  LatLng(58.77, 28.10),
  LatLng(58.70, 26.84),
  LatLng(58.44, 25.72),
  LatLng(58.36, 24.22),
  LatLng(58.15, 23.58),
  LatLng(58.06, 20.55),
  LatLng(58.06, 20.14),
  LatLng(58.19, 19.60),
  LatLng(58.63, 18.51),
  LatLng(61.34, 17.87),
  LatLng(61.45, 17.97),
  LatLng(62.06, 17.83),
  LatLng(62.44, 17.97),
  LatLng(62.92, 18.38),
  LatLng(63.29, 18.95),
  LatLng(64.08, 19.36),
  LatLng(64.64, 20.18),
  LatLng(65.00, 21.16),
  LatLng(65.61, 21.44),
  LatLng(66.06, 22.01),
  LatLng(66.59, 21.44),
  LatLng(67.22, 21.20),
  LatLng(67.98, 21.57),
  LatLng(68.77, 21.44),
  LatLng(69.11, 21.61),
  LatLng(69.26, 21.74),
];

/// The FMI composite's grid: its box in the Finnish grid (EPSG:3067,
/// −118 to 876 km east, 6336 to 7908 km north), the ring its images are
/// drawn in, kept 3 km inside and simplified to within 1.5 km.
const List<LatLng> fmiRadarExtent = <LatLng>[
  LatLng(56.782, 16.909),
  LatLng(56.937, 19.042),
  LatLng(57.043, 20.925),
  LatLng(57.130, 23.090),
  LatLng(57.175, 24.992),
  LatLng(57.191, 26.899),
  LatLng(57.174, 29.077),
  LatLng(57.128, 30.980),
  LatLng(57.040, 33.144),
  LatLng(59.137, 33.517),
  LatLng(61.232, 33.948),
  LatLng(63.092, 34.391),
  LatLng(64.949, 34.902),
  LatLng(66.572, 35.418),
  LatLng(68.192, 36.013),
  LatLng(69.578, 36.601),
  LatLng(70.961, 37.277),
  LatLng(71.126, 33.683),
  LatLng(71.213, 30.496),
  LatLng(71.245, 26.829),
  LatLng(71.215, 23.621),
  LatLng(71.130, 20.433),
  LatLng(70.967, 16.837),
  LatLng(70.769, 13.752),
  LatLng(70.481, 10.314),
  LatLng(69.132, 11.376),
  LatLng(67.777, 12.306),
  LatLng(66.188, 13.252),
  LatLng(64.593, 14.077),
  LatLng(62.763, 14.897),
  LatLng(60.928, 15.609),
  LatLng(58.857, 16.305),
];

/// The id of the OPERA radar ([operaRadar]).
const String operaRadarId = 'radar_opera';

/// The path under the relay the OPERA radar is served from.
const String operaRadarPath = '/weather/radar/opera';

/// Rain radar across Europe for Velorki Plus: EUMETNET OPERA's composite
/// of some 190 radars in 24 countries (CC BY 4.0), every five minutes,
/// drawn by the relay at [relayBase] (`{base}/weather/radar/opera/image`,
/// the same query as the other radars' WMS GetMap) in the DWD radar's
/// classes and colours ([RainPalette.dwd]), its "no data" grey; the past
/// two hours, no forecast. Listed after the national radars, so the
/// DWD's, KNMI's, FMI's and the DPC's ([dpcRadar]) draw where they reach
/// and OPERA around them; before the satellite, which it replaces where it
/// measures.
///
/// The image is the relay's, so it is drawn as an image in either look
/// ([WeatherMapSource.servesTiles] is false): MapLibre would load tiles
/// without the rider's Plus credentials. The newest frame is read off the
/// relay's frame list ([timesUrl], `parseFramesNewest`). Every request
/// carries the relay's credentials (see `relayAuthFor`), only the relay's
/// radars' ([relayRadarPaths]).
///
/// The composite's grid (Lambert azimuthal equal-area, 3800 × 4400 km)
/// bounds its images ([operaRadarExtent]); where its radars reach
/// ([operaRadarReach]) each frame says itself in its grey, so the sources
/// after it are cut by the frame, as beside the DWD's radar.
WeatherMapSource operaRadar(String relayBase) => _relayRadar(
  relayBase,
  id: operaRadarId,
  path: operaRadarPath,
  // The composite's grid's box, as the relay checks it.
  coverage: _box(-39.5, 31.7, 57.8, 73.9),
  reach: operaRadarReach,
  extent: operaRadarExtent,
  attribution: 'Radar: EUMETNET OPERA (CC BY 4.0)',
);

/// [sources] with [operaRadar] of [relayBase] put after the radars, before
/// the first rain source that is not one (the satellite).
List<WeatherMapSource> withOperaRadar(
  List<WeatherMapSource> sources,
  String relayBase,
) => _withRelayRadar(sources, operaRadar(relayBase));

/// The paths under the relay its radars are served from: the only requests
/// that carry the rider's credentials (see `relayAuthFor`).
const List<String> relayRadarPaths = <String>[operaRadarPath, dpcRadarPath];

/// A radar the relay at [relayBase] draws under [path] (`{base}{path}/image`,
/// the same query as the other radars' WMS GetMap; its frames at
/// `{base}{path}/frames`): Velorki Plus, the DWD radar's classes and
/// colours, 1 km, every five minutes, the past two hours.
WeatherMapSource _relayRadar(
  String relayBase, {
  required String id,
  required String path,
  required BoundingBox coverage,
  required List<List<LatLng>> reach,
  required List<LatLng> extent,
  required String attribution,
}) {
  final base = relayBase.endsWith('/')
      ? relayBase.substring(0, relayBase.length - 1)
      : relayBase;
  final image =
      '$base$path/image?time={time}&bbox={bbox-epsg-3857}'
      '&width={width}&height={height}';
  return WeatherMapSource(
    id: id,
    kind: WeatherKind.radar,
    urlTemplate: image,
    imageUrlTemplate: image,
    coverage: <BoundingBox>[coverage],
    reach: reach,
    extent: extent,
    timeFormat: WeatherTimeFormat.iso,
    nativeMetresPerPixel: 1000,
    attribution: attribution,
    timesUrl: '$base$path/frames',
  );
}

/// [sources] with [radar] put before the source [before] where there is
/// one, else after the radars, before the first rain source that is not
/// one (the satellite); any source of its id before taken out.
List<WeatherMapSource> _withRelayRadar(
  List<WeatherMapSource> sources,
  WeatherMapSource radar, {
  String? before,
}) {
  final out = <WeatherMapSource>[
    for (final s in sources)
      if (s.id != radar.id) s,
  ];
  var at = before == null ? -1 : out.indexWhere((s) => s.id == before);
  if (at < 0) {
    at = out.indexWhere(
      (s) => s.kind == WeatherKind.radar && s.role != RainRole.radar,
    );
  }
  return out..insert(at < 0 ? out.length : at, radar);
}

/// The OPERA composite's grid, the ring its images are drawn in: its box in
/// its own projection (centred on 55° N 10° E, 3800 × 4400 cells of 1 km
/// from −500 m east, 500 m north of its false origin), kept 3 km inside, 40
/// points an edge.
const List<LatLng> operaRadarExtent = <LatLng>[
  LatLng(67.022, -39.453),
  LatLng(67.589, -37.818),
  LatLng(68.141, -36.111),
  LatLng(68.676, -34.330),
  LatLng(69.193, -32.470),
  LatLng(69.691, -30.529),
  LatLng(70.169, -28.503),
  LatLng(70.626, -26.391),
  LatLng(71.059, -24.191),
  LatLng(71.467, -21.901),
  LatLng(71.850, -19.522),
  LatLng(72.205, -17.053),
  LatLng(72.530, -14.497),
  LatLng(72.824, -11.857),
  LatLng(73.086, -9.137),
  LatLng(73.313, -6.345),
  LatLng(73.505, -3.487),
  LatLng(73.661, -0.573),
  LatLng(73.779, 2.386),
  LatLng(73.858, 5.379),
  LatLng(73.899, 8.392),
  LatLng(73.900, 11.412),
  LatLng(73.862, 14.427),
  LatLng(73.785, 17.421),
  LatLng(73.670, 20.383),
  LatLng(73.516, 23.300),
  LatLng(73.327, 26.162),
  LatLng(73.101, 28.959),
  LatLng(72.842, 31.683),
  LatLng(72.550, 34.328),
  LatLng(72.227, 36.890),
  LatLng(71.874, 39.364),
  LatLng(71.493, 41.750),
  LatLng(71.086, 44.045),
  LatLng(70.654, 46.251),
  LatLng(70.199, 48.369),
  LatLng(69.723, 50.400),
  LatLng(69.226, 52.346),
  LatLng(68.710, 54.211),
  LatLng(68.176, 55.998),
  LatLng(67.625, 57.709),
  LatLng(66.904, 55.964),
  LatLng(66.162, 54.329),
  LatLng(65.404, 52.797),
  LatLng(64.629, 51.360),
  LatLng(63.839, 50.012),
  LatLng(63.037, 48.747),
  LatLng(62.223, 47.557),
  LatLng(61.397, 46.437),
  LatLng(60.562, 45.383),
  LatLng(59.717, 44.389),
  LatLng(58.864, 43.450),
  LatLng(58.003, 42.564),
  LatLng(57.136, 41.726),
  LatLng(56.261, 40.933),
  LatLng(55.380, 40.181),
  LatLng(54.494, 39.468),
  LatLng(53.602, 38.791),
  LatLng(52.705, 38.148),
  LatLng(51.803, 37.536),
  LatLng(50.896, 36.953),
  LatLng(49.986, 36.398),
  LatLng(49.071, 35.869),
  LatLng(48.152, 35.364),
  LatLng(47.230, 34.882),
  LatLng(46.303, 34.421),
  LatLng(45.374, 33.980),
  LatLng(44.441, 33.558),
  LatLng(43.504, 33.154),
  LatLng(42.565, 32.766),
  LatLng(41.622, 32.395),
  LatLng(40.676, 32.039),
  LatLng(39.727, 31.696),
  LatLng(38.775, 31.368),
  LatLng(37.820, 31.052),
  LatLng(36.862, 30.748),
  LatLng(35.901, 30.456),
  LatLng(34.937, 30.175),
  LatLng(33.970, 29.905),
  LatLng(33.000, 29.644),
  LatLng(32.027, 29.393),
  LatLng(32.244, 28.427),
  LatLng(32.451, 27.456),
  LatLng(32.646, 26.480),
  LatLng(32.831, 25.501),
  LatLng(33.004, 24.518),
  LatLng(33.166, 23.531),
  LatLng(33.316, 22.541),
  LatLng(33.456, 21.547),
  LatLng(33.583, 20.550),
  LatLng(33.700, 19.551),
  LatLng(33.804, 18.549),
  LatLng(33.898, 17.545),
  LatLng(33.979, 16.539),
  LatLng(34.049, 15.531),
  LatLng(34.107, 14.521),
  LatLng(34.154, 13.510),
  LatLng(34.189, 12.499),
  LatLng(34.212, 11.486),
  LatLng(34.223, 10.474),
  LatLng(34.223, 9.461),
  LatLng(34.211, 8.448),
  LatLng(34.187, 7.436),
  LatLng(34.151, 6.424),
  LatLng(34.104, 5.413),
  LatLng(34.045, 4.404),
  LatLng(33.974, 3.396),
  LatLng(33.892, 2.390),
  LatLng(33.798, 1.386),
  LatLng(33.692, 0.384),
  LatLng(33.575, -0.615),
  LatLng(33.447, -1.612),
  LatLng(33.307, -2.605),
  LatLng(33.156, -3.595),
  LatLng(32.993, -4.582),
  LatLng(32.819, -5.565),
  LatLng(32.634, -6.544),
  LatLng(32.438, -7.519),
  LatLng(32.231, -8.490),
  LatLng(32.012, -9.456),
  LatLng(31.783, -10.418),
  LatLng(32.753, -10.680),
  LatLng(33.719, -10.952),
  LatLng(34.683, -11.235),
  LatLng(35.643, -11.529),
  LatLng(36.600, -11.834),
  LatLng(37.554, -12.151),
  LatLng(38.504, -12.481),
  LatLng(39.452, -12.824),
  LatLng(40.396, -13.181),
  LatLng(41.337, -13.552),
  LatLng(42.275, -13.940),
  LatLng(43.209, -14.343),
  LatLng(44.140, -14.764),
  LatLng(45.067, -15.204),
  LatLng(45.991, -15.662),
  LatLng(46.911, -16.142),
  LatLng(47.827, -16.643),
  LatLng(48.739, -17.168),
  LatLng(49.646, -17.717),
  LatLng(50.549, -18.292),
  LatLng(51.448, -18.896),
  LatLng(52.341, -19.530),
  LatLng(53.230, -20.195),
  LatLng(54.113, -20.895),
  LatLng(54.990, -21.631),
  LatLng(55.861, -22.406),
  LatLng(56.725, -23.223),
  LatLng(57.582, -24.086),
  LatLng(58.431, -24.996),
  LatLng(59.272, -25.958),
  LatLng(60.104, -26.976),
  LatLng(60.926, -28.054),
  LatLng(61.737, -29.197),
  LatLng(62.537, -30.409),
  LatLng(63.324, -31.695),
  LatLng(64.097, -33.062),
  LatLng(64.855, -34.514),
  LatLng(65.597, -36.059),
  LatLng(66.320, -37.703),
];

/// Where the OPERA radars reach: the cells measured (dry or rain, not "no
/// data") in any of three frames of 2026-10-12, on an 8 km grid, eroded by
/// a cell and simplified to within 6 km; the mainland, Iceland, Malta and
/// western Greece. A ring has no holes: the gaps inside the mainland where
/// no radar of the network reaches count as reached here, and each frame's
/// grey says where it actually measures.
const List<List<LatLng>> operaRadarReach = <List<LatLng>>[
  _operaReachMainland,
  _operaReachIceland,
  _operaReachMalta,
  _operaReachGreece,
];

const List<LatLng> _operaReachMainland = <LatLng>[
  LatLng(72.56, 30.62),
  LatLng(72.28, 32.53),
  LatLng(71.88, 33.99),
  LatLng(70.86, 35.30),
  LatLng(70.25, 35.20),
  LatLng(69.38, 34.15),
  LatLng(69.16, 33.47),
  LatLng(68.96, 33.25),
  LatLng(68.71, 33.40),
  LatLng(67.83, 33.10),
  LatLng(67.31, 32.39),
  LatLng(66.99, 32.48),
  LatLng(66.66, 32.16),
  LatLng(66.56, 32.27),
  LatLng(65.98, 31.56),
  LatLng(65.71, 31.88),
  LatLng(65.64, 32.37),
  LatLng(65.27, 33.33),
  LatLng(64.51, 34.26),
  LatLng(63.65, 34.37),
  LatLng(62.95, 33.94),
  LatLng(62.18, 34.45),
  LatLng(61.30, 34.22),
  LatLng(61.03, 34.01),
  LatLng(60.37, 33.03),
  LatLng(60.10, 32.38),
  LatLng(59.76, 30.79),
  LatLng(59.51, 30.48),
  LatLng(59.18, 29.69),
  LatLng(58.97, 29.57),
  LatLng(58.43, 29.69),
  LatLng(57.47, 29.16),
  LatLng(56.98, 28.49),
  LatLng(56.55, 27.33),
  LatLng(56.31, 27.48),
  LatLng(55.99, 28.13),
  LatLng(55.55, 28.59),
  LatLng(54.99, 28.84),
  LatLng(54.47, 28.85),
  LatLng(53.52, 28.29),
  LatLng(52.92, 27.41),
  LatLng(52.61, 26.54),
  LatLng(52.50, 25.77),
  LatLng(52.48, 24.80),
  LatLng(52.37, 24.52),
  LatLng(51.81, 24.33),
  LatLng(50.96, 25.23),
  LatLng(50.19, 25.44),
  LatLng(49.21, 25.12),
  LatLng(48.96, 24.81),
  LatLng(48.75, 24.75),
  LatLng(48.25, 25.15),
  LatLng(48.83, 26.22),
  LatLng(49.03, 27.31),
  LatLng(49.02, 27.76),
  LatLng(48.84, 28.82),
  LatLng(48.57, 29.50),
  LatLng(48.26, 29.94),
  LatLng(47.57, 30.44),
  LatLng(46.96, 30.51),
  LatLng(46.06, 30.16),
  LatLng(45.88, 29.98),
  LatLng(45.28, 30.70),
  LatLng(44.69, 31.00),
  LatLng(44.24, 31.04),
  LatLng(43.96, 30.93),
  LatLng(43.87, 31.00),
  LatLng(43.27, 30.67),
  LatLng(42.73, 30.07),
  LatLng(42.38, 29.24),
  LatLng(42.25, 28.40),
  LatLng(42.25, 28.00),
  LatLng(42.59, 26.50),
  LatLng(42.52, 26.08),
  LatLng(42.64, 25.32),
  LatLng(42.47, 24.98),
  LatLng(42.35, 24.36),
  LatLng(42.32, 23.56),
  LatLng(42.52, 22.62),
  LatLng(42.82, 22.00),
  LatLng(43.24, 21.49),
  LatLng(43.80, 21.10),
  LatLng(43.19, 19.99),
  LatLng(42.99, 18.97),
  LatLng(43.07, 18.10),
  LatLng(42.53, 17.54),
  LatLng(42.21, 17.01),
  LatLng(42.03, 16.51),
  LatLng(41.87, 15.53),
  LatLng(41.91, 14.76),
  LatLng(42.17, 13.82),
  LatLng(42.48, 13.26),
  LatLng(43.15, 12.61),
  LatLng(43.31, 12.23),
  LatLng(43.17, 12.03),
  LatLng(42.51, 12.39),
  LatLng(41.71, 12.36),
  LatLng(40.85, 11.85),
  LatLng(40.28, 11.00),
  LatLng(39.85, 9.41),
  LatLng(39.83, 8.12),
  LatLng(39.97, 7.56),
  LatLng(40.31, 6.80),
  LatLng(41.14, 5.90),
  LatLng(41.13, 5.62),
  LatLng(41.32, 5.03),
  LatLng(41.08, 4.67),
  LatLng(40.87, 4.69),
  LatLng(40.19, 4.28),
  LatLng(39.71, 3.67),
  LatLng(39.36, 2.88),
  LatLng(39.32, 2.33),
  LatLng(39.24, 2.24),
  LatLng(39.25, 1.50),
  LatLng(39.39, 0.74),
  LatLng(39.63, 0.24),
  LatLng(39.57, -0.96),
  LatLng(39.02, -1.33),
  LatLng(38.61, -0.43),
  LatLng(38.29, -0.02),
  LatLng(37.40, 0.57),
  LatLng(36.82, 0.65),
  LatLng(35.83, 0.34),
  LatLng(35.26, -0.20),
  LatLng(34.76, -1.26),
  LatLng(34.66, -2.03),
  LatLng(34.72, -2.12),
  LatLng(34.67, -2.47),
  LatLng(34.81, -3.01),
  LatLng(34.76, -3.36),
  LatLng(34.53, -3.84),
  LatLng(34.44, -4.87),
  LatLng(34.74, -6.08),
  LatLng(35.33, -6.92),
  LatLng(35.14, -7.86),
  LatLng(35.28, -8.97),
  LatLng(35.81, -9.93),
  LatLng(36.58, -10.52),
  LatLng(37.06, -10.67),
  LatLng(37.15, -10.61),
  LatLng(37.43, -10.69),
  LatLng(37.68, -10.59),
  LatLng(38.20, -10.94),
  LatLng(38.97, -11.19),
  LatLng(39.90, -11.03),
  LatLng(40.44, -10.63),
  LatLng(41.03, -9.65),
  LatLng(41.24, -8.63),
  LatLng(41.19, -8.13),
  LatLng(41.38, -7.50),
  LatLng(41.55, -7.35),
  LatLng(42.13, -7.43),
  LatLng(42.68, -7.29),
  LatLng(43.35, -6.79),
  LatLng(43.65, -6.37),
  LatLng(43.90, -5.73),
  LatLng(44.47, -5.38),
  LatLng(44.91, -4.88),
  LatLng(45.21, -4.34),
  LatLng(45.37, -3.76),
  LatLng(45.54, -3.60),
  LatLng(45.68, -3.63),
  LatLng(46.34, -4.65),
  LatLng(46.47, -5.76),
  LatLng(46.85, -6.63),
  LatLng(47.60, -7.42),
  LatLng(48.37, -7.70),
  LatLng(48.60, -7.67),
  LatLng(49.22, -8.36),
  LatLng(49.84, -8.60),
  LatLng(50.45, -8.50),
  LatLng(50.55, -8.78),
  LatLng(50.53, -9.36),
  LatLng(50.66, -10.24),
  LatLng(51.07, -11.26),
  LatLng(51.66, -12.05),
  LatLng(52.77, -12.51),
  LatLng(53.15, -12.46),
  LatLng(53.74, -12.15),
  LatLng(54.35, -11.32),
  LatLng(54.61, -10.68),
  LatLng(54.69, -10.20),
  LatLng(55.79, -9.45),
  LatLng(56.39, -8.42),
  LatLng(56.61, -8.93),
  LatLng(57.22, -9.80),
  LatLng(58.11, -10.31),
  LatLng(58.88, -10.19),
  LatLng(59.39, -9.76),
  LatLng(60.00, -8.63),
  LatLng(60.15, -8.12),
  LatLng(60.39, -6.15),
  LatLng(60.16, -4.26),
  LatLng(59.57, -2.86),
  LatLng(59.60, -1.72),
  LatLng(59.42, -0.37),
  LatLng(58.81, 1.21),
  LatLng(58.97, 1.45),
  LatLng(59.31, 1.09),
  LatLng(60.02, 0.90),
  LatLng(60.92, 1.39),
  LatLng(61.40, 2.16),
  LatLng(61.66, 2.86),
  LatLng(61.95, 4.62),
  LatLng(61.85, 6.16),
  LatLng(62.23, 6.73),
  LatLng(63.14, 5.68),
  LatLng(64.14, 5.52),
  LatLng(64.81, 6.09),
  LatLng(65.33, 7.04),
  LatLng(65.84, 7.16),
  LatLng(66.28, 7.64),
  LatLng(66.99, 6.84),
  LatLng(67.63, 6.57),
  LatLng(67.71, 6.75),
  LatLng(68.29, 6.86),
  LatLng(68.81, 7.58),
  LatLng(69.25, 8.73),
  LatLng(69.55, 10.14),
  LatLng(70.20, 10.56),
  LatLng(70.55, 11.21),
  LatLng(71.05, 12.77),
  LatLng(71.24, 14.12),
  LatLng(71.34, 16.14),
  LatLng(71.47, 16.63),
  LatLng(72.02, 17.52),
  LatLng(72.52, 19.63),
  LatLng(72.67, 21.15),
  LatLng(72.70, 23.12),
  LatLng(72.63, 24.28),
  LatLng(72.36, 25.99),
  LatLng(72.51, 26.86),
  LatLng(72.61, 28.43),
  LatLng(72.51, 30.31),
];

const List<LatLng> _operaReachIceland = <LatLng>[
  LatLng(67.66, -23.70),
  LatLng(68.10, -21.53),
  LatLng(68.16, -20.32),
  LatLng(68.13, -19.19),
  LatLng(67.95, -17.90),
  LatLng(67.61, -16.65),
  LatLng(67.04, -15.80),
  LatLng(67.00, -15.56),
  LatLng(66.22, -15.12),
  LatLng(65.49, -15.32),
  LatLng(65.12, -15.69),
  LatLng(64.67, -16.52),
  LatLng(64.28, -17.76),
  LatLng(63.62, -17.96),
  LatLng(63.06, -18.43),
  LatLng(62.38, -19.81),
  LatLng(62.00, -21.47),
  LatLng(61.93, -22.44),
  LatLng(61.95, -23.34),
  LatLng(62.12, -24.60),
  LatLng(62.47, -25.78),
  LatLng(63.21, -27.00),
  LatLng(63.71, -27.34),
  LatLng(64.18, -27.46),
  LatLng(64.96, -27.06),
  LatLng(65.36, -26.46),
  LatLng(65.68, -25.51),
  LatLng(66.83, -25.21),
  LatLng(67.46, -24.26),
];

const List<LatLng> _operaReachMalta = <LatLng>[
  LatLng(37.58, 14.09),
  LatLng(37.53, 15.08),
  LatLng(37.27, 15.77),
  LatLng(36.95, 16.19),
  LatLng(36.26, 16.57),
  LatLng(35.60, 16.60),
  LatLng(35.53, 16.50),
  LatLng(35.24, 16.48),
  LatLng(34.82, 16.18),
  LatLng(34.48, 15.81),
  LatLng(34.16, 15.01),
  LatLng(34.23, 13.73),
  LatLng(34.31, 13.48),
  LatLng(34.47, 13.15),
  LatLng(34.93, 12.65),
  LatLng(35.37, 12.40),
  LatLng(36.11, 12.34),
  LatLng(36.18, 12.43),
  LatLng(36.47, 12.44),
  LatLng(36.90, 12.72),
  LatLng(37.32, 13.27),
];

const List<LatLng> _operaReachGreece = <LatLng>[
  LatLng(39.48, 21.17),
  LatLng(39.37, 21.99),
  LatLng(39.06, 22.68),
  LatLng(38.64, 23.06),
  LatLng(38.17, 23.24),
  LatLng(37.66, 23.23),
  LatLng(36.85, 22.71),
  LatLng(36.55, 22.21),
  LatLng(36.38, 21.28),
  LatLng(36.45, 20.67),
  LatLng(36.75, 20.00),
  LatLng(37.00, 19.68),
  LatLng(37.70, 19.33),
  LatLng(38.50, 19.44),
  LatLng(38.97, 19.79),
  LatLng(39.40, 20.60),
];

/// The id of the DPC's radar over Italy ([dpcRadar]).
const String dpcRadarId = 'radar_dpc';

/// The path under the relay the DPC's radar is served from.
const String dpcRadarPath = '/weather/radar/dpc';

/// Rain radar over Italy for Velorki Plus: the surface rainfall intensity
/// (SRI, mm an hour, the national radar network adjusted by rain gauges) of
/// the Dipartimento della Protezione Civile's Radar-DPC platform, CC BY-SA
/// 4.0, every five minutes, drawn by the relay at [relayBase] from the
/// DPC's data alone (`{base}/weather/radar/dpc/image`) in the DWD radar's
/// classes and colours ([RainPalette.dwd]), its "no data" grey; the past
/// two hours, no forecast. Listed with the national radars, before
/// [operaRadar], so over Italy and its seas the DPC's radar draws and OPERA
/// around it; before the satellite. Requested as [operaRadar] is, with the
/// relay's credentials (see `relayAuthFor`).
///
/// The product's grid (Transverse Mercator about 42° N 12.5° E, 1200 × 1400
/// km) bounds its images ([dpcRadarExtent]); where its radars reach
/// ([dpcRadarReach]) each frame says itself in its grey.
WeatherMapSource dpcRadar(String relayBase) => _relayRadar(
  relayBase,
  id: dpcRadarId,
  path: dpcRadarPath,
  // The product's grid's box, as the relay checks it.
  coverage: _box(4.5, 35, 20.5, 47.9),
  reach: dpcRadarReach,
  extent: dpcRadarExtent,
  attribution:
      'Radar: Radar-DPC, Dipartimento della Protezione Civile (CC BY-SA 4.0)',
);

/// [sources] with [dpcRadar] of [relayBase] put with the national radars:
/// before [operaRadar] where it is there, else before the first rain source
/// that is not a radar (the satellite).
List<WeatherMapSource> withDpcRadar(
  List<WeatherMapSource> sources,
  String relayBase,
) => _withRelayRadar(sources, dpcRadar(relayBase), before: operaRadarId);

/// The DPC's grid, the ring its images are drawn in: its box in its own
/// projection (1200 × 1400 cells of 1 km from 600 km west and 650 km north
/// of 42° N 12.5° E), kept 3 km inside, 40 points an edge.
const List<LatLng> dpcRadarExtent = <LatLng>[
  LatLng(47.547, 4.567),
  LatLng(47.574, 4.960),
  LatLng(47.599, 5.354),
  LatLng(47.623, 5.748),
  LatLng(47.646, 6.142),
  LatLng(47.667, 6.537),
  LatLng(47.687, 6.933),
  LatLng(47.705, 7.329),
  LatLng(47.723, 7.725),
  LatLng(47.738, 8.122),
  LatLng(47.753, 8.519),
  LatLng(47.766, 8.916),
  LatLng(47.778, 9.314),
  LatLng(47.788, 9.711),
  LatLng(47.797, 10.109),
  LatLng(47.805, 10.507),
  LatLng(47.811, 10.906),
  LatLng(47.816, 11.304),
  LatLng(47.819, 11.703),
  LatLng(47.821, 12.101),
  LatLng(47.822, 12.500),
  LatLng(47.821, 12.899),
  LatLng(47.819, 13.297),
  LatLng(47.816, 13.696),
  LatLng(47.811, 14.094),
  LatLng(47.805, 14.493),
  LatLng(47.797, 14.891),
  LatLng(47.788, 15.289),
  LatLng(47.778, 15.686),
  LatLng(47.766, 16.084),
  LatLng(47.753, 16.481),
  LatLng(47.738, 16.878),
  LatLng(47.723, 17.275),
  LatLng(47.705, 17.671),
  LatLng(47.687, 18.067),
  LatLng(47.667, 18.463),
  LatLng(47.646, 18.858),
  LatLng(47.623, 19.252),
  LatLng(47.599, 19.646),
  LatLng(47.574, 20.040),
  LatLng(47.547, 20.433),
  LatLng(47.236, 20.386),
  LatLng(46.926, 20.340),
  LatLng(46.615, 20.295),
  LatLng(46.305, 20.251),
  LatLng(45.994, 20.207),
  LatLng(45.683, 20.164),
  LatLng(45.373, 20.122),
  LatLng(45.062, 20.080),
  LatLng(44.751, 20.039),
  LatLng(44.440, 19.999),
  LatLng(44.129, 19.959),
  LatLng(43.818, 19.920),
  LatLng(43.507, 19.881),
  LatLng(43.196, 19.844),
  LatLng(42.885, 19.806),
  LatLng(42.574, 19.770),
  LatLng(42.262, 19.734),
  LatLng(41.951, 19.698),
  LatLng(41.640, 19.663),
  LatLng(41.328, 19.629),
  LatLng(41.017, 19.595),
  LatLng(40.706, 19.562),
  LatLng(40.394, 19.529),
  LatLng(40.083, 19.497),
  LatLng(39.771, 19.465),
  LatLng(39.460, 19.433),
  LatLng(39.148, 19.403),
  LatLng(38.836, 19.372),
  LatLng(38.525, 19.342),
  LatLng(38.213, 19.313),
  LatLng(37.901, 19.284),
  LatLng(37.589, 19.255),
  LatLng(37.277, 19.227),
  LatLng(36.966, 19.200),
  LatLng(36.654, 19.172),
  LatLng(36.342, 19.146),
  LatLng(36.030, 19.119),
  LatLng(35.718, 19.093),
  LatLng(35.406, 19.068),
  LatLng(35.094, 19.042),
  LatLng(35.111, 18.717),
  LatLng(35.127, 18.391),
  LatLng(35.143, 18.065),
  LatLng(35.157, 17.739),
  LatLng(35.171, 17.413),
  LatLng(35.184, 17.086),
  LatLng(35.196, 16.760),
  LatLng(35.207, 16.433),
  LatLng(35.217, 16.106),
  LatLng(35.226, 15.778),
  LatLng(35.235, 15.451),
  LatLng(35.242, 15.123),
  LatLng(35.249, 14.796),
  LatLng(35.255, 14.468),
  LatLng(35.260, 14.140),
  LatLng(35.264, 13.812),
  LatLng(35.267, 13.484),
  LatLng(35.269, 13.156),
  LatLng(35.270, 12.828),
  LatLng(35.271, 12.500),
  LatLng(35.270, 12.172),
  LatLng(35.269, 11.844),
  LatLng(35.267, 11.516),
  LatLng(35.264, 11.188),
  LatLng(35.260, 10.860),
  LatLng(35.255, 10.532),
  LatLng(35.249, 10.204),
  LatLng(35.242, 9.877),
  LatLng(35.235, 9.549),
  LatLng(35.226, 9.222),
  LatLng(35.217, 8.894),
  LatLng(35.207, 8.567),
  LatLng(35.196, 8.240),
  LatLng(35.184, 7.914),
  LatLng(35.171, 7.587),
  LatLng(35.157, 7.261),
  LatLng(35.143, 6.935),
  LatLng(35.127, 6.609),
  LatLng(35.111, 6.283),
  LatLng(35.094, 5.958),
  LatLng(35.406, 5.932),
  LatLng(35.718, 5.907),
  LatLng(36.030, 5.881),
  LatLng(36.342, 5.854),
  LatLng(36.654, 5.828),
  LatLng(36.966, 5.800),
  LatLng(37.277, 5.773),
  LatLng(37.589, 5.745),
  LatLng(37.901, 5.716),
  LatLng(38.213, 5.687),
  LatLng(38.525, 5.658),
  LatLng(38.836, 5.628),
  LatLng(39.148, 5.597),
  LatLng(39.460, 5.567),
  LatLng(39.771, 5.535),
  LatLng(40.083, 5.503),
  LatLng(40.394, 5.471),
  LatLng(40.706, 5.438),
  LatLng(41.017, 5.405),
  LatLng(41.328, 5.371),
  LatLng(41.640, 5.337),
  LatLng(41.951, 5.302),
  LatLng(42.262, 5.266),
  LatLng(42.574, 5.230),
  LatLng(42.885, 5.194),
  LatLng(43.196, 5.156),
  LatLng(43.507, 5.119),
  LatLng(43.818, 5.080),
  LatLng(44.129, 5.041),
  LatLng(44.440, 5.001),
  LatLng(44.751, 4.961),
  LatLng(45.062, 4.920),
  LatLng(45.373, 4.878),
  LatLng(45.683, 4.836),
  LatLng(45.994, 4.793),
  LatLng(46.305, 4.749),
  LatLng(46.615, 4.705),
  LatLng(46.926, 4.660),
  LatLng(47.236, 4.614),
];

/// Where the DPC's radars reach: the cells measured (dry or rain, not "no
/// data") in any of twelve frames of 2026-10-08 to 10-13, on an 8 km grid
/// (half its cells measured), eroded by a cell and simplified to within 6
/// km: the mainland, Sardinia and Corsica, Sicily and the seas between, in
/// one ring. A ring has no holes: the gaps inside where no radar reaches
/// count as reached here, and each frame's grey says where it actually
/// measures.
const List<List<LatLng>> dpcRadarReach = <List<LatLng>>[_dpcReach];

const List<LatLng> _dpcReach = <LatLng>[
  LatLng(47.77, 11.11),
  LatLng(47.76, 14.74),
  LatLng(47.61, 14.95),
  LatLng(47.46, 14.94),
  LatLng(47.39, 15.15),
  LatLng(47.10, 15.24),
  LatLng(47.09, 15.35),
  LatLng(46.23, 15.40),
  LatLng(46.23, 15.30),
  LatLng(45.16, 15.15),
  LatLng(45.16, 15.04),
  LatLng(44.73, 14.82),
  LatLng(44.66, 14.62),
  LatLng(44.52, 14.61),
  LatLng(44.38, 14.31),
  LatLng(44.16, 14.30),
  LatLng(44.02, 14.60),
  LatLng(43.87, 14.59),
  LatLng(43.65, 14.88),
  LatLng(43.56, 15.47),
  LatLng(43.49, 15.47),
  LatLng(43.41, 15.86),
  LatLng(43.26, 15.95),
  LatLng(43.26, 16.15),
  LatLng(42.96, 16.52),
  LatLng(42.81, 16.51),
  LatLng(42.73, 16.70),
  LatLng(42.08, 16.95),
  LatLng(42.06, 17.24),
  LatLng(42.14, 17.24),
  LatLng(42.12, 17.53),
  LatLng(42.20, 17.54),
  LatLng(42.18, 17.92),
  LatLng(42.25, 17.93),
  LatLng(42.22, 18.51),
  LatLng(42.15, 18.50),
  LatLng(42.05, 18.97),
  LatLng(41.83, 19.05),
  LatLng(41.65, 19.60),
  LatLng(39.08, 19.34),
  LatLng(39.09, 19.15),
  LatLng(38.95, 19.05),
  LatLng(38.96, 18.87),
  LatLng(38.83, 18.67),
  LatLng(38.27, 18.35),
  LatLng(37.93, 17.87),
  LatLng(37.94, 17.69),
  LatLng(37.74, 17.40),
  LatLng(37.68, 16.94),
  LatLng(36.75, 16.98),
  LatLng(36.75, 16.89),
  LatLng(36.32, 16.78),
  LatLng(36.26, 16.59),
  LatLng(36.11, 16.59),
  LatLng(35.63, 15.94),
  LatLng(35.63, 15.77),
  LatLng(35.49, 15.59),
  LatLng(35.50, 15.32),
  LatLng(35.43, 15.32),
  LatLng(35.37, 14.61),
  LatLng(35.44, 14.61),
  LatLng(35.45, 14.17),
  LatLng(35.52, 14.18),
  LatLng(35.67, 13.65),
  LatLng(36.25, 12.95),
  LatLng(36.83, 12.77),
  LatLng(36.83, 12.68),
  LatLng(37.48, 12.68),
  LatLng(37.48, 12.77),
  LatLng(37.69, 12.77),
  LatLng(37.69, 12.86),
  LatLng(38.13, 13.05),
  LatLng(38.55, 13.60),
  LatLng(38.55, 13.78),
  LatLng(38.62, 13.79),
  LatLng(38.62, 13.97),
  LatLng(38.76, 14.16),
  LatLng(38.76, 14.43),
  LatLng(39.26, 14.45),
  LatLng(39.27, 14.35),
  LatLng(40.06, 14.47),
  LatLng(40.06, 14.00),
  LatLng(40.14, 14.00),
  LatLng(40.21, 13.63),
  LatLng(40.36, 13.54),
  LatLng(40.36, 13.07),
  LatLng(40.29, 13.06),
  LatLng(40.29, 12.78),
  LatLng(40.22, 12.78),
  LatLng(40.21, 11.75),
  LatLng(39.64, 11.75),
  LatLng(39.64, 11.66),
  LatLng(39.20, 11.57),
  LatLng(38.99, 11.30),
  LatLng(38.84, 11.30),
  LatLng(38.55, 10.94),
  LatLng(38.55, 10.76),
  LatLng(38.40, 10.67),
  LatLng(38.40, 10.49),
  LatLng(38.25, 10.31),
  LatLng(38.24, 9.94),
  LatLng(38.17, 9.94),
  LatLng(38.15, 9.21),
  LatLng(38.23, 9.21),
  LatLng(38.21, 8.85),
  LatLng(38.29, 8.84),
  LatLng(38.41, 8.29),
  LatLng(38.96, 7.61),
  LatLng(38.95, 7.33),
  LatLng(39.15, 7.04),
  LatLng(39.14, 6.86),
  LatLng(39.41, 6.46),
  LatLng(39.56, 6.45),
  LatLng(39.62, 6.26),
  LatLng(39.76, 6.25),
  LatLng(39.89, 6.05),
  LatLng(40.18, 6.02),
  LatLng(40.17, 5.93),
  LatLng(41.04, 5.94),
  LatLng(41.04, 6.03),
  LatLng(41.34, 6.10),
  LatLng(41.42, 6.28),
  LatLng(41.56, 6.27),
  LatLng(41.87, 6.62),
  LatLng(41.88, 6.81),
  LatLng(42.03, 6.90),
  LatLng(42.20, 7.66),
  LatLng(42.28, 7.65),
  LatLng(42.31, 8.43),
  LatLng(42.23, 8.43),
  LatLng(42.24, 8.72),
  LatLng(42.17, 8.72),
  LatLng(42.18, 9.01),
  LatLng(42.11, 9.02),
  LatLng(42.06, 9.99),
  LatLng(42.35, 9.98),
  LatLng(42.48, 9.39),
  LatLng(42.82, 8.88),
  LatLng(42.79, 7.81),
  LatLng(42.86, 7.80),
  LatLng(42.91, 7.31),
  LatLng(43.05, 7.20),
  LatLng(43.04, 7.00),
  LatLng(43.24, 6.69),
  LatLng(43.38, 6.68),
  LatLng(43.44, 6.47),
  LatLng(43.80, 6.34),
  LatLng(43.79, 6.24),
  LatLng(44.15, 6.20),
  LatLng(44.14, 6.10),
  LatLng(44.29, 6.09),
  LatLng(44.42, 5.87),
  LatLng(44.63, 5.85),
  LatLng(44.63, 5.75),
  LatLng(45.27, 5.67),
  LatLng(45.28, 5.77),
  LatLng(45.64, 5.83),
  LatLng(46.26, 6.59),
  LatLng(46.63, 6.75),
  LatLng(46.93, 7.14),
  LatLng(47.10, 7.65),
  LatLng(47.25, 7.74),
  LatLng(47.26, 8.06),
  LatLng(47.41, 8.26),
  LatLng(47.43, 8.79),
  LatLng(47.50, 8.78),
  LatLng(47.52, 9.53),
  LatLng(47.45, 9.53),
  LatLng(47.46, 10.06),
  LatLng(47.39, 10.06),
  LatLng(47.40, 10.70),
  LatLng(47.48, 10.70),
  LatLng(47.55, 11.01),
];

/// Base reflectivity over the US from the National Weather Service: the
/// past two hours, no forecast.
///
/// `format=png32`, not `png`: the plain PNG is RGB with a colour key for
/// transparency, which MapLibre's Android decoder rejects. The soft look's
/// image is asked for with `interpolation=RSP_NearestNeighbor`: the
/// service resamples bilinearly by default, mixing its colours into ones
/// its ramp does not hold ([RainPalette.noaa]), and the phone smooths it
/// anyway.
final WeatherMapSource noaaRadar = WeatherMapSource(
  id: 'radar_noaa',
  kind: WeatherKind.radar,
  palette: RainPalette.noaa,
  urlTemplate:
      'https://mapservices.weather.noaa.gov/eventdriven/rest/services/radar/'
      'radar_base_reflectivity_time/ImageServer/exportImage'
      '?bbox={bbox-epsg-3857}&bboxSR=3857&imageSR=3857&size=256,256'
      '&format=png32&transparent=true&time={timeMs}&f=image',
  imageUrlTemplate:
      'https://mapservices.weather.noaa.gov/eventdriven/rest/services/radar/'
      'radar_base_reflectivity_time/ImageServer/exportImage'
      '?bbox={bbox-epsg-3857}&bboxSR=3857&imageSR=3857'
      '&size={width},{height}&format=png32&transparent=true&time={timeMs}'
      '&interpolation=RSP_NearestNeighbor&f=image',
  // The mosaic is gridded at about a kilometre.
  nativeMetresPerPixel: 1000,
  // Its newest frame is some 14 minutes old, and a moment it has no frame
  // for yet comes back as an empty image, not an error: dry, not missing.
  delayMinutes: 20,
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

/// Rain from satellite over Europe, Africa and the Atlantic: the EUMETSAT
/// H SAF product H40B, Meteosat Third Generation's infrared calibrated by
/// microwave passes, every ten minutes; the present only, where no radar
/// reaches.
///
/// Every SAF product is Core data under the EUMETSAT Data Policy, CC BY 4.0
/// at any latency, so unlike the Meteosat images ([eumetsatClouds]) it is
/// taken every ten minutes, as new as it comes ([enforceWeatherLicences]
/// leaves it so). Its newest frame lags 20 minutes to an hour, and the
/// service answers a moment past it with an XML error, not the nearest
/// frame: so the newest one is read off the layer's capabilities
/// ([WeatherMapSource.timesUrl]) and never asked past; until that is known,
/// a 25-minute delay on its 10-minute grid. Where it has no frame of "Now"
/// (it failed, or its newest is too old), ICON-EU's hour stands in
/// ([rainStandIn]). The data reach ±70° from the sub-satellite point; the
/// box keeps to where the view is not too slanted.
final WeatherMapSource hsafRain = WeatherMapSource(
  id: 'rain_hsaf',
  kind: WeatherKind.radar,
  role: RainRole.satellite,
  palette: RainPalette.hsaf,
  urlTemplate: _hsafUrl,
  imageUrlTemplate: _hsafUrl,
  coverage: <BoundingBox>[_box(-60, -60, 60, 66)],
  timeFormat: WeatherTimeFormat.iso,
  stepMinutes: 10,
  delayMinutes: 25,
  historyMinutes: 0,
  // The geostationary infrared is some 3 km a pixel over Europe.
  nativeMetresPerPixel: 3000,
  attribution: 'Satellite rain: Contains modified EUMETSAT H SAF data {year}',
  timesUrl: _eumetsatTimesUrl('mtg_fd', 'h40b'),
);

/// The capabilities of the one EUMETSAT layer [workspace]:[layer], about
/// 6 KB, whose time dimension names its newest frame.
String _eumetsatTimesUrl(String workspace, String layer) =>
    'https://view.eumetsat.int/geoserver/$workspace/$layer/ows'
    '?service=WMS&version=1.3.0&request=GetCapabilities';

const String _hsafUrl =
    'https://view.eumetsat.int/geoserver/ows?service=WMS&version=1.3.0'
    '&request=GetMap&layers=mtg_fd:h40b&styles=&crs=EPSG:3857'
    '&bbox={bbox-epsg-3857}&width={width}&height={height}'
    '&format=image/png&transparent=true&time={time}';

/// The DWD's map service for a model layer [layer] drawn in [style].
String _dwdModelUrl(String layer, String style) =>
    'https://maps.dwd.de/geoserver/dwd/wms?service=WMS&version=1.3.0'
    '&request=GetMap&layers=dwd:$layer&styles=$style&crs=EPSG:3857'
    '&bbox={bbox-epsg-3857}&width={width}&height={height}'
    '&format=image/png&transparent=true&time={time}';

/// The forecast over Europe from the DWD's ICON-EU model: the rain of each
/// hour (`TOTPREC01H`), on a 0.0625° grid, up to 78 hours from each run (00,
/// 06, 12 and 18 UTC). The service serves the latest run, an hour after it
/// to its end; a moment outside answers with an error.
///
/// Asked for in the radar's own style (`niederschlagsradar`), not the
/// layer's, which paints all rain under 2 mm an hour one grey. That style's
/// thresholds are mm in ten minutes, about a sixth of its labels, while the
/// model's values are mm in an hour: drawn as it comes, the forecast would
/// look six times as heavy. So its colours are read back as the rates they
/// stand for here and drawn in the radar's class for each
/// ([RainPalette.dwdModel1h]), and the forecast reads like the radar beside
/// it.
final WeatherMapSource iconEuRain = WeatherMapSource(
  id: 'rain_icon_eu',
  kind: WeatherKind.radar,
  role: RainRole.model,
  urlTemplate: _dwdModelUrl(
    'Icon-eu_reg00625_fd_sl_TOTPREC01H',
    'niederschlagsradar',
  ),
  imageUrlTemplate: _dwdModelUrl(
    'Icon-eu_reg00625_fd_sl_TOTPREC01H',
    'niederschlagsradar',
  ),
  palette: RainPalette.dwdModel1h,
  coverage: <BoundingBox>[_box(-23.5, 29.5, 62.5, 70.5)],
  timeFormat: WeatherTimeFormat.iso,
  stepMinutes: 60,
  delayMinutes: 0,
  historyMinutes: 0,
  // Well inside the 78 hours of a run even half a day after it.
  forecastMinutes: 60 * 60,
  // 0.0625° is about 7 km of Web Mercator x.
  nativeMetresPerPixel: 7000,
  attribution: 'Forecast: Deutscher Wetterdienst (CC BY 4.0)',
);

/// The forecast everywhere else from the DWD's global ICON model, on a
/// 0.25° grid.
///
/// The service has no hourly rain for it: `TOTPREC` is summed from the
/// run's start, so it only grows; the shortest span is `TOTPREC06H`, the
/// rain of the six hours up to 00, 06, 12 and 18 UTC. That is used, each
/// step showing the six hours its hour falls in, recoloured on the phone
/// into the radar's palette at the mean rate per hour (see
/// [RainPalette.dwdModel6h]); drawn as measured it keeps the service's own
/// six-hour scale.
final WeatherMapSource iconGlobalRain = WeatherMapSource(
  id: 'rain_icon',
  kind: WeatherKind.radar,
  role: RainRole.model,
  palette: RainPalette.dwdModel6h,
  urlTemplate: _dwdModelUrl('Icon_reg025_fd_sl_TOTPREC06H', ''),
  imageUrlTemplate: _dwdModelUrl('Icon_reg025_fd_sl_TOTPREC06H', ''),
  coverage: <BoundingBox>[_box(-180, -85, 180, 85)],
  timeFormat: WeatherTimeFormat.iso,
  stepMinutes: 360,
  delayMinutes: 0,
  historyMinutes: 0,
  forecastMinutes: 100 * 60,
  // 0.25° is about 28 km.
  nativeMetresPerPixel: 28000,
  attribution: 'Forecast: Deutscher Wetterdienst (CC BY 4.0)',
);

/// The forecast over the contiguous US from NOAA's HRRR model (3 km,
/// hourly runs to 18 hours ahead), as the Iowa Environmental Mesonet draws
/// its simulated reflectivity (`REFD`) in tiles, every 15 minutes of a run
/// (public domain; attribution appreciated).
///
/// A tile names its run and the minutes from it (`F0015`, …, `F1080`), so
/// the tiles of one run never mix with the next's: the newest run is read
/// off the latest-run document ([parseModelRunTime]), two to three hours
/// behind the clock, and each step shows the frame of that run nearest its
/// moment ([runFrameAt]); a moment past the run's end is left to the
/// global model, and so is everything while the run is not known. Drawn as
/// the radar's classes from IEM's N0Q ramp ([RainPalette.n0q]). The image
/// of a view is put together from the tiles on the phone (z7, some 1.2 km a
/// pixel, at most [weatherMosaicMaxTiles] of them; [tileMosaicOf]).
///
/// The model's grid is a Lambert conformal one, so its edge is no box:
/// [hrrrDomain] is that edge, and the global model after it fades in
/// across the seam inside it, as beside the DWD's radar (see
/// [WeatherMapSource.extent]).
final WeatherMapSource hrrrRain = WeatherMapSource(
  id: 'rain_hrrr',
  kind: WeatherKind.radar,
  role: RainRole.model,
  palette: RainPalette.n0q,
  urlTemplate: _hrrrTiles,
  imageUrlTemplate: _hrrrTiles,
  coverage: <BoundingBox>[_box(-134, 21, -61, 53)],
  reach: const <List<LatLng>>[hrrrDomain],
  extent: hrrrDomain,
  maxZoom: 7,
  timeFormat: WeatherTimeFormat.modelRun,
  stepMinutes: 15,
  delayMinutes: 0,
  historyMinutes: 0,
  forecastMinutes: 18 * 60,
  // 3 km on the ground is about 3.8 km of Web Mercator at 38° N.
  nativeMetresPerPixel: 3800,
  attribution: 'Forecast: NOAA HRRR via Iowa Environmental Mesonet',
  timesUrl:
      'https://mesonet.agron.iastate.edu/data/gis/images/4326/hrrr/'
      'refd_0000.json',
);

const String _hrrrTiles =
    'https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/'
    'hrrr::REFD-F{runMinute}-{run}/{z}/{x}/{y}.png';

/// The edge of the HRRR's grid (Lambert conformal, 38.5° N, 97.5° W,
/// 1799 × 1059 cells of 3 km from 21.138° N, 122.720° W), 30 km inside it,
/// eight points an edge.
const List<LatLng> hrrrDomain = <LatLng>[
  LatLng(21.46, -122.53),
  LatLng(22.82, -116.47),
  LatLng(23.82, -110.25),
  LatLng(24.42, -103.91),
  LatLng(24.63, -97.51),
  LatLng(24.42, -91.10),
  LatLng(23.82, -84.76),
  LatLng(22.83, -78.53),
  LatLng(21.46, -72.48),
  LatLng(24.71, -71.48),
  LatLng(28.00, -70.39),
  LatLng(31.30, -69.21),
  LatLng(34.61, -67.92),
  LatLng(37.92, -66.52),
  LatLng(41.22, -64.99),
  LatLng(44.48, -63.30),
  LatLng(47.70, -61.43),
  LatLng(49.70, -69.84),
  LatLng(51.16, -78.75),
  LatLng(52.06, -88.03),
  LatLng(52.35, -97.51),
  LatLng(52.05, -106.98),
  LatLng(51.16, -116.26),
  LatLng(49.70, -125.17),
  LatLng(47.70, -133.58),
  LatLng(44.48, -131.71),
  LatLng(41.21, -130.03),
  LatLng(37.92, -128.49),
  LatLng(34.61, -127.09),
  LatLng(31.30, -125.80),
  LatLng(27.99, -124.62),
  LatLng(24.71, -123.53),
];

/// The wind 10 m above the ground everywhere, from the DWD's global ICON
/// model on its 0.25° grid: the u and v components of one box at one
/// moment as a plain-text grid from the DWD's WCS (`format=text/plain`;
/// see `parseWcsWindGrid`), drawn as arrows on the phone.
///
/// The coverage's frames are hourly for some three days from each run
/// (then three-hourly), the runs four a day: so every hour of the next 24
/// is there, the hour of "Now" among them. A moment past the newest frame
/// answers with the newest; one before the oldest with an error.
/// `{west}`, `{south}`, `{east}` and `{north}` are the box in degrees, its
/// east past 180° for a box across the antimeridian, which the service
/// wraps.
///
/// The coverage holds the last day and a half of runs, and a request that
/// names none is answered from the oldest; so each names the newest run
/// (`{runTime}`), read off the coverage's DescribeCoverage ([timesUrl],
/// `parseNewestRun`), and there is no wind before it is known.
final WeatherMapSource dwdWind = WeatherMapSource(
  id: 'wind_icon',
  kind: WeatherKind.wind,
  urlTemplate:
      'https://maps.dwd.de/geoserver/ows?service=WCS&version=2.0.1'
      '&request=GetCoverage&coverageId=dwd__Icon_reg025_fd_sl_UV10M'
      '&format=text/plain&subset=Lat({south},{north})'
      '&subset=Long({west},{east})&subset=time(%22{time}%22)'
      '&subset=REFERENCE_TIME(%22{runTime}%22)',
  timesUrl:
      'https://maps.dwd.de/geoserver/ows?service=WCS&version=2.0.1'
      '&request=DescribeCoverage&coverageId=dwd__Icon_reg025_fd_sl_UV10M',
  coverage: <BoundingBox>[_box(-180, -85, 180, 85)],
  timeFormat: WeatherTimeFormat.iso,
  stepMinutes: 60,
  delayMinutes: 0,
  historyMinutes: 0,
  forecastMinutes: 24 * 60,
  // 0.25° is about 28 km.
  nativeMetresPerPixel: 28000,
  attribution: 'Wind: Deutscher Wetterdienst (CC BY 4.0)',
);

/// The NASA GIBS map service the GOES clouds come from: one GetMap for a
/// whole region. `TIME=default` is the latest image, which the URL cannot
/// name, so a region is fetched again with every refresh.
String _gibsGoes(String layer) =>
    'https://gibs.earthdata.nasa.gov/wms/epsg3857/best/wms.cgi?SERVICE=WMS'
    '&REQUEST=GetMap&VERSION=1.3.0&LAYERS=$layer&STYLES=&FORMAT=image/png'
    '&TRANSPARENT=TRUE&CRS=EPSG:3857&BBOX={bbox-epsg-3857}'
    '&WIDTH={width}&HEIGHT={height}&TIME=default';

/// GOES band 13 is sampled every 2 km at the sub-satellite point.
const double goesNativeMetresPerPixel = 2000;

// The cloud sources all reach from 70° south to 70° north, each split at a
// latitude into a northern and a southern image, so a view of one asks for
// one image half the size; neighbours overlap by [cloudSeamWidth] of
// longitude, where each fades into the other ([cloudFadesOf]).

/// How far north and south the satellites' clouds reach, in degrees: some
/// way short of their discs' edges, where the view is too slanted to tell
/// much.
const double cloudMaxLat = 70;

/// How wide the band is where two cloud sources overlap, and one fades
/// into the other, in degrees of longitude.
const double cloudSeamWidth = 10;

/// Infrared clouds over the eastern Americas, GOES-East through NASA GIBS:
/// the latest image only.
final WeatherMapSource goesEastClouds = WeatherMapSource(
  id: 'clouds_goes_east',
  kind: WeatherKind.clouds,
  urlTemplate: _gibsGoes('GOES-East_ABI_Band13_Clean_Infrared'),
  coverage: <BoundingBox>[
    _box(-120, 0, -20, cloudMaxLat),
    _box(-120, -cloudMaxLat, -20, 0),
  ],
  maxZoom: 6,
  nativeMetresPerPixel: goesNativeMetresPerPixel,
  attribution: 'Clouds: NOAA GOES via NASA GIBS',
);

/// The same over the western Americas and the Pacific, GOES-West.
final WeatherMapSource goesWestClouds = WeatherMapSource(
  id: 'clouds_goes_west',
  kind: WeatherKind.clouds,
  urlTemplate: _gibsGoes('GOES-West_ABI_Band13_Clean_Infrared'),
  coverage: <BoundingBox>[
    _box(-180, 0, -110, cloudMaxLat),
    _box(-180, -cloudMaxLat, -110, 0),
    _box(165, 0, 180, cloudMaxLat),
    _box(165, -cloudMaxLat, 180, 0),
  ],
  maxZoom: 6,
  nativeMetresPerPixel: goesNativeMetresPerPixel,
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
  coverage: <BoundingBox>[
    _box(-30, 25, 45, cloudMaxLat),
    _box(-30, -cloudMaxLat, 45, 25),
  ],
  maxZoom: 8,
  timeFormat: WeatherTimeFormat.iso,
  stepMinutes: 60,
  delayMinutes: 20,
  historyMinutes: 0,
  // The high-resolution fast imagery samples its 10.5 µm channel every
  // kilometre.
  nativeMetresPerPixel: 1000,
  // Meteosat's grey is far darker than GOES' for the same cold: matched
  // pixel by pixel where the two overlap over the Atlantic, GOES' clear
  // threshold (110) is about 30 here, and the cold at which GOES turns to
  // its colour scale, full cloud there, about 128. With GOES' window the
  // clouds over Europe came out a fraction of those over America.
  cloudLuminance: (clear: 30, full: 128),
  attribution: 'Clouds: Contains modified EUMETSAT Meteosat data {year}',
  timesUrl: _eumetsatTimesUrl('mtg_fd', 'ir105_hrfi'),
);

/// Where a cloud image fades into a neighbour's: over the band of
/// longitude from [west] to [east], its alpha from none to full eastward
/// ([rising]) or from full to none; beyond the band untouched.
@immutable
class CloudFade {
  /// Creates the fade.
  const CloudFade({
    required this.west,
    required this.east,
    required this.rising,
  });

  final double west;
  final double east;
  final bool rising;

  /// How much of its alpha the image keeps at [lon], 0..1: the ramp
  /// across the band, all of it beyond (where the image is either in full
  /// or, the band being at its box's edge, not at all; another box of the
  /// same source may lie there).
  double factorAt(double lon) {
    if (east <= west || lon <= west || lon >= east) return 1;
    final t = (lon - west) / (east - west);
    return rising ? t : 1 - t;
  }

  /// What names the fade in an image's cache name.
  String get key =>
      '${rising ? 'r' : 'f'}${west.toStringAsFixed(1)}'
      '_${east.toStringAsFixed(1)}';

  @override
  bool operator ==(Object other) =>
      other is CloudFade &&
      other.west == west &&
      other.east == east &&
      other.rising == rising;

  @override
  int get hashCode => Object.hash(west, east, rising);

  @override
  String toString() => 'CloudFade($key)';
}

/// Where [source]'s clouds fade into those of the other enabled cloud
/// sources in [sources]: for each band of longitude where a coverage box of
/// its overlaps one of theirs (at latitudes both reach) and neither holds
/// the other, a ramp across the band, rising where its box begins inside
/// theirs (it lies east of them), falling where it ends there. Two
/// neighbours' ramps over a band add up to one.
List<CloudFade> cloudFadesOf(
  WeatherMapSource source,
  Iterable<WeatherMapSource> sources,
) {
  final out = <CloudFade>{};
  for (final other in sources) {
    if (other.id == source.id ||
        !other.enabled ||
        other.kind != WeatherKind.clouds) {
      continue;
    }
    for (final mine in source.coverage) {
      for (final theirs in other.coverage) {
        final south = math.max(mine.south, theirs.south);
        final north = math.min(mine.north, theirs.north);
        if (north <= south) continue;
        final west = math.max(mine.west, theirs.west);
        final east = math.min(mine.east, theirs.east);
        if (east <= west) continue;
        if (mine.west < theirs.west && mine.east < theirs.east) {
          out.add(CloudFade(west: west, east: east, rising: false));
        } else if (mine.west > theirs.west && mine.east > theirs.east) {
          out.add(CloudFade(west: west, east: east, rising: true));
        }
      }
    }
  }
  return out.toList();
}

/// The sources a build ships with, before the mirror's override.
///
/// The rain sources from the most trusted down: each draws only where none
/// before it shows the same moment (see [rainPartsAt]).
final List<WeatherMapSource> defaultWeatherMapSources = <WeatherMapSource>[
  dwdRadar,
  knmiRadar,
  fmiRadar,
  noaaRadar,
  hsafRain,
  iconEuRain,
  hrrrRain,
  iconGlobalRain,
  goesEastClouds,
  goesWestClouds,
  eumetsatClouds,
  dwdWind,
];

/// The host whose images may only be taken on the full hour; see
/// [eumetsatClouds].
const String _eumetsatHost = 'view.eumetsat.int';

/// A request for an H SAF product (`layers=…:h40b` and the like): Core
/// data at any latency under the EUMETSAT Data Policy, unlike the Meteosat
/// imagery.
final RegExp _safLayer = RegExp(
  r'[?&]layers=[a-z0-9_]+:h\d+[a-z]*(&|$)',
  caseSensitive: false,
);

bool _onEumetsat(WeatherMapSource source) {
  bool held(String? url) {
    if (url == null) return false;
    if (Uri.tryParse(url)?.host != _eumetsatHost) return false;
    return !_safLayer.hasMatch(url);
  }

  return held(source.urlTemplate) || held(source.imageUrlTemplate);
}

/// [sources] with every source on the EUMETSAT host held to full hours at
/// least 20 minutes old with the moment in the URL; one whose URL names no
/// moment is switched off. H SAF products are left as they are.
List<WeatherMapSource> enforceWeatherLicences(List<WeatherMapSource> sources) =>
    <WeatherMapSource>[
      for (final source in sources)
        if (!_onEumetsat(source))
          source
        else if (!source.urlTemplate.contains('{time}') ||
            !(source.imageUrlTemplate?.contains('{time}') ?? true))
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
  final imageUrl = _str(row['imageUrl']);
  if (imageUrl != null && !imageUrl.startsWith('https://')) return null;
  final timesUrl = _str(row['timesUrl']);
  if (timesUrl != null && !timesUrl.startsWith('https://')) return null;
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
    nativeMetresPerPixel: _positive(row['metresPerPixel']),
    imageUrlTemplate: imageUrl,
    enabled: row['enabled'] is bool ? row['enabled']! as bool : null,
    role: _role(row['role']),
    palette: _palette(row['palette']),
    timesUrl: timesUrl,
  );
}

String? _str(Object? v) => v is String && v.trim().isNotEmpty ? v : null;

int? _int(Object? v) => v is num && v >= 0 ? v.toInt() : null;

double? _num(Object? v) => v is num ? v.toDouble() : null;

double? _positive(Object? v) => v is num && v > 0 ? v.toDouble() : null;

WeatherKind? _kind(Object? v) => switch (v) {
  'radar' => WeatherKind.radar,
  'clouds' => WeatherKind.clouds,
  'wind' => WeatherKind.wind,
  _ => null,
};

RainRole? _role(Object? v) => switch (v) {
  'radar' => RainRole.radar,
  'satellite' => RainRole.satellite,
  'model' => RainRole.model,
  _ => null,
};

RainPalette? _palette(Object? v) => switch (v) {
  // `radarHue` is the older name of the DWD's legend.
  'dwd' || 'radarHue' => RainPalette.dwd,
  'noaa' => RainPalette.noaa,
  'hsaf' => RainPalette.hsaf,
  'dwdModel6h' => RainPalette.dwdModel6h,
  'dwdModel1h' => RainPalette.dwdModel1h,
  'n0q' => RainPalette.n0q,
  'knmi' => RainPalette.knmi,
  'fmi' => RainPalette.fmi,
  _ => null,
};

WeatherTimeFormat? _timeFormat(Object? v) => switch (v) {
  'none' => WeatherTimeFormat.none,
  'iso' => WeatherTimeFormat.iso,
  'epochMs' => WeatherTimeFormat.epochMs,
  'modelRun' => WeatherTimeFormat.modelRun,
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

/// The steps of the rain's time control, in minutes from now: now, then
/// every quarter hour to two hours ahead, then every hour to a day ahead.
const List<int> weatherRadarOffsets = <int>[
  0,
  15, 30, 45, 60, 75, 90, 105, 120, //
  180, 240, 300, 360, 420, 480, 540, 600, 660, 720, 780, 840, 900, 960, //
  1020, 1080, 1140, 1200, 1260, 1320, 1380, 1440,
];

/// The control's slider position for [offsetMinutes] (the nearest step)
/// and back.
int weatherSliderIndexOf(int offsetMinutes) {
  var best = 0;
  for (var i = 1; i < weatherRadarOffsets.length; i++) {
    if ((weatherRadarOffsets[i] - offsetMinutes).abs() <
        (weatherRadarOffsets[best] - offsetMinutes).abs()) {
      best = i;
    }
  }
  return best;
}

int weatherOffsetOfSliderIndex(int index) =>
    weatherRadarOffsets[index.clamp(0, weatherRadarOffsets.length - 1)];

/// [minutes] moved onto the nearest step of the control.
int snapWeatherOffset(int minutes) =>
    weatherOffsetOfSliderIndex(weatherSliderIndexOf(minutes));

/// Every step of the control from the one nearest [minutes] outwards,
/// alternately one later and one earlier along the slider; on one end
/// running on along the other side.
List<int> weatherStepsOutwards(int minutes) {
  final at = weatherSliderIndexOf(minutes);
  return <int>[
    for (var d = 0; d < weatherRadarOffsets.length; d++)
      for (final i in d == 0 ? <int>[at] : <int>[at + d, at - d])
        if (i >= 0 && i < weatherRadarOffsets.length) weatherRadarOffsets[i],
  ];
}

/// One rain source's part of the map at a step: the moment it shows, and
/// the places it leaves to the sources before it that show the same step
/// ([masks], lon/lat rings, named by [maskedBy]), so a radar and a
/// satellite or a model never draw over each other.
///
/// Of those before it, the ones with an [WeatherMapSource.extent] are
/// listed in [cutBy] as well: drawn soft, the part is cut where their frame
/// of the step measures (see `RainCoverage`), and their rings in [masks]
/// only stand in where that frame cannot be had.
@immutable
class RainPart {
  /// Creates the part.
  const RainPart({
    required this.source,
    required this.frame,
    this.masks = const <List<LatLng>>[],
    this.maskedBy = const <String>[],
    this.cutBy = const <WeatherMapSource>[],
  });

  final WeatherMapSource source;
  final WeatherFrame frame;
  final List<List<LatLng>> masks;
  final List<String> maskedBy;
  final List<WeatherMapSource> cutBy;

  /// What tells this part's masks from another's, for an image's cache key.
  String get maskKey => maskedBy.isEmpty ? '' : '-${maskedBy.join('+')}';

  /// Whether [view] lies wholly inside the fixed [masks] of [cutBy]'s
  /// sources (their reach): where their frames cannot be had, nothing of
  /// this part would show there.
  bool hiddenByReach(BoundingBox view) => cutBy.any(
    (before) => before.reachRings.any((ring) => _boxInsideRing(view, ring)),
  );

  @override
  String toString() => 'RainPart(${source.id}, $frame, masked by $maskedBy)';
}

/// What each rain source in [sources] (the enabled ones, most trusted
/// first) draws over [view] at [offsetMinutes] from [now]: those that have
/// a frame for it and meet the view, each masked by the reach of those
/// before it in the list.
///
/// So at "Now" the radars draw where they reach and the satellite around
/// them; ahead, the DWD's nowcast in its reach for two hours, ICON-EU over
/// Europe around it, the HRRR over the contiguous US and the global ICON
/// everywhere else.
///
/// A source is left out where the view lies wholly inside the coverage of
/// one before it without an [WeatherMapSource.extent]; one with an extent
/// measures where its frame says, so what follows it stays a part (see
/// [RainPart.cutBy]).
///
/// [newest] holds, by source id, the newest frame a service said it has
/// (see [WeatherMapSource.frameAt]). [missing] names the satellites known
/// to have no frame of "Now" (failed, or their newest too old): at "Now"
/// they are left out, and where one of them meets the view the first model
/// stands in for it ([rainStandIn]).
List<RainPart> rainPartsAt(
  Iterable<WeatherMapSource> sources,
  DateTime now,
  int offsetMinutes, {
  required BoundingBox view,
  Map<String, DateTime> newest = const <String, DateTime>{},
  Set<String> missing = const <String>{},
}) {
  final standIn = offsetMinutes == 0
      ? rainStandIn(sources, missing, (s) => s.covers(view))
      : null;
  final out = <RainPart>[];
  for (final source in sources) {
    if (source.kind != WeatherKind.radar || !source.enabled) continue;
    if (!source.covers(view)) continue;
    final frame = _rainFrame(
      source,
      now,
      offsetMinutes,
      newest: newest,
      missing: missing,
      standIn: standIn,
    );
    if (frame == null) continue;
    // Wholly left to one before it (a view inside Europe, for the global
    // model): nothing to draw, nothing to ask.
    if (out.any(
      (before) =>
          before.source.extent == null &&
          before.source.reachRings.any((ring) => _boxInsideRing(view, ring)),
    )) {
      continue;
    }
    out.add(
      RainPart(
        source: source,
        frame: frame,
        masks: <List<LatLng>>[
          for (final before in out) ...before.source.reachRings,
        ],
        maskedBy: <String>[for (final before in out) before.source.id],
        cutBy: <WeatherMapSource>[
          for (final before in out)
            if (before.source.extent != null) before.source,
        ],
      ),
    );
  }
  return out;
}

/// The model that stands in at "Now" for a satellite named in [missing]
/// that is enabled among [sources] and passes [where]: the first enabled
/// model (ICON-EU), so the rain beyond the radars never goes blank; `null`
/// where no such satellite or no model is there.
WeatherMapSource? rainStandIn(
  Iterable<WeatherMapSource> sources,
  Set<String> missing,
  bool Function(WeatherMapSource source) where,
) {
  if (missing.isEmpty) return null;
  bool rain(WeatherMapSource s) => s.kind == WeatherKind.radar && s.enabled;
  final down = sources.any(
    (s) =>
        rain(s) &&
        s.role == RainRole.satellite &&
        missing.contains(s.id) &&
        where(s),
  );
  if (!down) return null;
  return sources.where((s) => rain(s) && s.role == RainRole.model).firstOrNull;
}

/// [source]'s frame [offsetMinutes] from [now] among the rain's sources: at
/// "Now" none for a satellite in [missing], and for the [standIn] the hour
/// "Now" falls in, as its first step ahead would show.
WeatherFrame? _rainFrame(
  WeatherMapSource source,
  DateTime now,
  int offsetMinutes, {
  required Map<String, DateTime> newest,
  required Set<String> missing,
  required WeatherMapSource? standIn,
}) {
  if (offsetMinutes == 0) {
    if (source.role == RainRole.satellite && missing.contains(source.id)) {
      return null;
    }
    if (identical(source, standIn)) {
      final time = source.modelFrameTime(now, 0);
      return time == null ? null : WeatherFrame(time);
    }
  }
  return source.frameAt(
    now,
    offsetMinutes: offsetMinutes,
    newest: newest[source.id],
  );
}

/// How wide the seam is where a source measuring by its frame (the DWD's
/// radar and nowcast) hands over to the sources after it, in metres on the
/// ground: inside its coverage, this far from its edge, it fades out as
/// they fade in, so the two read as one; further in it alone draws.
const double rainSeamMetres = 25000;

/// Where a source with an [WeatherMapSource.extent] measures in one of its
/// frames: a weight over the image of [box] (Web Mercator, [width] ×
/// [height], rows from the north), one byte a pixel: 0 where it does not
/// measure (its "no data", beyond its grid), 255 where it measures and is
/// [rainSeamMetres] or more inside the edge of where it does, and in
/// between in that seam, rising with the distance from the edge. The
/// sources after it keep 1 − weight of their alpha there, and the source
/// itself the weight (see `rainSeamWeights`).
@immutable
class RainCoverage {
  /// Creates the coverage.
  RainCoverage({
    required this.box,
    required this.width,
    required this.height,
    required this.covered,
  }) : _gap = _gapOf(width, height, covered),
       _x0 = mercatorX(box.west),
       _xSpan = mercatorX(box.east) - mercatorX(box.west),
       _y1 = mercatorY(box.north),
       _ySpan = mercatorY(box.north) - mercatorY(box.south);

  final BoundingBox box;
  final int width;
  final int height;

  /// The weight of each pixel, 0..255.
  final Uint8List covered;

  /// The pixels around all those under full weight (left, top, right,
  /// bottom, inclusive); `null` where there are none.
  final (int, int, int, int)? _gap;

  /// The [box] in Web Mercator: its west, width, north and height.
  final double _x0;
  final double _xSpan;
  final double _y1;
  final double _ySpan;

  static (int, int, int, int)? _gapOf(int width, int height, Uint8List c) {
    var left = width;
    var top = height;
    var right = -1;
    var bottom = -1;
    for (var y = 0; y < height; y++) {
      final row = y * width;
      for (var x = 0; x < width; x++) {
        if (c[row + x] == 255) continue;
        if (x < left) left = x;
        if (x > right) right = x;
        if (y < top) top = y;
        bottom = y;
      }
    }
    return right < 0 ? null : (left, top, right, bottom);
  }

  /// The weight at the Web Mercator point ([x], [y]), 0..1: of the pixel
  /// there, 0 outside the [box].
  double weightAtMercator(double x, double y) {
    final px = ((x - _x0) / _xSpan * width).floor();
    final py = ((_y1 - y) / _ySpan * height).floor();
    if (px < 0 || py < 0 || px >= width || py >= height) return 0;
    return covered[py * width + px] / 255;
  }

  /// Whether the source measures at the Web Mercator point ([x], [y]):
  /// inside the [box] and over 0 there.
  bool coversMercator(double x, double y) => weightAtMercator(x, y) > 0;

  /// Whether the source alone draws all over [view], measuring and past
  /// its seam everywhere: nothing after it shows there.
  bool coversAll(BoundingBox view) {
    if (view.west < box.west ||
        view.east > box.east ||
        view.south < box.south ||
        view.north > box.north) {
      return false;
    }
    final gap = _gap;
    if (gap == null) return true;
    final left = ((mercatorX(view.west) - _x0) / _xSpan * width).floor();
    final right = ((mercatorX(view.east) - _x0) / _xSpan * width).ceil() - 1;
    final top = ((_y1 - mercatorY(view.north)) / _ySpan * height).floor();
    final bottom = ((_y1 - mercatorY(view.south)) / _ySpan * height).ceil() - 1;
    final (gl, gt, gr, gb) = gap;
    // Around the gaps, not each: one gap in a corner beyond the view keeps
    // its box from counting as covered, which only costs a request.
    return right < gl || left > gr || bottom < gt || top > gb;
  }
}

/// What the rain at [point] shows at [offsetMinutes] from [now]: the role
/// of the first source in [sources] with a frame whose reach holds the
/// point, and the moment it shows (for a model, the hour the step falls
/// in; for one named by its run, its frame's moment). `null` where none does, or the source names no moment. [newest]
/// and [missing] as for [rainPartsAt]: where a model stands in at "Now",
/// the model and the hour "Now" falls in.
({RainRole role, DateTime time})? rainAtPoint(
  Iterable<WeatherMapSource> sources,
  LatLng point,
  DateTime now,
  int offsetMinutes, {
  Map<String, DateTime> newest = const <String, DateTime>{},
  Set<String> missing = const <String>{},
}) {
  final standIn = offsetMinutes == 0
      ? rainStandIn(sources, missing, (s) => s.reaches(point))
      : null;
  for (final source in sources) {
    if (source.kind != WeatherKind.radar || !source.enabled) continue;
    if (!source.reaches(point)) continue;
    final frame = _rainFrame(
      source,
      now,
      offsetMinutes,
      newest: newest,
      missing: missing,
      standIn: standIn,
    );
    if (frame == null) continue;
    final time = frame.time;
    if (time == null) return null;
    // A measurement, or a model's frame of its own moment (named by its
    // run): that moment.
    if (source.role != RainRole.model || frame.run != null) {
      return (role: source.role, time: time);
    }
    // The hour the step falls in, or where the model's frames end before
    // it, the last hour of the last frame.
    final moment = now
        .add(Duration(minutes: offsetMinutes))
        .toUtc()
        .millisecondsSinceEpoch;
    final hour = moment - moment % Duration.millisecondsPerHour;
    final lastHour = time.millisecondsSinceEpoch - Duration.millisecondsPerHour;
    return (
      role: RainRole.model,
      time: DateTime.fromMillisecondsSinceEpoch(
        math.min(hour, lastHour),
        isUtc: true,
      ),
    );
  }
  return null;
}

/// Whether [box] lies wholly inside [ring]: its corners inside, and no
/// corner of the ring inside the box, which a bay of the ring would have.
bool _boxInsideRing(BoundingBox box, List<LatLng> ring) {
  if (box.west > box.east) return false;
  final corners = <LatLng>[
    LatLng(box.south, box.west),
    LatLng(box.south, box.east),
    LatLng(box.north, box.east),
    LatLng(box.north, box.west),
  ];
  if (!corners.every((c) => ringContains(ring, c))) return false;
  return !ring.any(
    (p) =>
        p.lat > box.south &&
        p.lat < box.north &&
        p.lon > box.west &&
        p.lon < box.east,
  );
}

/// Whether [point] lies inside [ring] (lon/lat, closed or not), by the
/// crossings of a ray along its latitude.
bool ringContains(List<LatLng> ring, LatLng point) {
  var inside = false;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final a = ring[i];
    final b = ring[j];
    if ((a.lat > point.lat) != (b.lat > point.lat) &&
        point.lon <
            (b.lon - a.lon) * (point.lat - a.lat) / (b.lat - a.lat) + a.lon) {
      inside = !inside;
    }
  }
  return inside;
}

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
       frameKey = tiles,
       visible = true,
       preloaded = const <WeatherImageFrame>[];

  /// A layer of one image over [imageBox]; with [preloaded], more frames
  /// kept on the map unseen, any of which a later list can show at once,
  /// and with [visible] false none of them shown.
  const WeatherLayer.image({
    required this.id,
    required this.kind,
    required Uint8List this.image,
    required BoundingBox this.imageBox,
    required this.frameKey,
    required this.attribution,
    this.opacity,
    this.visible = true,
    this.preloaded = const <WeatherImageFrame>[],
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

  /// Whether the frame named is shown; a layer that is not holds frames
  /// for later only.
  final bool visible;

  /// The image's other frames the map keeps unseen, so a later list can
  /// show one of them without loading anything (see
  /// `WeatherMapDriver.preview`).
  final List<WeatherImageFrame> preloaded;

  /// The frame this layer names, as one of a layer's [preloaded]; `null`
  /// for tiles.
  WeatherImageFrame? get asFrame {
    final image = this.image;
    final box = imageBox;
    if (image == null || box == null) return null;
    return WeatherImageFrame(frameKey: frameKey, image: image, box: box);
  }

  /// This layer showing [frame] instead, nothing preloaded: one of its
  /// frames as the map draws it.
  WeatherLayer showing(WeatherImageFrame frame) => WeatherLayer.image(
    id: id,
    kind: kind,
    image: frame.image,
    imageBox: frame.box,
    frameKey: frame.frameKey,
    attribution: attribution,
    opacity: opacity,
  );

  @override
  bool operator ==(Object other) =>
      other is WeatherLayer &&
      other.id == id &&
      other.visible == visible &&
      listEquals(other.preloaded, preloaded) &&
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
    visible,
    Object.hashAll(preloaded),
  );

  @override
  String toString() =>
      'WeatherLayer($id, $frameKey${visible ? '' : ', hidden'}'
      '${preloaded.isEmpty ? '' : ', +${preloaded.length}'})';
}

/// One frame of an image layer: its image over its box, named by its
/// frame key. Two are the same frame when their keys and boxes are.
@immutable
class WeatherImageFrame {
  /// Creates the frame.
  const WeatherImageFrame({
    required this.frameKey,
    required this.image,
    required this.box,
  });

  final String frameKey;
  final Uint8List image;
  final BoundingBox box;

  @override
  bool operator ==(Object other) =>
      other is WeatherImageFrame &&
      other.frameKey == frameKey &&
      other.box == box;

  @override
  int get hashCode => Object.hash(frameKey, box);

  @override
  String toString() => 'WeatherImageFrame($frameKey)';
}
