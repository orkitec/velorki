import 'dart:convert';
import 'dart:typed_data';

import 'package:fit_sdk/fit_sdk.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'fit_format_exception.dart';
import 'fit_models.dart';
import 'fit_sniffer.dart';
import 'fit_sport.dart';

/// Seconds between the Unix epoch (1970-01-01T00:00:00Z) and the FIT epoch
/// (1989-12-31T00:00:00Z).
const int fitEpochOffsetSeconds = 631065600;

/// Degrees per FIT semicircle: `180 / 2^31`.
const double degreesPerSemicircle = 180.0 / 2147483648.0;

/// Semicircles per degree: `2^31 / 180`.
const double semicirclesPerDegree = 2147483648.0 / 180.0;

// ---------------------------------------------------------------------------
// FIT field numbers used below. Named so the encoder reads like the profile.
// ---------------------------------------------------------------------------

const int _fMessageIndex = 254;
const int _fTimestamp = 253;

// file_id
const int _fFileIdType = 0;
const int _fFileIdManufacturer = 1;
const int _fFileIdProduct = 2;
const int _fFileIdSerialNumber = 3;
const int _fFileIdTimeCreated = 4;

// sport
const int _fSportSport = 0;
const int _fSportSubSport = 1;
const int _fSportName = 3;

// event
const int _fEventEvent = 0;
const int _fEventType = 1;

// record
const int _fRecordPositionLat = 0;
const int _fRecordPositionLong = 1;
const int _fRecordAltitude = 2;
const int _fRecordHeartRate = 3;
const int _fRecordCadence = 4;
const int _fRecordDistance = 5;
const int _fRecordSpeed = 6;
const int _fRecordPower = 7;
const int _fRecordEnhancedSpeed = 73;
const int _fRecordEnhancedAltitude = 78;

// lap
const int _fLapEvent = 0;
const int _fLapEventType = 1;
const int _fLapStartTime = 2;
const int _fLapStartPositionLat = 3;
const int _fLapStartPositionLong = 4;
const int _fLapEndPositionLat = 5;
const int _fLapEndPositionLong = 6;
const int _fLapTotalElapsedTime = 7;
const int _fLapTotalTimerTime = 8;
const int _fLapTotalDistance = 9;
const int _fLapAvgSpeed = 13;
const int _fLapAvgHeartRate = 15;
const int _fLapMaxHeartRate = 16;
const int _fLapAvgCadence = 17;
const int _fLapAvgPower = 19;
const int _fLapMaxPower = 20;
const int _fLapSport = 25;

// session
const int _fSessionEvent = 0;
const int _fSessionEventType = 1;
const int _fSessionStartTime = 2;
const int _fSessionStartPositionLat = 3;
const int _fSessionStartPositionLong = 4;
const int _fSessionSport = 5;
const int _fSessionSubSport = 6;
const int _fSessionTotalElapsedTime = 7;
const int _fSessionTotalTimerTime = 8;
const int _fSessionTotalDistance = 9;
const int _fSessionAvgSpeed = 14;
const int _fSessionAvgHeartRate = 16;
const int _fSessionMaxHeartRate = 17;
const int _fSessionAvgCadence = 18;
const int _fSessionAvgPower = 20;
const int _fSessionMaxPower = 21;
const int _fSessionFirstLapIndex = 25;
const int _fSessionNumLaps = 26;
const int _fSessionTrigger = 28;

// activity
const int _fActivityTotalTimerTime = 0;
const int _fActivityNumSessions = 1;
const int _fActivityType = 2;
const int _fActivityEvent = 3;
const int _fActivityEventType = 4;

// course
const int _fCourseSport = 4;
const int _fCourseName = 5;

// Local message numbers. Each message type gets its own slot so definitions
// never have to be repeated.
const int _lnFileId = 0;
const int _lnMeta = 1; // sport / course
const int _lnEvent = 2;
const int _lnRecord = 3;
const int _lnLap = 4;
const int _lnSession = 5;
const int _lnActivity = 6;

