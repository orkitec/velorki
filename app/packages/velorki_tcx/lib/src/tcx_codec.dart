import 'package:velorki_geo/velorki_geo.dart';
import 'package:xml/xml.dart';

import 'tcx_format_exception.dart';
import 'tcx_models.dart';

/// The TCX namespace, the root's default one.
const String tcxNamespace =
    'http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2';

/// The activity extension namespace, where speed and power live.
const String activityExtensionNamespace =
    'http://www.garmin.com/xmlschemas/ActivityExtension/v2';

/// Reads and writes TCX activities and courses.
///
/// All methods are static; the class is a namespace, not a value. Elements
/// are matched by local name whatever prefix a file uses, since Garmin
/// writes `ns3:` for the extensions and others write `x:` or none.
class TcxCodec {
  const TcxCodec._();

  /// Decodes a TCX document: its activities with laps, heart rate, cadence
  /// and power, and its courses with their course points.
  ///
  /// Throws [TcxFormatException] when [xml] is not a TCX document.
  static TcxDocument decode(String xml) {
    if (xml.trim().isEmpty) {
      throw const TcxFormatException('the input is empty');
    }
    final XmlDocument document;
    try {
      document = XmlDocument.parse(xml);
    } on XmlException catch (e) {
      throw TcxFormatException('the file is not well-formed XML', e);
    }
    final root = document.rootElement;
    if (root.name.local != 'TrainingCenterDatabase') {
      throw TcxFormatException(
        'the root element is <${root.name.qualified}>, not '
        '<TrainingCenterDatabase>',
      );
    }
    try {
      return TcxDocument(
        activities: [
          for (final activities in _children(root, 'Activities'))
            for (final activity in _children(activities, 'Activity'))
              _activity(activity),
        ],
        courses: [
          for (final courses in _children(root, 'Courses'))
            for (final course in _children(courses, 'Course')) _course(course),
        ],
        author: _text(_child(_child(root, 'Author'), 'Name')),
      );
    } on FormatException catch (e) {
      throw TcxFormatException(
        'the file contains a malformed number or timestamp',
        e,
      );
    }
  }

  static TcxActivity _activity(XmlElement activity) {
    final creator = _text(_child(_child(activity, 'Creator'), 'Name'));
    return TcxActivity(
      sport: switch (activity.getAttribute('Sport')) {
        'Biking' => TcxSport.biking,
        'Running' => TcxSport.running,
        _ => TcxSport.other,
      },
      id: _time(_text(_child(activity, 'Id'))),
      creator: creator,
      laps: [for (final lap in _children(activity, 'Lap')) _lap(lap)],
    );
  }

  static TcxLap _lap(XmlElement lap) {
    final lx = _descendant(_child(lap, 'Extensions'), 'LX');
    return TcxLap(
      startTime:
          _time(lap.getAttribute('StartTime')) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      points: [
        for (final track in _children(lap, 'Track'))
          for (final point in _children(track, 'Trackpoint'))
            ?_trackPoint(point),
      ],
      totalTimeS: _double(_text(_child(lap, 'TotalTimeSeconds'))),
      distanceM: _double(_text(_child(lap, 'DistanceMeters'))),
      calories: _int(_text(_child(lap, 'Calories'))),
      avgHeartRate: _int(
        _text(_child(_child(lap, 'AverageHeartRateBpm'), 'Value')),
      ),
      maxHeartRate: _int(
        _text(_child(_child(lap, 'MaximumHeartRateBpm'), 'Value')),
      ),
      avgCadence: _int(_text(_child(lap, 'Cadence'))),
      avgWatts: _int(_text(_child(lx, 'AvgWatts'))),
      maxWatts: _int(_text(_child(lx, 'MaxWatts'))),
      maxSpeedMps: _double(_text(_child(lap, 'MaximumSpeed'))),
    );
  }

