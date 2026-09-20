import 'dart:convert';
import 'dart:typed_data';

import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_fit/velorki_fit.dart';
import 'package:velorki_geo/velorki_geo.dart';
import 'package:velorki_gpx/velorki_gpx.dart';

import '../../planner/domain/route_poi.dart';
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
  throw ImportException(ImportFailure.unknownFormat, fileName: fileName);
}

/// Decodes [bytes] and wraps the result in a candidate for the preview screen.
ImportCandidate decodeCandidate(
  Uint8List bytes, {
  required String fileName,
  String? sourceHint,
}) => ImportCandidate.of(
  decodeTrack(bytes, fileName: fileName),
  fileName: fileName,
  sourceHint: sourceHint,
);

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

  final points = track?.points ?? route?.points ?? const <TrackPoint>[];
  if (points.isEmpty) {
    throw ImportException(ImportFailure.empty, fileName: fileName);
  }
  // A route's cue sheet only means something on the route's own points.
  final turns = track == null && route != null
      ? cueSheetTurns(route.cues)
      : const <TurnHint>[];

  return ImportedTrack(
    format: ImportFormat.gpx,
    points: points,
    name: document.name ?? track?.name ?? route?.name,
    description:
        document.description ?? track?.description ?? route?.description,
    creator: document.creator,
    turns: turns,
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
        ),
    ],
  );
}

ImportedTrack _decodeFit(Uint8List bytes, String? fileName) {
  final List<TrackPoint> points;
  try {
    points = FitCodec.decodeActivity(bytes);
  } on FitFormatException catch (e) {
    throw ImportException(
      ImportFailure.malformed,
      fileName: fileName,
      cause: e,
    );
  }
  if (points.isEmpty) {
    throw ImportException(ImportFailure.empty, fileName: fileName);
  }
  return ImportedTrack(format: ImportFormat.fit, points: points);
}

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
