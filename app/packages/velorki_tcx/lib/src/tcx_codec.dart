import 'package:velorki_geo/velorki_geo.dart';

import 'tcx_models.dart';

/// Reads and writes TCX activities and courses.
///
/// All methods are static; the class is a namespace, not a value. Every
/// method throws [UnimplementedError] until phase 4 of the formats
/// programme; the tests under `test/` say what they will do.
class TcxCodec {
  const TcxCodec._();

  /// Decodes a TCX document: its activities with laps, heart rate, cadence
  /// and power, and its courses with their course points.
  ///
  /// Throws `TcxFormatException` when [xml] is not a TCX document.
  static TcxDocument decode(String xml) {
    throw UnimplementedError('Phase 4: TCX import is not written yet');
  }

  /// Encodes [laps] as one `<Activity>` of [sport], with heart rate,
  /// cadence and power on the points that carry them.
  static String encodeActivity({
    required List<TcxLap> laps,
    TcxSport sport = TcxSport.biking,
    String creator = 'Velorki',
  }) {
    throw UnimplementedError('Phase 4: TCX export is not written yet');
  }

  /// Encodes [points] as one `<Course>` named [name], with [coursePoints]
  /// as its cues.
  static String encodeCourse({
    required String name,
    required List<TrackPoint> points,
    List<TcxCoursePoint> coursePoints = const <TcxCoursePoint>[],
    String creator = 'Velorki',
  }) {
    throw UnimplementedError('Phase 4: TCX export is not written yet');
  }
}