// Representable ranges of the scaled integer fields we write.
const int _uint8Max = 254; // 255 is the "invalid" sentinel
const int _uint16Max = 65534; // 65535 is the "invalid" sentinel
const int _uint32Max = 4294967294; // 4294967295 is the "invalid" sentinel
const int _sint32PositionMax = 2147483646; // 2147483647 is "invalid"
const int _sint32PositionMin = -2147483648;

/// Longest UTF-8 byte length written for a course or activity name.
const int _maxNameBytes = 64;

/// Reads and writes Garmin FIT activity and course files as lists of
/// [TrackPoint]s.
///
/// All methods are static; the class is a namespace, not a value.
class FitCodec {
  const FitCodec._();

  /// Decodes the `record` messages of the FIT file in [bytes] into track
  /// points, in file order.
  ///
  /// Positions are converted from FIT semicircles to degrees. Elevation comes
  /// from the `altitude` field, falling back to `enhanced_altitude`; speed
  /// comes from `speed`, falling back to `enhanced_speed`; heart rate, cadence
  /// and power come from the record fields of those names; the timestamp is
  /// the FIT `date_time` converted to a UTC [DateTime]. Records without a
  /// position are skipped, because a track point without coordinates carries
  /// no information for this package. A valid FIT file that contains no
  /// `record` messages at all decodes to an empty list.
  ///
  /// Throws [FitFormatException] if [bytes] is not a FIT file, if the CRC does
  /// not match, or if the decoder fails anywhere else. No exception from the
  /// underlying `fit_sdk` is allowed to escape.
  static List<TrackPoint> decodeActivity(Uint8List bytes) {
    if (!looksLikeFit(bytes)) {
      throw const FitFormatException(
        'Not a FIT file: missing ".FIT" signature or bad header size',
      );
    }

    final points = <TrackPoint>[];
    final decoder = Decode();
    decoder.onMesg = (Mesg mesg) {
      if (mesg.num != MesgNum.record) return;
      final point = _recordToTrackPoint(mesg);
      if (point != null) points.add(point);
    };

    try {
      decoder.read(bytes);
    } on FitException catch (e) {
      throw FitFormatException(
        'FIT file could not be decoded: ${e.message}',
        e,
      );
    } catch (e) {
      throw FitFormatException('FIT file could not be decoded', e);
    }
    return points;
  }

