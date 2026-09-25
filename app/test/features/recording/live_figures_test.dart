import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/recording/domain/live_figures.dart';
import 'package:velorki/features/recording/domain/recording_snapshot.dart';
import 'package:velorki/features/sensors/application/sensors_seen.dart';

RecordingSnapshot _snapshot({
  int? heartRateBpm,
  int? powerW,
  double avgSpeedMps = 5,
}) => RecordingSnapshot(
  rideId: 'ride-1',
  status: RecordingStatus.active,
  startedAt: DateTime.utc(2026, 9, 12, 10),
  distanceM: 1200,
  moving: const Duration(minutes: 4),
  avgSpeedMps: avgSpeedMps,
  ascentM: 30,
  descentM: 10,
  heartRateBpm: heartRateBpm,
  powerW: powerW,
);

List<LiveFigure> _kinds(List<LiveFigureReading> readings) =>
    readings.map((r) => r.figure).toList();

void main() {
  test('without sensors or a route: the six the grid always had, in its '
      'order', () {
    final figures = liveFigures(
      snapshot: _snapshot(),
      remembered: const SensorsSeenState(),
      speedMps: 6,
      paused: false,
    );
    expect(_kinds(figures), [
      LiveFigure.distance,
      LiveFigure.speed,
      LiveFigure.avgSpeed,
      LiveFigure.ascent,
      LiveFigure.descent,
      LiveFigure.movingTime,
    ]);
    expect(figures[1].value, 6);
    expect(figures[5].duration, const Duration(minutes: 4));
  });

  test('a sensor that has reported joins; one gone silent keeps its last '
      'value, marked lost, except while paused', () {
    final remembered = const SensorsSeenState(rideId: 'ride-1', powerW: 180);
    final running = liveFigures(
      snapshot: _snapshot(heartRateBpm: 140),
      remembered: remembered,
      speedMps: 6,
      paused: false,
    );
    expect(_kinds(running).skip(6), [LiveFigure.heartRate, LiveFigure.power]);
    expect(running[6].lost, isFalse);
    expect(running[7].value, 180);
    expect(running[7].lost, isTrue);

    final paused = liveFigures(
      snapshot: _snapshot(heartRateBpm: 140),
      remembered: remembered,
      speedMps: 0,
      paused: true,
    );
    expect(paused[7].lost, isFalse);
  });

  test('another ride\'s sensors are not this one\'s', () {
    final figures = liveFigures(
      snapshot: _snapshot(),
      remembered: const SensorsSeenState(rideId: 'ride-0', heartRateBpm: 150),
      speedMps: 6,
      paused: false,
    );
    expect(_kinds(figures), isNot(contains(LiveFigure.heartRate)));
  });

  test('on a route, what is left and when it ends; no arrival without an '
      'average speed to reckon it by', () {
    final now = DateTime.utc(2026, 9, 12, 12);
    final figures = liveFigures(
      snapshot: _snapshot(),
      remembered: const SensorsSeenState(),
      speedMps: 6,
      paused: false,
      remainingM: 3000,
      now: now,
    );
    expect(_kinds(figures).skip(6), [LiveFigure.remaining, LiveFigure.arrival]);
    expect(figures.last.time, now.add(const Duration(minutes: 10)));

    final standing = liveFigures(
      snapshot: _snapshot(avgSpeedMps: 0),
      remembered: const SensorsSeenState(),
      speedMps: 0,
      paused: false,
      remainingM: 3000,
    );
    expect(_kinds(standing).last, LiveFigure.remaining);
  });

  test('a chosen order is followed, and what has no value is still left '
      'out', () {
    final figures = liveFigures(
      snapshot: _snapshot(),
      remembered: const SensorsSeenState(),
      speedMps: 6,
      paused: false,
      order: const [
        LiveFigure.heartRate,
        LiveFigure.movingTime,
        LiveFigure.distance,
      ],
    );
    expect(_kinds(figures), [LiveFigure.movingTime, LiveFigure.distance]);
  });
}
