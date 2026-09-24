import 'dart:convert';
import 'dart:typed_data';

import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_fit/velorki_fit.dart';
import 'package:velorki_geo/velorki_geo.dart';
import 'package:velorki_gpx/velorki_gpx.dart';
import 'package:velorki_tcx/velorki_tcx.dart';

import '../../../core/files/course_points.dart';
import '../../planner/domain/route_poi.dart';
import '../../../core/files/bike_type.dart';
import '../domain/imported_track.dart';

/// Why a file could not be imported.
enum ImportFailure {
  /// Neither the GPX nor the FIT sniffer recognised the bytes.
  unknownFormat,

  /// The sniffer said yes but the decoder said no.
  malformed,

  /// The file decoded but held no track points.
  empty,

  /// The bytes could not be read at all (permission, deleted, unreadable
  /// content URI).
  unreadable,

  /// A link to a route on another service could not be fetched.
  linkUnreachable,

  /// A link to a route on another service that only its owner may fetch,
  /// and no account for that service is connected.
  accountNeeded,
}

/// A file that could not be turned into an [ImportedTrack].
class ImportException implements Exception {
  /// Creates a failure.
  const ImportException(this.failure, {this.fileName, this.cause});

  /// What went wrong.
  final ImportFailure failure;

  /// The file it went wrong for, when known.
  final String? fileName;

  /// The underlying error, for the log.
  final Object? cause;

  @override
  String toString() =>
      'ImportException(${failure.name}, file: $fileName, cause: $cause)';
}

/// Turns the bytes of a file into an [ImportedTrack].
///
/// The format is decided by sniffing the bytes — `looksLikeGpx` and
/// `looksLikeFit` — never by the file name or the MIME type the sender
/// claimed, because senders get both wrong all the time (`application/
/// octet-stream` for a GPX, `.fit` for an XML export).
///
/// Throws [ImportException] and nothing else.
ImportedTrack decodeTrack(Uint8List bytes, {String? fileName}) {
  if (looksLikeGpx(bytes)) return _decodeGpx(bytes, fileName);
  if (looksLikeFit(bytes)) return _decodeFit(bytes, fileName);
  if (looksLikeTcx(bytes)) return _decodeTcx(bytes, fileName);
  throw ImportException(ImportFailure.unknownFormat, fileName: fileName);
}

/// Every track in [bytes]: a GPX with several `<trk>` gives one per track,
/// in file order, so the preview can ask which of them to keep; anything
/// else gives the one track [decodeTrack] would.
///
/// Throws [ImportException] as [decodeTrack] does.
List<ImportedTrack> decodeTracks(Uint8List bytes, {String? fileName}) {
  if (!looksLikeGpx(bytes)) return [decodeTrack(bytes, fileName: fileName)];
  final GpxDocument document;
  try {
    document = GpxCodec.decode(utf8.decode(bytes, allowMalformed: true));
  } on GpxFormatException catch (e) {
    throw ImportException(
      ImportFailure.malformed,
      fileName: fileName,
      cause: e,
    );
  }
  final tracks = [
    for (final track in document.tracks)
      if (track.pointCount > 0) track,
  ];
  if (tracks.length < 2) return [decodeTrack(bytes, fileName: fileName)];
  return [
    for (final track in tracks)
      _gpxTrack(document, track, null, fileName, named: true),
  ];
}

/// Decodes [bytes] and wraps the result in a candidate for the preview screen.
ImportCandidate decodeCandidate(
  Uint8List bytes, {
  required String fileName,
  String? sourceHint,
}) {
  final tracks = decodeTracks(bytes, fileName: fileName);
  return ImportCandidate.of(
    tracks.first,
    fileName: fileName,
    sourceHint: sourceHint,
    tracks: tracks.length > 1 ? tracks : const <ImportedTrack>[],
  );
}

