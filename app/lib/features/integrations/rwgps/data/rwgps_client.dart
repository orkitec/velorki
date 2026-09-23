import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';

import '../../common/data/dio_errors.dart';
import '../../common/domain/integration_exception.dart';
import '../domain/rwgps_models.dart';

final Logger _log = Logger('RwgpsClient');

/// The Ride with GPS v1 endpoints Velorki uses.
///
/// Every path is relative: [dio] is based at the relay's pass-through for
/// Ride with GPS, which opens the wrapped token `OAuthTokenInterceptor` put
/// in `X-Velorki-Token` and forwards the call to `ridewithgps.com` with the
/// same path. The relay's allowlist is exactly these calls, so a new one here
/// needs its counterpart in `web/src/server/passthrough.ts`.
///
/// **Headers.** Upstream, an OAuth request carries exactly one authentication
/// header, `Authorization: Bearer <access_token>`, which the relay puts on.
/// `x-rwgps-api-key` and `x-rwgps-auth-token` belong to the *basic* scheme —
/// the one for single-user and organisation accounts — and must not be sent
/// alongside a bearer token. There is no API version header.
/// Source: <https://ridewithgps.com/api/v1/doc/authentication> and the
/// machine-readable spec at <https://ridewithgps.com/api/v1/openapi.yaml>.
///
/// **Uploads are asynchronous.** `POST /api/v1/routes.json` and
/// `POST /api/v1/trips.json` take `multipart/form-data` with a `file` field
/// and answer `202` with `{"task": {...}}`; the task is polled at
/// `GET /api/v1/tasks/{id}.json` until its `status` is `completed`, and the
/// outcome is then in its `items` and `errors` arrays.
class RwgpsClient {
  /// Creates a client over [dio].
  RwgpsClient({required this.dio, this.sleep = realSleep});

  /// The API root, under the relay's pass-through.
  static const String apiBase = '/api/v1';

  /// The OAuth root, under the relay's pass-through.
  static const String oauthBase = '/oauth';

