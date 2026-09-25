import '../../sensors/application/sensors_seen.dart';
import 'recording_snapshot.dart';

/// A figure a ride shows while it is recorded.
enum LiveFigure {
  distance,
  speed,
  avgSpeed,
  ascent,
  descent,
  movingTime,
  heartRate,
  cadence,
  power,
  remaining,
  arrival,
}

/// The order the figures are shown in unless the rider chose another: the
/// three a rider glances at most, then the climb and the moving time, then
/// the sensors, then what is left of a followed route.
const List<LiveFigure> defaultLiveFigureOrder = LiveFigure.values;

/// One figure with what it reads now.
///
/// Only the fields its [figure] uses are set: metres for the distances and
/// heights, metres a second for the speeds, a count for the sensors, a
/// duration for the moving time, a clock time for the arrival.
class LiveFigureReading {
  /// Creates the reading.
  const LiveFigureReading(
    this.figure, {
    this.value,
    this.duration,
    this.time,
    this.lost = false,
    this.average,
  });

  /// Which figure.
  final LiveFigure figure;

  /// The figure's value, in the unit the figure is counted in.
  final double? value;

  /// The moving time.
  final Duration? duration;

  /// When the ride reaches the end of the route.
  final DateTime? time;

  /// A sensor that has fallen silent: [value] is the last it reported.
  final bool lost;

  /// The ride's average of a sensor figure, when it keeps one.
  final double? average;

  @override
  bool operator ==(Object other) =>
      other is LiveFigureReading &&
      other.figure == figure &&
      other.value == value &&
      other.duration == duration &&
      other.time == time &&
      other.lost == lost &&
      other.average == average;

  @override
  int get hashCode => Object.hash(figure, value, duration, time, lost, average);
}

/// The ride's figures in [order], each only when it has something to show:
/// a sensor once it has reported this ride (the last value, marked [lost],
/// while it is silent; paused, nothing is lost), what is left of a route
/// and when it ends only on a route with some left, the arrival only once
/// there is an average speed to reckon it by.
///
/// Every view of the figures reads this one list: the grid on the sheet in
/// full, the bar the docked sheet becomes its first four. So a rider's own
/// order, once they can choose one, is followed everywhere at once.
List<LiveFigureReading> liveFigures({
  required RecordingSnapshot snapshot,
  required SensorsSeenState remembered,
  required double speedMps,
  required bool paused,
  double? remainingM,
  DateTime? now,
  List<LiveFigure> order = defaultLiveFigureOrder,
}) {
  final seen = remembered.rideId == snapshot.rideId
      ? remembered
      : const SensorsSeenState();
  final onRoute = remainingM != null && remainingM > 0;
  LiveFigureReading? sensor(
    LiveFigure figure,
    int? current,
    int? last, {
    int? average,
  }) {
    final value = current ?? last;
    if (value == null) return null;
    return LiveFigureReading(
      figure,
      value: value.toDouble(),
      lost: current == null && !paused,
      average: average?.toDouble(),
    );
  }

  LiveFigureReading? reading(LiveFigure figure) => switch (figure) {
    LiveFigure.distance => LiveFigureReading(figure, value: snapshot.distanceM),
    LiveFigure.speed => LiveFigureReading(figure, value: speedMps),
    LiveFigure.avgSpeed => LiveFigureReading(
      figure,
      value: snapshot.avgSpeedMps,
    ),
    LiveFigure.ascent => LiveFigureReading(figure, value: snapshot.ascentM),
    LiveFigure.descent => LiveFigureReading(figure, value: snapshot.descentM),
    LiveFigure.movingTime => LiveFigureReading(
      figure,
      duration: snapshot.moving,
    ),
    LiveFigure.heartRate => sensor(
      figure,
      snapshot.heartRateBpm,
      seen.heartRateBpm,
      average: snapshot.avgHeartRateBpm,
    ),
    LiveFigure.cadence => sensor(figure, snapshot.cadenceRpm, seen.cadenceRpm),
    LiveFigure.power => sensor(figure, snapshot.powerW, seen.powerW),
    LiveFigure.remaining =>
      onRoute ? LiveFigureReading(figure, value: remainingM) : null,
    LiveFigure.arrival => switch (_arrival(
      remainingM,
      snapshot.avgSpeedMps,
      now ?? DateTime.now(),
    )) {
      final eta? when onRoute => LiveFigureReading(figure, time: eta),
      _ => null,
    },
  };

  return <LiveFigureReading>[for (final figure in order) ?reading(figure)];
}

/// When the ride reaches the end of a route [remainingM] away at
/// [avgSpeedMps], from [now]; `null` without both.
DateTime? _arrival(double? remainingM, double avgSpeedMps, DateTime now) {
  if (remainingM == null || remainingM <= 0 || avgSpeedMps < 0.5) {
    return null;
  }
  return now.add(Duration(seconds: (remainingM / avgSpeedMps).round()));
}
