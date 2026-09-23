import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';

import '../../common/data/dio_errors.dart';
import '../../common/data/token_bucket.dart';
import '../../common/domain/integration_exception.dart';
import '../domain/strava_models.dart';

final Logger _log = Logger('StravaClient');

/// The Strava endpoints Velorki uses.
///
/// Written by hand rather than taken from `strava_client`, which expects the
/// client secret to live inside the app. Every path here is relative: [dio]
/// is based at the relay's pass-through for Strava, which checks the
/// subscription, opens the wrapped token `OAuthTokenInterceptor` put on the
/// request and forwards the call to `www.strava.com` with the same path.
/// The relay's allowlist is exactly these calls, so a new one here needs its
/// counterpart in `web/src/server/passthrough.ts`.
///
/// Documentation: <https://developers.strava.com/docs/reference/> and
/// <https://developers.strava.com/docs/uploads/>.
class StravaClient {
  /// Creates a client over [dio].
  ///
  /// [readBucket] keeps reads under Strava's 100-per-15-minutes limit;
  /// uploads are writes and are not counted against it. [sleep] is the delay
  /// between upload polls, injected so tests do not wait 30 seconds.
  StravaClient({
    required this.dio,
    this.sleep = realSleep,
    TokenBucket? readBucket,
  }) : _bucket = readBucket;

  /// Strava's API root, under the relay's pass-through. The host Strava
  /// moves to on 2027-01-04 is the relay's concern.
  static const String apiBase = '/api/v3';

  /// Strava's OAuth root, under the relay's pass-through.
  static const String oauthBase = '/oauth';