  /// The waits between task polls. Ride with GPS imports a GPX in a second or
  /// two, so the first poll is quick and the ceiling is low.
  static const List<Duration> taskPollBackoff = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 8),
    Duration(seconds: 8),
  ];

  /// Ride with GPS' page size floor is 20 and its ceiling 200.
  static const int defaultPageSize = 50;

  /// The client Ride with GPS is talked to over.
  final Dio dio;

  /// The delay between task polls.
  final Sleeper sleep;

  /// The authenticated user. `GET /api/v1/users/current.json`.
  Future<RwgpsUser> currentUser() async =>
      RwgpsUser.fromJson(await _get('$apiBase/users/current.json'));

  /// Uploads [gpxBytes] as a route. `POST /api/v1/routes.json`.
  ///
  /// Returns the pending task; hand it to [pollTask].
  Future<RwgpsTask> uploadRoute({
    required List<int> gpxBytes,
    required String name,
    String? description,
  }) async {
    final task = RwgpsTask.fromJson(
      await _post(
        '$apiBase/routes.json',
        _fileForm(bytes: gpxBytes, name: name, description: description),
      ),
    );
    _log.info('started Ride with GPS route upload ${task.id}');
    return task;
  }

  /// Uploads [gpxBytes] as a trip. `POST /api/v1/trips.json`.
  ///
  /// A trip is a ride that happened, so its track points must carry
  /// timestamps; Ride with GPS answers a file without them with the
  /// `time_data_missing` error code rather than refusing the upload outright.
  Future<RwgpsTask> uploadTrip({
    required List<int> gpxBytes,
    required String name,
    String? description,
  }) async {
    final task = RwgpsTask.fromJson(
      await _post(
        '$apiBase/trips.json',
        _fileForm(bytes: gpxBytes, name: name, description: description),
      ),
    );
    _log.info('started Ride with GPS trip upload ${task.id}');
    return task;
  }

  /// Reads one task. `GET /api/v1/tasks/{id}.json`.
  Future<RwgpsTask> readTask(String taskId) async =>
      RwgpsTask.fromJson(await _get('$apiBase/tasks/$taskId.json'));

  /// Polls [taskId] until it completes.
  ///
  /// Throws [IntegrationException] when the task reported errors and created
  /// nothing, and when it was still pending after every attempt.
  Future<RwgpsTask> pollTask(
    String taskId, {
    List<Duration> backoff = taskPollBackoff,
  }) async {
    for (final wait in backoff) {
      await sleep(wait);
      final task = await readTask(taskId);
      if (!task.isCompleted) continue;
      if (task.items.isEmpty && task.errors.isNotEmpty) {
        throw IntegrationException(
          IntegrationFailure.rejected,
          'Ride with GPS could not import the file: '
          '${task.errors.map((e) => e.display).join('; ')}',
        );
      }
      return task;
    }
    throw const IntegrationException(
      IntegrationFailure.serviceError,
      'Ride with GPS is still processing the upload. It will appear in the '
      'account on its own.',
    );
  }

  /// Uploads a route and waits for the task, which is what the UI wants.
  Future<RwgpsTask> uploadRouteAndWait({
    required List<int> gpxBytes,
    required String name,
    String? description,
  }) async {
    final started = await uploadRoute(
      gpxBytes: gpxBytes,
      name: name,
      description: description,
    );
    return started.isCompleted ? started : pollTask(started.id);
  }

  /// Uploads a trip and waits for the task.
  Future<RwgpsTask> uploadTripAndWait({
    required List<int> gpxBytes,
    required String name,
    String? description,
  }) async {
    final started = await uploadTrip(
      gpxBytes: gpxBytes,
      name: name,
      description: description,
    );
    return started.isCompleted ? started : pollTask(started.id);
  }

  /// The user's routes. `GET /api/v1/routes.json`.
  Future<List<RwgpsRouteSummary>> listRoutes({
    int page = 1,
    int pageSize = defaultPageSize,
  }) async {
    final json = await _get(
      '$apiBase/routes.json',
      query: <String, Object?>{'page': page, 'page_size': pageSize},
    );
    final routes = json['routes'];
    return <RwgpsRouteSummary>[
      if (routes is List)
        for (final entry in routes)
          if (entry is Map<String, Object?>) RwgpsRouteSummary.fromJson(entry),
    ];
  }

  /// The user's trips. `GET /api/v1/trips.json`.
  Future<List<RwgpsTripSummary>> listTrips({
    int page = 1,
    int pageSize = defaultPageSize,
  }) async {
    final json = await _get(
      '$apiBase/trips.json',
      query: <String, Object?>{'page': page, 'page_size': pageSize},
    );
    final trips = json['trips'];
    return <RwgpsTripSummary>[
      if (trips is List)
        for (final entry in trips)
          if (entry is Map<String, Object?>) RwgpsTripSummary.fromJson(entry),
    ];
  }

  /// One route as a GPX file. `GET /api/v1/routes/{id}.gpx`.
  ///
  /// The extension picks the format; `gpx` is a GPX 1.1 track at full
  /// resolution, without waypoints.
  Future<Uint8List> routeGpx(String routeId) async {
    try {
      final response = await dio.get<List<int>>(
        '$apiBase/routes/$routeId.gpx',
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) {
        throw const IntegrationException(
          IntegrationFailure.serviceError,
          'Ride with GPS returned an empty GPX file for this route.',
        );
      }
      return Uint8List.fromList(bytes);
    } on DioException catch (e) {
      throw integrationExceptionFromDio(e, service: 'Ride with GPS');
    }
  }

  /// Revokes the app's access. `POST /oauth/revoke.json`.
  ///
  /// Ride with GPS revokes with the client id and secret in the body, which
  /// the relay writes for this one call; the app sends nothing but the
  /// wrapped token in its header. Failing to reach the relay does not stop
  /// the local disconnect; the caller deletes the token either way.
  Future<void> revoke() async {
    try {
      await dio.post<dynamic>('$oauthBase/revoke.json');
    } on DioException catch (e) {
      throw integrationExceptionFromDio(e, service: 'Ride with GPS');
    }
  }

  FormData _fileForm({
    required List<int> bytes,
    required String name,
    String? description,
  }) => FormData.fromMap(<String, Object?>{
    'file': MultipartFile.fromBytes(bytes, filename: '$name.gpx'),
    'name': name,
    if (description != null && description.isNotEmpty)
      'description': description,
  });

  Future<Map<String, Object?>> _get(
    String url, {
    Map<String, Object?>? query,
  }) async {
    try {
      final response = await dio.get<dynamic>(url, queryParameters: query);
      return _asObject(response.data);
    } on DioException catch (e) {
      throw integrationExceptionFromDio(e, service: 'Ride with GPS');
    }
  }

  Future<Map<String, Object?>> _post(String url, Object? body) async {
    try {
      final response = await dio.post<dynamic>(url, data: body);
      return _asObject(response.data);
    } on DioException catch (e) {
      throw integrationExceptionFromDio(e, service: 'Ride with GPS');
    }
  }

  static Map<String, Object?> _asObject(Object? data) {
    if (data is Map<String, Object?>) return data;
    if (data is Map) return data.cast<String, Object?>();
    throw const IntegrationException(
      IntegrationFailure.serviceError,
      'Ride with GPS answered with something that is not a JSON object.',
    );
  }
}
