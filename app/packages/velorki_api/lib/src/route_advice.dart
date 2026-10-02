part of 'models.dart';

/// What a finding about a route is about.
///
/// JSON values: `traffic`, `steep`, `surface`, `water`, `food`, `detour`,
/// `profile`, `other`.
enum FindingKind {
  /// Motor traffic: a busy road.
  traffic('traffic'),

  /// A steep climb or descent.
  steep('steep'),

  /// The surface: gravel, a track, cobbles.
  surface('surface'),

  /// Water: a tap, a fountain, a long stretch without.
  water('water'),

  /// Food: a café, a bakery.
  food('food'),

  /// A detour the route takes.
  detour('detour'),

  /// The bike profile.
  profile('profile'),

  /// Anything else.
  other('other');

  const FindingKind(this.json);

  /// The snake_case string used on the wire.
  final String json;

  /// Parses [value]; a kind this client does not know is [other], since a
  /// finding is only ever shown, never routed on.
  static FindingKind fromJson(String value) {
    for (final kind in values) {
      if (kind.json == value) return kind;
    }
    return other;
  }
}

/// A change the app can make to the route for a finding.
///
/// Sealed, so a `switch` over a [RouteFix] is exhaustive.
sealed class RouteFix {
  /// Creates a fix.
  const RouteFix();

  /// Parses a `fix` object, or `null` for a fix type this client does not
  /// know: the finding is still shown, only without its action.
  static RouteFix? fromJson(Map<String, Object?> json) => switch (_reqString(
    json,
    'type',
  )) {
    'add_stop' => AddStopFix(_reqString(json, 'place_id')),
    'avoid' => AvoidFix(
      fromKm: _reqDouble(json, 'from_km'),
      toKm: _reqDouble(json, 'to_km'),
    ),
    'profile' => ProfileFix(ProfileHint.fromJson(_reqString(json, 'profile'))),
    _ => null,
  };

  /// Serialises to a `fix` object.
  Map<String, Object?> toJson();
}

/// Ride past a place of the digest: `{"type": "add_stop", "place_id": "p3"}`.
final class AddStopFix extends RouteFix {
  /// Creates the fix.
  const AddStopFix(this.placeId);

  /// The id of a [DigestPlace] in the digest the question was sent with.
  final String placeId;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'add_stop',
    'place_id': placeId,
  };

  @override
  bool operator ==(Object other) =>
      other is AddStopFix && other.placeId == placeId;

  @override
  int get hashCode => placeId.hashCode;

  @override
  String toString() => 'AddStopFix($placeId)';
}

/// Route around a stretch: `{"type": "avoid", "from_km": .., "to_km": ..}`.
final class AvoidFix extends RouteFix {
  /// Creates the fix.
  const AvoidFix({required this.fromKm, required this.toKm});

  /// Where the stretch starts, in kilometres from the route's start.
  final double fromKm;

  /// Where it ends, in kilometres from the route's start.
  final double toKm;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'avoid',
    'from_km': fromKm,
    'to_km': toKm,
  };

  @override
  bool operator ==(Object other) =>
      other is AvoidFix && other.fromKm == fromKm && other.toKm == toKm;

  @override
  int get hashCode => Object.hash(fromKm, toKm);

  @override
  String toString() => 'AvoidFix($fromKm-$toKm km)';
}

/// Plan again with another bike: `{"type": "profile", "profile": "gravel"}`.
final class ProfileFix extends RouteFix {
  /// Creates the fix.
  const ProfileFix(this.profile);

  /// The profile to switch to.
  final ProfileHint profile;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'profile',
    'profile': profile.json,
  };

  @override
  bool operator ==(Object other) =>
      other is ProfileFix && other.profile == profile;

  @override
  int get hashCode => profile.hashCode;

  @override
  String toString() => 'ProfileFix(${profile.json})';
}

/// One concrete point along the route, from the `route` step.
class RouteFinding {
  /// Creates a finding.
  const RouteFinding({
    required this.kind,
    required this.text,
    this.fromKm,
    this.toKm,
    this.placeId,
    this.fix,
  });

  /// What it is about.
  final FindingKind kind;

  /// One sentence for the rider, in their language and units.
  final String text;

  /// Where along the route it starts, in kilometres, for a stretch.
  final double? fromKm;

  /// Where along the route it ends, in kilometres, for a stretch.
  final double? toKm;

  /// The digest place it is about, for a place.
  final String? placeId;

  /// What the app can do about it; `null` when nothing.
  final RouteFix? fix;

  /// Parses one `findings` entry.
  factory RouteFinding.fromJson(Map<String, Object?> json) {
    final fix = _optObject(json, 'fix');
    return RouteFinding(
      kind: FindingKind.fromJson(_reqString(json, 'kind')),
      text: _reqString(json, 'text'),
      fromKm: _optDouble(json, 'from_km'),
      toKm: _optDouble(json, 'to_km'),
      placeId: _optString(json, 'place_id'),
      fix: fix == null ? null : RouteFix.fromJson(fix),
    );
  }

  /// Serialises to one `findings` entry.
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.json,
    if (fromKm != null) 'from_km': fromKm,
    if (toKm != null) 'to_km': toKm,
    if (placeId != null) 'place_id': placeId,
    'text': text,
    if (fix != null) 'fix': fix!.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is RouteFinding &&
      other.kind == kind &&
      other.text == text &&
      other.fromKm == fromKm &&
      other.toKm == toKm &&
      other.placeId == placeId &&
      other.fix == fix;

  @override
  int get hashCode => Object.hash(kind, text, fromKm, toKm, placeId, fix);

  @override
  String toString() =>
      'RouteFinding(${kind.json}, $text, $fromKm-$toKm, $placeId, $fix)';
}

/// The answer to a question about a route: the `route_advice` event, the
/// arguments of the relay's `advise_route` tool call.
///
/// The relay has already checked every place id against the digest that was
/// sent and every kilometre against the route's length.
class RouteAdvice {
  /// Creates the advice.
  const RouteAdvice({
    required this.answer,
    this.findings = const <RouteFinding>[],
  });

  /// A short answer, in the rider's language and units.
  final String answer;

  /// Up to six findings, in route order.
  final List<RouteFinding> findings;

  /// Parses the `route_advice` data.
  factory RouteAdvice.fromJson(Map<String, Object?> json) => RouteAdvice(
    answer: _reqString(json, 'answer'),
    findings: _objectList(json, 'findings', RouteFinding.fromJson),
  );

  /// Serialises to the `route_advice` data.
  Map<String, Object?> toJson() => <String, Object?>{
    'answer': answer,
    'findings': [for (final f in findings) f.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is RouteAdvice &&
      other.answer == answer &&
      _listEquals(other.findings, findings);

  @override
  int get hashCode => Object.hash(answer, Object.hashAll(findings));

  @override
  String toString() => 'RouteAdvice($answer, ${findings.length} findings)';
}