  /// Encodes [points] as a FIT *activity* file.
  ///
  /// The file contains `file_id` (type `activity`), an optional `sport`
  /// message carrying [name], timer start/stop `event` messages, one `record`
  /// per point, and the `lap`, `session` and `activity` messages a Garmin
  /// activity file needs. Total distance is the great circle length of the
  /// track; total elapsed and timer time are taken from the point timestamps.
  /// A track that carries heart rate, cadence or power writes those record
  /// fields too, and the `lap` and `session` messages carry their averages and
  /// maxima, which is where a head unit and Strava read them from.
  ///
  /// Points that have no timestamp are given one second per point starting at
  /// [startTime] (defaulting to the first known point time, else "now"), so
  /// the resulting file always has a monotonic time base.
  ///
  /// Throws [ArgumentError] if [points] is empty.
  static Uint8List encodeActivity(
    List<TrackPoint> points, {
    FitSport sport = FitSport.cycling,
    DateTime? startTime,
    String? name,
  }) {
    if (points.isEmpty) {
      throw ArgumentError.value(
        points,
        'points',
        'cannot encode a FIT activity with no track points',
      );
    }

    final times = _timeline(points, startTime);
    final track = _Track(points, times);

    final encoder = Encode()..open();
    _writeFileId(encoder, File.activity, track.start);

    if (name != null && name.trim().isNotEmpty) {
      final sportMesg = Mesg.fromMesgNum(MesgNum.sport)
        ..setFieldValue(_fSportSport, sport.fitValue)
        ..setFieldValue(_fSportSubSport, SubSport.generic)
        ..setFieldValue(_fSportName, _fitString(name));
      _writeMesg(encoder, sportMesg, _lnMeta);
    }

    _writeTimerEvent(encoder, track.start, EventType.start);
    _writeRecords(encoder, track);
    _writeTimerEvent(encoder, track.end, EventType.stopAll);

    final lap = Mesg.fromMesgNum(MesgNum.lap)
      ..setFieldValue(_fMessageIndex, 0)
      ..setFieldValue(_fTimestamp, _fitTime(track.end))
      ..setFieldValue(_fLapStartTime, _fitTime(track.start))
      ..setFieldValue(_fLapEvent, Event.lap)
      ..setFieldValue(_fLapEventType, EventType.stop)
      ..setFieldValue(_fLapSport, sport.fitValue)
      ..setFieldValue(_fLapTotalElapsedTime, track.elapsedSeconds)
      ..setFieldValue(_fLapTotalTimerTime, track.elapsedSeconds)
      ..setFieldValue(_fLapTotalDistance, _clampDistance(track.totalDistance));
    _setPosition(
      lap,
      _fLapStartPositionLat,
      _fLapStartPositionLong,
      points.first.pos,
    );
    _setPosition(
      lap,
      _fLapEndPositionLat,
      _fLapEndPositionLong,
      points.last.pos,
    );
    if (track.avgSpeed != null) {
      lap.setFieldValue(_fLapAvgSpeed, track.avgSpeed);
    }
    _setSensorSummary(
      lap,
      track,
      avgHeartRate: _fLapAvgHeartRate,
      maxHeartRate: _fLapMaxHeartRate,
      avgCadence: _fLapAvgCadence,
      avgPower: _fLapAvgPower,
      maxPower: _fLapMaxPower,
    );
    _writeMesg(encoder, lap, _lnLap);

    final session = Mesg.fromMesgNum(MesgNum.session)
      ..setFieldValue(_fMessageIndex, 0)
      ..setFieldValue(_fTimestamp, _fitTime(track.end))
      ..setFieldValue(_fSessionStartTime, _fitTime(track.start))
      ..setFieldValue(_fSessionEvent, Event.session)
      ..setFieldValue(_fSessionEventType, EventType.stop)
      ..setFieldValue(_fSessionSport, sport.fitValue)
      ..setFieldValue(_fSessionSubSport, SubSport.generic)
      ..setFieldValue(_fSessionTotalElapsedTime, track.elapsedSeconds)
      ..setFieldValue(_fSessionTotalTimerTime, track.elapsedSeconds)
      ..setFieldValue(
        _fSessionTotalDistance,
        _clampDistance(track.totalDistance),
      )
      ..setFieldValue(_fSessionFirstLapIndex, 0)
      ..setFieldValue(_fSessionNumLaps, 1)
      ..setFieldValue(_fSessionTrigger, SessionTrigger.activityEnd);
    _setPosition(
      session,
      _fSessionStartPositionLat,
      _fSessionStartPositionLong,
      points.first.pos,
    );
    if (track.avgSpeed != null) {
      session.setFieldValue(_fSessionAvgSpeed, track.avgSpeed);
    }
    _setSensorSummary(
      session,
      track,
      avgHeartRate: _fSessionAvgHeartRate,
      maxHeartRate: _fSessionMaxHeartRate,
      avgCadence: _fSessionAvgCadence,
      avgPower: _fSessionAvgPower,
      maxPower: _fSessionMaxPower,
    );
    _writeMesg(encoder, session, _lnSession);

    final activity = Mesg.fromMesgNum(MesgNum.activity)
      ..setFieldValue(_fTimestamp, _fitTime(track.end))
      ..setFieldValue(_fActivityTotalTimerTime, track.elapsedSeconds)
      ..setFieldValue(_fActivityNumSessions, 1)
      ..setFieldValue(_fActivityType, Activity.manual)
      ..setFieldValue(_fActivityEvent, Event.activity)
      ..setFieldValue(_fActivityEventType, EventType.stop);
    _writeMesg(encoder, activity, _lnActivity);

    return encoder.close();
  }

