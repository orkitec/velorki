import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_fit/velorki_fit.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../features/planner/domain/route_poi.dart';

/// The cue sheet and the points of interest of a route as the `course_point`s
/// a FIT course carries: what a head unit shows as the next turn, and the
/// places it announces on the way.
///
/// A turn takes the note the author wrote when there is one, else a plain
/// word for the manoeuvre, since the name is all the head unit shows. The
/// finish is left out: the course ends where the track ends.
List<FitCoursePoint> courseCuePoints({
  required List<TrackPoint> points,
  List<TurnHint> turns = const <TurnHint>[],
  List<RoutePoi> pois = const <RoutePoi>[],
}) {
  if (points.isEmpty) return const <FitCoursePoint>[];
  final cues = <FitCoursePoint>[
    for (final turn in turns)
      if (turn.kind != TurnKind.end &&
          turn.pointIndex >= 0 &&
          turn.pointIndex < points.length)
        FitCoursePoint(
          pos: points[turn.pointIndex].pos,
          name: turn.note ?? turnWord(turn.kind),
          type: coursePointTypeOf(turn.kind),
        ),
    for (final poi in pois)
      FitCoursePoint(
        pos: poi.pos,
        name: poi.name.isEmpty ? poi.description : poi.name,
        type: coursePointTypeOfPoi(poi),
      ),
  ];
  return cues;
}

/// The FIT course point type for a place.
///
/// A point of no particular kind that came out of a FIT course goes back as
/// the type it arrived as, so a climb category or a segment marker — things
/// no kind of ours stands for — survives the round trip.
FitCoursePointType coursePointTypeOfPoi(RoutePoi poi) {
  if (poi.kind == PoiKind.generic) {
    final source = poi.sourceType;
    for (final type in FitCoursePointType.values) {
      if (type.name == source) return type;
    }
  }
  return switch (poi.kind) {
    PoiKind.water => FitCoursePointType.water,
    PoiKind.food => FitCoursePointType.food,
    PoiKind.danger => FitCoursePointType.danger,
    PoiKind.summit => FitCoursePointType.summit,
    PoiKind.firstAid => FitCoursePointType.firstAid,
    PoiKind.toilet => FitCoursePointType.toilet,
    PoiKind.campsite => FitCoursePointType.campsite,
    _ => FitCoursePointType.generic,
  };
}

/// The FIT course point type for a turn.
FitCoursePointType coursePointTypeOf(TurnKind kind) => switch (kind) {
  TurnKind.left => FitCoursePointType.left,
  TurnKind.right => FitCoursePointType.right,
  TurnKind.slightLeft => FitCoursePointType.slightLeft,
  TurnKind.slightRight => FitCoursePointType.slightRight,
  TurnKind.sharpLeft => FitCoursePointType.sharpLeft,
  TurnKind.sharpRight => FitCoursePointType.sharpRight,
  TurnKind.keepLeft || TurnKind.exitLeft => FitCoursePointType.leftFork,
  TurnKind.keepRight || TurnKind.exitRight => FitCoursePointType.rightFork,
  TurnKind.uTurn ||
  TurnKind.uTurnLeft ||
  TurnKind.uTurnRight => FitCoursePointType.uTurn,
  TurnKind.roundabout || TurnKind.roundaboutLeft => FitCoursePointType.generic,
  _ => FitCoursePointType.straight,
};

/// The turn a FIT course point type stands for, `null` for a place rather
/// than a manoeuvre.
TurnKind? turnKindOf(FitCoursePointType type) => switch (type) {
  FitCoursePointType.left => TurnKind.left,
  FitCoursePointType.right => TurnKind.right,
  FitCoursePointType.straight => TurnKind.straight,
  FitCoursePointType.slightLeft => TurnKind.slightLeft,
  FitCoursePointType.slightRight => TurnKind.slightRight,
  FitCoursePointType.sharpLeft => TurnKind.sharpLeft,
  FitCoursePointType.sharpRight => TurnKind.sharpRight,
  FitCoursePointType.leftFork => TurnKind.keepLeft,
  FitCoursePointType.rightFork => TurnKind.keepRight,
  FitCoursePointType.uTurn => TurnKind.uTurn,
  _ => null,
};

/// The point of interest kind a FIT course point type stands for.
PoiKind poiKindOf(FitCoursePointType type) => switch (type) {
  FitCoursePointType.water => PoiKind.water,
  FitCoursePointType.food => PoiKind.food,
  FitCoursePointType.danger => PoiKind.danger,
  FitCoursePointType.summit => PoiKind.summit,
  FitCoursePointType.firstAid => PoiKind.firstAid,
  FitCoursePointType.toilet => PoiKind.toilet,
  FitCoursePointType.campsite => PoiKind.campsite,
  _ => PoiKind.generic,
};

/// A plain English word for a manoeuvre, for a cue the author left unnamed.
/// English on purpose: the file is read by a head unit, not by the app's
/// own screens, and a course point name has room for little more.
String turnWord(TurnKind kind) => switch (kind) {
  TurnKind.left => 'Turn left',
  TurnKind.right => 'Turn right',
  TurnKind.slightLeft => 'Slight left',
  TurnKind.slightRight => 'Slight right',
  TurnKind.sharpLeft => 'Sharp left',
  TurnKind.sharpRight => 'Sharp right',
  TurnKind.keepLeft || TurnKind.exitLeft => 'Keep left',
  TurnKind.keepRight || TurnKind.exitRight => 'Keep right',
  TurnKind.uTurn || TurnKind.uTurnLeft || TurnKind.uTurnRight => 'U-turn',
  TurnKind.roundabout || TurnKind.roundaboutLeft => 'Roundabout',
  TurnKind.end => 'Finish',
  _ => 'Continue',
};

/// The manoeuvre as a GPX cue's `sym` and `type`, the words Ride with GPS
/// and Garmin write and the import reads back.
String cueSymbol(TurnKind kind) => switch (kind) {
  TurnKind.left => 'Left',
  TurnKind.right => 'Right',
  TurnKind.slightLeft => 'Slight Left',
  TurnKind.slightRight => 'Slight Right',
  TurnKind.sharpLeft => 'Sharp Left',
  TurnKind.sharpRight => 'Sharp Right',
  TurnKind.keepLeft || TurnKind.exitLeft => 'Left',
  TurnKind.keepRight || TurnKind.exitRight => 'Right',
  TurnKind.uTurn || TurnKind.uTurnLeft || TurnKind.uTurnRight => 'U-Turn',
  TurnKind.end => 'End',
  _ => 'Straight',
};
