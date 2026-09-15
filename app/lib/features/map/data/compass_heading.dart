/// The phone's own compass, for the heading a GNSS cannot give.
///
/// A GNSS course is a course *over ground*: it says which way the rider has
/// been moving, so standing still there is none. The magnetometer, held
/// level by the accelerometer, says which way the phone is pointing, which is
/// what a rider waiting at a junction wants the map to show.
///
/// Neither sensor needs a runtime permission on Android or iOS, so nothing
/// has to be asked for before this starts.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'heading_smoother.dart';

part 'compass_heading.g.dart';

/// How often the two sensors are read out into one heading.
///
/// Ten times a second is smooth to the eye and cheap: both sensors are
/// already running at that rate, this only decides how often they are paired
/// up.
const Duration compassSampleInterval = Duration(milliseconds: 100);

/// Weight of the newest sample in the compass' circular average.
///
/// The raw magnetometer wobbles by several degrees between samples; a quarter
/// of each new reading is enough to follow a rider turning on the spot and
/// still hold the needle still while they stand.
const double compassSmoothingAlpha = 0.25;

/// How far the smoothed heading has to move before it is worth telling
/// anyone. Below a degree nothing on screen would change.
const double compassMinChangeDegrees = 1;

/// Shortest vector length the rotation matrix is still meaningful at.
///
/// The same idea as Android's own guard: a magnetic field parallel to gravity
/// (or none at all) leaves no east to point at.
const double _minimumVectorLength = 1e-6;

/// The heading the phone is pointing in, in degrees clockwise from north.
///
/// This is the tilt-compensated azimuth Android computes in
/// `SensorManager.getRotationMatrix` followed by `getOrientation`: the
/// magnetic field crossed with gravity gives east, gravity crossed with east
/// gives north, and the azimuth is the angle between the device's own y axis
/// and that north.
///
/// [accelerometer] and [magnetometer] are the raw three-axis readings in
/// device coordinates, in m/s² and µT. Returns `null` when the two vectors
/// carry no rotation — no field, no gravity, or the two parallel.
///
/// This is magnetic north, not true north: the declination between them is up
/// to a few degrees in Europe and correcting for it needs a world magnetic
/// model we do not carry. A cone a few degrees off is not worth the tables.
double? azimuthDegrees({
  required List<double> accelerometer,
  required List<double> magnetometer,
}) {
  if (accelerometer.length < 3 || magnetometer.length < 3) return null;
  final gravity = _Vector3.of(accelerometer);
  final field = _Vector3.of(magnetometer);
  if (gravity == null || field == null) return null;

  // A phone at rest reads gravity as an upward force, so this vector is the
  // up axis. East is perpendicular to both it and the field; north is what is
  // left of the field once east is taken out of it.
  final east = field.cross(gravity).normalized();
  final up = gravity.normalized();
  if (east == null || up == null) return null;
  final north = up.cross(east);

  // atan2 of the device's y axis against east and north: the angle the top of
  // the phone makes with magnetic north.
  final radians = math.atan2(east.y, north.y);
  final degrees = radians * 180 / math.pi;
  return (degrees + 360) % 360;
}

/// A three-element vector, only as much of one as the azimuth needs.
class _Vector3 {
  const _Vector3(this.x, this.y, this.z);

  /// The first three finite values of [values], or `null` for anything else.
  static _Vector3? of(List<double> values) {
    final x = values[0], y = values[1], z = values[2];
    if (!x.isFinite || !y.isFinite || !z.isFinite) return null;
    return _Vector3(x, y, z);
  }

  final double x;
  final double y;
  final double z;

  _Vector3 cross(_Vector3 other) => _Vector3(
    y * other.z - z * other.y,
    z * other.x - x * other.z,
    x * other.y - y * other.x,
  );

  /// The same direction at length one, or `null` when there is no direction.
  _Vector3? normalized() {
    final length = math.sqrt(x * x + y * y + z * z);
    if (!length.isFinite || length < _minimumVectorLength) return null;
    return _Vector3(x / length, y / length, z / length);
  }
}

/// Where the phone is pointing, as a stream.
///
/// Behind an interface so tests can drive a heading without a magnetometer,
/// and so nothing outside this file imports the sensor plugin.
abstract interface class CompassSource {
  /// Smoothed headings in degrees clockwise from north.
  ///
  /// Every listener gets its own subscription; the sensors run only while
  /// somebody is listening.
  Stream<double> get headings;
}

/// [CompassSource] over the accelerometer and the magnetometer.
class SensorsCompassSource implements CompassSource {
  /// Creates a source over the real sensors.
  ///
  /// The two streams can be replaced for a test that wants to feed raw
  /// samples rather than finished headings.
  const SensorsCompassSource({
    this.accelerometer,
    this.magnetometer,
    this.sampleInterval = compassSampleInterval,
  });

  /// Where the raw accelerometer samples come from; the sensor itself when
  /// this is left out.
  final Stream<AccelerometerEvent> Function()? accelerometer;

  /// The same for the magnetometer.
  final Stream<MagnetometerEvent> Function()? magnetometer;

  /// How often the latest sample of each sensor is turned into a heading.
  final Duration sampleInterval;

  @override
  Stream<double> get headings {
    late final StreamController<double> controller;
    StreamSubscription<AccelerometerEvent>? gravity;
    StreamSubscription<MagnetometerEvent>? field;
    Timer? timer;
    List<double>? lastGravity;
    List<double>? lastField;
    double? smoothed;
    double? sent;

    void sample() {
      final a = lastGravity;
      final m = lastField;
      if (a == null || m == null) return;
      final azimuth = azimuthDegrees(accelerometer: a, magnetometer: m);
      if (azimuth == null) return;
      final next = smoothed == null
          ? azimuth
          : blendHeadings(smoothed!, azimuth, compassSmoothingAlpha);
      smoothed = next;
      final last = sent;
      if (last != null &&
          headingDifference(next, last) < compassMinChangeDegrees) {
        return;
      }
      sent = next;
      controller.add(next);
    }

    controller = StreamController<double>(
      onListen: () {
        final gravitySamples =
            accelerometer?.call() ??
            accelerometerEventStream(samplingPeriod: sampleInterval);
        final fieldSamples =
            magnetometer?.call() ??
            magnetometerEventStream(samplingPeriod: sampleInterval);
        gravity = gravitySamples.listen((e) {
          lastGravity = <double>[e.x, e.y, e.z];
        });
        field = fieldSamples.listen((e) {
          lastField = <double>[e.x, e.y, e.z];
        });
        timer = Timer.periodic(sampleInterval, (_) => sample());
      },
      onCancel: () async {
        // Both sensors are let go in the same turn, not one after the other:
        // nobody is listening any more, so nothing should still be running.
        timer?.cancel();
        timer = null;
        final running = <Future<void>>[?gravity?.cancel(), ?field?.cancel()];
        gravity = null;
        field = null;
        await Future.wait(running);
      },
    );
    return controller.stream;
  }
}

/// The compass behind the app, overridable in tests.
@Riverpod(keepAlive: true)
CompassSource compassSource(Ref ref) => const SensorsCompassSource();

/// The heading the phone is pointing in, while anybody watches.
///
/// Deliberately `autoDispose`: listening starts the magnetometer, so the
/// sensor stops the moment the last screen that navigates goes away.
@riverpod
Stream<double> compassHeading(Ref ref) =>
    ref.watch(compassSourceProvider).headings;