  /// Decodes a FIT *course* file: its track and its `course_point`s.
  ///
  /// Throws [FitFormatException] when [bytes] is not a FIT file or not a
  /// course.
  static FitCourse decodeCourse(Uint8List bytes) {
    // Phase 1: courses come back with their course points as cues.
    throw UnimplementedError('Phase 1: FIT course import is not written yet');
  }

  /// Decodes a FIT *activity* file whole: the records as [decodeActivity]
  /// gives them, plus the temperatures, the laps and the session totals.
  ///
  /// Throws [FitFormatException] as [decodeActivity] does.
  static FitActivity decodeActivityFile(Uint8List bytes) {
    // Phase 2: laps, session totals and temperature reach the ride.
    throw UnimplementedError('Phase 2: FIT laps and totals are not read yet');
  }

  /// Encodes [points] as a FIT *course* file — the thing a Garmin head unit
  /// imports as a navigable route.
  ///
  /// The file contains `file_id` (type `course`), a `course` message holding
  /// [name] and [sport], a `lap` message with the start and end position,
  /// total distance and total timer time, a timer start `event`, one `record`
  /// per point and a timer stop `event`.
  ///
  /// Course points have no natural time base, so each record is stamped one
  /// second after the previous one unless the point carries its own time.
  ///
  /// Throws [ArgumentError] if [points] is empty or [name] is blank.
  static Uint8List encodeCourse(
    List<TrackPoint> points, {
    required String name,
    FitSport sport = FitSport.cycling,
    List<FitCoursePoint> coursePoints = const <FitCoursePoint>[],
  }) {
    // Phase 1: the cue sheet goes out as `course_point` messages.
    if (coursePoints.isNotEmpty) {
      throw UnimplementedError('Phase 1: course points are not written yet');
    }
    if (points.isEmpty) {
      throw ArgumentError.value(
        points,
        'points',
        'cannot encode a FIT course with no track points',
      );
    }
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'course name must not be blank');
    }

    final times = _timeline(points, null);
    final track = _Track(points, times);

    final encoder = Encode()..open();
    _writeFileId(encoder, File.course, track.start);

    final course = Mesg.fromMesgNum(MesgNum.course)
      ..setFieldValue(_fCourseSport, sport.fitValue)
      ..setFieldValue(_fCourseName, _fitString(name));
    _writeMesg(encoder, course, _lnMeta);

    final lap = Mesg.fromMesgNum(MesgNum.lap)
      ..setFieldValue(_fMessageIndex, 0)
      ..setFieldValue(_fTimestamp, _fitTime(track.end))
      ..setFieldValue(_fLapStartTime, _fitTime(track.start))
      ..setFieldValue(_fLapTotalElapsedTime, track.elapsedSeconds)
      ..setFieldValue(_fLapTotalTimerTime, track.elapsedSeconds)
      ..setFieldValue(_fLapTotalDistance, _clampDistance(track.totalDistance));
    _setPosition(
      lap,
      _fLapStartPositionLat,
      _fLapStartPositionLong,
      points.first.pos,
    );
    _setPosition(
      lap,
      _fLapEndPositionLat,
      _fLapEndPositionLong,
      points.last.pos,
    );
    _writeMesg(encoder, lap, _lnLap);

    _writeTimerEvent(encoder, track.start, EventType.start);
    _writeRecords(encoder, track);
    _writeTimerEvent(encoder, track.end, EventType.stopDisableAll);

    return encoder.close();
  }

  // -------------------------------------------------------------------------
  // Encoding helpers
  // -------------------------------------------------------------------------

  static void _writeFileId(Encode encoder, int fileType, DateTime created) {
    final mesg = Mesg.fromMesgNum(MesgNum.fileId)
      ..setFieldValue(_fFileIdType, fileType)
      ..setFieldValue(_fFileIdManufacturer, Manufacturer.development)
      ..setFieldValue(_fFileIdProduct, 0)
      ..setFieldValue(_fFileIdSerialNumber, 1)
      ..setFieldValue(_fFileIdTimeCreated, _fitTime(created));
    _writeMesg(encoder, mesg, _lnFileId);
  }

  static void _writeTimerEvent(Encode encoder, DateTime when, int eventType) {
    final mesg = Mesg.fromMesgNum(MesgNum.event)
      ..setFieldValue(_fTimestamp, _fitTime(when))
      ..setFieldValue(_fEventEvent, Event.timer)
      ..setFieldValue(_fEventType, eventType);
    _writeMesg(encoder, mesg, _lnEvent);
  }

  static void _writeRecords(Encode encoder, _Track track) {
    // One shared definition for every record, built from a template that
    // carries exactly the fields this track can fill. Fields a single point
    // does not have are written as the FIT "invalid" sentinel.
    final template = Mesg.fromMesgNum(MesgNum.record)
      ..localNum = _lnRecord
      ..setFieldValue(_fTimestamp, null)
      ..setFieldValue(_fRecordPositionLat, null)
      ..setFieldValue(_fRecordPositionLong, null)
      ..setFieldValue(_fRecordDistance, null);
    if (track.hasElevation) template.setFieldValue(_fRecordAltitude, null);
    if (track.hasSpeed) template.setFieldValue(_fRecordSpeed, null);
    if (track.hasHeartRate) template.setFieldValue(_fRecordHeartRate, null);
    if (track.hasCadence) template.setFieldValue(_fRecordCadence, null);
    if (track.hasPower) template.setFieldValue(_fRecordPower, null);

    final definition = MesgDefinition.fromMesg(template);
    encoder.writeMesgDefinition(definition);

    for (var i = 0; i < track.points.length; i++) {
      final point = track.points[i];
      final mesg = Mesg.fromMesgNum(MesgNum.record)..localNum = _lnRecord;
      mesg.setFieldValue(_fTimestamp, _fitTime(track.times[i]));
      _setPosition(mesg, _fRecordPositionLat, _fRecordPositionLong, point.pos);
      mesg.setFieldValue(
        _fRecordDistance,
        _clampDistance(track.cumulativeDistance[i]),
      );
      if (track.hasElevation) {
        mesg.setFieldValue(_fRecordAltitude, _altitudeOrNull(point.ele));
      }
      if (track.hasSpeed) {
        mesg.setFieldValue(_fRecordSpeed, _speedOrNull(point.speedMps));
      }
      if (track.hasHeartRate) {
        mesg.setFieldValue(
          _fRecordHeartRate,
          _inRange(point.heartRateBpm, _uint8Max),
        );
      }
      if (track.hasCadence) {
        mesg.setFieldValue(
          _fRecordCadence,
          _inRange(point.cadenceRpm, _uint8Max),
        );
      }
      if (track.hasPower) {
        mesg.setFieldValue(_fRecordPower, _inRange(point.powerW, _uint16Max));
      }
      encoder.writeMesg(mesg, definition);
    }
  }

  /// Puts the track's sensor averages on a `lap` or `session` message.
  ///
  /// The field numbers differ between the two messages, so they are passed in;
  /// a figure the track does not have is left off the message entirely rather
  /// than written as the invalid sentinel.
  static void _setSensorSummary(
    Mesg mesg,
    _Track track, {
    required int avgHeartRate,
    required int maxHeartRate,
    required int avgCadence,
    required int avgPower,
    required int maxPower,
  }) {
    void set(int field, int? value, int max) {
      final clamped = _inRange(value, max);
      if (clamped != null) mesg.setFieldValue(field, clamped);
    }

    set(avgHeartRate, track.avgHeartRate, _uint8Max);
    set(maxHeartRate, track.maxHeartRate, _uint8Max);
    set(avgCadence, track.avgCadence, _uint8Max);
    set(avgPower, track.avgPower, _uint16Max);
    set(maxPower, track.maxPower, _uint16Max);
  }

  /// Writes [mesg] at local message number [localNum], emitting its definition
  /// the first time that slot is used.
  static void _writeMesg(Encode encoder, Mesg mesg, int localNum) {
    mesg.localNum = localNum;
    final definition = MesgDefinition.fromMesg(mesg);
    encoder.writeMesgDefinition(definition);
    encoder.writeMesg(mesg, definition);
  }

  static void _setPosition(Mesg mesg, int latField, int lonField, LatLng pos) {
    mesg.setFieldValue(latField, _toSemicircles(pos.lat));
    mesg.setFieldValue(lonField, _toSemicircles(pos.lon));
  }

  // -------------------------------------------------------------------------
  // Decoding helpers
  // -------------------------------------------------------------------------

  static TrackPoint? _recordToTrackPoint(Mesg mesg) {
    final lat = _asNum(mesg.getFieldValue(_fRecordPositionLat));
    final lon = _asNum(mesg.getFieldValue(_fRecordPositionLong));
    if (lat == null || lon == null) return null;

    final ele =
        _asNum(mesg.getFieldValue(_fRecordAltitude)) ??
        _asNum(mesg.getFieldValue(_fRecordEnhancedAltitude));
    final speed =
        _asNum(mesg.getFieldValue(_fRecordSpeed)) ??
        _asNum(mesg.getFieldValue(_fRecordEnhancedSpeed));
    final stamp = _asNum(mesg.getFieldValue(_fTimestamp));

    return TrackPoint(
      LatLng(lat * degreesPerSemicircle, lon * degreesPerSemicircle),
      ele: ele?.toDouble(),
      time: stamp == null ? null : _fromFitTime(stamp.toInt()),
      speedMps: speed?.toDouble(),
      heartRateBpm: _asNum(mesg.getFieldValue(_fRecordHeartRate))?.round(),
      cadenceRpm: _asNum(mesg.getFieldValue(_fRecordCadence))?.round(),
      powerW: _asNum(mesg.getFieldValue(_fRecordPower))?.round(),
    );
  }

  static num? _asNum(Object? value) => value is num ? value : null;
}

