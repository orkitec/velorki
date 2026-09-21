/// The stretch of road a grade is measured over: a hundred metres, long
/// enough that the heights at either end are not the same GPS wobble.
const double climbWindowM = 100;

/// Below this grade the road is not a climb worth a figure.
const double climbGradeMinPercent = 3;

/// How far the road has to drop from its high point for the climb to count
/// as over: a dip in a long climb is not the top.
const double climbEndDropM = 10;

/// The shortest rise the ride page lists as a climb, in metres of road.
const double climbMinLengthM = 300;

/// The least a rise has to gain, in metres, to be listed as a climb.
const double climbMinAscentM = 20;

/// How far below the high point the top may be: the first fix within this of
/// the highest is the top, since the last half metre of a smoothed GPS climb
/// is the receiver's, not the road's, and would otherwise stretch a climb
/// across the whole plateau after it.
const double climbTopSlackM = 0.5;

/// One accepted step of a ride as the climb detection needs it: how far along
/// the track it went, how high, how long it took, and what the sensors read at
/// its start.
///
/// The heights are whatever the caller smoothed them to; the detection reads
/// them as they are. A [isBreak] step was not ridden: it moves the track
/// neither forward nor upward, and its time counts nowhere.
class ClimbLeg {
  /// Creates the step.
  const ClimbLeg({
    required this.fromM,
    required this.toM,
    required this.fromEle,
    required this.toEle,
    required this.duration,
    required this.moving,
    required this.isBreak,
    this.heartRateBpm,
    this.powerW,
  });

  /// Distance from the start of the track at the step's start, in metres.
  final double fromM;

  /// Distance from the start of the track at the step's end, in metres; the
  /// same as [fromM] across a break.
  final double toM;

  /// Height at the step's start, or `null` where the fix carried none.
  final double? fromEle;

  /// Height at the step's end, or `null` where the fix carried none.
  final double? toEle;

  /// How long the step took.
  final Duration duration;

  /// Whether the rider was moving over the step.
  final bool moving;

  /// Whether the step crosses a pause.
  final bool isBreak;

  /// The heart rate at the step's start, if a sensor reported one.
  final int? heartRateBpm;

  /// The power at the step's start, if a meter reported one.
  final int? powerW;
}

/// One climb of a ride: where it started, how long and how steep it was, and
/// how fast it was ridden.
class RideClimb {
  /// Creates a climb.
  const RideClimb({
    required this.startM,
    required this.lengthM,
    required this.ascentM,
    required this.maxGradePercent,
    required this.movingTime,
    this.avgHeartRateBpm,
    this.avgPowerW,
  });

  /// Distance from the start of the track to the foot of the climb, in metres.
  final double startM;

  /// Metres of road from the foot to the top.
  final double lengthM;

  /// Metres gained over the ridden road from the foot to the top.
  final double ascentM;

  /// The steepest [climbWindowM] of the climb, in percent.
  final double maxGradePercent;

  /// Time spent moving between the foot and the top.
  final Duration movingTime;

  /// The mean heart rate over the climb's moving legs, weighted by their
  /// time; `null` without a reading.
  final int? avgHeartRateBpm;

  /// The mean power over the climb's moving legs, weighted by their time;
  /// `null` without a reading.
  final int? avgPowerW;

  /// Ascent over length, in percent.
  double get avgGradePercent => lengthM <= 0 ? 0 : ascentM / lengthM * 100;

  /// Metres climbed per hour of moving time, the customary measure of how
  /// fast a climb was ridden; zero while nothing moved.
  double get vamMPerHour {
    final hours = movingTime.inMicroseconds / Duration.microsecondsPerHour;
    return hours <= 0 ? 0 : ascentM / hours;
  }

  @override
  String toString() =>
      'RideClimb(at ${startM.round()} m, ${lengthM.round()} m, '
      '+${ascentM.round()} m, ${avgGradePercent.toStringAsFixed(1)} %, '
      '$movingTime)';
}

