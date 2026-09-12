import 'dart:convert';

/// A partner service the app can connect to.
enum IntegrationService {
  /// Strava: ride upload and route import.
  strava,

  /// Ride with GPS: routes and trips in both directions.
  rwgps;

  /// The stable string used in storage keys, JSON and deep-link paths.
  String get id => name;

  /// The service whose [id] is [value], or `null`.
  static IntegrationService? fromId(String value) {
    for (final service in IntegrationService.values) {
      if (service.id == value) return service;
    }
    return null;
  }
}

/// One connected partner account, as it is kept in secure storage.
///
/// Access tokens never leave the phone: the relay only ever exchanges a code
/// or refreshes a token and hands the result back, and every upload and
/// download goes from the phone to the service directly.
class ConnectedAccount {
  /// Creates an account.
  const ConnectedAccount({
    required this.service,
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
    this.athleteId,
    this.athleteName,
    this.scopes = const <String>[],
  });

  /// Reads an account back from [toJson].
  factory ConnectedAccount.fromJson(Map<String, Object?> json) {
    final serviceId = json['service'];
    final service = serviceId is String
        ? IntegrationService.fromId(serviceId)
        : null;
    final accessToken = json['access_token'];
    if (service == null || accessToken is! String || accessToken.isEmpty) {
      throw const FormatException('not a connected account');
    }
    final expires = json['expires_at'];
    final scopes = json['scopes'];
    return ConnectedAccount(
      service: service,
      accessToken: accessToken,
      refreshToken: json['refresh_token'] as String?,
      expiresAt: expires is int
          ? DateTime.fromMillisecondsSinceEpoch(expires * 1000, isUtc: true)
          : null,
      athleteId: json['athlete_id'] as String?,
      athleteName: json['athlete_name'] as String?,
      scopes: scopes is List
          ? <String>[
              for (final scope in scopes)
                if (scope is String) scope,
            ]
          : const <String>[],
    );
  }

  /// Parses the JSON document [source] holds.
  ///
  /// Throws [FormatException] when it is not one, which is how a secure
  /// storage entry left over from an older version is discarded.
  factory ConnectedAccount.decode(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('not a connected account');
    }
    return ConnectedAccount.fromJson(decoded);
  }

  /// Which service this account belongs to.
  final IntegrationService service;

  /// The bearer token for the service's API.
  final String accessToken;

  /// The token that buys the next access token; Ride with GPS issues none.
  final String? refreshToken;

  /// When [accessToken] stops working, or `null` when it never does.
  final DateTime? expiresAt;

  /// The service's own id for the connected athlete, as a string.
  final String? athleteId;

  /// The athlete's display name, for the settings tile.
  final String? athleteName;

  /// The scopes the token was granted.
  final List<String> scopes;

  /// Whether the token is due for a refresh [leeway] before it expires.
  ///
  /// An account without an [expiresAt] never expires, and one without a
  /// [refreshToken] cannot be refreshed, so neither is ever due.
  bool needsRefresh({
    Duration leeway = const Duration(seconds: 60),
    DateTime? now,
  }) {
    final expiry = expiresAt;
    if (expiry == null || refreshToken == null) return false;
    return (now ?? DateTime.now()).toUtc().add(leeway).isAfter(expiry);
  }

  /// Whether [scope] was granted.
  bool hasScope(String scope) => scopes.contains(scope);

  /// A copy with the given fields replaced.
  ConnectedAccount copyWith({
    String? accessToken,
    String? refreshToken,
    DateTime? expiresAt,
    String? athleteId,
    String? athleteName,
    List<String>? scopes,
  }) => ConnectedAccount(
    service: service,
    accessToken: accessToken ?? this.accessToken,
    refreshToken: refreshToken ?? this.refreshToken,
    expiresAt: expiresAt ?? this.expiresAt,
    athleteId: athleteId ?? this.athleteId,
    athleteName: athleteName ?? this.athleteName,
    scopes: scopes ?? this.scopes,
  );

  /// This account as JSON, for secure storage.
  Map<String, Object?> toJson() => <String, Object?>{
    'service': service.id,
    'access_token': accessToken,
    if (refreshToken != null) 'refresh_token': refreshToken,
    if (expiresAt != null)
      'expires_at': expiresAt!.toUtc().millisecondsSinceEpoch ~/ 1000,
    if (athleteId != null) 'athlete_id': athleteId,
    if (athleteName != null) 'athlete_name': athleteName,
    if (scopes.isNotEmpty) 'scopes': scopes,
  };

  /// This account as the string secure storage holds.
  String encode() => jsonEncode(toJson());

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConnectedAccount &&
          other.service == service &&
          other.accessToken == accessToken &&
          other.refreshToken == refreshToken &&
          other.expiresAt == expiresAt &&
          other.athleteId == athleteId &&
          other.athleteName == athleteName;

  @override
  int get hashCode => Object.hash(
    service,
    accessToken,
    refreshToken,
    expiresAt,
    athleteId,
    athleteName,
  );

  /// Never prints the tokens: this object ends up in logs and error messages.
  @override
  String toString() =>
      'ConnectedAccount(${service.id}, athlete: ${athleteName ?? athleteId}, '
      'expires: $expiresAt)';
}
