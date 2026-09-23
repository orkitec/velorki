# velorki_tcx

Garmin **TCX** (Training Center XML v2) for Velorki: activities with their
laps, heart rate, cadence and power as `velorki_geo` track points, and
courses with their course points; and the same written back out.

Pure Dart. No Flutter dependency, no `dart:ui`, tested on the desktop VM.

## Public API

```dart
class TcxCodec {
  static TcxDocument decode(String xml);
  static String encodeActivity({required List<TcxLap> laps, ...});
  static String encodeCourse({required String name, required List<TrackPoint> points, ...});
}

bool looksLikeTcx(Uint8List bytes);
```
