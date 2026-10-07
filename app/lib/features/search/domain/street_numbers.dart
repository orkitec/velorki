/// A street's house numbers as the gazetteer stores them, and where a number
/// on it is.
///
/// `street_numbers.data` (see `tools/gazetteer/README.md`): a version byte,
/// then the odd numbers and then the even ones, each side a count and its
/// points — number, latitude and longitude as varint deltas, the coordinates
/// in 1e-5 degrees. Each side is thinned by the builder so that every
/// address on it lies within 20 m of the line between its neighbours, which
/// is why a number between two points of its own side is good as exact.
library;

import 'dart:typed_data';

import 'package:velorki_geo/velorki_geo.dart';

/// One stored house number.
typedef NumberPoint = ({int number, LatLng position});

/// The two sides of a street.
typedef StreetSides = ({List<NumberPoint> odd, List<NumberPoint> even});

/// The blob format this app reads.
const int streetNumbersVersion = 1;

/// [data] decoded, or `null` when it is not a blob this app can read.
StreetSides? decodeStreetNumbers(Uint8List data) {
  if (data.isEmpty || data[0] != streetNumbersVersion) return null;
  var offset = 1;
  int next() {
    var value = 0;
    var shift = 0;
    while (true) {
      if (offset >= data.length) throw const FormatException('truncated');
      final byte = data[offset++];
      value |= (byte & 0x7f) << shift;
      if (byte < 0x80) return value;
      shift += 7;
      if (shift > 56) throw const FormatException('varint too long');
    }
  }

  int signed() {
    final raw = next();
    return (raw >> 1) ^ -(raw & 1);
  }

  try {
    var lat = 0;
    var lon = 0;
    List<NumberPoint> run() {
      final count = next();
      var number = 0;
      return <NumberPoint>[
        for (var i = 0; i < count; i++)
          (
            number: number += next(),
            position: LatLng((lat += signed()) / 1e5, (lon += signed()) / 1e5),
          ),
      ];
    }

    final odd = run();
    final even = run();
    if (offset != data.length) return null;
    return (odd: odd, even: even);
  } on FormatException {
    return null;
  }
}

/// Where [number] is on a street with [sides], or `null` when the street has
/// no numbers at all.
///
/// The number's own side answers: between two of its points it is
/// interpolated by number and is exact (the builder kept every address within
/// 20 m of that line); past either end it is the nearer end point and
/// approximate. A side with no points borrows the other side, approximate.
({LatLng position, bool approximate})? locateOnStreet(
  StreetSides sides,
  int number,
) {
  final own = number.isOdd ? sides.odd : sides.even;
  final other = number.isOdd ? sides.even : sides.odd;
  final points = own.isNotEmpty ? own : other;
  if (points.isEmpty) return null;
  final borrowed = own.isEmpty;
  if (number <= points.first.number) {
    return (
      position: points.first.position,
      approximate: borrowed || number != points.first.number,
    );
  }
  if (number >= points.last.number) {
    return (
      position: points.last.position,
      approximate: borrowed || number != points.last.number,
    );
  }
  for (var i = 0; i + 1 < points.length; i++) {
    final low = points[i];
    final high = points[i + 1];
    if (number < low.number || number > high.number) continue;
    final t = (number - low.number) / (high.number - low.number);
    return (
      position: LatLng(
        low.position.lat + (high.position.lat - low.position.lat) * t,
        low.position.lon + (high.position.lon - low.position.lon) * t,
      ),
      approximate: borrowed,
    );
  }
  return null;
}