  /// A track point with a position; one without is not on the map and is
  /// left out, as the FIT decoder leaves out records without one.
  static TrackPoint? _trackPoint(XmlElement point) {
    final position = _child(point, 'Position');
    final lat = _double(_text(_child(position, 'LatitudeDegrees')));
    final lon = _double(_text(_child(position, 'LongitudeDegrees')));
    if (lat == null || lon == null) return null;
    final tpx = _descendant(_child(point, 'Extensions'), 'TPX');
    return TrackPoint(
      LatLng(lat, lon),
      ele: _double(_text(_child(point, 'AltitudeMeters'))),
      time: _time(_text(_child(point, 'Time'))),
      speedMps: _double(_text(_child(tpx, 'Speed'))),
      heartRateBpm: _int(_text(_child(_child(point, 'HeartRateBpm'), 'Value'))),
      cadenceRpm:
          _int(_text(_child(point, 'Cadence'))) ??
          _int(_text(_child(tpx, 'RunCadence'))),
      powerW: _int(_text(_child(tpx, 'Watts'))),
    );
  }

  static TcxCourse _course(XmlElement course) {
    final points = <TrackPoint>[
      for (final track in _children(course, 'Track'))
        for (final point in _children(track, 'Trackpoint')) ?_trackPoint(point),
    ];
    return TcxCourse(
      name: _text(_child(course, 'Name')),
      points: points,
      distanceM: _double(
        _text(_child(_child(course, 'Lap'), 'DistanceMeters')),
      ),
      coursePoints: [
        for (final cp in _children(course, 'CoursePoint')) ?_coursePoint(cp),
      ],
    );
  }

  static TcxCoursePoint? _coursePoint(XmlElement cp) {
    final position = _child(cp, 'Position');
    final lat = _double(_text(_child(position, 'LatitudeDegrees')));
    final lon = _double(_text(_child(position, 'LongitudeDegrees')));
    final time = _time(_text(_child(cp, 'Time')));
    if (lat == null || lon == null || time == null) return null;
    return TcxCoursePoint(
      pos: LatLng(lat, lon),
      time: time,
      name: _text(_child(cp, 'Name')),
      type: TcxCoursePointType.fromXml(_text(_child(cp, 'PointType'))),
      notes: _text(_child(cp, 'Notes')),
    );
  }

  // --- encoding -----------------------------------------------------------

  /// Encodes [laps] as one `<Activity>` of [sport], with heart rate,
  /// cadence and power on the points that carry them and the lap's own
  /// totals where they were given.
  ///
  /// Throws [ArgumentError] when there is no lap or no point.
  static String encodeActivity({
    required List<TcxLap> laps,
    TcxSport sport = TcxSport.biking,
    String creator = 'Velorki',
  }) {
    if (laps.isEmpty || laps.every((l) => l.points.isEmpty)) {
      throw ArgumentError.value(laps, 'laps', 'nothing to encode');
    }
    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element(
      'TrainingCenterDatabase',
      namespaceUris: {null: tcxNamespace},
      attributes: {
        'xmlns:xsi': 'http://www.w3.org/2001/XMLSchema-instance',
        'xsi:schemaLocation':
            '$tcxNamespace '
            'http://www.garmin.com/xmlschemas/TrainingCenterDatabasev2.xsd',
      },
      nest: () {
        builder.element(
          'Activities',
          nest: () {
            builder.element(
              'Activity',
              attributes: {
                'Sport': switch (sport) {
                  TcxSport.biking => 'Biking',
                  TcxSport.running => 'Running',
                  TcxSport.other => 'Other',
                },
              },
              nest: () {
                builder.element('Id', nest: _iso(laps.first.startTime));
                var along = 0.0;
                for (final lap in laps) {
                  along = _writeLap(builder, lap, along);
                }
                _creator(builder, creator);
              },
            );
          },
        );
        _author(builder, creator);
      },
    );
    return builder.buildDocument().toXmlString(pretty: true, indent: '  ');
  }

