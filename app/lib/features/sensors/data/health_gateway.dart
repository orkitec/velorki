import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'health_gateway.g.dart';

final Logger _log = Logger('velorki.sensors.health');

/// One heart rate reading as the platform's health store keeps it.
@immutable
class HeartRateSample {
  /// Creates a sample.
  const HeartRateSample({
    required this.bpm,
    required this.at,
    required this.sourceName,
  });

  /// Beats per minute.
  final int bpm;

  /// When it was measured.
  final DateTime at;

  /// What wrote it — the watch, the strap's own app, whatever else. Shown
  /// nowhere yet; kept because a rider with two writers will want to know.
  final String sourceName;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HeartRateSample &&
          other.bpm == bpm &&
          other.at == at &&
          other.sourceName == sourceName;

  @override
  int get hashCode => Object.hash(bpm, at, sourceName);

  @override
  String toString() => 'HeartRateSample($bpm bpm at $at from $sourceName)';
}

/// The platform's health store — Apple Health on iOS, Health Connect on
/// Android — as the little of it Velorki uses.
///
/// Everything the `health` package offers is behind this one interface, so the
/// tests never touch the plugin and the app never touches the plugin's
/// vocabulary. Nothing here is called before the rider switches Health on in
/// Settings: the first call that can raise an OS permission prompt is
/// [requestAuthorization], and that one is only made by the switch itself.
abstract interface class HealthGateway {
  /// Whether this device has a health store at all: HealthKit on iOS, an
  /// installed and usable Health Connect on Android.
  Future<bool> isAvailable();

  /// Asks the OS for access, showing its permission sheet.
  ///
  /// [write] also asks for permission to save rides as workouts. Returns
  /// whether the rider granted what was asked for.
  Future<bool> requestAuthorization({required bool write});

  /// Whether access has already been granted, without asking for it.
  Future<bool> hasAuthorization({required bool write});

  /// Every heart rate sample stored between [from] and [to], oldest first.
  Future<List<HeartRateSample>> heartRate(DateTime from, DateTime to);

  /// Saves a ride as a cycling workout. Returns whether it was written.
  Future<bool> writeCyclingWorkout({
    required DateTime start,
    required DateTime end,
    required double distanceM,
    double? avgHeartRateBpm,
  });
}

/// What the platform's health store is called.
///
/// A brand name, so it reads the same in every language; the section in
/// Settings still takes its title from the localisations, because the sentence
/// around it is translated.
String healthStoreName(TargetPlatform platform) =>
    platform == TargetPlatform.android ? 'Health Connect' : 'Apple Health';

/// Whether [platform] has a health store Velorki can talk to.
///
/// Linux and Windows have none, so the whole Sensors section is hidden there
/// rather than shown with a switch that cannot do anything.
bool healthSupportedOn(TargetPlatform platform) => switch (platform) {
  TargetPlatform.iOS || TargetPlatform.macOS || TargetPlatform.android => true,
  TargetPlatform.linux ||
  TargetPlatform.windows ||
  TargetPlatform.fuchsia => false,
};

/// [HealthGateway] over the `health` package.
///
/// Every call is wrapped: a plugin that is not there — a desktop build, a
/// phone whose Health Connect was uninstalled mid-ride — answers "no" instead
/// of throwing into a recording.
class PluginHealthGateway implements HealthGateway {
  /// Creates a gateway. [health] is only injected by the package's own tests.
  PluginHealthGateway({Health? health, TargetPlatform? platform})
    : _health = health ?? Health(),
      _platform = platform ?? defaultTargetPlatform;

  /// Heart rate is the only kind read, and a cycling workout the only thing
  /// written; asking for more would be asking the rider for more.
  static const List<HealthDataType> _readTypes = <HealthDataType>[
    HealthDataType.HEART_RATE,
  ];

  static const List<HealthDataType> _writeTypes = <HealthDataType>[
    HealthDataType.WORKOUT,
  ];

  final Health _health;
  final TargetPlatform _platform;

  bool _configured = false;

  @override
  Future<bool> isAvailable() async {
    if (!healthSupportedOn(_platform)) return false;
    return _guard('isAvailable', false, () async {
      await _configure();
      // Only Android has a store that can be missing: Health Connect is an
      // app, HealthKit is part of the system.
      if (_platform != TargetPlatform.android) return true;
      return _health.isHealthConnectAvailable();
    });
  }

  @override
  Future<bool> requestAuthorization({required bool write}) =>
      _guard('requestAuthorization', false, () async {
        await _configure();
        return _health.requestAuthorization(
          _types(write: write),
          permissions: _access(write: write),
        );
      });

  @override
  Future<bool> hasAuthorization({required bool write}) =>
      _guard('hasAuthorization', false, () async {
        await _configure();
        final granted = await _health.hasPermissions(
          _types(write: write),
          permissions: _access(write: write),
        );
        return granted ?? false;
      });

  @override
  Future<List<HeartRateSample>> heartRate(DateTime from, DateTime to) =>
      _guard('heartRate', const <HeartRateSample>[], () async {
        await _configure();
        final points = await _health.getHealthDataFromTypes(
          types: _readTypes,
          startTime: from,
          endTime: to,
        );
        final samples = <HeartRateSample>[
          for (final point in points)
            if (point.value case final NumericHealthValue value)
              HeartRateSample(
                bpm: value.numericValue.round(),
                at: point.dateTo,
                sourceName: point.sourceName,
              ),
        ]..sort((a, b) => a.at.compareTo(b.at));
        return samples;
      });

  @override
  Future<bool> writeCyclingWorkout({
    required DateTime start,
    required DateTime end,
    required double distanceM,
    double? avgHeartRateBpm,
  }) => _guard('writeCyclingWorkout', false, () async {
    await _configure();
    // [avgHeartRateBpm] has nowhere to go: the package writes a workout
    // without a heart rate summary, and the samples it would be computed from
    // are already in the store. It stays in the interface because the fake
    // asserts on it and a later package version may take it.
    return _health.writeWorkoutData(
      activityType: HealthWorkoutActivityType.BIKING,
      start: start,
      end: end,
      totalDistance: distanceM <= 0 ? null : distanceM.round(),
    );
  });

  List<HealthDataType> _types({required bool write}) => <HealthDataType>[
    ..._readTypes,
    if (write) ..._writeTypes,
  ];

  List<HealthDataAccess> _access({required bool write}) => <HealthDataAccess>[
    ...List<HealthDataAccess>.filled(_readTypes.length, HealthDataAccess.READ),
    if (write)
      ...List<HealthDataAccess>.filled(
        _writeTypes.length,
        HealthDataAccess.WRITE,
      ),
  ];

  /// `configure()` reads the device id and must run before anything else; it
  /// is cheap and idempotent, so it is simply done on the first call.
  Future<void> _configure() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  Future<T> _guard<T>(
    String what,
    T fallback,
    Future<T> Function() body,
  ) async {
    try {
      return await body();
    } on Object catch (error, stackTrace) {
      _log.warning('health $what failed', error, stackTrace);
      return fallback;
    }
  }
}

/// The health store of this platform, or `null` where there is none.
///
/// Constructing it asks the OS for nothing; the gateway only reaches the
/// plugin once something calls it, and the only thing that calls it is a ride
/// recorded with the Health switch on.
@Riverpod(keepAlive: true)
HealthGateway? healthGateway(Ref ref) =>
    healthSupportedOn(defaultTargetPlatform) ? PluginHealthGateway() : null;