ImportedTrack _decodeGpx(Uint8List bytes, String? fileName) {
  final GpxDocument document;
  try {
    // allowMalformed: a GPX with one bad byte in a waypoint name should still
    // import; the geometry is pure ASCII either way.
    document = GpxCodec.decode(utf8.decode(bytes, allowMalformed: true));
  } on GpxFormatException catch (e) {
    throw ImportException(
      ImportFailure.malformed,
      fileName: fileName,
      cause: e,
    );
  }

  // A file can hold both; prefer the recorded track, because that is the one
  // with the timestamps and the denser geometry.
  GpxTrack? track;
  for (final candidate in document.tracks) {
    if (candidate.pointCount > 0) {
      track = candidate;
      break;
    }
  }
  GpxRoute? route;
  for (final candidate in document.routes) {
    if (candidate.points.isNotEmpty) {
      route = candidate;
      break;
    }
  }

  return _gpxTrack(document, track, route, fileName);
}

/// One imported track out of a GPX file: [track] when it has one, else
/// [route], with the file's waypoints as points of interest.
ImportedTrack _gpxTrack(
  GpxDocument document,
  GpxTrack? track,
  GpxRoute? route,
  String? fileName, {
  bool named = false,
}) {
  final points = track?.points ?? route?.points ?? const <TrackPoint>[];
  if (points.isEmpty) {
    throw ImportException(ImportFailure.empty, fileName: fileName);
  }
  // A route's cue sheet only means something on the route's own points.
  final turns = track == null && route != null
      ? cueSheetTurns(route.cues)
      : const <TurnHint>[];
  final extensions = track?.pointExtensions ?? const <GpxExtensions?>[];
  final temperatures = <double?>[for (final e in extensions) e?.temperatureC];

  return ImportedTrack(
    format: ImportFormat.gpx,
    points: points,
    // One track of several is called by its own name, not the file's.
    name: named
        ? track?.name ?? document.name
        : document.name ?? track?.name ?? route?.name,
    description:
        document.description ?? track?.description ?? route?.description,
    creator: document.creator,
    link: document.link,
    profile: profileFromGpxType(track?.type ?? route?.type),
    turns: turns,
    temperaturesC: temperatures.any((t) => t != null)
        ? temperatures
        : const <double?>[],
    pois: [
      for (final w in document.waypoints)
        RoutePoi(
          pos: w.pos,
          name: w.name?.trim().isNotEmpty ?? false
              ? w.name!.trim()
              : (w.symbol ?? w.type ?? ''),
          description: w.description?.trim().isNotEmpty ?? false
              ? w.description!.trim()
              : null,
          kind: PoiKind.fromGpx(
            type: w.type,
            symbol: w.symbol,
            comment: w.comment,
          ),
          // What the file called it, kept for the way back out.
          sourceType: w.type?.trim().isNotEmpty ?? false
              ? w.type!.trim()
              : w.symbol?.trim(),
        ),
    ],
  );
}

ImportedTrack _decodeFit(Uint8List bytes, String? fileName) {
  if (FitCodec.isCourse(bytes)) return _decodeFitCourse(bytes, fileName);
  final FitActivity activity;
  try {
    activity = FitCodec.decodeActivityFile(bytes);
  } on FitFormatException catch (e) {
    throw ImportException(
      ImportFailure.malformed,
      fileName: fileName,
      cause: e,
    );
  }
  final points = activity.points;
  if (points.isEmpty) {
    throw ImportException(ImportFailure.empty, fileName: fileName);
  }
  final session = activity.session;
  return ImportedTrack(
    format: ImportFormat.fit,
    points: points,
    creator: activity.manufacturer,
    profile: session == null
        ? null
        : profileFromFit(session.sport, session.subSport),
    temperaturesC: activity.temperaturesC,
    laps: [
      for (final lap in activity.laps)
        ImportedLap(
          startTime: lap.startTime,
          endTime: lap.endTime,
          distanceM: lap.totalDistanceM,
          movingS: lap.totalTimerS,
          calories: lap.calories,
        ),
    ],
    deviceTotals: session == null
        ? null
        : ImportedTotals(
            distanceM: session.totalDistanceM,
            movingS: session.totalTimerS,
            elapsedS: session.totalElapsedS,
            calories: session.calories,
            ascentM: session.totalAscentM,
            descentM: session.totalDescentM,
          ),
  );
}

