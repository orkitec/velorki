import 'dart:math' as math;

/// When the sun rises and sets on one day at one place, in UTC; `rise` and
/// `set` are both null in a polar night and [allDay] in a midnight sun.
typedef SunDay = ({DateTime? rise, DateTime? set, bool allDay});

/// Sunrise and sunset of the solar day [day] (its date is what counts, read
/// in UTC) at [lat], [lon] degrees, by the sunrise equation with refraction
/// and the sun's radius (−0.833°). Good to a few minutes, which is all a
/// "ride in daylight" needs.
SunDay sunDay(DateTime day, double lat, double lon) {
  const toRad = math.pi / 180;
  final noonUtc = DateTime.utc(day.year, day.month, day.day, 12);
  final julianDay = noonUtc.millisecondsSinceEpoch / 86400000 + 2440587.5;
  final n = (julianDay - 2451545.0 + 0.0008).roundToDouble();
  final meanSolarNoon = n - lon / 360;
  final anomaly = (357.5291 + 0.98560028 * meanSolarNoon) % 360;
  final m = anomaly * toRad;
  final centre =
      1.9148 * math.sin(m) + 0.02 * math.sin(2 * m) + 0.0003 * math.sin(3 * m);
  final longitude = (anomaly + centre + 180 + 102.9372) % 360 * toRad;
  final transit =
      2451545.0 +
      meanSolarNoon +
      0.0053 * math.sin(m) -
      0.0069 * math.sin(2 * longitude);
  final sinDeclination = math.sin(longitude) * math.sin(23.4397 * toRad);
  final cosDeclination = math.cos(math.asin(sinDeclination));
  final phi = lat * toRad;
  final cosHourAngle =
      (math.sin(-0.833 * toRad) - math.sin(phi) * sinDeclination) /
      (math.cos(phi) * cosDeclination);
  if (cosHourAngle > 1) return (rise: null, set: null, allDay: false);
  if (cosHourAngle < -1) return (rise: null, set: null, allDay: true);
  final halfDay = math.acos(cosHourAngle) / toRad / 360;
  DateTime at(double jd) => DateTime.fromMillisecondsSinceEpoch(
    ((jd - 2440587.5) * 86400000).round(),
    isUtc: true,
  );
  return (
    rise: at(transit - halfDay),
    set: at(transit + halfDay),
    allDay: false,
  );
}

/// Whether [start] to [end] lies wholly between one sunrise and its sunset
/// at [lat], [lon]. The day is the local solar day of [start], so a ride far
/// east or west of Greenwich is not judged by the wrong UTC date.
bool inDaylight(DateTime start, DateTime end, double lat, double lon) {
  final solar = start.toUtc().add(Duration(minutes: (lon * 4).round()));
  final sun = sunDay(solar, lat, lon);
  if (sun.allDay) return end.difference(start) < const Duration(hours: 24);
  final rise = sun.rise;
  final set = sun.set;
  if (rise == null || set == null) return false;
  return !start.isBefore(rise) && !end.isAfter(set);
}
