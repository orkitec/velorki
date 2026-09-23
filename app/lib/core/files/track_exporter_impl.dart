import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_fit/velorki_fit.dart';
import 'package:velorki_geo/velorki_geo.dart';
import 'package:velorki_gpx/velorki_gpx.dart';
import 'package:velorki_tcx/velorki_tcx.dart';

import '../../features/planner/domain/route_poi.dart';
import 'course_points.dart';
import 'track_exporter.dart';

/// MIME type of a GPX file, as registered on both platforms.
const String gpxMimeType = 'application/gpx+xml';

/// MIME type of a Garmin FIT file.
const String fitMimeType = 'application/vnd.ant.fit';

/// Name of the directory below the temporary directory that holds the files
/// handed to the share sheet.
const String exportDirectoryName = 'export';

/// Hands a written export file to the platform. Production wires this to
/// `share_plus`; tests pass their own so no plugin is touched.
typedef ShareFilesCallback = Future<void> Function(
  File file, {
  required String mimeType,
});

/// Answers with the directory temporary export files are written below.
typedef TemporaryDirectoryCallback = Future<Directory> Function();

/// The MIME type for [format].
String mimeTypeFor(TrackFormat format) => switch (format) {
  TrackFormat.gpx => gpxMimeType,
  TrackFormat.fit => fitMimeType,
  TrackFormat.tcx => tcxMimeType,
};

/// The MIME type Garmin registers for TCX.
const String tcxMimeType = 'application/vnd.garmin.tcx+xml';

/// The file extension for [format], without the dot.
String extensionFor(TrackFormat format) => format.name;

/// Turns [name] into something safe to use as a file name.
///
/// Path separators, the characters Windows and iCloud reject and control
/// characters all become `_`; runs of whitespace collapse to a single space;
/// the result is trimmed and cut to 80 characters, and a name that is left
/// empty becomes `track`.
String safeFileName(String name) {
  final cleaned = name
      .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ')
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  // A leading dot would hide the file, and "." / ".." are not names at all.
  final withoutDots = cleaned.replaceAll(RegExp(r'^\.+'), '').trim();
  if (withoutDots.isEmpty) return 'track';
  return withoutDots.length <= 80 ? withoutDots : withoutDots.substring(0, 80);
}

/// The [TrackExporter] the app runs with: encodes the track, writes it to a
/// temporary file and hands that file to the share sheet.
///
/// The file is written below `<temporary>/export/`, which the operating system
/// may clear at any time — that is exactly what a share source wants. Older
/// exports are deleted before a new one is written, so the directory never
/// grows without bound. Nothing here is persistent storage: the route or ride
/// itself lives in the database.
class ShareTrackExporter implements TrackExporter {
  /// Creates an exporter.
  ///
  /// [shareFiles] and [temporaryDirectory] exist so tests can run the whole
  /// encode-and-write path without a platform channel.
  ShareTrackExporter({
    ShareFilesCallback? shareFiles,
    TemporaryDirectoryCallback? temporaryDirectory,
    this.creator = 'Velorki',
  }) : _shareFiles = shareFiles ?? _shareWithSharePlus,
       _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  final ShareFilesCallback _shareFiles;
  final TemporaryDirectoryCallback _temporaryDirectory;

  /// Written into the GPX root element's `creator` attribute.
  final String creator;

  @override
  Future<void> share({
    required String name,
    required List<TrackPoint> points,
    required TrackKind kind,
    required TrackFormat format,
    DateTime? startTime,
    List<RoutePoi> pois = const <RoutePoi>[],
    List<TurnHint> turns = const <TurnHint>[],
    List<double?> temperaturesC = const <double?>[],
    List<DateTime> lapEnds = const <DateTime>[],
  }) async {
    final file = await write(
      name: name,
      points: points,
      kind: kind,
      format: format,
      startTime: startTime,
      pois: pois,
      turns: turns,
      temperaturesC: temperaturesC,
      lapEnds: lapEnds,
    );
    await _shareFiles(file, mimeType: mimeTypeFor(format));
  }

