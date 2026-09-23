import 'package:velorki_geo/velorki_geo.dart';

/// The `Sport` attribute of an activity.
enum TcxSport { biking, running, other }

/// The `PointType` of a course point, as the schema lists them.
enum TcxCoursePointType {
  generic('Generic'),
  summit('Summit'),
  valley('Valley'),
  water('Water'),
  food('Food'),
  danger('Danger'),
  left('Left'),
  right('Right'),
  straight('Straight'),
  firstAid('First Aid'),
  fourthCategory('4th Category'),
  thirdCategory('3rd Category'),
  secondCategory('2nd Category'),
  firstCategory('1st Category'),
  horsCategory('Hors Category'),
  sprint('Sprint');

  const TcxCoursePointType(this.xmlValue);

  /// The value as it is written in the file.
  final String xmlValue;

  /// The type for a written value, [generic] for one this build does not
  /// know.
  static TcxCoursePointType fromXml(String? value) => values.firstWhere(
    (t) => t.xmlValue == value,
    orElse: () => TcxCoursePointType.generic,
  );
}

/// One `<CoursePoint>`: a cue or a place on a course.
class TcxCoursePoint {
  /// Creates a course point.
  const TcxCoursePoint({
    required this.pos,
    required this.time,
    this.name,
    this.type = TcxCoursePointType.generic,
    this.notes,
  });

  /// `<Position>`.
  final LatLng pos;

  /// `<Time>`: which track point it belongs to, by time.
  final DateTime time;

  /// `<Name>`, at most ten characters on the devices that read it.
  final String? name;

  /// `<PointType>`.
  final TcxCoursePointType type;

  /// `<Notes>`.
  final String? notes;

  @override
  String toString() => 'TcxCoursePoint($type, $name)';
}

/// One `<Lap>` of an activity: its totals and its track points.
class TcxLap {
  /// Creates a lap.
  const TcxLap({
    required this.startTime,
    required this.points,
    this.totalTimeS,
    this.distanceM,
    this.calories,
    this.avgHeartRate,
    this.maxHeartRate,
    this.avgCadence,
    this.avgWatts,
    this.maxWatts,
    this.maxSpeedMps,
  });

  /// The `StartTime` attribute.
  final DateTime startTime;

  /// The `<Trackpoint>`s of every `<Track>` of the lap, in order; heart
  /// rate, cadence, power and speed on the points that carry them.
  final List<TrackPoint> points;

  /// `<TotalTimeSeconds>`.
  final double? totalTimeS;

  /// `<DistanceMeters>`.
  final double? distanceM;

  /// `<Calories>`.
  final int? calories;

  /// `<AverageHeartRateBpm>`.
  final int? avgHeartRate;

  /// `<MaximumHeartRateBpm>`.
  final int? maxHeartRate;

  /// `<Cadence>` of the lap.
  final int? avgCadence;

  /// `ns3:LX/AvgWatts`.
  final int? avgWatts;

  /// `ns3:LX/MaxWatts`.
  final int? maxWatts;

  /// `<MaximumSpeed>`, in metres per second.
  final double? maxSpeedMps;
}

/// One `<Activity>`.
class TcxActivity {
  /// Creates an activity.
  const TcxActivity({
    required this.sport,
    required this.laps,
    this.id,
    this.creator,
  });

  /// The `Sport` attribute.
  final TcxSport sport;

  /// The laps, in order.
  final List<TcxLap> laps;

  /// `<Id>`, the start time as written.
  final DateTime? id;

  /// `<Creator><Name>`: the device, e.g. `Garmin Forerunner 220`.
  final String? creator;

  /// Every point of every lap, in order.
  List<TrackPoint> get points => [for (final lap in laps) ...lap.points];
}

/// One `<Course>`.
class TcxCourse {
  /// Creates a course.
  const TcxCourse({
    required this.points,
    this.name,
    this.coursePoints = const <TcxCoursePoint>[],
    this.distanceM,
  });

  /// `<Name>`.
  final String? name;

  /// The `<Trackpoint>`s, in order.
  final List<TrackPoint> points;

  /// The `<CoursePoint>`s, in order.
  final List<TcxCoursePoint> coursePoints;

  /// The course lap's `<DistanceMeters>`.
  final double? distanceM;
}

/// A decoded TCX file: its activities and its courses.
class TcxDocument {
  /// Creates a document.
  const TcxDocument({
    this.activities = const <TcxActivity>[],
    this.courses = const <TcxCourse>[],
    this.author,
  });

  /// The `<Activity>` elements, in document order.
  final List<TcxActivity> activities;

  /// The `<Course>` elements, in document order.
  final List<TcxCourse> courses;

  /// `<Author><Name>`: the application that wrote the file.
  final String? author;

  /// Whether the file contained no activity and no course.
  bool get isEmpty => activities.isEmpty && courses.isEmpty;
}
