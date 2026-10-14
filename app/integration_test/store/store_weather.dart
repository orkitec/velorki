/// The weather the store pictures show: one rainy afternoon over Madeira,
/// the same on every run whatever the sky does. The map's rain and the free
/// forecast along the route are read off one field ([storeRainAt]), so the
/// route's colours agree with the rain drawn under it; the clock stands at
/// the status bar's 9:41 ([storeWeatherClock]), so the time control's
/// labels read the same on every run too.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:velorki/features/map/data/rain_legend.dart';
import 'package:velorki/features/map/data/weather_fetcher.dart';
import 'package:velorki/features/map/data/weather_map_preferences.dart';
import 'package:velorki/features/map/domain/weather_map.dart';
import 'package:velorki/features/map/domain/wind_field.dart';
import 'package:velorki/features/weather/application/route_weather_controller.dart';
import 'package:velorki/features/weather/data/dwd_route_forecast.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// Today at 9:41, the time the status bar shows.
DateTime storeWeatherClock() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day, 9, 41);
}

/// The overrides that put the store's weather in place of the network's.
List<Override> storeWeatherOverrides() => [
  weatherFetcherProvider.overrideWithValue(StoreWeatherFetcher()),
  weatherMapSourcesProvider.overrideWith(StoreWeatherSources.new),
  weatherClockProvider.overrideWithValue(storeWeatherClock),
  weatherMapClockProvider.overrideWithValue(storeWeatherClock),
];

/// Where the rain falls, around Camacha: a band of light rain from the
/// north-east with one heavier core, a light shower out at sea and a small
/// one over the hills; Funchal, where the featured route starts, stays dry.
/// Each cell is (east, north) in km from [_origin], its spread along and
/// across its axis in km, the axis's angle from east and its peak in mm an
/// hour.
const List<(double, double, double, double, double, double)> _cells = [
  (3.4, 3.6, 3.2, 1.8, 0.5, 1.0),
  (2.5, 3.0, 1.3, 0.9, 0.4, 6.0),
  (4.9, 4.5, 0.9, 0.8, 0.0, 2.0),
  (-5.5, -6.5, 2.2, 1.4, -0.3, 0.8),
  (-4.5, 6.0, 1.3, 1.0, 0.8, 0.6),
];

const LatLng _origin = LatLng(32.66, -16.85);

/// The hour from which the rain stands still over Camacha: the one the
/// weather slide's departure, four hours on, falls in.
final DateTime _settled = () {
  final at = storeWeatherClock().add(const Duration(hours: 4));
  return DateTime(at.year, at.month, at.day, at.hour);
}();

/// How fast the rain comes in before [_settled], east and north, km an hour:
/// at the clock's own hour it lies over Funchal and the sea west of it.
const double _driftEast = 4.0;
const double _driftNorth = 1.0;

/// The rain at [lat]/[lon] in mm an hour at [time] (the clock's time when
/// `null`): drifting in from the west-south-west until [_settled], then
/// still.
double storeRainAt(double lat, double lon, [DateTime? time]) {
  final at = time ?? storeWeatherClock();
  final hours = math.min(0.0, at.difference(_settled).inMinutes / 60);
  var x =
      (lon - _origin.lon) * 111.32 * math.cos(_origin.lat * math.pi / 180) -
      _driftEast * hours;
  var y = (lat - _origin.lat) * 110.57 - _driftNorth * hours;
  // Ragged edges: the place is pushed about a little before the cells are
  // read, so no edge is an ellipse.
  final dx = 0.6 * math.sin(0.83 * y + 1.3) + 0.3 * math.sin(1.9 * y + 0.7 * x);
  final dy = 0.6 * math.sin(0.71 * x + 0.4) + 0.3 * math.sin(2.3 * x - 0.6 * y);
  x += dx;
  y += dy;
  var rain = 0.0;
  for (final (cx, cy, along, across, angle, peak) in _cells) {
    final ex = x - cx;
    final ey = y - cy;
    final u = ex * math.cos(angle) + ey * math.sin(angle);
    final v = -ex * math.sin(angle) + ey * math.cos(angle);
    rain +=
        peak *
        math.exp(-0.5 * (u * u / (along * along) + v * v / (across * across)));
  }
  // A little texture inside the rain.
  return rain * (0.85 + 0.15 * math.sin(1.7 * x + 2.9) * math.cos(1.3 * y));
}

/// The hourly rain at which ICON-EU's map (`niederschlagsradar`) turns to
/// each colour of [dwdModel1hLegend], mm an hour.
const List<double> _modelRainSteps = [
  0.017, 0.033, 0.083, 0.167, 0.25, 0.417, 0.625, 0.833, 1.25, 2.5, //
  3.75, 6.25, 8.33, 12.5, 25,
];

/// ICON-EU's rain, as the map shows it a few hours ahead, at half a
/// kilometre a pixel rather than its seven: the field's cells are a few
/// kilometres wide.
final WeatherMapSource storeRainSource = iconEuRain.copyWith(
  nativeMetresPerPixel: 500,
);

/// The map's weather sources for the store: the forecast's rain alone, so
/// no other source asks the network or says it failed.
class StoreWeatherSources extends WeatherMapSources {
  @override
  List<WeatherMapSource> build() => [storeRainSource];