  /// Encodes and writes the export file without sharing it, and returns it.
  ///
  /// Split out from [share] so the write path can be tested and so a later
  /// "save to Files" action can reuse it.
  ///
  /// Throws [ArgumentError] when [points] is empty: there is nothing to
  /// export, and both encoders would reject it anyway.
  Future<File> write({
    required String name,
    required List<TrackPoint> points,
    required TrackKind kind,
    required TrackFormat format,
    DateTime? startTime,
    List<RoutePoi> pois = const <RoutePoi>[],
    List<TurnHint> turns = const <TurnHint>[],
    List<double?> temperaturesC = const <double?>[],
    List<DateTime> lapEnds = const <DateTime>[],
  }) async {
    if (points.isEmpty) {
      throw ArgumentError.value(points, 'points', 'nothing to export');
    }

    final directory = Directory(
      p.join((await _temporaryDirectory()).path, exportDirectoryName),
    );
    await directory.create(recursive: true);
    await _deleteOldExports(directory);

    final file = File(
      p.join(directory.path, '${safeFileName(name)}.${extensionFor(format)}'),
    );
    switch (format) {
      case TrackFormat.gpx:
        await file.writeAsString(
          _encodeGpx(
            name: name,
            points: points,
            kind: kind,
            pois: pois,
            turns: turns,
            temperaturesC: temperaturesC,
          ),
          flush: true,
        );
      case TrackFormat.tcx:
        await file.writeAsString(
          _encodeTcx(
            name: name,
            points: points,
            kind: kind,
            startTime: startTime,
            pois: pois,
            turns: turns,
            lapEnds: lapEnds,
          ),
          flush: true,
        );
      case TrackFormat.fit:
        await file.writeAsBytes(
          _encodeFit(
            name: name,
            points: points,
            kind: kind,
            startTime: startTime,
            pois: pois,
            turns: turns,
          ),
          flush: true,
        );
    }
    return file;
  }

  String _encodeGpx({
    required String name,
    required List<TrackPoint> points,
    required TrackKind kind,
    List<RoutePoi> pois = const <RoutePoi>[],
    List<TurnHint> turns = const <TurnHint>[],
    List<double?> temperaturesC = const <double?>[],
  }) => switch (kind) {
    // A planned route is a <rte>: turn points, no time base, and its points
    // of interest as <wpt>, so a route goes out the way it came in.
    TrackKind.route => _encodeGpxRoute(
      name: name,
      points: points,
      pois: pois,
      turns: turns,
    ),
    // A ride is a <trk> and keeps the timestamps it was recorded with, and
    // the temperature the file it came from carried.
    TrackKind.ride => GpxCodec.encodeTrack(
      points: points,
      name: name,
      creator: creator,
      extensions: [
        for (final t in temperaturesC)
          t == null ? null : GpxExtensions(temperatureC: t),
      ],
    ),
  };

  /// A route as Ride with GPS writes one: the `<rte>` holds the ends and
  /// the turns, each with the manoeuvre as `sym` and `type` and the note as
  /// its name, and the `<trk>` beside it holds the whole line. A route
  /// without a cue sheet keeps every point on the `<rte>`, as before.
  String _encodeGpxRoute({
    required String name,
    required List<TrackPoint> points,
    required List<RoutePoi> pois,
    required List<TurnHint> turns,
  }) {
    final cued = [
      for (final t in turns)
        if (t.pointIndex > 0 && t.pointIndex < points.length - 1) t,
    ]..sort((a, b) => a.pointIndex.compareTo(b.pointIndex));
    if (cued.isEmpty) {
      return GpxCodec.encodeRoute(
        points: points,
        name: name,
        creator: creator,
        waypoints: gpxWaypoints(pois),
      );
    }
    final rtepts = <TrackPoint>[points.first];
    final cues = <GpxRouteCue>[];
    var last = -1;
    for (final t in cued) {
      if (t.pointIndex == last) continue;
      last = t.pointIndex;
      rtepts.add(points[t.pointIndex]);
      cues.add(
        GpxRouteCue(
          pointIndex: rtepts.length - 1,
          name: t.note ?? turnWord(t.kind),
          symbol: cueSymbol(t.kind),
          type: cueSymbol(t.kind),
        ),
      );
    }
    rtepts.add(points.last);
    return GpxCodec.encodeRoute(
      points: rtepts,
      name: name,
      creator: creator,
      waypoints: gpxWaypoints(pois),
      cues: cues,
      track: points,
    );
  }