  /// Writes [lap], its points' distance counted on from [along]; returns
  /// where the lap ended.
  static double _writeLap(XmlBuilder builder, TcxLap lap, double along) {
    final points = lap.points;
    final distances = cumulativeDistancesMeters(
      points.map((p) => p.pos).toList(growable: false),
    );
    final lapDistance =
        lap.distanceM ?? (distances.isEmpty ? 0 : distances.last);
    final totalTime =
        lap.totalTimeS ??
        (points.length >= 2 &&
                points.first.time != null &&
                points.last.time != null
            ? points.last.time!.difference(points.first.time!).inMilliseconds /
                  1000
            : 0.0);
    builder.element(
      'Lap',
      attributes: {'StartTime': _iso(lap.startTime)},
      nest: () {
        builder.element('TotalTimeSeconds', nest: _number(totalTime));
        builder.element('DistanceMeters', nest: _number(lapDistance));
        final maxSpeed =
            lap.maxSpeedMps ??
            points
                .map((p) => p.speedMps)
                .nonNulls
                .fold<double?>(null, (m, s) => m == null || s > m ? s : m);
        if (maxSpeed != null) {
          builder.element('MaximumSpeed', nest: _number(maxSpeed));
        }
        builder.element('Calories', nest: '${lap.calories ?? 0}');
        final rates = points.map((p) => p.heartRateBpm).nonNulls.toList();
        final avgHr =
            lap.avgHeartRate ??
            (rates.isEmpty
                ? null
                : (rates.reduce((a, b) => a + b) / rates.length).round());
        final maxHr =
            lap.maxHeartRate ??
            (rates.isEmpty ? null : rates.reduce((a, b) => a > b ? a : b));
        if (avgHr != null) {
          builder.element(
            'AverageHeartRateBpm',
            nest: () => builder.element('Value', nest: '$avgHr'),
          );
        }
        if (maxHr != null) {
          builder.element(
            'MaximumHeartRateBpm',
            nest: () => builder.element('Value', nest: '$maxHr'),
          );
        }
        builder.element('Intensity', nest: 'Active');
        final cadences = points.map((p) => p.cadenceRpm).nonNulls.toList();
        final avgCadence =
            lap.avgCadence ??
            (cadences.isEmpty
                ? null
                : (cadences.reduce((a, b) => a + b) / cadences.length).round());
        if (avgCadence != null) {
          builder.element('Cadence', nest: '$avgCadence');
        }
        builder.element('TriggerMethod', nest: 'Manual');
        builder.element(
          'Track',
          nest: () {
            for (var i = 0; i < points.length; i++) {
              _writeTrackPoint(builder, points[i], along + distances[i]);
            }
          },
        );
        final watts = points.map((p) => p.powerW).nonNulls.toList();
        final avgWatts =
            lap.avgWatts ??
            (watts.isEmpty
                ? null
                : (watts.reduce((a, b) => a + b) / watts.length).round());
        final maxWatts =
            lap.maxWatts ??
            (watts.isEmpty ? null : watts.reduce((a, b) => a > b ? a : b));
        if (avgWatts != null || maxWatts != null) {
          builder.element(
            'Extensions',
            nest: () => builder.element(
              'LX',
              namespaceUris: {null: activityExtensionNamespace},
              nest: () {
                if (avgWatts != null) {
                  builder.element('AvgWatts', nest: '$avgWatts');
                }
                if (maxWatts != null) {
                  builder.element('MaxWatts', nest: '$maxWatts');
                }
              },
            ),
          );
        }
      },
    );
    return along + lapDistance;
  }