  /// The backoff between upload polls, as the milestone specifies.
  static const List<Duration> uploadPollBackoff = <Duration>[
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 16),
    Duration(seconds: 16),
    Duration(seconds: 16),
  ];

  /// How many routes one page of the route list holds.
  static const int defaultPerPage = 30;

  /// The client Strava is talked to over.
  final Dio dio;

  /// The delay between upload polls.
  final Sleeper sleep;

  final TokenBucket? _bucket;

  /// Starts an upload and returns Strava's first answer.
  ///
  /// `POST /uploads`, `multipart/form-data` with `file`, `data_type`, `name`,
  /// `description`, `sport_type` and `external_id`. Strava processes the file
  /// asynchronously, so the returned [StravaUpload] normally has neither an
  /// activity nor an error yet — feed it to [pollUpload].
  ///
  /// [externalId] is how a second upload of the same ride is recognised as a
  /// duplicate by Strava; the app sends the ride's uuid.
  Future<StravaUpload> uploadActivity({
    required List<int> bytes,
    required StravaDataType dataType,
    required String name,
    String? description,
    String sportType = 'Ride',
    String? externalId,
    String? fileName,
  }) async {
    final form = FormData.fromMap(<String, Object?>{
      'file': MultipartFile.fromBytes(
        bytes,
        filename: fileName ?? 'velorki.${dataType.wire}',
      ),
      'data_type': dataType.wire,
      'name': name,
      if (description != null && description.isNotEmpty)
        'description': description,
      'sport_type': sportType,
      'external_id': ?externalId,
    });
    final json = await _post('$apiBase/uploads', form);
    _log.info('started Strava upload ${json['id']}');
    return StravaUpload.fromJson(json);
  }

  /// Reads one upload's state. `GET /uploads/{uploadId}`.
  Future<StravaUpload> readUpload(String uploadId) async =>
      StravaUpload.fromJson(await _get('$apiBase/uploads/$uploadId'));

  /// Polls [uploadId] until Strava produced an activity or an error.
  ///
  /// Waits 2, 4, 8 then 16 seconds between attempts. Reports progress through
  /// [onProgress] so the UI can show Strava's own wording. Throws an
  /// [IntegrationException] when Strava reported an error, and when the
  /// upload was still pending after every attempt.
  Future<StravaUpload> pollUpload(
    String uploadId, {
    List<Duration> backoff = uploadPollBackoff,
    void Function(StravaUpload upload)? onProgress,
  }) async {
    StravaUpload? last;
    for (final wait in backoff) {
      await sleep(wait);
      final upload = await readUpload(uploadId);
      last = upload;
      onProgress?.call(upload);
      if (upload.succeeded) return upload;
      if (upload.failed) {
        throw IntegrationException(
          IntegrationFailure.rejected,
          'Strava rejected the upload: ${upload.error}',
        );
      }
    }
    throw IntegrationException(
      IntegrationFailure.serviceError,
      'Strava is still processing the upload. It will appear in Strava on '
      'its own; the link can be opened there.'
      '${last?.status == null ? '' : ' (${last!.status})'}',
    );
  }

  /// Uploads and waits, which is what the ride detail screen wants.
  Future<StravaUpload> uploadAndWait({
    required List<int> bytes,
    required StravaDataType dataType,
    required String name,
    String? description,
    String sportType = 'Ride',
    String? externalId,
    String? fileName,
    void Function(StravaUpload upload)? onProgress,
  }) async {
    final started = await uploadActivity(
      bytes: bytes,
      dataType: dataType,
      name: name,
      description: description,
      sportType: sportType,
      externalId: externalId,
      fileName: fileName,
    );
    onProgress?.call(started);
    if (started.failed) {
      throw IntegrationException(
        IntegrationFailure.rejected,
        'Strava rejected the upload: ${started.error}',
      );
    }
    if (started.succeeded) return started;
    return pollUpload(started.id, onProgress: onProgress);
  }

  /// The athlete's routes, newest first. `GET /athletes/{id}/routes`.
  Future<List<StravaRouteSummary>> listRoutes({
    required String athleteId,
    int page = 1,
    int perPage = defaultPerPage,
  }) async {
    final data = await _getList(
      '$apiBase/athletes/$athleteId/routes',
      query: <String, Object?>{'page': page, 'per_page': perPage},
    );
    return <StravaRouteSummary>[
      for (final entry in data)
        if (entry is Map<String, Object?>) StravaRouteSummary.fromJson(entry),
    ];
  }

  /// One route as a GPX file. `GET /routes/{id}/export_gpx`.
  Future<Uint8List> exportRouteGpx(String routeId) async {
    _bucket?.consume();
    try {
      final response = await dio.get<List<int>>(
        '$apiBase/routes/$routeId/export_gpx',
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) {
        throw const IntegrationException(
          IntegrationFailure.serviceError,
          'Strava returned an empty GPX file for this route.',
        );
      }
      return Uint8List.fromList(bytes);
    } on DioException catch (e) {
      throw integrationExceptionFromDio(e, service: 'Strava');
    }
  }

  /// Revokes the app's access. `POST /oauth/deauthorize`.
  ///
  /// The newer `POST /oauth/revoke` needs HTTP basic auth with the client
  /// secret, which by design is not in the app, so the legacy endpoint — which
  /// authenticates with the access token itself, here the bearer the relay
  /// puts on — is the one we can call. Failing to reach Strava does not stop
  /// the local disconnect; the caller deletes the token either way.
  Future<void> deauthorize() async {
    try {
      await dio.post<dynamic>('$oauthBase/deauthorize');
    } on DioException catch (e) {
      throw integrationExceptionFromDio(e, service: 'Strava');
    }
  }

  Future<Map<String, Object?>> _get(String url) async {
    _bucket?.consume();
    try {
      final response = await dio.get<dynamic>(url);
      return _asObject(response.data);
    } on DioException catch (e) {
      throw integrationExceptionFromDio(e, service: 'Strava');
    }
  }

  Future<List<Object?>> _getList(
    String url, {
    Map<String, Object?>? query,
  }) async {
    _bucket?.consume();
    try {
      final response = await dio.get<dynamic>(url, queryParameters: query);
      final data = response.data;
      if (data is List) return data;
      throw const IntegrationException(
        IntegrationFailure.serviceError,
        'Strava answered with something that is not a list.',
      );
    } on DioException catch (e) {
      throw integrationExceptionFromDio(e, service: 'Strava');
    }
  }

  Future<Map<String, Object?>> _post(String url, Object? body) async {
    try {
      final response = await dio.post<dynamic>(url, data: body);
      return _asObject(response.data);
    } on DioException catch (e) {
      throw integrationExceptionFromDio(e, service: 'Strava');
    }
  }

  static Map<String, Object?> _asObject(Object? data) {
    if (data is Map<String, Object?>) return data;
    if (data is Map) return data.cast<String, Object?>();
    throw const IntegrationException(
      IntegrationFailure.serviceError,
      'Strava answered with something that is not a JSON object.',
    );
  }
}