  /// A ride as a TCX activity of one lap per device lap (one lap when the
  /// ride has none), a route as a TCX course with the cue sheet and the
  /// places as course points.
  String _encodeTcx({
    required String name,
    required List<TrackPoint> points,
    required TrackKind kind,
    required DateTime? startTime,
    List<RoutePoi> pois = const <RoutePoi>[],
    List<TurnHint> turns = const <TurnHint>[],
    List<DateTime> lapEnds = const <DateTime>[],
  }) => switch (kind) {
    TrackKind.route => TcxCodec.encodeCourse(
      name: name,
      points: points,
      creator: creator,
      startTime: startTime,
      coursePoints: [
        for (final turn in turns)
          if (turn.kind != TurnKind.end &&
              turn.pointIndex >= 0 &&
              turn.pointIndex < points.length)
            TcxCoursePoint(
              pos: points[turn.pointIndex].pos,
              time: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
              name: turn.note ?? turnWord(turn.kind),
              type: tcxCoursePointTypeOf(turn.kind),
            ),
        for (final poi in pois)
          TcxCoursePoint(
            pos: poi.pos,
            time: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
            name: poi.name.isEmpty ? null : poi.name,
            notes: poi.description,
            type: switch (poi.kind) {
              PoiKind.water => TcxCoursePointType.water,
              PoiKind.food => TcxCoursePointType.food,
              PoiKind.danger => TcxCoursePointType.danger,
              PoiKind.summit => TcxCoursePointType.summit,
              _ => TcxCoursePointType.generic,
            },
          ),
      ],
    ),
    TrackKind.ride => TcxCodec.encodeActivity(
      creator: creator,
      laps: tcxLaps(points, lapEnds: lapEnds, startTime: startTime),
    ),
  };

  Uint8List _encodeFit({
    required String name,
    required List<TrackPoint> points,
    required TrackKind kind,
    required DateTime? startTime,
    List<RoutePoi> pois = const <RoutePoi>[],
    List<TurnHint> turns = const <TurnHint>[],
  }) => switch (kind) {
    // A course carries its cue sheet and its places as course points, which
    // is what the head unit shows as the next turn.
    TrackKind.route => FitCodec.encodeCourse(
      points,
      name: safeFileName(name),
      coursePoints: courseCuePoints(points: points, turns: turns, pois: pois),
    ),
    TrackKind.ride => FitCodec.encodeActivity(
      points,
      name: name,
      startTime: startTime,
    ),
  };

  /// Removes whatever a previous export left in [directory].
  ///
  /// Best effort: a file the system is still reading, or one that vanished
  /// between the listing and the delete, must not fail the export.
  Future<void> _deleteOldExports(Directory directory) async {
    try {
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File) continue;
        try {
          await entity.delete();
        } on FileSystemException {
          // Still in use by the receiving app; it will be cleared later.
        }
      }
    } on FileSystemException {
      // The directory disappeared under us; create() will put it back.
    }
  }
}

Future<void> _shareWithSharePlus(File file, {required String mimeType}) async {
  await SharePlus.instance.share(
    ShareParams(files: [XFile(file.path, mimeType: mimeType)]),
  );
}

/// The TCX course point type for a turn: the schema knows left, right and
/// straight, so the slight and sharp ones say left or right.
TcxCoursePointType tcxCoursePointTypeOf(TurnKind kind) => switch (kind) {
  TurnKind.left ||
  TurnKind.slightLeft ||
  TurnKind.sharpLeft ||
  TurnKind.keepLeft ||
  TurnKind.exitLeft ||
  TurnKind.uTurnLeft => TcxCoursePointType.left,
  TurnKind.right ||
  TurnKind.slightRight ||
  TurnKind.sharpRight ||
  TurnKind.keepRight ||
  TurnKind.exitRight ||
  TurnKind.uTurnRight => TcxCoursePointType.right,
  _ => TcxCoursePointType.straight,
};

/// [points] cut into TCX laps at [lapEnds], the device's lap ends when the
/// ride came with them; one lap otherwise. Points without a time get one a
/// second apart from [startTime], as the FIT encoder does.
List<TcxLap> tcxLaps(
  List<TrackPoint> points, {
  List<DateTime> lapEnds = const <DateTime>[],
  DateTime? startTime,
}) {
  if (points.isEmpty) return const <TcxLap>[];
  final base =
      (startTime ??
              points
                  .firstWhere((p) => p.time != null, orElse: () => points.first)
                  .time ??
              DateTime.now())
          .toUtc();
  final timed = [
    for (var i = 0; i < points.length; i++)
      points[i].time == null
          ? points[i].copyWith(time: base.add(Duration(seconds: i)))
          : points[i],
  ];
  final ends = [...lapEnds]..sort();
  final laps = <TcxLap>[];
  var cut = 0;
  for (final end in ends) {
    var i = cut;
    while (i < timed.length && timed[i].time!.isBefore(end)) {
      i++;
    }
    if (i <= cut || i >= timed.length) continue;
    laps.add(
      TcxLap(startTime: timed[cut].time!, points: timed.sublist(cut, i)),
    );
    cut = i;
  }
  laps.add(TcxLap(startTime: timed[cut].time!, points: timed.sublist(cut)));
  return laps;
}
