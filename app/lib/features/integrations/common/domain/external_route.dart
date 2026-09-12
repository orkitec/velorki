/// One route as it sits in a partner account, before anything is imported.
///
/// Strava and Ride with GPS describe a route with the same four numbers, so
/// one screen lists both and one cache stores both.
class ExternalRoute {
  /// Creates a summary.
  const ExternalRoute({
    required this.id,
    required this.name,
    required this.distanceM,
    required this.elevationGainM,
    this.description,
    this.createdAt,
  });

  /// Reads a summary back from [toJson].
  factory ExternalRoute.fromJson(Map<String, Object?> json) {
    final created = json['created_at'];
    return ExternalRoute(
      id: '${json['id'] ?? ''}',
      name: json['name'] as String? ?? 'Route',
      distanceM: (json['distance_m'] as num?)?.toDouble() ?? 0,
      elevationGainM: (json['elevation_gain_m'] as num?)?.toDouble() ?? 0,
      description: json['description'] as String?,
      createdAt: created is String ? DateTime.tryParse(created) : null,
    );
  }

  /// The service's own id, used to fetch the GPX.
  final String id;

  /// The name the rider gave it.
  final String name;

  /// Length in metres.
  final double distanceM;

  /// Total climbing in metres.
  final double elevationGainM;

  /// The rider's description, when there is one.
  final String? description;

  /// When the route was created in the partner account.
  final DateTime? createdAt;

  /// This summary as JSON, for the seven-day list cache.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'distance_m': distanceM,
    'elevation_gain_m': elevationGainM,
    if (description != null) 'description': description,
    if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExternalRoute &&
          other.id == id &&
          other.name == name &&
          other.distanceM == distanceM &&
          other.elevationGainM == elevationGainM;

  @override
  int get hashCode => Object.hash(id, name, distanceM, elevationGainM);

  @override
  String toString() => 'ExternalRoute($id, $name)';
}
