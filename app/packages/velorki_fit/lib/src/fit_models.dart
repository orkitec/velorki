import 'package:velorki_geo/velorki_geo.dart';

import 'fit_sport.dart';

/// What a FIT `course_point` marks, the profile's `course_point` type.
///
/// The turn types are what a head unit shows as a cue; the rest are the
/// places a course author flags along the way.
enum FitCoursePointType {
  generic(0),
  summit(1),
  valley(2),
  water(3),
  food(4),
  danger(5),
  left(6),
  right(7),
  straight(8),
  firstAid(9),
  fourthCategory(10),
  thirdCategory(11),
  secondCategory(12),
  firstCategory(13),
  horsCategory(14),
  sprint(15),
  leftFork(16),
  rightFork(17),
  middleFork(18),
  slightLeft(19),
  sharpLeft(20),
  slightRight(21),
  sharpRight(22),
  uTurn(23),
  segmentStart(24),
  segmentEnd(25),
  campsite(27),
  toilet(39);

  const FitCoursePointType(this.fitValue);

  /// The profile's enum value.
  final int fitValue;

  /// The type for a profile value, [generic] for one this build does not know.
  static FitCoursePointType fromFit(int? value) => values.firstWhere(
    (t) => t.fitValue == value,
    orElse: () => FitCoursePointType.generic,
  );
}

/// One `course_point` message: a cue or a place on a course.
class FitCoursePoint {
  /// Creates a course point.
  const FitCoursePoint({
    required this.pos,
    this.name,
    this.type = FitCoursePointType.generic,
    this.distanceM,
    this.time,
  });

  /// Where it is.
  final LatLng pos;

  /// `name`, at most 16 bytes on most head units.
  final String? name;

  /// What it marks.
  final FitCoursePointType type;

  /// `distance`: metres from the start of the course along the track.
  final double? distanceM;

  /// `timestamp`: when the course's virtual clock passes it.
  final DateTime? time;

  @override
  String toString() => 'FitCoursePoint($type, $name, ${distanceM}m)';
}

/// A decoded FIT course file: its track and its course points.
class FitCourse {
  /// Creates a course.
  const FitCourse({
    required this.points,
    this.name,
    this.sport = FitSport.cycling,
    this.coursePoints = const <FitCoursePoint>[],
  });

  /// `course.name`.
  final String? name;

  /// `course.sport`.
  final FitSport sport;

  /// The `record`s with a position, in file order.
  final List<TrackPoint> points;

  /// The `course_point`s, in file order.
  final List<FitCoursePoint> coursePoints;
}

/// What a `lap` message says about one lap of an activity.
class FitLap {
  /// Creates a lap.
  const FitLap({
    required this.startTime,
    required this.endTime,
    this.totalTimerS,
    this.totalElapsedS,
    this.totalDistanceM,
    this.calories,
    this.totalAscentM,
    this.totalDescentM,
    this.avgHeartRate,
    this.maxHeartRate,
    this.avgCadence,
    this.avgPower,
    this.maxPower,
    this.avgTemperatureC,
  });

  /// `start_time`.
  final DateTime startTime;

  /// The lap's `timestamp`, which is when it ended.
  final DateTime endTime;

  /// `total_timer_time`, the moving time in seconds.
  final double? totalTimerS;

  /// `total_elapsed_time`, in seconds.
  final double? totalElapsedS;

  /// `total_distance`, in metres.
  final double? totalDistanceM;

  /// `total_calories`.
  final int? calories;

  /// `total_ascent`, in metres.
  final double? totalAscentM;

  /// `total_descent`, in metres.
  final double? totalDescentM;

  /// `avg_heart_rate`.
  final int? avgHeartRate;

  /// `max_heart_rate`.
  final int? maxHeartRate;

  /// `avg_cadence`.
  final int? avgCadence;

  /// `avg_power`.
  final int? avgPower;

  /// `max_power`.
  final int? maxPower;

  /// `avg_temperature`, in degrees Celsius.
  final double? avgTemperatureC;
}

/// What the `session` message says about the whole activity: the totals as
/// the device computed them.
class FitSession {
  /// Creates a session.
  const FitSession({
    required this.startTime,
    required this.endTime,
    this.sport = FitSport.cycling,
    this.totalTimerS,
    this.totalElapsedS,
    this.totalDistanceM,
    this.calories,
    this.totalAscentM,
    this.totalDescentM,
    this.avgHeartRate,
    this.maxHeartRate,
    this.avgCadence,
    this.avgPower,
    this.maxPower,
    this.avgTemperatureC,
    this.numLaps,
  });

  /// `start_time`.
  final DateTime startTime;

  /// The session's `timestamp`, which is when it ended.
  final DateTime endTime;

  /// `sport`.
  final FitSport sport;

  /// `total_timer_time`, the moving time in seconds.
  final double? totalTimerS;

  /// `total_elapsed_time`, in seconds.
  final double? totalElapsedS;

  /// `total_distance`, in metres.
  final double? totalDistanceM;

  /// `total_calories`.
  final int? calories;

  /// `total_ascent`, in metres.
  final double? totalAscentM;

  /// `total_descent`, in metres.
  final double? totalDescentM;

  /// `avg_heart_rate`.
  final int? avgHeartRate;

  /// `max_heart_rate`.
  final int? maxHeartRate;

  /// `avg_cadence`.
  final int? avgCadence;

  /// `avg_power`.
  final int? avgPower;

  /// `max_power`.
  final int? maxPower;

  /// `avg_temperature`, in degrees Celsius.
  final double? avgTemperatureC;

  /// `num_laps`.
  final int? numLaps;
}

/// A decoded FIT activity file: the records, the laps and the session.
class FitActivity {
  /// Creates an activity.
  const FitActivity({
    required this.points,
    this.temperaturesC = const <double?>[],
    this.laps = const <FitLap>[],
    this.session,
    this.deviceName,
    this.manufacturer,
  });

  /// The `record`s with a position, in file order.
  final List<TrackPoint> points;

  /// `record.temperature` per point of [points], `null` where the record had
  /// none; empty when no record carried a temperature.
  final List<double?> temperaturesC;

  /// The `lap` messages, in order.
  final List<FitLap> laps;

  /// The `session` message, or `null` when the file has none.
  final FitSession? session;

  /// `device_info.product_name` of the recording device, or the product's
  /// name from the profile (`ELEMNT BOLT`, `Edge 820`), when known.
  final String? deviceName;

  /// `file_id.manufacturer` as a name (`garmin`, `wahoo_fitness`, `zwift`).
  final String? manufacturer;
}