/// A FIT course: a route, with its course points as the cue sheet and the
/// points of interest.
///
/// A turn type becomes a turn at the track point the course point sits on,
/// its name as the note; a place (water, food, danger, anything else) a
/// point of interest. A generic point on the first track point is the
/// start and says nothing; one on the last is the finish.
ImportedTrack _decodeFitCourse(Uint8List bytes, String? fileName) {
  final FitCourse course;
  try {
    course = FitCodec.decodeCourse(bytes);
  } on FitFormatException catch (e) {
    throw ImportException(
      ImportFailure.malformed,
      fileName: fileName,
      cause: e,
    );
  }
  final points = course.points;
  if (points.isEmpty) {
    throw ImportException(ImportFailure.empty, fileName: fileName);
  }
  final turns = <TurnHint>[];
  final pois = <RoutePoi>[];
  for (final cue in course.coursePoints) {
    final at = _nearestIndex(points, cue.pos);
    final kind = turnKindOf(cue.type);
    if (kind != null) {
      turns.add(TurnHint(pointIndex: at, kind: kind, note: cue.name));
      continue;
    }
    if (cue.type == FitCoursePointType.generic) {
      if (at == 0) continue;
      if (at == points.length - 1) {
        turns.add(TurnHint(pointIndex: at, kind: TurnKind.end, note: cue.name));
        continue;
      }
    }
    pois.add(
      RoutePoi(
        pos: cue.pos,
        name: cue.name ?? '',
        kind: poiKindOf(cue.type),
        sourceType: cue.type.name,
      ),
    );
  }
  turns.sort((a, b) => a.pointIndex.compareTo(b.pointIndex));
  return ImportedTrack(
    format: ImportFormat.fit,
    points: points,
    name: course.name,
    turns: turns,
    pois: pois,
    isCourse: true,
    profile: profileFromFit(course.sport, course.subSport),
  );
}

int _nearestIndex(List<TrackPoint> points, LatLng pos) {
  var best = 0;
  var bestD = double.infinity;
  for (var i = 0; i < points.length; i++) {
    final d = haversineMeters(points[i].pos, pos);
    if (d < bestD) {
      bestD = d;
      best = i;
    }
  }
  return best;
}

/// A TCX file: an activity as a ride with its laps and sensors, a course
/// as a route with its course points as the cue sheet and the places.
ImportedTrack _decodeTcx(Uint8List bytes, String? fileName) {
  final TcxDocument document;
  try {
    document = TcxCodec.decode(utf8.decode(bytes, allowMalformed: true));
  } on TcxFormatException catch (e) {
    throw ImportException(
      ImportFailure.malformed,
      fileName: fileName,
      cause: e,
    );
  }
  final activity = document.activities
      .where((a) => a.points.isNotEmpty)
      .firstOrNull;
  if (activity != null) return _tcxActivity(activity, document);
  final course = document.courses.where((c) => c.points.isNotEmpty).firstOrNull;
  if (course != null) return _tcxCourse(course, document);
  throw ImportException(ImportFailure.empty, fileName: fileName);
}

ImportedTrack _tcxActivity(TcxActivity activity, TcxDocument document) {
  final laps = <ImportedLap>[];
  var distance = 0.0;
  var moving = 0.0;
  var calories = 0;
  var totals = false;
  for (final lap in activity.laps) {
    final timeS = lap.totalTimeS;
    laps.add(
      ImportedLap(
        startTime: lap.startTime,
        endTime: timeS == null
            ? (lap.points.lastOrNull?.time ?? lap.startTime)
            : lap.startTime.add(Duration(milliseconds: (timeS * 1000).round())),
        distanceM: lap.distanceM,
        movingS: timeS,
        calories: lap.calories,
      ),
    );
    if (lap.distanceM != null || timeS != null || lap.calories != null) {
      totals = true;
    }
    distance += lap.distanceM ?? 0;
    moving += timeS ?? 0;
    calories += lap.calories ?? 0;
  }
  return ImportedTrack(
    format: ImportFormat.tcx,
    points: activity.points,
    creator: activity.creator ?? document.author,
    laps: laps,
    // TCX has no session: the laps summed are what the device wrote.
    deviceTotals: totals
        ? ImportedTotals(
            distanceM: distance > 0 ? distance : null,
            movingS: moving > 0 ? moving : null,
            calories: calories > 0 ? calories : null,
          )
        : null,
  );
}

