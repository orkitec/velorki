import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:velorki/core/files/track_exporter.dart';
import 'package:velorki/core/files/track_exporter_impl.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki/features/planner/domain/route_poi.dart';
import 'package:velorki_fit/velorki_fit.dart';
import 'package:velorki_geo/velorki_geo.dart';
import 'package:velorki_gpx/velorki_gpx.dart';

/// One recorded call to the injected share callback.
class _SharedFile {
  const _SharedFile(this.file, this.mimeType);

  final File file;
  final String mimeType;
}

/// An exporter writing into a throwaway directory and recording the share.
class _Harness {
  _Harness() {
    tempDirectory = Directory.systemTemp.createTempSync('velorki_export_test');
    addTearDown(() {
      if (tempDirectory.existsSync()) {
        tempDirectory.deleteSync(recursive: true);
      }
    });
    exporter = ShareTrackExporter(
      temporaryDirectory: () async => tempDirectory,
      shareFiles: (file, {required String mimeType}) async {
        shared.add(_SharedFile(file, mimeType));
      },
    );
  }

  late final Directory tempDirectory;
  late final ShareTrackExporter exporter;
  final List<_SharedFile> shared = <_SharedFile>[];

  Directory get exportDirectory =>
      Directory(p.join(tempDirectory.path, exportDirectoryName));
}

final DateTime _start = DateTime.utc(2026, 9, 12, 8);

List<TrackPoint> _points({bool withTime = false}) =>
    List<TrackPoint>.generate(4, (i) {
      return TrackPoint(
        LatLng(48.0 + i * 0.001, 11.0 + i * 0.001),
        ele: 500 + i * 4.0,
        time: withTime ? _start.add(Duration(seconds: i * 10)) : null,
      );
    }, growable: false);

