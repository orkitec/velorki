import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/map/domain/weather_map.dart';
import 'package:velorki/features/map/domain/wind_field.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// Real answers of the DWD's WCS, `format=text/plain`, for 2026-10-11 05 UTC:
/// Lat(48,52) Long(5,10); Lat(48,49) Long(179,181) across the antimeridian;
/// and Lat(20,70) Long(-20,40) scaled to 30 × 25 (`scalesize=i(30),j(25)`).
String _fixture(String name) =>
    File('test/fixtures/weather/$name').readAsStringSync();

/// A grid of [columns] × [rows] on 0.25° from [lon0]/[lat0], u and v by
/// [wind].
WindGrid _grid({
  double lon0 = 8,
  double lat0 = 50,
  int columns = 3,
  int rows = 3,
  required (double, double) Function(int column, int row) wind,
}) {
  final u = Float32List(columns * rows);
  final v = Float32List(columns * rows);
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < columns; c++) {
      final (a, b) = wind(c, r);
      u[r * columns + c] = a;
      v[r * columns + c] = b;
    }
  }
  return WindGrid(
    lon0: lon0,
    lat0: lat0,
    lonStep: windGridStep,
    latStep: -windGridStep,
    columns: columns,
    rows: rows,
    u: u,
    v: v,
  );
}

BoundingBox _view(double west, double south, double east, double north) =>
    BoundingBox(south: south, west: west, north: north, east: east);