  static void _writeTrackPoint(
    XmlBuilder builder,
    TrackPoint point,
    double distanceM, {
    DateTime? time,
  }) {
    builder.element(
      'Trackpoint',
      nest: () {
        final when = time ?? point.time;
        if (when != null) builder.element('Time', nest: _iso(when));
        builder.element(
          'Position',
          nest: () {
            builder.element('LatitudeDegrees', nest: _number(point.lat));
            builder.element('LongitudeDegrees', nest: _number(point.lon));
          },
        );
        if (point.ele != null) {
          builder.element('AltitudeMeters', nest: _number(point.ele!));
        }
        builder.element('DistanceMeters', nest: _number(distanceM));
        if (point.heartRateBpm != null) {
          builder.element(
            'HeartRateBpm',
            nest: () => builder.element('Value', nest: '${point.heartRateBpm}'),
          );
        }
        if (point.cadenceRpm != null) {
          builder.element('Cadence', nest: '${point.cadenceRpm}');
        }
        if (point.speedMps != null || point.powerW != null) {
          builder.element(
            'Extensions',
            nest: () => builder.element(
              'TPX',
              namespaceUris: {null: activityExtensionNamespace},
              nest: () {
                if (point.speedMps != null) {
                  builder.element('Speed', nest: _number(point.speedMps!));
                }
                if (point.powerW != null) {
                  builder.element('Watts', nest: '${point.powerW}');
                }
              },
            ),
          );
        }
      },
    );
  }