/// Per-track values derived once and reused by every message of a file.
class _Track {
  _Track(this.points, this.times)
    : cumulativeDistance = cumulativeDistancesMeters(
        points.map((p) => p.pos).toList(growable: false),
      ),
      hasElevation = points.any((p) => p.ele != null),
      hasSpeed = points.any((p) => p.speedMps != null),
      hasHeartRate = points.any((p) => p.heartRateBpm != null),
      hasCadence = points.any((p) => p.cadenceRpm != null),
      hasPower = points.any((p) => p.powerW != null);

  final List<TrackPoint> points;
  final List<DateTime> times;
  final List<double> cumulativeDistance;
  final bool hasElevation;
  final bool hasSpeed;
  final bool hasHeartRate;
  final bool hasCadence;
  final bool hasPower;

  /// Mean heart rate over the points that carried one, `null` when none did.
  int? get avgHeartRate => _mean((p) => p.heartRateBpm);

  /// Highest heart rate seen, `null` when no point carried one.
  int? get maxHeartRate => _max((p) => p.heartRateBpm);

  /// Mean cadence over the points that carried one.
  int? get avgCadence => _mean((p) => p.cadenceRpm);

  /// Mean power over the points that carried one.
  int? get avgPower => _mean((p) => p.powerW);

  /// Highest power seen.
  int? get maxPower => _max((p) => p.powerW);

