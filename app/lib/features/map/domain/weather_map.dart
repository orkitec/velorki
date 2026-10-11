import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// What a weather layer shows: the rain (measured, estimated or
/// forecast; the "Rain radar" switch), or the clouds.
enum WeatherKind { radar, clouds }

/// Where a rain source's picture of the rain comes from.
enum RainRole {
  /// A weather radar: measured, and for the DWD also its two-hour nowcast.
  radar,

  /// A satellite's estimate, where no radar reaches; the present only.
  satellite,

  /// A weather model's forecast, for the moments ahead.
  model,
}

/// How the colours of a rain image are read when it is drawn soft, and what
/// of it is no rain at all.
enum RainPalette {
  /// A radar's palette, light blue and cyan through green, yellow and red to
  /// purple: alpha by hue (see `radarIntensityAlpha`). The DWD's radar
  /// palette serves the ICON-EU forecast too, asked for in that style.
  radarHue,

  /// The H SAF satellite rain: light green, greens, blues, purples.
  hsaf,

  /// The DWD's six-hour precipitation scale for the global ICON forecast,
  /// recoloured into the radar's palette at the mean rate per hour.
  dwdModel6h,
}

/// How the rain radar is drawn, chosen under Settings → Appearance.
enum RadarStyle {
  /// One image of the view, smoothed on the phone: soft edges, light rain
  /// fainter than heavy (see `softenRadarPixels`).
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
/// that renders a box. Clouds come as one image per [coverage] box, and
/// zoomed in a second, finer image of the view's surroundings
/// ([detailImageUrl]): the URL is a WMS GetMap with `{bbox-epsg-3857}`,
/// `{width}` and `{height}`, which the app fetches itself and turns into
/// white cloud on a clear ground (see `weather_fetcher.dart`). Either names
/// its moment with `{time}` or `{timeMs}` ([timeFormat]).
///
/// A radar drawn soft ([RadarStyle.soft]) is one image of the view as
/// well, from [imageUrlTemplate]; a radar without one stays on its tiles.
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
    this.imageUrlTemplate,
    this.enabled = true,
    this.role = RainRole.radar,
    this.palette = RainPalette.radarHue,
    this.reach,
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

  /// How far ahead it forecasts, in minutes; 0 for none.
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

