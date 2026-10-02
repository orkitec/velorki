import 'package:flutter/foundation.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';
import 'package:velorki_loops/velorki_loops.dart';

/// Radius of one circle of an avoided stretch, in metres: the road itself,
/// not the parallel street one block over.
const double avoidRadiusM = 50;

/// Distance between two circles along an avoided stretch, in metres, so
/// neighbouring circles overlap on the road between them.
const double avoidSpacingM = 80;

/// Cost weight of an avoided stretch.
///
/// BRouter adds `distance within the circle * weight` to the cost of a way,
/// where a good road costs about its own length: at 5 the stretch costs some
/// six times what it did, so the router takes a fair detour around it, but
/// where there is no other way it still goes through rather than failing.
const double avoidWeight = 5;

/// The most circles one avoided stretch is drawn with; a longer stretch gets
/// them further apart. They travel in a server query's URL.
const int avoidMaxCircles = 60;

/// A stretch of a route the rider asked the router to keep off.
///
/// Kept as the piece of line it was cut from, which is what the map draws,
/// and turned into weighted no-go circles along it for every routing query
/// while it is part of the plan.
@immutable
class AvoidArea {
  /// Creates an area along [line], from [fromKm] to [toKm] of the route it
  /// was cut from.
  AvoidArea({required this.line, required this.fromKm, required this.toKm})
    : nogos = nogosAlong(
        line,
        sampleEveryM: avoidSpacingM,
        skipEndsM: 0,
        radiusM: avoidRadiusM,
        weight: avoidWeight,
        maxNogos: avoidMaxCircles,
      );

  /// The piece of the route to keep off, in riding order.
  final List<LatLng> line;

  /// Where it started on the route it was cut from, in kilometres.
  final double fromKm;

  /// Where it ended, in kilometres.
  final double toKm;

  /// The circles the router is asked to keep off.
  final List<NoGo> nogos;

  /// The piece of [track] from [fromM] to [toM] metres along it, the ends
  /// interpolated; empty when the range does not lie on the track.
  static List<LatLng> cut(List<LatLng> track, double fromM, double toM) {
    if (track.length < 2 || toM <= fromM) return const <LatLng>[];
    final along = cumulativeDistancesMeters(track);
    final total = along.last;
    final from = fromM.clamp(0, total).toDouble();
    final to = toM.clamp(0, total).toDouble();
    if (to <= from) return const <LatLng>[];
    LatLng at(double d) {
      var i = 1;
      while (i < along.length - 1 && along[i] < d) {
        i++;
      }
      final span = along[i] - along[i - 1];
      final t = span <= 0 ? 0.0 : ((d - along[i - 1]) / span).clamp(0.0, 1.0);
      final a = track[i - 1];
      final b = track[i];
      return LatLng(a.lat + (b.lat - a.lat) * t, a.lon + (b.lon - a.lon) * t);
    }

    return <LatLng>[
      at(from),
      for (var i = 0; i < track.length; i++)
        if (along[i] > from && along[i] < to) track[i],
      at(to),
    ];
  }
}