  int? _mean(int? Function(TrackPoint) of) {
    var sum = 0;
    var count = 0;
    for (final point in points) {
      final value = of(point);
      if (value == null) continue;
      sum += value;
      count++;
    }
    return count == 0 ? null : (sum / count).round();
  }

  int? _max(int? Function(TrackPoint) of) {
    int? highest;
    for (final point in points) {
      final value = of(point);
      if (value != null && (highest == null || value > highest)) {
        highest = value;
      }
    }
    return highest;
  }

  DateTime get start => times.first;

  DateTime get end => times.last;

  double get totalDistance => cumulativeDistance.last;

  double get elapsedSeconds =>
      end.difference(start).inMilliseconds / Duration.millisecondsPerSecond;

  /// Average speed in m/s, or `null` when the track has no duration.
  double? get avgSpeed {
    final seconds = elapsedSeconds;
    if (seconds <= 0) return null;
    return _speedOrNull(totalDistance / seconds);
  }
}

/// Builds a strictly increasing timestamp for every point.
///
/// Points that carry a [TrackPoint.time] keep it; points that do not are given
/// one second per point counted from [startTime], the first known point time,
/// or "now" — in that order of preference.
List<DateTime> _timeline(List<TrackPoint> points, DateTime? startTime) {
  final base =
      (startTime ??
              points
                  .firstWhere((p) => p.time != null, orElse: () => points.first)
                  .time ??
              DateTime.now())
          .toUtc();
  return List<DateTime>.generate(
    points.length,
    (i) => points[i].time?.toUtc() ?? base.add(Duration(seconds: i)),
    growable: false,
  );
}

