import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:velorki_fit/velorki_fit.dart';
import 'package:velorki_geo/velorki_geo.dart';
import 'package:velorki_gpx/velorki_gpx.dart';

import '../../features/planner/domain/route_poi.dart';
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
String mimeTypeFor(TrackFormat format) =>
    format == TrackFormat.gpx ? gpxMimeType : fitMimeType;

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
  }) async {
    final file = await write(
      name: name,
      points: points,
      kind: kind,
      format: format,
      startTime: startTime,
      pois: pois,
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
          _encodeGpx(name: name, points: points, kind: kind, pois: pois),
          flush: true,
        );
      case TrackFormat.fit:
        await file.writeAsBytes(
          _encodeFit(
            name: name,
            points: points,
            kind: kind,
            startTime: startTime,
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
  }) => switch (kind) {
    // A planned route is a <rte>: turn points, no time base, and its points
    // of interest as <wpt>, so a route goes out the way it came in.
    TrackKind.route => GpxCodec.encodeRoute(
      points: points,
      name: name,
      creator: creator,
      waypoints: gpxWaypoints(pois),
    ),
    // A ride is a <trk> and keeps the timestamps it was recorded with.
    TrackKind.ride => GpxCodec.encodeTrack(
      points: points,
      name: name,
      creator: creator,
    ),
  };

  Uint8List _encodeFit({
    required String name,
    required List<TrackPoint> points,
    required TrackKind kind,
    required DateTime? startTime,
  }) => switch (kind) {
    TrackKind.route => FitCodec.encodeCourse(points, name: safeFileName(name)),
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
