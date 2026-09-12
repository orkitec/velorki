/// One asset an upload task produced.
class RwgpsTaskItem {
  /// Creates an item.
  const RwgpsTaskItem({
    required this.itemType,
    required this.itemId,
    this.itemUrl,
  });

  /// Parses one entry of a task's `items` array.
  factory RwgpsTaskItem.fromJson(Map<String, Object?> json) => RwgpsTaskItem(
    itemType: json['item_type'] as String? ?? '',
    itemId: '${json['item_id'] ?? ''}',
    itemUrl: json['item_url'] as String?,
  );

  /// `route` or `trip`.
  final String itemType;

  /// Ride with GPS' id for the created asset.
  final String itemId;

  /// The API URL of the asset.
  final String? itemUrl;

  /// The page a rider can open in a browser.
  String? get webUrl => switch (itemType) {
    'route' => rwgpsRouteUrl(itemId),
    'trip' => rwgpsTripUrl(itemId),
    _ => null,
  };

  @override
  String toString() => 'RwgpsTaskItem($itemType $itemId)';
}

/// One thing that went wrong while a task ran.
class RwgpsTaskError {
  /// Creates an error.
  const RwgpsTaskError({
    required this.code,
    required this.message,
    this.itemId,
  });

  /// Parses one entry of a task's `errors` array.
  factory RwgpsTaskError.fromJson(Map<String, Object?> json) => RwgpsTaskError(
    code: json['code'] as String? ?? 'error',
    message: json['message'] as String? ?? '',
    itemId: json['item_id'] == null ? null : '${json['item_id']}',
  );

  /// One of `duplicate`, `time_data_missing`, `no_tracks`, `empty_file`,
  /// `parse_failed`, `failed_to_process`, `weigh_in_failed`, `error`.
  final String code;

  /// Ride with GPS' own English wording.
  final String message;

  /// The existing asset this error refers to, as for a duplicate.
  final String? itemId;

  /// The file held no timestamps, so it cannot become a trip.
  bool get isTimeDataMissing => code == 'time_data_missing';

  /// The ride is already on Ride with GPS.
  bool get isDuplicate => code == 'duplicate';

  /// A sentence fit to show.
  String get display => message.isEmpty ? code : message;

  @override
  String toString() => 'RwgpsTaskError($code: $message)';
}

/// The asynchronous job an upload starts.
class RwgpsTask {
  /// Creates a task.
  const RwgpsTask({
    required this.id,
    required this.status,
    this.items = const <RwgpsTaskItem>[],
    this.errors = const <RwgpsTaskError>[],
  });

  /// Parses `{"task": {...}}` or a bare task object.
  factory RwgpsTask.fromJson(Map<String, Object?> json) {
    final inner = json['task'];
    final task = inner is Map<String, Object?> ? inner : json;
    final items = task['items'];
    final errors = task['errors'];
    return RwgpsTask(
      id: '${task['id'] ?? ''}',
      status: task['status'] as String? ?? 'pending',
      items: <RwgpsTaskItem>[
        if (items is List)
          for (final entry in items)
            if (entry is Map<String, Object?>) RwgpsTaskItem.fromJson(entry),
      ],
      errors: <RwgpsTaskError>[
        if (errors is List)
          for (final entry in errors)
            if (entry is Map<String, Object?>) RwgpsTaskError.fromJson(entry),
      ],
    );
  }

  /// The task id, polled at `GET /api/v1/tasks/{id}.json`.
  final String id;

  /// `pending` until the task has run, then `completed`.
  final String status;

  /// What the task created; empty while pending.
  final List<RwgpsTaskItem> items;

  /// What went wrong; empty when nothing did.
  final List<RwgpsTaskError> errors;

  /// Whether Ride with GPS has finished with it.
  bool get isCompleted => status == 'completed';

  /// The first asset the task created, when it created one.
  RwgpsTaskItem? get firstItem => items.isEmpty ? null : items.first;

  @override
  String toString() =>
      'RwgpsTask($id, $status, ${items.length} items, ${errors.length} errors)';
}

/// One entry of `GET /api/v1/routes.json`.
class RwgpsRouteSummary {
  /// Creates a summary.
  const RwgpsRouteSummary({
    required this.id,
    required this.name,
    required this.distanceM,
    required this.elevationGainM,
    this.description,
    this.createdAt,
  });

  /// Parses one route object.
  factory RwgpsRouteSummary.fromJson(Map<String, Object?> json) {
    final created = json['created_at'] ?? json['first_lat_lng_created_at'];
    return RwgpsRouteSummary(
      id: '${json['id'] ?? ''}',
      name: json['name'] as String? ?? 'Route',
      distanceM: (json['distance'] as num?)?.toDouble() ?? 0,
      elevationGainM: (json['elevation_gain'] as num?)?.toDouble() ?? 0,
      description: json['description'] as String?,
      createdAt: created is String ? DateTime.tryParse(created) : null,
    );
  }

  /// Ride with GPS' route id.
  final String id;

  /// The name the rider gave it.
  final String name;

  /// Length in metres.
  final double distanceM;

  /// Total climbing in metres.
  final double elevationGainM;

  /// The rider's description, when there is one.
  final String? description;

  /// When the route was created.
  final DateTime? createdAt;

  /// This summary as JSON, for the list cache.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'distance': distanceM,
    'elevation_gain': elevationGainM,
    if (description != null) 'description': description,
    if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RwgpsRouteSummary &&
          other.id == id &&
          other.name == name &&
          other.distanceM == distanceM &&
          other.elevationGainM == elevationGainM;

  @override
  int get hashCode => Object.hash(id, name, distanceM, elevationGainM);

  @override
  String toString() => 'RwgpsRouteSummary($id, $name)';
}

/// One entry of `GET /api/v1/trips.json`.
class RwgpsTripSummary {
  /// Creates a summary.
  const RwgpsTripSummary({
    required this.id,
    required this.name,
    required this.distanceM,
    this.departedAt,
  });

  /// Parses one trip object.
  factory RwgpsTripSummary.fromJson(Map<String, Object?> json) {
    final departed = json['departed_at'] ?? json['created_at'];
    return RwgpsTripSummary(
      id: '${json['id'] ?? ''}',
      name: json['name'] as String? ?? 'Ride',
      distanceM: (json['distance'] as num?)?.toDouble() ?? 0,
      departedAt: departed is String ? DateTime.tryParse(departed) : null,
    );
  }

  /// Ride with GPS' trip id.
  final String id;

  /// The name of the ride.
  final String name;

  /// Length in metres.
  final double distanceM;

  /// When the ride started.
  final DateTime? departedAt;

  @override
  String toString() => 'RwgpsTripSummary($id, $name)';
}

/// The connected Ride with GPS user.
class RwgpsUser {
  /// Creates a user.
  const RwgpsUser({required this.id, this.name});

  /// Parses `{"user": {...}}` or a bare user object.
  factory RwgpsUser.fromJson(Map<String, Object?> json) {
    final inner = json['user'];
    final user = inner is Map<String, Object?> ? inner : json;
    return RwgpsUser(id: '${user['id'] ?? ''}', name: user['name'] as String?);
  }

  /// Ride with GPS' user id.
  final String id;

  /// The display name.
  final String? name;

  @override
  String toString() => 'RwgpsUser($id, $name)';
}

/// The web page of a Ride with GPS route.
String rwgpsRouteUrl(String routeId) =>
    'https://ridewithgps.com/routes/$routeId';

/// The web page of a Ride with GPS trip.
String rwgpsTripUrl(String tripId) => 'https://ridewithgps.com/trips/$tripId';
