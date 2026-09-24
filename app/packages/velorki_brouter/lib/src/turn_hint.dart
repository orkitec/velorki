/// What a rider has to do at one point of a route.
///
/// The kinds are BRouter's voice-hint commands; the numbers in the doc
/// comments are the indices BRouter writes into a GeoJSON `voicehints` row.
enum TurnKind {
  /// 1: carry on.
  straight,

  /// 2: turn left.
  left,

  /// 3: turn slightly left.
  slightLeft,

  /// 4: turn sharply left.
  sharpLeft,

  /// 5: turn right.
  right,

  /// 6: turn slightly right.
  slightRight,

  /// 7: turn sharply right.
  sharpRight,

  /// 8: keep left.
  keepLeft,

  /// 9: keep right.
  keepRight,

  /// 10: U-turn to the left.
  uTurnLeft,

  /// 11: U-turn to the right.
  uTurnRight,

  /// 12: the route leaves the mapped way (BRouter's "off route").
  offRoad,

  /// 13: roundabout, take [TurnHint.exitNumber].
  roundabout,

  /// 14: roundabout driven clockwise (left-hand traffic).
  roundaboutLeft,

  /// 15: turn around.
  uTurn,

  /// 16: a straight line to the next point with no way underneath.
  beeline,

  /// 17: take the exit on the left.
  exitLeft,

  /// 18: take the exit on the right.
  exitRight,

  /// 100: the end of the route.
  end;

  /// The kind BRouter numbers [index], or `null` for a number it never uses.
  static TurnKind? fromBRouterIndex(int index) => switch (index) {
    1 => straight,
    2 => left,
    3 => slightLeft,
    4 => sharpLeft,
    5 => right,
    6 => slightRight,
    7 => sharpRight,
    8 => keepLeft,
    9 => keepRight,
    10 => uTurnLeft,
    11 => uTurnRight,
    12 => offRoad,
    13 => roundabout,
    14 => roundaboutLeft,
    15 => uTurn,
    16 => beeline,
    17 => exitLeft,
    18 => exitRight,
    100 => end,
    _ => null,
  };

  /// BRouter's number for this kind, the inverse of [fromBRouterIndex].
  int get brouterIndex => switch (this) {
    straight => 1,
    left => 2,
    slightLeft => 3,
    sharpLeft => 4,
    right => 5,
    slightRight => 6,
    sharpRight => 7,
    keepLeft => 8,
    keepRight => 9,
    uTurnLeft => 10,
    uTurnRight => 11,
    offRoad => 12,
    roundabout => 13,
    roundaboutLeft => 14,
    uTurn => 15,
    beeline => 16,
    exitLeft => 17,
    exitRight => 18,
    end => 100,
  };
}

/// One turn instruction of a route, anchored to a point of its geometry.
class TurnHint {
  /// Creates a hint.
  const TurnHint({
    required this.pointIndex,
    required this.kind,
    this.exitNumber = 0,
    this.distanceToNextM = 0,
    this.angleDeg = 0,
    this.note,
  });

  /// Index into the route geometry of the point the turn happens at.
  final int pointIndex;

  /// What to do there.
  final TurnKind kind;

  /// The exit to take at a roundabout, counted from 1; 0 elsewhere.
  final int exitNumber;

  /// Distance along the route from this turn to the next hint, in metres
  /// (BRouter's `distanceToNext`).
  final double distanceToNextM;

  /// Turn angle in degrees, negative to the left, as BRouter measured it.
  final double angleDeg;

  /// What the route's author wrote for this turn — "Turn left onto Main
  /// Street", "gravel section starts" — when the route came from a file
  /// with a cue sheet. `null` for a turn the router worked out.
  final String? note;

  /// Reads one row of a GeoJSON `voicehints` array:
  /// `[pointIndex, command, exitNumber, distanceToNext, angle, ...]`.
  /// Returns `null` for a row that is malformed or names an unknown command.
  static TurnHint? fromBRouterRow(List<Object?> row) {
    if (row.length < 2) return null;
    final index = _int(row[0]);
    final command = _int(row[1]);
    if (index == null || command == null) return null;
    final kind = TurnKind.fromBRouterIndex(command);
    if (kind == null) return null;
    return TurnHint(
      pointIndex: index,
      kind: kind,
      exitNumber: row.length > 2 ? _int(row[2]) ?? 0 : 0,
      distanceToNextM: row.length > 3 ? _double(row[3]) ?? 0 : 0,
      angleDeg: row.length > 4 ? _double(row[4]) ?? 0 : 0,
    );
  }

  /// A JSON-friendly map, the inverse of [fromMap].
  Map<String, Object?> toMap() => <String, Object?>{
    'i': pointIndex,
    'k': kind.brouterIndex,
    if (exitNumber != 0) 'x': exitNumber,
    if (distanceToNextM != 0) 'd': distanceToNextM,
    if (angleDeg != 0) 'a': angleDeg,
    if (note != null) 'n': note,
  };

  /// Reads a map written by [toMap]; `null` when it is not one.
  static TurnHint? fromMap(Map<Object?, Object?> map) {
    final index = _int(map['i']);
    final command = _int(map['k']);
    if (index == null || command == null) return null;
    final kind = TurnKind.fromBRouterIndex(command);
    if (kind == null) return null;
    return TurnHint(
      pointIndex: index,
      kind: kind,
      exitNumber: _int(map['x']) ?? 0,
      distanceToNextM: _double(map['d']) ?? 0,
      angleDeg: _double(map['a']) ?? 0,
      note: map['n'] is String ? map['n'] as String : null,
    );
  }

  /// A copy anchored [offset] points further along, for a route stitched
  /// together from several results.
  TurnHint shifted(int offset) => TurnHint(
    pointIndex: pointIndex + offset,
    kind: kind,
    exitNumber: exitNumber,
    distanceToNextM: distanceToNextM,
    angleDeg: angleDeg,
    note: note,
  );

  static int? _int(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  static double? _double(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TurnHint &&
          other.pointIndex == pointIndex &&
          other.kind == kind &&
          other.exitNumber == exitNumber &&
          other.distanceToNextM == distanceToNextM &&
          other.angleDeg == angleDeg &&
          other.note == note;

  @override
  int get hashCode => Object.hash(
    pointIndex,
    kind,
    exitNumber,
    distanceToNextM,
    angleDeg,
    note,
  );

  @override
  String toString() =>
      'TurnHint(#$pointIndex ${kind.name}'
      '${exitNumber != 0 ? ' exit $exitNumber' : ''}, '
      'next ${distanceToNextM.toStringAsFixed(0)} m, '
      '${angleDeg.toStringAsFixed(0)}°)';
}
