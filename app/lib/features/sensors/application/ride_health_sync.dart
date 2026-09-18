import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../../app/app_config.dart';
import '../../../core/geo/ride_stats.dart';
import '../../recording/data/ride_repository.dart';
import '../../recording/domain/ride.dart';
import '../data/health_gateway.dart';
import '../data/sensor_settings.dart';

final Logger _log = Logger('velorki.sensors.health');

/// How far a stored sample may be from a fix and still count as its heart
/// rate. A watch writes every few seconds; half a minute either way is still
/// the same effort, and beyond it the number would be made up.
const Duration healthAttachWindow = Duration(seconds: 30);

/// The rides already written to the health store, newest last.
const String prefsHealthWorkoutsWritten = 'sensors.health.written';

/// How many ride ids the marker remembers. A rider who has recorded more than
/// this since a ride was written is in no danger of it being written again:
/// the marker is only consulted right after a ride is saved.
const int _writtenMemory = 200;

/// What happens to a finished ride when Health is on: the heart rate the
/// phone's store knows about is stamped onto the track, and the ride goes back
/// into the store as a cycling workout.
///
/// Both halves are best effort and neither may break saving a ride, so
/// everything here is caught and logged. The attach only fills gaps: a fix
/// that already carries a heart rate got it live from a strap or a watch,
/// which is the better reading of the two.
class RideHealthSync {
  /// Creates the sync.
  RideHealthSync({
    required this.rides,
    required this.prefs,
    required this.settings,
    this.gateway,
  });

  /// Where the updated ride row is written.
  final RideRepository rides;

  /// Where the "already written" marker is kept.
  final SharedPreferences prefs;

  /// The rider's choices; both halves are off while [SensorSettings.health] is.
  final SensorSettings settings;

  /// The health store, `null` on a platform that has none.
  final HealthGateway? gateway;

  /// Runs both halves for [ride]. Does nothing at all while Health is off.
  Future<void> afterRide(Ride ride) async {
    final gateway = this.gateway;
    if (gateway == null || !settings.health) return;
    try {
      final attached = await _attach(ride, gateway);
      if (!settings.healthWrite) return;
      await _write(ride, (attached ?? ride).stats, gateway);
    } on Object catch (error, stackTrace) {
      // A ride that is saved is saved; the health store is the part that may
      // fail.
      _log.warning('health sync for ride ${ride.id} failed', error, stackTrace);
    }
  }

  /// Fills the fixes that have no heart rate from the store's samples and
  /// rewrites the row when anything was filled. Returns the updated ride, or
  /// `null` when nothing changed.
  Future<Ride?> _attach(Ride ride, HealthGateway gateway) async {
    final points = ride.points;
    if (points.isEmpty) return null;
    final samples = await gateway.heartRate(ride.startedAt, ride.endedAt);
    if (samples.isEmpty) return null;
    final ordered = <HeartRateSample>[...samples]
      ..sort((a, b) => a.at.compareTo(b.at));

    var changed = false;
    var cursor = 0;
    final filled = <TrackPoint>[];
    for (final point in points) {
      final time = point.time;
      if (time == null || point.heartRateBpm != null) {
        filled.add(point);
        continue;
      }
      // The fixes are in order and so are the samples, so the nearest sample
      // is found by walking the one cursor forward, not by searching.
      while (cursor + 1 < ordered.length &&
          _gap(ordered[cursor + 1], time) <= _gap(ordered[cursor], time)) {
        cursor++;
      }
      final nearest = ordered[cursor];
      if (_gap(nearest, time) > healthAttachWindow) {
        filled.add(point);
        continue;
      }
      filled.add(point.copyWith(heartRateBpm: nearest.bpm));
      changed = true;
    }
    if (!changed) return null;

    final updated = Ride(
      id: ride.id,
      name: ride.name,
      startedAt: ride.startedAt,
      endedAt: ride.endedAt,
      stats: computeRideStats(filled, breaks: statsBreaksOf(ride.pauses)),
      geometry: PackedTrack.encode(filled),
      routeId: ride.routeId,
      pauses: ride.pauses,
      uploads: ride.uploads,
      notes: ride.notes,
    );
    await rides.save(updated);
    return updated;
  }

  /// Writes the workout, once per ride and never again.
  Future<void> _write(Ride ride, RideStats stats, HealthGateway gateway) async {
    final written = prefs.getStringList(prefsHealthWorkoutsWritten) ?? const [];
    if (written.contains(ride.id)) return;
    final ok = await gateway.writeCyclingWorkout(
      start: ride.startedAt,
      end: ride.endedAt,
      distanceM: stats.distanceM,
      avgHeartRateBpm: stats.avgHeartRateBpm?.toDouble(),
    );
    // A refused write is not a written workout: the marker stays off, so the
    // next ride is still offered to the store.
    if (!ok) return;
    final next = <String>[...written, ride.id];
    await prefs.setStringList(
      prefsHealthWorkoutsWritten,
      next.length <= _writtenMemory
          ? next
          : next.sublist(next.length - _writtenMemory),
    );
  }

  static Duration _gap(HeartRateSample sample, DateTime time) =>
      sample.at.difference(time).abs();
}

/// The post-ride sync over the app's repository and health store.
final rideHealthSyncProvider = Provider<RideHealthSync>(
  (ref) => RideHealthSync(
    rides: ref.watch(rideRepositoryProvider),
    prefs: ref.watch(sharedPreferencesProvider),
    settings: ref.watch(sensorSettingsProvider),
    gateway: ref.watch(healthGatewayProvider),
  ),
);
