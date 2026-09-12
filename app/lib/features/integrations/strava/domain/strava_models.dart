/// The file formats Strava's upload endpoint accepts from Velorki.
///
/// Strava also takes `tcx` and the gzipped forms of all three; the app only
/// ever produces GPX and FIT.
enum StravaDataType {
  /// A GPX track.
  gpx,

  /// A Garmin FIT activity.
  fit;

  /// The value of the `data_type` multipart field.
  String get wire => name;
}

/// One row of `POST /uploads` and `GET /uploads/{id}`.
///
/// Strava processes an upload asynchronously: the POST answers immediately
/// with `status: "Your activity is still being processed."` and no
/// `activity_id`, and the app polls until either [activityId] is set or
/// [error] is.
class StravaUpload {
  /// Creates an upload record.
  const StravaUpload({
    required this.id,
    this.externalId,
    this.error,
    this.status,
    this.activityId,
  });

  /// Parses Strava's upload JSON.
  ///
  /// `id` and `activity_id` are 64-bit integers that JavaScript clients get
  /// as `id_str`; they are kept as strings here so nothing is lost on a
  /// platform with 53-bit numbers.
  factory StravaUpload.fromJson(Map<String, Object?> json) {
    final activity = json['activity'];
    return StravaUpload(
      id: _id(json['id_str']) ?? _id(json['id']) ?? '',
      externalId: json['external_id'] as String?,
      error: json['error'] as String?,
      status: json['status'] as String?,
      activityId:
          _id(json['activity_id']) ??
          (activity is Map<String, Object?> ? _id(activity['id']) : null),
    );
  }

  /// Strava's id for this upload, used for polling.
  final String id;

  /// The `external_id` the app sent, echoed back.
  final String? externalId;

  /// Why the upload failed, when it did. Strava's own wording.
  final String? error;

  /// Strava's progress message, shown while polling.
  final String? status;

  /// The activity that was created, once processing finished.
  final String? activityId;

  /// Whether the upload became an activity.
  bool get succeeded => activityId != null && activityId!.isNotEmpty;

  /// Whether Strava gave up on the file.
  bool get failed => error != null && error!.isNotEmpty;

  /// Whether Strava is still working on it.
  bool get pending => !succeeded && !failed;

  /// The public page of the created activity.
  String? get activityUrl => succeeded ? stravaActivityUrl(activityId!) : null;

  @override
  String toString() =>
      'StravaUpload($id, activity: $activityId, error: $error)';

  static String? _id(Object? value) {
    if (value == null) return null;
    if (value is String) return value.isEmpty ? null : value;
    if (value is num) return value.toInt().toString();
    return null;
  }
}

/// The web page of a Strava activity.
String stravaActivityUrl(String activityId) =>
    'https://www.strava.com/activities/$activityId';

/// The web page of a Strava route.
String stravaRouteUrl(String routeId) =>
    'https://www.strava.com/routes/$routeId';

/// One entry of `GET /athletes/{id}/routes`.
class StravaRouteSummary {
  /// Creates a summary.
  const StravaRouteSummary({
    required this.id,
    required this.name,
    required this.distanceM,
    required this.elevationGainM,
    this.description,
    this.createdAt,
  });

  /// Parses one route object.
  factory StravaRouteSummary.fromJson(Map<String, Object?> json) {
    final id = json['id_str'] ?? json['id'];
    final created = json['created_at'];
    return StravaRouteSummary(
      id: id is String ? id : '${id ?? ''}',
      name: json['name'] as String? ?? 'Route',
      distanceM: (json['distance'] as num?)?.toDouble() ?? 0,
      elevationGainM: (json['elevation_gain'] as num?)?.toDouble() ?? 0,
      description: json['description'] as String?,
      createdAt: created is String ? DateTime.tryParse(created) : null,
    );
  }

  /// Strava's route id.
  final String id;

  /// The name the athlete gave it.
  final String name;

  /// Length in metres.
  final double distanceM;

  /// Total climbing in metres.
  final double elevationGainM;

  /// The athlete's own description, when there is one.
  final String? description;

  /// When the route was created on Strava.
  final DateTime? createdAt;

  /// This summary as JSON, for the seven-day list cache.
  Map<String, Object?> toJson() => <String, Object?>{
    'id_str': id,
    'name': name,
    'distance': distanceM,
    'elevation_gain': elevationGainM,
    if (description != null) 'description': description,
    if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StravaRouteSummary &&
          other.id == id &&
          other.name == name &&
          other.distanceM == distanceM &&
          other.elevationGainM == elevationGainM;

  @override
  int get hashCode => Object.hash(id, name, distanceM, elevationGainM);

  @override
  String toString() => 'StravaRouteSummary($id, $name)';
}