/// Finds the climbs in [legs], the accepted steps of a ride in riding order.
///
/// The rule is the one the record sheet's profile applies to the road ahead:
/// a climb starts where the next [climbWindowM] of road rise by at least
/// [climbGradeMinPercent], and it ends at its high point once the road has
/// dropped more than [climbEndDropM] below it, so a dip in a long climb does
/// not cut it in two. Rises shorter than [climbMinLengthM] or gaining less
/// than [climbMinAscentM] are not listed, and neither is a stretch that
/// averages under [climbGradeMinPercent] from foot to top, which is what two
/// bumps with a long flat between them would otherwise add up to.
///
/// Heights are read as gained over ridden road: the step across a pause
/// contributes nothing, and a fix without a height is taken at the height of
/// the one before it.
List<RideClimb> detectClimbs(List<ClimbLeg> legs) {
  if (legs.isEmpty) return const <RideClimb>[];
  // Fix k is the start of leg k, and the end of leg k - 1; the last fix is
  // the end of the last leg.
  final fixes = legs.length + 1;
  final distanceAt = List<double>.filled(fixes, 0);
  final heightAt = List<double>.filled(fixes, 0);
  distanceAt[0] = legs.first.fromM;
  for (var k = 0; k < legs.length; k++) {
    final leg = legs[k];
    distanceAt[k + 1] = leg.toM;
    final from = leg.fromEle;
    final to = leg.toEle;
    final delta = leg.isBreak || from == null || to == null ? 0.0 : to - from;
    heightAt[k + 1] = heightAt[k] + delta;
  }

  final climbs = <RideClimb>[];
  var i = 0;
  while (i < fixes) {
    // The grade over the next window of road; no window left, no climb left.
    var m = i;
    while (m < fixes && distanceAt[m] - distanceAt[i] < climbWindowM) {
      m++;
    }
    if (m >= fixes) break;
    final rise = heightAt[m] - heightAt[i];
    if (rise / (distanceAt[m] - distanceAt[i]) * 100 < climbGradeMinPercent) {
      i++;
      continue;
    }
    // The climb runs to its high point, found once the road has fallen away
    // from it by more than the drop, or at the end of the track.
    var high = i;
    for (var j = i + 1; j < fixes; j++) {
      if (heightAt[j] > heightAt[high]) high = j;
      if (heightAt[high] - heightAt[j] > climbEndDropM) break;
    }
    var top = i;
    while (heightAt[top] < heightAt[high] - climbTopSlackM) {
      top++;
    }
    final lengthM = distanceAt[top] - distanceAt[i];
    final ascentM = heightAt[top] - heightAt[i];
    if (lengthM >= climbMinLengthM &&
        ascentM >= climbMinAscentM &&
        ascentM / lengthM * 100 >= climbGradeMinPercent) {
      climbs.add(_climb(legs, distanceAt, heightAt, i, top));
    }
    i = high + 1;
  }
  return List<RideClimb>.unmodifiable(climbs);
}

RideClimb _climb(
  List<ClimbLeg> legs,
  List<double> distanceAt,
  List<double> heightAt,
  int foot,
  int top,
) {
  var movingMicros = 0;
  var heartRateMicros = 0;
  var beatSeconds = 0.0;
  var powerMicros = 0;
  var wattSeconds = 0.0;
  for (var k = foot; k < top; k++) {
    final leg = legs[k];
    if (leg.isBreak || !leg.moving) continue;
    final micros = leg.duration.inMicroseconds;
    final seconds = micros / Duration.microsecondsPerSecond;
    movingMicros += micros;
    final bpm = leg.heartRateBpm;
    if (bpm != null) {
      heartRateMicros += micros;
      beatSeconds += bpm * seconds;
    }
    final watts = leg.powerW;
    if (watts != null) {
      powerMicros += micros;
      wattSeconds += watts * seconds;
    }
  }

  // The steepest window: from every fix of the climb to the first one a
  // window further on, as long as that is still on the climb.
  var maxGrade = double.negativeInfinity;
  var b = foot;
  for (var a = foot; a < top; a++) {
    while (b <= top && distanceAt[b] - distanceAt[a] < climbWindowM) {
      b++;
    }
    if (b > top) break;
    final run = distanceAt[b] - distanceAt[a];
    final grade = (heightAt[b] - heightAt[a]) / run * 100;
    if (grade > maxGrade) maxGrade = grade;
  }
  final lengthM = distanceAt[top] - distanceAt[foot];
  final ascentM = heightAt[top] - heightAt[foot];
  if (maxGrade == double.negativeInfinity) {
    maxGrade = lengthM <= 0 ? 0 : ascentM / lengthM * 100;
  }

  return RideClimb(
    startM: distanceAt[foot],
    lengthM: lengthM,
    ascentM: ascentM,
    maxGradePercent: maxGrade,
    movingTime: Duration(microseconds: movingMicros),
    avgHeartRateBpm: heartRateMicros <= 0
        ? null
        : (beatSeconds / (heartRateMicros / Duration.microsecondsPerSecond))
              .round(),
    avgPowerW: powerMicros <= 0
        ? null
        : (wattSeconds / (powerMicros / Duration.microsecondsPerSecond))
              .round(),
  );
}