void main() {
  group('parseWcsWindGrid', () {
    test('the real answer: its grid, u from band 0 and v from band 1', () {
      final grid = parseWcsWindGrid(_fixture('dwd_wind_uv10m.txt'))!;
      // Grid range 741..760 × 153..168: 20 columns, 16 rows.
      expect(grid.columns, 20);
      expect(grid.rows, 16);
      // The affine gives a cell's middle: 0.25 × 741 − 180, −0.25 × 153 + 90.
      expect(grid.lon0, 5.25);
      expect(grid.lat0, 51.75);
      expect(grid.lonStep, 0.25);
      expect(grid.latStep, -0.25);
      // The first and last value of the first row of each band, and the
      // first of the last row: rows run from the north.
      expect(grid.u[0], closeTo(3.116993, 1e-5));
      expect(grid.u[19], closeTo(2.074024, 1e-5));
      expect(grid.v[0], closeTo(2.944458, 1e-5));
      expect(grid.v[19], closeTo(2.508911, 1e-5));
      expect(grid.u[15 * 20], closeTo(1.156055, 1e-5));
      expect(grid.v[15 * 20], closeTo(0.704224, 1e-5));
      // A grid point samples to its own value.
      final (u, v) = grid.sample(51.75, 5.25)!;
      expect(u, closeTo(3.116993, 1e-5));
      expect(v, closeTo(2.944458, 1e-5));
      // The south-west corner, 48.0 / 5.25, is the first of the last row.
      expect(grid.sample(48, 5.25)!.$1, closeTo(1.156055, 1e-5));
      // Beyond the grid there is nothing.
      expect(grid.sample(52.5, 7), isNull);
      expect(grid.sample(50, 10.5), isNull);
    });

    test('scaled by the service: the affine it reports places the cells', () {
      final grid = parseWcsWindGrid(_fixture('dwd_wind_uv10m_scaled.txt'))!;
      expect(grid.columns, 30);
      expect(grid.rows, 25);
      // 2 × 641 − 1300.875 and −2 × 81 + 230.875.
      expect(grid.lon0, closeTo(-18.875, 1e-9));
      expect(grid.lat0, closeTo(68.875, 1e-9));
      expect(grid.lonStep, 2);
      expect(grid.latStep, -2);
      expect(grid.u.every((x) => x.isFinite), isTrue);
    });

    test('across the antimeridian: east past 180, the missing column NaN', () {
      final grid = parseWcsWindGrid(
        _fixture('dwd_wind_uv10m_antimeridian.txt'),
      )!;
      expect(grid.columns, 8);
      expect(grid.lon0, 179.25);
      // Column 3 is 180.0 exactly, where the model's grid has no value.
      expect(grid.u[3].isNaN, isTrue);
      // On the missing column the neighbours stand in.
      final at180 = grid.sample(48.5, 180)!;
      expect(at180.$1.isFinite, isTrue);
      // A point given west of the grid is a turn further east.
      final east = grid.sample(48.5, 180.5)!;
      final west = grid.sample(48.5, -179.5)!;
      expect(west.$1, east.$1);
      expect(west.$2, east.$2);
    });

    test('a parameter equal to the identity is left out: 1 is assumed', () {
      const text = '''
Grid range: GridEnvelope2D[160..161, 20..20]
Grid to world: PARAM_MT["Affine",
  PARAMETER["num_row", 3],
  PARAMETER["num_col", 3],
  PARAMETER["elt_0_2", -179.375],
  PARAMETER["elt_1_1", -1.0],
  PARAMETER["elt_1_2", 89.375]]
Contents:
Band 0:
1.5 NaN
Band 1:
-2 3
''';
      final grid = parseWcsWindGrid(text)!;
      expect(grid.lonStep, 1);
      expect(grid.lon0, 160 - 179.375);
      expect(grid.lat0, 89.375 - 20);
      expect(grid.u[0], 1.5);
      expect(grid.u[1].isNaN, isTrue);
      expect(grid.v[1], 3);
    });

    test('an error, or values that do not fill the grid, is no grid', () {
      expect(
        parseWcsWindGrid(
          '<?xml version="1.0"?><ows:ExceptionReport>'
          'Cannot find suitable model-run</ows:ExceptionReport>',
        ),
        isNull,
      );
      expect(
        parseWcsWindGrid('''
Grid range: GridEnvelope2D[0..1, 0..1]
Contents:
Band 0:
1 2 3
Band 1:
1 2 3 4
'''),
        isNull,
      );
    });
  });

  group('speed and direction', () {
    test('the direction is where the wind blows to, clockwise from north', () {
      // A north wind blows south: the arrow points down.
      expect(windDirectionSpeed(0, -5).dir, closeTo(180, 1e-9));
      // A west wind blows east.
      expect(windDirectionSpeed(5, 0).dir, closeTo(90, 1e-9));
      // A south wind blows north.
      expect(windDirectionSpeed(0, 5).dir, closeTo(0, 1e-9));
      // An east wind blows west.
      expect(windDirectionSpeed(-5, 0).dir, closeTo(270, 1e-9));
      // From the south-west, to the north-east.
      expect(windDirectionSpeed(3, 3).dir, closeTo(45, 1e-9));
    });

    test('the speed is the length of (u, v)', () {
      expect(windDirectionSpeed(3, -4).ms, closeTo(5, 1e-12));
      expect(windDirectionSpeed(0, 0).ms, 0);
    });

    test('classes: calm, light, moderate, fresh, strong', () {
      expect(windSpeedClass(0), 0);
      expect(windSpeedClass(1.9), 0);
      expect(windSpeedClass(2), 1);
      expect(windSpeedClass(4.9), 1);
      expect(windSpeedClass(5), 2);
      expect(windSpeedClass(8), 3);
      expect(windSpeedClass(10.9), 3);
      expect(windSpeedClass(11), 4);
      expect(windSpeedClass(30), 4);
    });
  });

  group('interpolation', () {
    test('between four points, bilinear', () {
      final grid = _grid(wind: (c, r) => (c.toDouble(), r.toDouble() * 2));
      // Halfway between columns 0 and 1, a quarter from row 1 to row 2.
      final (u, v) = grid.sample(50 - 0.25 * 1.25, 8 + 0.125)!;
      expect(u, closeTo(0.5, 1e-9));
      expect(v, closeTo(2.5, 1e-9));
    });

    test('a point without a value is left out, the others weighed up', () {
      final grid = _grid(
        wind: (c, r) => c == 1 && r == 0 ? (double.nan, double.nan) : (4, 0),
      );
      final (u, _) = grid.sample(50 - 0.125, 8 + 0.125)!;
      expect(u, closeTo(4, 1e-9));
      final none = _grid(columns: 1, rows: 1, wind: (_, _) => (double.nan, 0));
      expect(none.sample(50, 8), isNull);
    });
  });

  group('spacing', () {
    test('about 70 px apart at every zoom, rounded down to a half', () {
      for (final zoom in <double>[3, 6.5, 9, 12, 15]) {
        final metres = windArrowSpacingMetres(zoom);
        final metresPerPx = 2 * 20037508.342789244 / (512 * math.pow(2, zoom));
        expect(metres / metresPerPx, closeTo(windArrowSpacingPx, 1e-6));
      }
      // Zoom 9.3 spaces as 9: the arrows stay put for a small zoom.
      expect(windArrowSpacingMetres(9.3), windArrowSpacingMetres(9));
      expect(windArrowSpacingMetres(9.6), windArrowSpacingMetres(9.5));
    });

    test('zoomed out the grid is thinned, zoomed in it is the model own', () {
      expect(windThinning(12), 1);
      expect(windThinning(8), 1);
      // At zoom 3 the arrows are some 6° apart: 3° a step, 8 cells.
      expect(windThinning(3), 8);
      expect(windThinning(5), 2);
      // Never fewer than two steps between arrows.
      for (var z = 3.0; z <= 7; z += 0.5) {
        if (windThinning(z) == 1) continue;
        final degrees = windArrowSpacingMetres(z) / (2 * 20037508.34 / 360);
        expect(windThinning(z) * windGridStep * 2, lessThanOrEqualTo(degrees));
      }
    });

    test('arrows on a grid fixed to the world, a pan keeps them in place', () {
      final grid = _grid(
        lon0: 0,
        lat0: 60,
        columns: 81,
        rows: 81,
        wind: (_, _) => (0, -5),
      );
      final a = windArrowsFor(grid, _view(8, 46, 10, 50), 7);
      final b = windArrowsFor(grid, _view(8.3, 46.2, 10.3, 50.2), 7);
      expect(a, isNotEmpty);
      final shared = a.toSet().intersection(b.toSet());
      expect(shared.length, greaterThan(a.length ~/ 2));
      // A north wind: every arrow points south, at 5 m/s.
      expect(a.every((w) => w.dir == 180 && w.ms == 5), isTrue);
      // Neighbours are the spacing apart, in Web Mercator x.
      final row = a.where((w) => w.at.lat == a.first.at.lat).toList();
      final dx = mercatorX(row[1].at.lon) - mercatorX(row[0].at.lon);
      expect(dx, closeTo(windArrowSpacingMetres(7), 2));
    });

    test('zoomed in, more arrows over the same place', () {
      final grid = _grid(
        lon0: 0,
        lat0: 60,
        columns: 81,
        rows: 81,
        wind: (_, _) => (5, 0),
      );
      final view = _view(8.8, 47.8, 9.2, 48.2);
      final near = windArrowsFor(grid, view, 11);
      final far = windArrowsFor(grid, view, 9);
      expect(near.length, greaterThan(far.length * 3));
    });

    test('across the antimeridian the longitudes come back within ±180', () {
      final grid = parseWcsWindGrid(
        _fixture('dwd_wind_uv10m_antimeridian.txt'),
      )!;
      final arrows = windArrowsFor(grid, _view(179.6, 48.2, -179.4, 48.6), 9);
      expect(arrows, isNotEmpty);
      expect(arrows.every((w) => w.at.lon >= -180 && w.at.lon <= 180), isTrue);
      expect(arrows.any((w) => w.at.lon < 0), isTrue);
      expect(arrows.any((w) => w.at.lon > 0), isTrue);
    });
  });

  group('the request', () {
    test('none below the least zoom', () {
      expect(windRequestFor(_view(8, 46, 10, 50), 2.9), isNull);
      expect(
        windRequestFor(_view(8, 46, 10, 50), weatherImageMinZoom),
        isNotNull,
      );
    });

    test('the view and a quarter around it, on the grid, a step beyond', () {
      final view = _view(8, 46, 10, 50);
      final request = windRequestFor(view, 9)!;
      expect(request.thinning, 1);
      expect(request.area.west, closeTo(7.5, 1e-9));
      expect(request.area.east, closeTo(10.5, 1e-9));
      expect(request.area.south, closeTo(45, 1e-9));
      expect(request.area.north, closeTo(51, 1e-9));
      // Snapped outward to 2° (eight steps), then a step more.
      expect(request.box.west, closeTo(5.75, 1e-9));
      expect(request.box.east, closeTo(12.25, 1e-9));
      expect(request.box.south, closeTo(43.75, 1e-9));
      expect(request.box.north, closeTo(52.25, 1e-9));
      expect(request.fits(view, 9.4), isTrue);
      // A small pan asks for the same box.
      expect(windRequestFor(_view(8.2, 46.1, 10.2, 50.1), 9)!.key, request.key);
      // Zoomed out the grid is thinned, so it no longer fits.
      expect(request.fits(view, 5), isFalse);
      // Panned out of the area.
      expect(request.fits(_view(9, 46, 11, 50), 9), isFalse);
    });

    test('latitude clipped to ±85, longitude to the world', () {
      final request = windRequestFor(_view(-179.5, 70, -170, 84.9), 5)!;
      expect(request.box.north, windMaxLat);
      expect(request.box.west, -180);
    });

    test('across the antimeridian: one box, its east past 180', () {
      final view = _view(175, 40, -175, 50);
      final request = windRequestFor(view, 6)!;
      expect(request.box.west, lessThan(180));
      expect(request.box.east, greaterThan(180));
      expect(request.box.east - request.box.west, lessThan(360));
      expect(request.fits(view, 6), isTrue);
      expect(
        request.url(dwdWind, WeatherFrame(DateTime.utc(2026, 10, 11, 5))),
        contains(
          '&subset=Long(${request.box.west.toStringAsFixed(3)},'
          '${request.box.east.toStringAsFixed(3)})',
        ),
      );
    });

    test('the URL: the box, the hour, and the size when thinned', () {
      final frame = WeatherFrame(DateTime.utc(2026, 10, 11, 5));
      final fine = windRequestFor(_view(8, 46, 10, 50), 9)!;
      final url = fine.url(dwdWind, frame);
      expect(url, startsWith('https://maps.dwd.de/geoserver/ows?service=WCS'));
      expect(url, contains('coverageId=dwd__Icon_reg025_fd_sl_UV10M'));
      expect(url, contains('format=text/plain'));
      expect(url, contains('subset=Lat(43.750,52.250)'));
      expect(url, contains('subset=Long(5.750,12.250)'));
      expect(url, contains('subset=time(%222026-10-11T05:00:00.000Z%22)'));
      expect(url, isNot(contains('scalesize')));
      final coarse = windRequestFor(_view(-10, 35, 30, 60), 3.5)!;
      expect(coarse.thinning, greaterThan(1));
      expect(
        coarse.url(dwdWind, frame),
        endsWith('&scalesize=i(${coarse.columns}),j(${coarse.rows})'),
      );
    });
  });

  group('the hour of each step', () {
    final now = DateTime.utc(2026, 10, 11, 14, 42);

    test('Now is the hour now falls in, ahead the hour the step falls in', () {
      DateTime? at(int offset) =>
          dwdWind.frameAt(now, offsetMinutes: offset)?.time;
      expect(at(0), DateTime.utc(2026, 10, 11, 14));
      expect(at(15), DateTime.utc(2026, 10, 11, 14));
      expect(at(30), DateTime.utc(2026, 10, 11, 15));
      expect(at(120), DateTime.utc(2026, 10, 11, 16));
      expect(at(1440), DateTime.utc(2026, 10, 12, 14));
      // Every step of the control has an hour.
      for (final offset in weatherRadarOffsets) {
        expect(at(offset), isNotNull);
      }
    });

    test('clamped to the hours there are', () {
      expect(
        windFrameTime(now, 3000, forecastMinutes: 24 * 60),
        DateTime.utc(2026, 10, 12, 14),
      );
      expect(dwdWind.frameAt(now, offsetMinutes: -60), isNull);
    });
  });
}
