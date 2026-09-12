import 'dart:convert';

/// Where a ride ended up after it was uploaded, per service.
///
/// Stored in the ride's `uploads_json` column as
/// `{"strava": {"upload_id": "...", "activity_id": "...", "status": "...",
/// "uploaded_at": "..."}}`, so the detail screen can offer "Open on Strava"
/// instead of uploading the same ride twice.
class RideUpload {
  /// Creates an upload record.
  const RideUpload({
    required this.status,
    required this.uploadedAt,
    this.uploadId,
    this.activityId,
    this.url,
    this.message,
  });

  /// Reads a record back from [toJson].
  factory RideUpload.fromJson(Map<String, Object?> json) => RideUpload(
    status: json['status'] as String? ?? RideUploadStatus.done,
    uploadedAt:
        DateTime.tryParse(json['uploaded_at'] as String? ?? '')?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    uploadId: json['upload_id'] as String?,
    activityId: json['activity_id'] as String?,
    url: json['url'] as String?,
    message: json['message'] as String?,
  );

  /// `pending`, `done` or `failed`.
  final String status;

  /// When the upload was last attempted.
  final DateTime uploadedAt;

  /// The service's id for the upload job, while it is running.
  final String? uploadId;

  /// The service's id for the activity or trip that was created.
  final String? activityId;

  /// The page a rider can open in a browser.
  final String? url;

  /// The service's own error wording, when it failed.
  final String? message;

  /// Whether the ride is on the service and can be opened.
  bool get isDone =>
      status == RideUploadStatus.done &&
      activityId != null &&
      activityId!.isNotEmpty;

  /// Whether the last attempt failed.
  bool get isFailed => status == RideUploadStatus.failed;

  /// This record as JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'status': status,
    'uploaded_at': uploadedAt.toUtc().toIso8601String(),
    if (uploadId != null) 'upload_id': uploadId,
    if (activityId != null) 'activity_id': activityId,
    if (url != null) 'url': url,
    if (message != null) 'message': message,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RideUpload &&
          other.status == status &&
          other.uploadedAt == uploadedAt &&
          other.uploadId == uploadId &&
          other.activityId == activityId &&
          other.url == url &&
          other.message == message;

  @override
  int get hashCode =>
      Object.hash(status, uploadedAt, uploadId, activityId, url, message);

  @override
  String toString() => 'RideUpload($status, activity: $activityId)';
}

/// The values [RideUpload.status] takes.
abstract final class RideUploadStatus {
  /// The service accepted the file but has not finished with it.
  static const String pending = 'pending';

  /// The activity or trip exists.
  static const String done = 'done';

  /// The service rejected it.
  static const String failed = 'failed';
}

/// The `uploads_json` column.
String encodeRideUploads(Map<String, RideUpload> uploads) => jsonEncode(
  uploads.map((service, upload) => MapEntry(service, upload.toJson())),
);

/// Parses the `uploads_json` column; anything unreadable yields no uploads
/// rather than an unopenable ride.
Map<String, RideUpload> decodeRideUploads(String? json) {
  if (json == null || json.isEmpty) return const <String, RideUpload>{};
  Object? decoded;
  try {
    decoded = jsonDecode(json);
  } on FormatException {
    return const <String, RideUpload>{};
  }
  if (decoded is! Map) return const <String, RideUpload>{};
  return <String, RideUpload>{
    for (final entry in decoded.entries)
      if (entry.key is String && entry.value is Map<String, Object?>)
        entry.key as String: RideUpload.fromJson(
          entry.value as Map<String, Object?>,
        ),
  };
}