void main() {
  test('a route becomes a GPX <rte> under a safe name', () async {
    final h = _Harness();
    await h.exporter.share(
      name: 'Isar loop / evening',
      points: _points(),
      kind: TrackKind.route,
      format: TrackFormat.gpx,
    );

    expect(h.shared, hasLength(1));
    final shared = h.shared.single;
    expect(shared.mimeType, 'application/gpx+xml');
    expect(p.basename(shared.file.path), 'Isar loop _ evening.gpx');
    expect(p.dirname(shared.file.path), h.exportDirectory.path);

    final xml = shared.file.readAsStringSync();
    expect(xml, contains('<rte>'));
    expect(xml, isNot(contains('<trk>')));
    expect(xml, contains('creator="Velorki"'));

    // It reads back as what went in.
    final decoded = GpxCodec.decode(xml);
    expect(decoded.routes.single.points, hasLength(4));
    expect(decoded.routes.single.points.first.lat, closeTo(48.0, 1e-9));
    expect(decoded.name, 'Isar loop / evening');
  });

  test('a ride becomes a GPX <trk> and keeps its timestamps', () async {
    final h = _Harness();
    await h.exporter.share(
      name: 'Morning ride',
      points: _points(withTime: true),
      kind: TrackKind.ride,
      format: TrackFormat.gpx,
      startTime: _start,
    );

    final xml = h.shared.single.file.readAsStringSync();
    expect(xml, contains('<trk>'));
    expect(xml, isNot(contains('<rte>')));

    final decoded = GpxCodec.decode(xml);
    final points = decoded.tracks.single.points;
    expect(points, hasLength(4));
    expect(points.first.time, _start);
    expect(points.last.time, _start.add(const Duration(seconds: 30)));
  });

  test('a route becomes a FIT course that decodes back', () async {
    final h = _Harness();
    await h.exporter.share(
      name: 'Ammersee',
      points: _points(),
      kind: TrackKind.route,
      format: TrackFormat.fit,
    );

    final shared = h.shared.single;
    expect(shared.mimeType, 'application/vnd.ant.fit');
    expect(p.basename(shared.file.path), 'Ammersee.fit');

    final bytes = shared.file.readAsBytesSync();
    expect(looksLikeFit(bytes), isTrue);
    final decoded = FitCodec.decodeActivity(bytes);
    expect(decoded, hasLength(4));
    expect(decoded.first.lat, closeTo(48.0, 1e-5));
  });

  test('a route\'s cue sheet and places go out as course points', () async {
    final h = _Harness();
    final points = _points();
    await h.exporter.share(
      name: 'Cued',
      points: points,
      kind: TrackKind.route,
      format: TrackFormat.fit,
      turns: const [
        TurnHint(pointIndex: 1, kind: TurnKind.left, note: 'Onto the bridge'),
        TurnHint(pointIndex: 2, kind: TurnKind.slightRight),
        TurnHint(pointIndex: 3, kind: TurnKind.end),
      ],
      pois: [RoutePoi(pos: points[2].pos, name: 'Tap', kind: PoiKind.water)],
    );
    final course = FitCodec.decodeCourse(
      h.shared.single.file.readAsBytesSync(),
    );
    expect(course.name, 'Cued');
    expect(course.points, hasLength(4));
    // The finish is the end of the track, not a course point.
    expect(course.coursePoints.map((c) => c.type), [
      FitCoursePointType.left,
      FitCoursePointType.slightRight,
      FitCoursePointType.water,
    ]);
    expect(course.coursePoints.map((c) => c.name), [
      'Onto the bridge',
      'Slight right',
      'Tap',
    ]);
    expect(course.coursePoints.first.pos.lat, closeTo(points[1].lat, 1e-5));
    expect(course.coursePoints.first.distanceM, greaterThan(0));
  });

  test('a ride becomes a FIT activity with the real timestamps', () async {
    final h = _Harness();
    final points = _points(withTime: true);
    await h.exporter.share(
      name: 'Morning ride',
      points: points,
      kind: TrackKind.ride,
      format: TrackFormat.fit,
      startTime: _start,
    );

    final decoded = FitCodec.decodeActivity(
      h.shared.single.file.readAsBytesSync(),
    );
    expect(decoded.first.time, _start);
    expect(decoded.last.time, _start.add(const Duration(seconds: 30)));
  });

  test('an earlier export is cleared before the next one is written', () async {
    final h = _Harness();
    await h.exporter.share(
      name: 'First',
      points: _points(),
      kind: TrackKind.route,
      format: TrackFormat.gpx,
    );
    await h.exporter.share(
      name: 'Second',
      points: _points(),
      kind: TrackKind.route,
      format: TrackFormat.gpx,
    );

    final left = h.exportDirectory
        .listSync()
        .map((e) => p.basename(e.path))
        .toList();
    expect(left, ['Second.gpx']);
  });

  test('a blank name still produces a usable file', () async {
    final h = _Harness();
    await h.exporter.share(
      name: '   ',
      points: _points(),
      kind: TrackKind.route,
      format: TrackFormat.gpx,
    );
    expect(p.basename(h.shared.single.file.path), 'track.gpx');
  });

  test('nothing is shared when there is nothing to export', () async {
    final h = _Harness();
    await expectLater(
      h.exporter.share(
        name: 'Empty',
        points: const [],
        kind: TrackKind.route,
        format: TrackFormat.gpx,
      ),
      throwsArgumentError,
    );
    expect(h.shared, isEmpty);
  });

  group('safeFileName', () {
    test('strips separators and control characters', () {
      expect(safeFileName('a/b\\c:d*e?f"g<h>i|j'), 'a_b_c_d_e_f_g_h_i_j');
      expect(safeFileName('line\nbreak'), 'line break');
    });

    test('never returns a hidden or empty name', () {
      expect(safeFileName('..'), 'track');
      expect(safeFileName('.hidden'), 'hidden');
      expect(safeFileName(''), 'track');
    });

    test('caps the length', () {
      expect(safeFileName('x' * 200).length, 80);
    });
  });
}
