import 'dart:async';

import 'package:geolocator/geolocator.dart' as geo;
import 'package:velorki/core/files/track_exporter.dart';
import 'package:velorki/core/permissions/location_permission.dart';
import 'package:velorki/features/planner/domain/route_profile.dart';
import 'package:velorki/features/map/data/position_provider.dart';
import 'package:velorki/features/recording/data/recording_gateways.dart';
import 'package:velorki/features/recording/data/recording_service.dart';
import 'package:velorki/features/recording/data/recording_task_handler.dart';
import 'package:velorki/features/recording/domain/gps_precision.dart';
import 'package:velorki/features/recording/domain/recording_snapshot.dart';
import 'package:velorki/features/recording/domain/recording_state.dart';
import 'package:velorki/features/recording/domain/ride.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';
import 'package:velorki/features/planner/domain/route_poi.dart';

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

  /// What [halt] answers: the recording left waiting for a name, or `null`
  /// when nothing was recorded.
  RecordingState? haltedRecording;

  /// The names [stop] and [finishInterrupted] were asked to save under, in
  /// order.
  final List<String> savedNames = <String>[];

  /// What [reattach] answers.
  bool reattaches = false;

  /// The rides [continueRide] was asked to record onto, in order.
  final List<Ride> continued = <Ride>[];

  /// When set, [start] throws it.
  RecordingException? startError;

  /// The GPS profile every start was asked for, in order.
  final List<GpsPrecision> precisions = <GpsPrecision>[];

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
    GpsPrecision precision = GpsPrecision.normal,
  }) async {
    calls.add('start($routeId)');
    precisions.add(precision);
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
    savedNames.add(rideName);
    running = false;
    return finishedRide;
  }

  @override
  Future<RecordingState?> halt() async {
    calls.add('halt');
    running = false;
    return haltedRecording;
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
    GpsPrecision? precision,
  }) async {
    calls.add('resumeInterrupted(${state.rideId})');
    if (precision != null) precisions.add(precision);
    running = true;
  }

  @override
  Future<void> continueRide(
    Ride ride, {
    required String notificationTitle,
    GpsPrecision precision = GpsPrecision.normal,
  }) async {
    calls.add('continueRide(${ride.id})');
    precisions.add(precision);
    continued.add(ride);
    running = true;
  }

  @override
  Future<Ride?> finishInterrupted(
    RecordingState state, {
    required String rideName,
  }) async {
    calls.add('finishInterrupted(${state.rideId})');
    savedNames.add(rideName);
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
    List<RoutePoi> pois = const <RoutePoi>[],
    List<TurnHint> turns = const <TurnHint>[],
    List<double?> temperaturesC = const <double?>[],
    List<DateTime> lapEnds = const <DateTime>[],
    RouteProfile? profile,
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

/// A screen dimmer that only remembers what it was asked for.
class FakeScreenDimmer implements ScreenDimmer {
  /// The brightness the app is being held at, `null` when the system's own
  /// brightness stands.
  double? brightness;

  /// Every call, in order, e.g. `dim(0.4)` then `reset`.
  final List<String> calls = <String>[];

  @override
  Future<void> dim(double value) async {
    brightness = value;
    calls.add('dim($value)');
  }

  @override
  Future<void> reset() async {
    brightness = null;
    calls.add('reset');
  }
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

/// A [ForegroundServiceHost] that records what the recording task asked of the
/// Android service instead of talking to a platform channel.
class FakeForegroundServiceHost implements ForegroundServiceHost {
  /// Everything sent to the UI isolate, in order: snapshots and the stop
  /// acknowledgement.
  final List<Map<Object?, Object?>> messages = <Map<Object?, Object?>>[];

  /// Every notification text the recorder asked for, in order.
  final List<String> notificationTexts = <String>[];

  /// How often the service was asked to stop itself.
  int stopServiceCalls = 0;

  /// How often the notification tap brought the app to the front.
  int launchAppCalls = 0;

  final List<Completer<void>> _waiting = <Completer<void>>[];

  /// The snapshots among [messages], decoded as the UI isolate decodes them.
  List<RecordingSnapshot> get snapshots => <RecordingSnapshot>[
    for (final message in messages)
      if (message[recordingMessageKind] == recordingSnapshotMessage)
        RecordingSnapshot.fromMap(message),
  ];

  /// The kinds of [messages], e.g. `['snapshot', 'stopped']`.
  List<Object?> get messageKinds => <Object?>[
    for (final message in messages) message[recordingMessageKind],
  ];

  /// A future that completes with the next message.
  ///
  /// The work behind a snapshot — flushing the journal, writing the state file
  /// — ends whenever that I/O ends, so a test waits for the message rather
  /// than for a stretch of real time.
  Future<void> nextMessage() {
    final completer = Completer<void>();
    _waiting.add(completer);
    return completer.future;
  }

  @override
  Future<void> stopService() async => stopServiceCalls++;

  @override
  void sendDataToMain(Object data) {
    messages.add(data as Map<Object?, Object?>);
    final waiting = List<Completer<void>>.of(_waiting);
    _waiting.clear();
    for (final completer in waiting) {
      completer.complete();
    }
  }

  @override
  Future<void> updateNotificationText(String text) async =>
      notificationTexts.add(text);

  @override
  void launchApp() => launchAppCalls++;
}

/// A geolocator platform that answers from a script, so the gateways over it
/// can be exercised without a device.
///
/// Install it with `geo.GeolocatorPlatform.instance = FakeGeolocatorPlatform()`
/// in a `setUp`; every `Geolocator` static call goes through it.
class FakeGeolocatorPlatform extends geo.GeolocatorPlatform {
  /// What [isLocationServiceEnabled] answers.
  bool serviceEnabled = true;

  /// What [checkPermission] answers.
  geo.LocationPermission permission = geo.LocationPermission.whileInUse;

  /// What [requestPermission] answers; [permission] when left unset.
  geo.LocationPermission? promptAnswer;

  /// What [getLastKnownPosition] answers.
  geo.Position? cachedPosition;

  /// What [getCurrentPosition] answers, unless [currentError] is set.
  geo.Position? freshPosition;

  /// Thrown by [getCurrentPosition] instead of a fix, when set.
  Object? currentError;

  /// What both settings pages answer.
  bool settingsOpen = true;

  /// How often the permission was checked.
  int checks = 0;

  /// How often the system prompt was asked for.
  int prompts = 0;

  /// Whether the app settings page was opened.
  bool openedAppSettings = false;

  /// Whether the location settings page was opened.
  bool openedLocationSettings = false;

  /// The settings every fix and every stream was asked for, in order.
  final List<geo.LocationSettings?> settings = <geo.LocationSettings?>[];

  final StreamController<geo.Position> _positions =
      StreamController<geo.Position>.broadcast();

  /// Whether the position stream is being listened to.
  bool get isStreaming => _positions.hasListener;

  /// Pushes [position] to whoever subscribed to the position stream.
  void emit(geo.Position position) => _positions.add(position);

  /// Closes the position stream.
  Future<void> close() =>
      _positions.isClosed ? Future<void>.value() : _positions.close();

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<geo.LocationPermission> checkPermission() async {
    checks++;
    return permission;
  }

  @override
  Future<geo.LocationPermission> requestPermission() async {
    prompts++;
    return promptAnswer ?? permission;
  }

  @override
  Future<geo.Position?> getLastKnownPosition({
    bool forceLocationManager = false,
  }) async => cachedPosition;

  @override
  Future<geo.Position> getCurrentPosition({
    geo.LocationSettings? locationSettings,
  }) async {
    settings.add(locationSettings);
    final failure = currentError;
    if (failure != null) throw failure;
    final position = freshPosition;
    if (position == null) throw TimeoutException('no fix was scripted');
    return position;
  }

  @override
  Stream<geo.Position> getPositionStream({
    geo.LocationSettings? locationSettings,
  }) {
    settings.add(locationSettings);
    return _positions.stream;
  }

  @override
  Future<bool> openAppSettings() async {
    openedAppSettings = true;
    return settingsOpen;
  }

  @override
  Future<bool> openLocationSettings() async {
    openedLocationSettings = true;
    return settingsOpen;
  }
}
