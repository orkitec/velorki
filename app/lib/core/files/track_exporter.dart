import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// What is being exported; decides GPX `<rte>` vs `<trk>` and FIT course vs
/// activity.
enum TrackKind { route, ride }

enum TrackFormat { gpx, fit }

/// Hands a route or ride to the platform share sheet (or "Save to Files") as a
/// GPX or FIT file. Implemented by the import/export feature; other features
/// consume it through [trackExporterProvider] and override it in tests.
abstract class TrackExporter {
  Future<void> share({
    required String name,
    required List<TrackPoint> points,
    required TrackKind kind,
    required TrackFormat format,
    DateTime? startTime,
  });
}

/// Overridden with the real implementation in the import/export feature's
/// provider wiring; the default throws so a missing override is loud.
final trackExporterProvider = Provider<TrackExporter>((ref) {
  throw UnimplementedError('trackExporterProvider must be overridden');
});
