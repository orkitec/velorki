import 'dart:async';

import 'package:geolocator/geolocator.dart' as geo;
import 'package:velorki/core/files/track_exporter.dart';
import 'package:velorki/core/permissions/location_permission.dart';
import 'package:velorki/features/map/data/position_provider.dart';
import 'package:velorki/features/recording/data/recording_gateways.dart';
import 'package:velorki/features/recording/data/recording_service.dart';
import 'package:velorki/features/recording/domain/recording_snapshot.dart';
import 'package:velorki/features/recording/domain/recording_state.dart';
import 'package:velorki/features/recording/domain/ride.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// A [RecordingService] that records what the screen asked of it.
class FakeRecordingService implements RecordingService {
  final StreamController<RecordingSnapshot> _snapshots =
      StreamController<RecordingSnapshot>.broadcast();

  /// Every call, in order, e.g. `start(route-1)`.
  final List<String> calls = <String>[];

  /// What [stop] and [finishInterrupted] hand back.
  Ride? finishedRide;

  /// What [isRunning] answers.
  bool running = false;

  /// What [pendingState] answers.
  RecordingState? pending;

  /// What [reattach] answers.
  bool reattaches = false;

  /// When set, [start] throws it.
  RecordingException? startError;

  RecordingSnapshot? _last;

  @override
  Stream<RecordingSnapshot> get snapshots => _snapshots.stream;

  @override
  RecordingSnapshot? get lastSnapshot => _last;

  @override
  Future<bool> get isRunning async => running;

  /// Pushes [snapshot] to the UI, as the real recorder does every second.
  void emit(RecordingSnapshot snapshot) {
    _last = snapshot.status.isRecording ? snapshot : null;
    _snapshots.add(snapshot);
  }

  @override
  Future<RecordingState?> pendingState() async => pending;

  @override
  Future<void> start({
    required String notificationTitle,
    String? routeId,
  }) async {
    calls.add('start($routeId)');
    final error = startError;
    if (error != null) throw error;
    running = true;
  }

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> resume() async => calls.add('resume');

  @override
  Future<Ride?> stop({required String rideName}) async {
    calls.add('stop($rideName)');
    running = false;
    return finishedRide;
  }

  @override
  Future<bool> reattach() async {
    calls.add('reattach');
    return reattaches;
  }

  @override
  Future<void> resumeInterrupted(
    RecordingState state, {
    required String notificationTitle,
  }) async {
    calls.add('resumeInterrupted(${state.rideId})');
    running = true;
  }

  @override
  Future<Ride?> finishInterrupted(
    RecordingState state, {
    required String rideName,
  }) async {
    calls.add('finishInterrupted(${state.rideId})');
    return finishedRide;
  }

  @override
  Future<void> discardInterrupted(RecordingState state) async =>
      calls.add('discardInterrupted(${state.rideId})');

  @override
  Future<void> dispose() async {
    if (!_snapshots.isClosed) await _snapshots.close();
  }
}

/// A [TrackExporter] that records the export instead of sharing a file.
class FakeTrackExporter implements TrackExporter {
  /// Every export, in order.
  final List<ExportedTrack> exports = <ExportedTrack>[];

  /// When set, [share] throws it.
  Object? error;

  @override
  Future<void> share({
    required String name,
    required List<TrackPoint> points,
    required TrackKind kind,
    required TrackFormat format,
    DateTime? startTime,
  }) async {
    final failure = error;
    if (failure != null) throw failure;
    exports.add(
      ExportedTrack(
        name: name,
        points: points,
        kind: kind,
        format: format,
        startTime: startTime,
      ),
    );
  }
}

/// One call to [FakeTrackExporter.share].
class ExportedTrack {
  /// Records the call.
  const ExportedTrack({
    required this.name,
    required this.points,
    required this.kind,
    required this.format,
    this.startTime,
  });

  /// The file's name.
  final String name;

  /// The geometry handed over.
  final List<TrackPoint> points;

