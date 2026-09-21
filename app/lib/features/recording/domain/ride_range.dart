import 'package:flutter/foundation.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../../core/geo/climbs.dart';
import '../../../core/geo/ride_analysis.dart';

/// Which table a [RideRange] was picked from.
enum RideRangeSource { split, climb }

/// A stretch of a ride, from [startM] to [endM] along the track, picked from
/// a row of the splits or the climbs table and shaded on the charts.
@immutable
class RideRange {
  /// Creates a range.
  const RideRange({
    required this.startM,
    required this.endM,
    required this.source,
    required this.index,
  });

  /// The stretch of [split]: from where the split started to where it ended,
  /// which for the partial one at the end is short of a whole split.
  RideRange.ofSplit(Split split, {required double splitLengthM})
    : this(
        startM: split.index * splitLengthM,
        endM: split.index * splitLengthM + split.distanceM,
        source: RideRangeSource.split,
        index: split.index,
      );

  /// The stretch of [climb], the [index]th in its table: from its foot to
  /// its top.
  RideRange.ofClimb(RideClimb climb, {required int index})
    : this(
        startM: climb.startM,
        endM: climb.startM + climb.lengthM,
        source: RideRangeSource.climb,
        index: index,
      );

  /// Where the stretch begins, in metres from the start of the ride.
  final double startM;

  /// Where it ends, in metres from the start of the ride.
  final double endM;

  /// Which table the row is in.
  final RideRangeSource source;

  /// The row in that table, counting from zero.
  final int index;

  /// The row selected in the table [source], or `null` for the other table.
  int? selectedIn(RideRangeSource table) => table == source ? index : null;

  @override
  bool operator ==(Object other) =>
      other is RideRange &&
      other.startM == startM &&
      other.endM == endM &&
      other.source == source &&
      other.index == index;

  @override
  int get hashCode => Object.hash(startM, endM, source, index);

  @override
  String toString() =>
      'RideRange(${startM.round()}–${endM.round()} m, ${source.name} $index)';
}

/// The piece of a track between [startM] and [endM] along it.
///
/// [distanceAt] is how far along each of [positions] is, as the analysis
/// measured it, so the piece lands where the charts and the tables say it
/// does. Both ends are interpolated onto the track, so a kilometre split
/// starts and ends on the kilometre rather than at the nearest fix. Empty
/// when the range lies outside the track or the lists disagree.
List<LatLng> trackSlice(
  List<LatLng> positions,
  List<double> distanceAt, {
  required double startM,
  required double endM,
}) {
  if (positions.length < 2 ||
      distanceAt.length != positions.length ||
      endM <= startM) {
    return const <LatLng>[];
  }
  final last = distanceAt.last;
  final from = startM.clamp(0.0, last);
  final to = endM.clamp(0.0, last);
  if (to <= from) return const <LatLng>[];

  final out = <LatLng>[];
  // The fix at or before the start and the one at or after the end, with
  // the boundary points lerped in between them and their neighbours.
  var i = 0;
  while (i < distanceAt.length - 1 && distanceAt[i + 1] <= from) {
    i++;
  }
  out.add(_at(positions, distanceAt, i, from));
  for (var j = i + 1; j < distanceAt.length; j++) {
    if (distanceAt[j] >= to) {
      out.add(_at(positions, distanceAt, j - 1, to));
      break;
    }
    if (distanceAt[j] > from) out.add(positions[j]);
  }
  return out;
}

/// The point [target] metres along the track, which lies between fix
/// [index] and the next; the fix itself when the two share a distance.
LatLng _at(
  List<LatLng> positions,
  List<double> distanceAt,
  int index,
  double target,
) {
  final a = positions[index];
  if (index + 1 >= positions.length) return a;
  final b = positions[index + 1];
  final span = distanceAt[index + 1] - distanceAt[index];
  if (span <= 0) return a;
  final f = ((target - distanceAt[index]) / span).clamp(0.0, 1.0);
  return LatLng(a.lat + (b.lat - a.lat) * f, a.lon + (b.lon - a.lon) * f);
}