ImportedTrack _tcxCourse(TcxCourse course, TcxDocument document) {
  final points = course.points;
  final turns = <TurnHint>[];
  final pois = <RoutePoi>[];
  for (final cp in course.coursePoints) {
    final at = _nearestIndex(points, cp.pos);
    final kind = tcxTurnKindOf(cp.type);
    if (kind != null) {
      turns.add(TurnHint(pointIndex: at, kind: kind, note: cp.name));
      continue;
    }
    if (cp.type == TcxCoursePointType.generic) {
      if (at == 0) continue;
      if (at == points.length - 1) {
        turns.add(TurnHint(pointIndex: at, kind: TurnKind.end, note: cp.name));
        continue;
      }
    }
    pois.add(
      RoutePoi(
        pos: cp.pos,
        name: cp.name ?? '',
        description: cp.notes,
        kind: tcxPoiKindOf(cp.type),
        sourceType: cp.type.xmlValue,
      ),
    );
  }
  turns.sort((a, b) => a.pointIndex.compareTo(b.pointIndex));
  return ImportedTrack(
    format: ImportFormat.tcx,
    points: points,
    name: course.name,
    creator: document.author,
    turns: turns,
    pois: pois,
    isCourse: true,
  );
}

/// The turn a TCX course point type stands for, `null` for a place.
TurnKind? tcxTurnKindOf(TcxCoursePointType type) => switch (type) {
  TcxCoursePointType.left => TurnKind.left,
  TcxCoursePointType.right => TurnKind.right,
  TcxCoursePointType.straight => TurnKind.straight,
  _ => null,
};

/// The point of interest kind a TCX course point type stands for.
PoiKind tcxPoiKindOf(TcxCoursePointType type) => switch (type) {
  TcxCoursePointType.water => PoiKind.water,
  TcxCoursePointType.food => PoiKind.food,
  TcxCoursePointType.danger => PoiKind.danger,
  TcxCoursePointType.summit => PoiKind.summit,
  TcxCoursePointType.firstAid => PoiKind.firstAid,
  _ => PoiKind.generic,
};

/// The turn instructions a GPX route's cue sheet spells out.
///
/// Ride with GPS and Garmin write the manoeuvre into `<sym>` and `<type>`
/// (`Left`, `Slight Right`, `Straight`, `Danger`, ...) and the instruction as
/// the author wrote it into `<name>`. A cue whose words name no manoeuvre
/// still becomes a turn, carrying on straight with its note, so nothing the
/// author wrote is lost; a cue with neither words nor a name is not a turn.
List<TurnHint> cueSheetTurns(List<GpxRouteCue> cues) {
  final turns = <TurnHint>[];
  for (final cue in cues) {
    final words = <String?>[
      cue.type,
      cue.symbol,
    ].nonNulls.map((s) => s.toLowerCase()).join(' ');
    final kind = _cueKind(words);
    final note = cue.name ?? cue.description;
    if (kind == null && note == null) continue;
    if (kind == TurnKind.straight && note == null) continue;
    turns.add(
      TurnHint(
        pointIndex: cue.pointIndex,
        kind: kind ?? TurnKind.straight,
        note: note,
      ),
    );
  }
  return turns;
}

TurnKind? _cueKind(String words) {
  if (words.isEmpty) return null;
  final sharp = words.contains('sharp');
  final slight = words.contains('slight') || words.contains('bear');
  if (words.contains('uturn') || words.contains('u-turn')) {
    return TurnKind.uTurn;
  }
  if (words.contains('left')) {
    return sharp
        ? TurnKind.sharpLeft
        : slight
        ? TurnKind.slightLeft
        : TurnKind.left;
  }
  if (words.contains('right')) {
    return sharp
        ? TurnKind.sharpRight
        : slight
        ? TurnKind.slightRight
        : TurnKind.right;
  }
  if (words.contains('straight') || words.contains('continue')) {
    return TurnKind.straight;
  }
  if (words.contains('end') ||
      words.contains('finish') ||
      words.contains('arrive')) {
    return TurnKind.end;
  }
  return null;
}