  /// Route or ride.
  final TrackKind kind;

  /// GPX or FIT.
  final TrackFormat format;

  /// The ride's start.
  final DateTime? startTime;
}

/// A location permission that answers from a script.
class FakeLocationPermissionGateway implements LocationPermissionGateway {
  /// Creates the gateway.
  FakeLocationPermissionGateway({
    this.status = LocationPermissionStatus.granted,
  });

  /// What [check] and [request] answer.
  LocationPermissionStatus status;

  /// How often [request] was called.
  int requests = 0;

  /// Whether the app settings page was opened.
  bool openedAppSettings = false;

  /// Whether the location settings page was opened.
  bool openedLocationSettings = false;

  @override
  Future<LocationPermissionStatus> check() async => status;

  @override
  Future<LocationPermissionStatus> request() async {
    requests++;
    return status;
  }

  @override
  Future<bool> openAppSettings() async => openedAppSettings = true;

  @override
  Future<bool> openLocationSettings() async => openedLocationSettings = true;
}

/// A notification permission that is granted unless a test says otherwise.
class FakeNotificationPermission implements NotificationPermissionGateway {
  /// Creates the gateway.
  FakeNotificationPermission({this.granted = true});

  /// What [isGranted] and [request] answer.
  bool granted;

  /// How often [request] was called.
  int requests = 0;

  @override
  Future<bool> isGranted() async => granted;

  @override
  Future<bool> request() async {
    requests++;
    return granted;
  }
}

/// A battery-optimisation gateway that is exempt unless a test says otherwise.
class FakeBatteryOptimization implements BatteryOptimizationGateway {
  /// Creates the gateway.
  FakeBatteryOptimization({this.ignored = true});

  /// What [isIgnored] answers.
  bool ignored;

  /// How often [request] was called.
  int requests = 0;

  @override
  Future<bool> isIgnored() async => ignored;

  @override
  Future<bool> request() async {
    requests++;
    return true;
  }
}

/// A screen wake lock that only remembers its state.
class FakeScreenWake implements ScreenWake {
  /// Whether the display is being kept awake.
  bool enabled = false;

  @override
  Future<void> enable() async => enabled = true;

  @override
  Future<void> disable() async => enabled = false;
}

/// A [PositionSource] fed from a test instead of from the GPS.
class FakePositionSource implements PositionSource {
  final StreamController<geo.Position> _positions =
      StreamController<geo.Position>.broadcast();

  /// The settings the recorder asked for.
  final List<geo.LocationSettings> settings = <geo.LocationSettings>[];

  /// Emits a fix [seconds] after 10:00 UTC, [meters] north of 48°/11°.
  void emit({required int seconds, required double meters, double? ele}) =>
      _positions.add(fakePosition(seconds: seconds, meters: meters, ele: ele));

  @override
  Stream<geo.Position> positions(geo.LocationSettings locationSettings) {
    settings.add(locationSettings);
    return _positions.stream;
  }

  @override
  Future<geo.Position?> lastKnown() async => null;

  @override
  Future<geo.Position?> current({
    Duration timeLimit = const Duration(seconds: 10),
  }) async => null;

  /// Closes the stream.
  Future<void> close() => _positions.close();
}

/// A geolocator fix for the tests: one degree of latitude is 111194.9266 m.
geo.Position fakePosition({
  required int seconds,
  required double meters,
  double? ele,
  double speed = 5,
}) => geo.Position(
  latitude: 48 + meters / 111194.9266,
  longitude: 11,
  timestamp: DateTime.utc(2026, 9, 12, 10, 0, seconds),
  accuracy: 4,
  altitude: ele ?? 0,
  altitudeAccuracy: 2,
  heading: 90,
  headingAccuracy: 5,
  speed: speed,
  speedAccuracy: 1,
  hasAccuracy: true,
  hasAltitude: ele != null,
  hasHeading: true,
  hasSpeed: true,
);