/// Converts [degrees] to FIT semicircles, clamped to the representable range.
///
/// The FIT sentinel `0x7FFFFFFF` means "no position", so longitudes of exactly
/// 180 degrees are stored one semicircle short of it (about 8.4e-8 degrees).
int _toSemicircles(double degrees) {
  final raw = (degrees * semicirclesPerDegree).round();
  if (raw > _sint32PositionMax) return _sint32PositionMax;
  if (raw < _sint32PositionMin) return _sint32PositionMin;
  return raw;
}

/// FIT `date_time` for [time], or `null` when it is outside the representable
/// range (before 1989-12-31 or beyond 2158).
int? _fitTime(DateTime time) {
  final seconds =
      time.toUtc().millisecondsSinceEpoch ~/ Duration.millisecondsPerSecond -
      fitEpochOffsetSeconds;
  if (seconds < 0 || seconds > _uint32Max) return null;
  return seconds;
}

/// UTC [DateTime] for the FIT `date_time` value [seconds].
DateTime _fromFitTime(int seconds) => DateTime.fromMillisecondsSinceEpoch(
  (seconds + fitEpochOffsetSeconds) * Duration.millisecondsPerSecond,
  isUtc: true,
);

/// Metres, clamped to what the scaled `uint32` distance fields can hold.
double _clampDistance(double meters) {
  if (meters.isNaN || meters < 0) return 0;
  const double max = _uint32Max / 100.0;
  return meters > max ? max : meters;
}

/// Metres, or `null` when the value cannot be stored in the FIT `altitude`
/// field (scale 5, offset 500, `uint16`) — i.e. outside -500..12606.8 m.
double? _altitudeOrNull(double? meters) {
  if (meters == null || meters.isNaN) return null;
  final raw = ((meters + 500.0) * 5.0).round();
  if (raw < 0 || raw > _uint16Max) return null;
  return meters;
}

/// Metres per second, or `null` when the value cannot be stored in the FIT
/// `speed` field (scale 1000, `uint16`) — i.e. outside 0..65.534 m/s.
double? _speedOrNull(double? mps) {
  if (mps == null || mps.isNaN) return null;
  final raw = (mps * 1000.0).round();
  if (raw < 0 || raw > _uint16Max) return null;
  return mps;
}

/// [value] clamped into `0..max`, or `null` when there is nothing to write.
///
/// The sensor fields have no scaling, so the only thing that can go wrong is a
/// reading outside the range of the integer they are stored in; clamping keeps
/// a nonsensical value from landing on the "invalid" sentinel and reading back
/// as no measurement at all.
int? _inRange(int? value, int max) {
  if (value == null) return null;
  if (value < 0) return 0;
  return value > max ? max : value;
}

/// Trims [value] to something a FIT string field can hold: no NUL bytes, at
/// most [_maxNameBytes] bytes of UTF-8, never split mid-character.
String _fitString(String value) {
  var text = value.replaceAll('\u0000', '').trim();
  while (utf8.encode(text).length > _maxNameBytes) {
    // Drop whole runes, never half of a multi byte character.
    final runes = text.runes.toList(growable: false);
    text = String.fromCharCodes(runes.take(runes.length - 1));
  }
  return text;
}
