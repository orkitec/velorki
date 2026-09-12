import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:velorki_fit/velorki_fit.dart';
import 'package:velorki_geo/velorki_geo.dart';
import 'package:velorki_gpx/velorki_gpx.dart';

import '../../recording/data/ride_repository.dart';
import '../../recording/domain/ride.dart';
import '../../recording/domain/ride_upload.dart';
import '../common/domain/connected_account.dart';
import '../common/domain/integration_exception.dart';
import '../rwgps/data/rwgps_client.dart';
import '../rwgps/data/rwgps_providers.dart';
import '../rwgps/domain/rwgps_models.dart';
import '../strava/data/strava_client.dart';
import '../strava/data/strava_providers.dart';
import '../strava/domain/strava_models.dart';

/// The GPX track of [ride], the bytes both services accept.
Uint8List rideGpxBytes(Ride ride, {String creator = 'Velorki'}) =>
    Uint8List.fromList(
      utf8.encode(
        GpxCodec.encodeTrack(
          points: ride.points,
          name: ride.name,
          creator: creator,
        ),
      ),
    );

/// The FIT activity of [ride].
Uint8List rideFitBytes(Ride ride) => FitCodec.encodeActivity(
  ride.points,
  name: ride.name,
  startTime: ride.startedAt,
);

/// Whether [points] carry the timestamps a Ride with GPS trip needs.
bool hasTimestamps(List<TrackPoint> points) =>
    points.any((point) => point.time != null);

/// Uploads a recorded ride to a partner service and remembers where it went.
///
/// Never uploads a ride twice: the `uploads` column already holds the
/// activity id of a successful upload, and the UI offers "Open on Strava"
/// instead. That is not only politeness — Strava counts an upload against the
/// write quota and would create a duplicate activity.
class RideUploader {
  /// Creates an uploader.
  RideUploader({
    required this.rides,
    required this.strava,
    required this.rwgps,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Where the upload record is written.
  final RideRepository rides;

  /// The Strava client.
  final StravaClient strava;

  /// The Ride with GPS client.
  final RwgpsClient rwgps;

  final DateTime Function() _clock;

  /// Uploads [ride] to Strava and returns the stored record.
  ///
  /// Throws [IntegrationException] when the ride is already there, so the
  /// caller has to offer "Open on Strava" rather than silently doing nothing.
  Future<RideUpload> uploadToStrava(
    Ride ride, {
    StravaDataType dataType = StravaDataType.gpx,
    void Function(StravaUpload upload)? onProgress,
  }) async {
    _refuseDuplicate(ride, IntegrationService.strava, 'Strava');
    if (ride.points.isEmpty) throw _emptyRide('Strava');

    final result = await strava.uploadAndWait(
      bytes: dataType == StravaDataType.fit
          ? rideFitBytes(ride)
          : rideGpxBytes(ride),
      dataType: dataType,
      name: ride.name,
      description: ride.notes,
      externalId: 'velorki-${ride.id}',
      fileName: 'velorki-${ride.id}.${dataType.wire}',
      onProgress: onProgress,
    );
    final upload = RideUpload(
      status: RideUploadStatus.done,
      uploadedAt: _clock().toUtc(),
      uploadId: result.id,
      activityId: result.activityId,
      url: result.activityUrl,
    );
    await rides.recordUpload(
      ride.id,
      serviceId: IntegrationService.strava.id,
      upload: upload,
    );
    return upload;
  }

  /// Uploads [ride] to Ride with GPS as a trip.
  ///
  /// A trip is a ride that happened, so the track must carry timestamps; an
  /// untimed one is refused here rather than after the round trip, because
  /// Ride with GPS would only answer `time_data_missing`.
  Future<RideUpload> uploadToRwgps(Ride ride) async {
    _refuseDuplicate(ride, IntegrationService.rwgps, 'Ride with GPS');
    if (ride.points.isEmpty) throw _emptyRide('Ride with GPS');
    if (!hasTimestamps(ride.points)) {
      throw const IntegrationException(
        IntegrationFailure.rejected,
        'Ride with GPS needs timestamps to store a ride as a trip, and this '
        'track has none. Send it as a route instead, or export the GPX.',
      );
    }

    final task = await rwgps.uploadTripAndWait(
      gpxBytes: rideGpxBytes(ride),
      name: ride.name,
      description: ride.notes,
    );
    final item = task.firstItem;
    if (item == null) {
      throw IntegrationException(
        IntegrationFailure.rejected,
        task.errors.isEmpty
            ? 'Ride with GPS created nothing from the upload.'
            : 'Ride with GPS could not import the ride: '
                  '${task.errors.map((e) => e.display).join('; ')}',
      );
    }
    final upload = RideUpload(
      status: RideUploadStatus.done,
      uploadedAt: _clock().toUtc(),
      uploadId: task.id,
      activityId: item.itemId,
      url: item.webUrl ?? rwgpsTripUrl(item.itemId),
    );
    await rides.recordUpload(
      ride.id,
      serviceId: IntegrationService.rwgps.id,
      upload: upload,
    );
    return upload;
  }

  void _refuseDuplicate(Ride ride, IntegrationService service, String label) {
    final existing = ride.uploadFor(service.id);
    if (existing != null && existing.isDone) {
      throw IntegrationException(
        IntegrationFailure.rejected,
        'This ride is already on $label.',
      );
    }
  }

  IntegrationException _emptyRide(String label) => IntegrationException(
    IntegrationFailure.rejected,
    'There is nothing to send to $label: this ride has no track points.',
  );
}

/// The uploader over the app's clients.
final rideUploaderProvider = Provider<RideUploader>(
  (ref) => RideUploader(
    rides: ref.watch(rideRepositoryProvider),
    strava: ref.watch(stravaClientProvider),
    rwgps: ref.watch(rwgpsClientProvider),
  ),
);