  /// Encodes [points] as one `<Course>` named [name], with [coursePoints]
  /// as its cues. Points without a time get one a second apart from
  /// [startTime] (else the first point's time, else now), since a course
  /// point finds its track point by time.
  ///
  /// Throws [ArgumentError] when [points] is empty or [name] is blank.
  static String encodeCourse({
    required String name,
    required List<TrackPoint> points,
    List<TcxCoursePoint> coursePoints = const <TcxCoursePoint>[],
    String creator = 'Velorki',
    DateTime? startTime,
  }) {
    if (points.isEmpty) {
      throw ArgumentError.value(points, 'points', 'nothing to encode');
    }
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'course name must not be blank');
    }
    final base =
        (startTime ??
                points
                    .firstWhere(
                      (p) => p.time != null,
                      orElse: () => points.first,
                    )
                    .time ??
                DateTime.now())
            .toUtc();
    final times = [
      for (var i = 0; i < points.length; i++)
        points[i].time?.toUtc() ?? base.add(Duration(seconds: i)),
    ];
    final distances = cumulativeDistancesMeters(
      points.map((p) => p.pos).toList(growable: false),
    );
    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element(
      'TrainingCenterDatabase',
      namespaceUris: {null: tcxNamespace},
      attributes: {
        'xmlns:xsi': 'http://www.w3.org/2001/XMLSchema-instance',
        'xsi:schemaLocation':
            '$tcxNamespace '
            'http://www.garmin.com/xmlschemas/TrainingCenterDatabasev2.xsd',
      },
      nest: () {
        builder.element(
          'Courses',
          nest: () => builder.element(
            'Course',
            nest: () {
              builder.element('Name', nest: _courseName(name));
              builder.element(
                'Lap',
                nest: () {
                  builder.element(
                    'TotalTimeSeconds',
                    nest: _number(
                      times.last.difference(times.first).inMilliseconds / 1000,
                    ),
                  );
                  builder.element(
                    'DistanceMeters',
                    nest: _number(distances.last),
                  );
                  builder.element(
                    'BeginPosition',
                    nest: () {
                      builder.element(
                        'LatitudeDegrees',
                        nest: _number(points.first.lat),
                      );
                      builder.element(
                        'LongitudeDegrees',
                        nest: _number(points.first.lon),
                      );
                    },
                  );
                  builder.element(
                    'EndPosition',
                    nest: () {
                      builder.element(
                        'LatitudeDegrees',
                        nest: _number(points.last.lat),
                      );
                      builder.element(
                        'LongitudeDegrees',
                        nest: _number(points.last.lon),
                      );
                    },
                  );
                  builder.element('Intensity', nest: 'Active');
                },
              );
              builder.element(
                'Track',
                nest: () {
                  for (var i = 0; i < points.length; i++) {
                    _writeTrackPoint(
                      builder,
                      points[i],
                      distances[i],
                      time: times[i],
                    );
                  }
                },
              );
              for (final cp in coursePoints) {
                final at = _nearestIndex(points, cp.pos);
                builder.element(
                  'CoursePoint',
                  nest: () {
                    builder.element(
                      'Name',
                      nest: _coursePointName(cp.name ?? cp.type.xmlValue),
                    );
                    builder.element('Time', nest: _iso(times[at]));
                    builder.element(
                      'Position',
                      nest: () {
                        builder.element(
                          'LatitudeDegrees',
                          nest: _number(points[at].lat),
                        );
                        builder.element(
                          'LongitudeDegrees',
                          nest: _number(points[at].lon),
                        );
                      },
                    );
                    builder.element('PointType', nest: cp.type.xmlValue);
                    if (cp.notes != null && cp.notes!.trim().isNotEmpty) {
                      builder.element('Notes', nest: cp.notes!.trim());
                    }
                  },
                );
              }
            },
          ),
        );
        _author(builder, creator);
      },
    );
    return builder.buildDocument().toXmlString(pretty: true, indent: '  ');
  }

  static void _creator(XmlBuilder builder, String creator) {
    builder.element(
      'Creator',
      attributes: {'xsi:type': 'Device_t'},
      nest: () {
        builder.element('Name', nest: creator);
        builder.element('UnitId', nest: '0');
        builder.element('ProductID', nest: '0');
        _version(builder);
      },
    );
  }

  static void _author(XmlBuilder builder, String creator) {
    builder.element(
      'Author',
      attributes: {'xsi:type': 'Application_t'},
      nest: () {
        builder.element('Name', nest: creator);
        builder.element('Build', nest: () => _version(builder));
        builder.element('LangID', nest: 'en');
        builder.element('PartNumber', nest: '000-00000-00');
      },
    );
  }

  static void _version(XmlBuilder builder) {
    builder.element(
      'Version',
      nest: () {
        builder.element('VersionMajor', nest: '1');
        builder.element('VersionMinor', nest: '0');
        builder.element('BuildMajor', nest: '0');
        builder.element('BuildMinor', nest: '0');
      },
    );
  }

  /// A course name as the schema allows: at most 15 characters.
  static String _courseName(String name) {
    final trimmed = name.trim();
    return trimmed.length <= 15 ? trimmed : trimmed.substring(0, 15);
  }

  /// A course point name as the schema allows: at most 10 characters.
  static String _coursePointName(String name) {
    final trimmed = name.trim();
    return trimmed.length <= 10 ? trimmed : trimmed.substring(0, 10);
  }

  static int _nearestIndex(List<TrackPoint> points, LatLng pos) {
    var best = 0;
    var bestD = double.infinity;
    for (var i = 0; i < points.length; i++) {
      final d = haversineMeters(points[i].pos, pos);
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  // --- helpers ------------------------------------------------------------

  static Iterable<XmlElement> _children(XmlElement? parent, String local) =>
      parent == null
      ? const <XmlElement>[]
      : parent.childElements.where((e) => e.name.local == local);

  static XmlElement? _child(XmlElement? parent, String local) =>
      _children(parent, local).firstOrNull;

  static XmlElement? _descendant(XmlElement? parent, String local) => parent
      ?.descendantElements
      .where((e) => e.name.local == local)
      .firstOrNull;

  static String? _text(XmlElement? element) {
    final text = element?.innerText.trim();
    return text == null || text.isEmpty ? null : text;
  }

  static double? _double(String? text) =>
      text == null ? null : double.parse(text);

  static int? _int(String? text) =>
      text == null ? null : double.parse(text).round();

  static DateTime? _time(String? text) {
    if (text == null) return null;
    final parsed = DateTime.tryParse(text);
    if (parsed == null) throw FormatException('not a timestamp: $text');
    return parsed.toUtc();
  }

  static String _iso(DateTime time) {
    final utc = time.toUtc();
    final ms = utc.millisecond;
    final base = utc.toIso8601String();
    // Whole seconds, the way the files in the wild are written.
    return ms == 0 ? base : '${base.substring(0, 19)}Z';
  }

  static String _number(double value) =>
      value == value.roundToDouble() ? '${value.round()}' : '$value';
}