  /// A radar's request for one image of a box, for the soft look: like
  /// [urlTemplate], with `{bbox-epsg-3857}`, `{width}` and `{height}` to
  /// fill; `null` where the service only serves tiles.
  final String? imageUrlTemplate;

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
  WeatherFrame? frameAt(DateTime now, {int offsetMinutes = 0}) {
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
    return WeatherFrame(
      latestFrameTime(
        now,
        stepMinutes: stepMinutes,
        delayMinutes: delayMinutes,
      ).add(Duration(minutes: offsetMinutes)),
    );
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
    return template
        .replaceAll('{time}', formatWeatherTime(time))
        .replaceAll('{timeMs}', '${time.toUtc().millisecondsSinceEpoch}');
  }

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
    String? imageUrlTemplate,
    bool? enabled,
    RainRole? role,
    RainPalette? palette,
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
    imageUrlTemplate: imageUrlTemplate ?? this.imageUrlTemplate,
    enabled: enabled ?? this.enabled,
    role: role ?? this.role,
    palette: palette ?? this.palette,
    reach: reach,
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
      other.imageUrlTemplate == imageUrlTemplate &&
      other.enabled == enabled &&
      other.role == role &&
      other.palette == palette &&
      identical(other.reach, reach);

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
    identityHashCode(reach),
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

/// The zoom from which the clouds get a detail image; at or above
/// [weatherImageMinZoom], below which no image of the view is drawn.
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
/// pixel a cell is what lets the map blend the cells into each other.
(int, int) radarSoftImageSize(WeatherMapSource source, BoundingBox box) =>
    cloudImageSize(
      box,
      metresPerPixel: source.nativeMetresPerPixel,
      maxSide: radarSoftMaxSide,
      minSide: source.role == RainRole.model ? 1 : radarSoftMinSide,
    );

// A model's cells are kilometres wide (7 for ICON-EU, 28 for the global
// ICON). An image of a city's view at the model's own resolution would be
// a few pixels, which the service then draws larger, each cell a hard
// block that the map's smoothing cannot undo. So a model's image covers at
// least [modelMinCells] cells a side, one pixel a cell, and the map's
// linear resampling turns the cells into gradients.

/// The fewest of a model's own cells each side of its image spans.
const int modelMinCells = 24;

/// How much of its alpha a model's rain keeps, in either look: a model
/// forecast is less certain than a measurement and should read lighter
/// than the radar.
const double forecastAlphaScale = 0.6;

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
/// measured, since each new measurement makes a new forecast of it.
String radarImageStamp(
  WeatherMapSource source,
  WeatherFrame frame,
  DateTime now,
) {
  final time = frame.time;
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
// unless [safeImageBox] passes it, and the view's images are not asked for
// zoomed out that far, where the rain and the clouds of a view say little
// anyway.

/// The zoom below which no image of the view is drawn: the rain's (soft
/// radar, satellite, models) and the clouds' detail. Further out the view's
/// box runs past the world's edges, the cause of MapLibre's crash above.
const double weatherImageMinZoom = 3;

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

/// Base reflectivity over the US from the National Weather Service: the
/// past two hours, no forecast.
///
/// `format=png32`, not `png`: the plain PNG is RGB with a colour key for
/// transparency, which MapLibre's Android decoder rejects.
final WeatherMapSource noaaRadar = WeatherMapSource(
  id: 'radar_noaa',
  kind: WeatherKind.radar,
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
      '&f=image',
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
/// leaves it so). Its newest frame lags some 20 minutes (a 25-minute delay
/// on its 10-minute grid); the service answers a moment it has no frame for
/// with the nearest one. The data reach ±70° from the sub-satellite point;
/// the box keeps to where the view is not too slanted.
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
);

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
/// Asked for in the radar's own style (`niederschlagsradar`, mm/h), not the
/// layer's, which paints all rain under 2 mm an hour one grey: so the
/// forecast reads like the radar beside it, and softens the same way.
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

/// Infrared clouds over the eastern Americas, GOES-East through NASA GIBS:
/// the latest image only.
final WeatherMapSource goesEastClouds = WeatherMapSource(
  id: 'clouds_goes_east',
  kind: WeatherKind.clouds,
  urlTemplate: _gibsGoes('GOES-East_ABI_Band13_Clean_Infrared'),
  coverage: <BoundingBox>[_box(-115, -60, -20, 60)],
  maxZoom: 6,
  nativeMetresPerPixel: goesNativeMetresPerPixel,
  attribution: 'Clouds: NOAA GOES via NASA GIBS',
);

/// The same over the western Americas and the Pacific, GOES-West.
final WeatherMapSource goesWestClouds = WeatherMapSource(
  id: 'clouds_goes_west',
  kind: WeatherKind.clouds,
  urlTemplate: _gibsGoes('GOES-West_ABI_Band13_Clean_Infrared'),
  coverage: <BoundingBox>[_box(-180, -60, -115, 60), _box(165, -60, 180, 60)],
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
  coverage: <BoundingBox>[_box(-30, 25, 45, 75)],
  maxZoom: 8,
  timeFormat: WeatherTimeFormat.iso,
  stepMinutes: 60,
  delayMinutes: 20,
  historyMinutes: 0,
  // The high-resolution fast imagery samples its 10.5 µm channel every
  // kilometre.
  nativeMetresPerPixel: 1000,
  attribution: 'Clouds: Contains modified EUMETSAT Meteosat data {year}',
);

/// The sources a build ships with, before the mirror's override.
///
/// The rain sources from the most trusted down: each draws only where none
/// before it shows the same moment (see [rainPartsAt]).
final List<WeatherMapSource> defaultWeatherMapSources = <WeatherMapSource>[
  dwdRadar,
  noaaRadar,
  hsafRain,
  iconEuRain,
  iconGlobalRain,
  goesEastClouds,
  goesWestClouds,
  eumetsatClouds,
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
  );
}

String? _str(Object? v) => v is String && v.trim().isNotEmpty ? v : null;

int? _int(Object? v) => v is num && v >= 0 ? v.toInt() : null;

double? _num(Object? v) => v is num ? v.toDouble() : null;

double? _positive(Object? v) => v is num && v > 0 ? v.toDouble() : null;

WeatherKind? _kind(Object? v) => switch (v) {
  'radar' => WeatherKind.radar,
  'clouds' => WeatherKind.clouds,
  _ => null,
};

RainRole? _role(Object? v) => switch (v) {
  'radar' => RainRole.radar,
  'satellite' => RainRole.satellite,
  'model' => RainRole.model,
  _ => null,
};

RainPalette? _palette(Object? v) => switch (v) {
  'radarHue' => RainPalette.radarHue,
  'hsaf' => RainPalette.hsaf,
  'dwdModel6h' => RainPalette.dwdModel6h,
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

/// One rain source's part of the map at a step: the moment it shows, and
/// the places it leaves to the sources before it that show the same step
/// ([masks], lon/lat rings, named by [maskedBy]), so a radar and a
/// satellite or a model never draw over each other.
@immutable
class RainPart {
  /// Creates the part.
  const RainPart({
    required this.source,
    required this.frame,
    this.masks = const <List<LatLng>>[],
    this.maskedBy = const <String>[],
  });

  final WeatherMapSource source;
  final WeatherFrame frame;
  final List<List<LatLng>> masks;
  final List<String> maskedBy;

  /// What tells this part's masks from another's, for an image's cache key.
  String get maskKey => maskedBy.isEmpty ? '' : '-${maskedBy.join('+')}';

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
/// Europe around it and the global ICON everywhere else.
List<RainPart> rainPartsAt(
  Iterable<WeatherMapSource> sources,
  DateTime now,
  int offsetMinutes, {
  required BoundingBox view,
}) {
  final out = <RainPart>[];
  for (final source in sources) {
    if (source.kind != WeatherKind.radar || !source.enabled) continue;
    if (!source.covers(view)) continue;
    final frame = source.frameAt(now, offsetMinutes: offsetMinutes);
    if (frame == null) continue;
    // Wholly left to one before it (a view inside Europe, for the global
    // model): nothing to draw, nothing to ask.
    if (out.any(
      (before) =>
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
      ),
    );
  }
  return out;
}

/// What the rain at [point] shows at [offsetMinutes] from [now]: the role
/// of the first source in [sources] with a frame whose reach holds the
/// point, and the moment it shows (for a model, the hour the step falls
/// in). `null` where none does, or the source names no moment.
({RainRole role, DateTime time})? rainAtPoint(
  Iterable<WeatherMapSource> sources,
  LatLng point,
  DateTime now,
  int offsetMinutes,
) {
  for (final source in sources) {
    if (source.kind != WeatherKind.radar || !source.enabled) continue;
    if (!source.reaches(point)) continue;
    final frame = source.frameAt(now, offsetMinutes: offsetMinutes);
    if (frame == null) continue;
    final time = frame.time;
    if (time == null) return null;
    if (source.role != RainRole.model) return (role: source.role, time: time);
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