  @override
  Future<void> applyPointer(Object? weatherLayers) async {}
}

/// The map's weather from [storeRainAt]: every rain image drawn in the
/// model's colours as its service would draw it, then prepared by the app
/// as any ([processRainImage]); no clouds and no wind.
class StoreWeatherFetcher implements WeatherFetcher {
  @override
  Future<bool> probe(String url) async => true;

  @override
  Future<DateTime?> newestFrame(WeatherMapSource source) async => null;

  @override
  bool takeRefusal(String sourceId) => false;

  @override
  Future<Uint8List?> cloudImage(
    WeatherMapSource source,
    int region,
    WeatherFrame frame,
    DateTime now, {
    List<CloudFade> fades = const <CloudFade>[],
  }) async => null;

  @override
  Future<Uint8List?> cloudDetailImage(
    WeatherMapSource source,
    BoundingBox box,
    WeatherFrame frame,
    DateTime now, {
    List<CloudFade> fades = const <CloudFade>[],
  }) async => null;

  @override
  Future<WindGrid?> windGrid(
    WeatherMapSource source,
    WindRequest request,
    WeatherFrame frame,
    DateTime now,
  ) async => null;

  @override
  Future<Uint8List?> radarImage(
    WeatherMapSource source,
    BoundingBox box,
    WeatherFrame frame,
    DateTime now, {
    RadarStyle style = RadarStyle.soft,
    List<List<LatLng>> masks = const <List<LatLng>>[],
    List<RainCoverage> coverages = const <RainCoverage>[],
    String maskKey = '',
  }) async {
    final (width, height) = radarSoftImageSize(source, box);
    final x0 = mercatorX(box.west);
    final x1 = mercatorX(box.east);
    final y0 = mercatorY(box.north);
    final y1 = mercatorY(box.south);
    final rgba = Uint8List(width * height * 4);
    final colours = dwdModel1hLegend.colours;
    for (var row = 0; row < height; row++) {
      final lat = latOfMercatorY(y0 + (row + 0.5) * (y1 - y0) / height);
      for (var column = 0; column < width; column++) {
        final lon = lonOfMercatorX(x0 + (column + 0.5) * (x1 - x0) / width);
        final rain = storeRainAt(lat, lon, frame.time);
        final step = _modelRainSteps.lastIndexWhere((s) => rain >= s);
        if (step < 0) continue;
        final colour = colours[step];
        final o = (row * width + column) * 4;
        rgba
          ..[o] = colour >> 16 & 0xFF
          ..[o + 1] = colour >> 8 & 0xFF
          ..[o + 2] = colour & 0xFF
          ..[o + 3] = 255;
      }
    }
    final soft = style == RadarStyle.soft;
    return processRainImage(
      encodePngRgba(width, height, rgba),
      RainImageJob(
        palette: source.palette,
        soft: soft,
        box: box,
        masks: masks,
        coverages: coverages,
        extent: soft ? source.extent : null,
      ),
    );
  }
}

/// The free route forecast from [storeRainAt]: the rain of every hour as
/// the field has it then, a light south-westerly and 19 °C.
class StoreDwdClient implements DwdForecastClient {
  /// The run every coverage names: the one before the clock's morning.
  static final DateTime _run = () {
    final now = storeWeatherClock().toUtc();
    return DateTime.utc(now.year, now.month, now.day);
  }();

  /// How far apart the grid's points are, degrees.
  static const double _step = 0.005;

  @override
  Future<DateTime?> newestRun(String coverageId) async => _run;

  @override
  DateTime? knownRun(String coverageId) => _run;

  @override
  Future<WcsGrid?> grid(
    String coverageId,
    BoundingBox box,
    DateTime time,
    DateTime run, {
    int bands = 1,
  }) async => loadedGrid(coverageId, box, time, run);

  @override
  WcsGrid? loadedGrid(
    String coverageId,
    BoundingBox box,
    DateTime time,
    DateTime run,
  ) {
    final south = box.south - _step;
    final west = box.west - _step;
    final rows = ((box.north + _step - south) / _step).ceil() + 1;
    final columns = ((box.east + _step - west) / _step).ceil() + 1;
    Float32List band(double Function(double lat, double lon) value) {
      final out = Float32List(rows * columns);
      for (var r = 0; r < rows; r++) {
        for (var c = 0; c < columns; c++) {
          out[r * columns + c] = value(south + r * _step, west + c * _step);
        }
      }
      return out;
    }

    final List<Float32List> values;
    if (coverageId == dwdWindCoverage) {
      values = [band((_, _) => 2.2), band((_, _) => 1.9)];
    } else if (coverageId == dwdTemperatureCoverage) {
      values = [band((_, _) => 19)];
    } else if (coverageId == dwdRainEuCoverage) {
      values = [band((lat, lon) => storeRainAt(lat, lon, time))];
    } else {
      return null;
    }
    return WcsGrid(
      lon0: west,
      lat0: south,
      lonStep: _step,
      latStep: _step,
      columns: columns,
      rows: rows,
      bands: values,
    );
  }
}
