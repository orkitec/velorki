import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../planner/domain/route_poi.dart';

/// The file format an import came from.
enum ImportFormat {
  /// A GPX 1.1 document.
  gpx('gpx'),

  /// A Garmin FIT activity or course.
  fit('fit');

  const ImportFormat(this.extension);

  /// The usual file extension, without the dot.
  final String extension;
}

/// What an imported track is saved as.
enum ImportKind {
  /// A `routes` row: a path to ride.
  route,

  /// A `rides` row: a ride that happened.
  ride,
}

/// The geometry and metadata read out of an imported file.
///
/// Deliberately format independent: the preview screen and the repository work
/// on this, not on `GpxDocument` or the FIT messages.
class ImportedTrack {
  /// Creates a decoded track.
  const ImportedTrack({
    required this.format,
    required this.points,
    this.name,
    this.description,
    this.creator,
    this.pois = const <RoutePoi>[],
    this.turns = const <TurnHint>[],
    this.laps = const <ImportedLap>[],
    this.deviceTotals,
    this.temperaturesC = const <double?>[],
    this.isCourse = false,
  });

  /// Whether the file was a course (a FIT course, a TCX course): a planned
  /// route with a virtual clock on its points, not a recording.
  final bool isCourse;

  /// The laps the device recorded, in order; empty when the file has none.
  /// A ride made from this track gets them as its splits.
  final List<ImportedLap> laps;

  /// The totals as the recording device computed them, shown beside the
  /// app's own figures when they differ; `null` when the file has none.
  final ImportedTotals? deviceTotals;

  /// The temperature per point of [points], `null` where the point had
  /// none; empty when the file carries no temperature at all.
  final List<double?> temperaturesC;

  /// Which decoder produced this track.
  final ImportFormat format;

  /// The track points, in file order.
  final List<TrackPoint> points;

  /// The name the file carried, if any: GPX `<metadata><name>` or the name of
  /// the first track or route.
  final String? name;

  /// The description the file carried, if any.
  final String? description;

  /// The tool that wrote the file, e.g. `komoot.de` or `StravaGPX`. Only GPX
  /// records this.
  final String? creator;

  /// The file's own waypoints — named points of interest beside the track,
  /// a water fountain, a dismount zone — kept with the route it becomes.
  final List<RoutePoi> pois;

  /// The file's cue sheet as turn instructions, anchored to [points], when
  /// the file was a GPX route with cues; empty otherwise.
  final List<TurnHint> turns;

  /// How many points the track has.
  int get pointCount => points.length;

  /// Whether any point carries a timestamp.
  ///
  /// This is what decides route versus ride: a planned route has no times, a
  /// recorded ride does.
  bool get hasTimestamps => points.any((p) => p.time != null);

  /// Whether any point carries an elevation.
  bool get hasElevation => points.any((p) => p.ele != null);

  /// The first timestamp in the track, or `null` when it has none.
  DateTime? get startTime {
    for (final point in points) {
      final time = point.time;
      if (time != null) return time;
    }
    return null;
  }

  /// The last timestamp in the track, or `null` when it has none.
  DateTime? get endTime {
    for (var i = points.length - 1; i >= 0; i--) {
      final time = points[i].time;
      if (time != null) return time;
    }
    return null;
  }

  /// The extent of the track, or `null` when it has no points.
  BoundingBox? get bounds =>
      points.isEmpty ? null : BoundingBox.fromPoints(points.map((p) => p.pos));

  /// The kind this track most likely is: a ride when it carries timestamps, a
  /// route otherwise.
  ImportKind get suggestedKind =>
      hasTimestamps && !isCourse ? ImportKind.ride : ImportKind.route;

  @override
  String toString() =>
      'ImportedTrack(${format.name}, $pointCount points, name: $name)';
}

/// One file waiting to be imported, as the preview screen receives it.
/// One lap of a recorded activity, as the device cut it.
class ImportedLap {
  /// Creates a lap.
  const ImportedLap({
    required this.startTime,
    required this.endTime,
    this.distanceM,
    this.movingS,
    this.calories,
  });

  /// When the lap began.
  final DateTime startTime;

  /// When it ended.
  final DateTime endTime;

  /// Its distance in metres, as the device summed it.
  final double? distanceM;

  /// Its moving time in seconds, as the device timed it.
  final double? movingS;

  /// Its calories, as the device estimated them.
  final int? calories;
}

/// The totals a device wrote for the whole activity.
class ImportedTotals {
  /// Creates the totals.
  const ImportedTotals({
    this.distanceM,
    this.movingS,
    this.elapsedS,
    this.calories,
    this.ascentM,
    this.descentM,
  });

  /// Distance in metres.
  final double? distanceM;

  /// Moving time in seconds.
  final double? movingS;

  /// Elapsed time in seconds.
  final double? elapsedS;

  /// Calories.
  final int? calories;

  /// Ascent in metres.
  final double? ascentM;

  /// Descent in metres.
  final double? descentM;
}

class ImportCandidate {
  /// Creates a candidate.
  const ImportCandidate({
    required this.fileName,
    required this.track,
    required this.suggested,
    this.sourceHint,
  });

  /// Builds a candidate from [track], taking the suggestion from the track
  /// itself.
  factory ImportCandidate.of(
    ImportedTrack track, {
    required String fileName,
    String? sourceHint,
  }) => ImportCandidate(
    fileName: fileName,
    track: track,
    suggested: track.suggestedKind,
    sourceHint: sourceHint,
  );

  /// The file's name as the sender gave it, e.g. `Isar loop.gpx`.
  final String fileName;

  /// What was decoded out of it.
  final ImportedTrack track;

  /// Route or ride, preselected in the preview.
  final ImportKind suggested;

  /// Where the file came from, for logging and for the preview's subtitle:
  /// `share`, `open`, `picker` or a deep link's host.
  final String? sourceHint;

  /// The name to offer in the preview: the file's own metadata name, else the
  /// file name without its extension.
  String get suggestedName {
    final fromFile = track.name?.trim();
    if (fromFile != null && fromFile.isNotEmpty) return fromFile;
    final base = fileName.contains('.')
        ? fileName.substring(0, fileName.lastIndexOf('.'))
        : fileName;
    final trimmed = base.trim();
    return trimmed.isEmpty ? 'Import' : trimmed;
  }

  @override
  String toString() =>
      'ImportCandidate($fileName, ${track.pointCount} points, '
      '${suggested.name}, from: $sourceHint)';
}
