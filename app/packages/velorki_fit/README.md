# velorki_fit

Garmin **FIT** activity and course files for Velorki: decode a recorded ride
into `velorki_geo` track points, and encode track points back into a FIT
activity (for upload / archiving) or a FIT course (what a Garmin head unit
imports as a navigable route).

Pure Dart. No Flutter dependency, no `dart:ui`, tested on the desktop VM.

## Public API

```dart
class FitCodec {
  static List<TrackPoint> decodeActivity(Uint8List bytes);

  static Uint8List encodeActivity(
    List<TrackPoint> points, {
    FitSport sport = FitSport.cycling,
    DateTime? startTime,
    String? name,
  });

  static Uint8List encodeCourse(
    List<TrackPoint> points, {
    required String name,
    FitSport sport = FitSport.cycling,
  });
}

/// Cheap content sniffer for the import pipeline.
bool looksLikeFit(Uint8List bytes);

/// Thrown by `decodeActivity` for anything that is not a readable FIT file.
class FitFormatException implements Exception {
  final String message;
  final Object? cause;
}

enum FitSport { generic, running, cycling, swimming, walking,
                crossCountrySkiing, rowing, hiking, eBiking, inlineSkating }

const int fitEpochOffsetSeconds = 631065600; // FIT epoch = 1989-12-31T00:00:00Z
const double degreesPerSemicircle = 180 / 2^31;
const double semicirclesPerDegree = 2^31 / 180;
```

## Usage

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:velorki_fit/velorki_fit.dart';
import 'package:velorki_geo/velorki_geo.dart';

void main() {
  final bytes = Uint8List.fromList(File('ride.fit').readAsBytesSync());

  if (looksLikeFit(bytes)) {
    final List<TrackPoint> points = FitCodec.decodeActivity(bytes);
    print('${points.length} points, ${polylineLengthMeters(
        points.map((p) => p.pos).toList())} m');

    // Hand the same track back to a head unit as a course.
    File('ride_course.fit')
        .writeAsBytesSync(FitCodec.encodeCourse(points, name: 'Sunday loop'));
  }
}
```

## What it covers

* **Decode** — `record` messages only. `position_lat`/`position_long`
  (semicircles → degrees), `altitude` falling back to `enhanced_altitude`,
  `speed` falling back to `enhanced_speed`, and `timestamp` as a UTC
  `DateTime`. Records without a position are skipped; order is file order. A
  valid FIT file with no `record` messages decodes to an empty list.
* **Encode activity** — `file_id` (type `activity`), an optional `sport`
  message carrying the name, timer start/stop `event`s, one `record` per
  point (timestamp, position, cumulative distance, and altitude/speed when any
  point has them), then `lap`, `session` and `activity`. Total distance is the
  great circle length of the track (`velorki_geo`); elapsed and timer time
  come from the point timestamps.
* **Encode course** — `file_id` (type `course`), `course` (name + sport),
  `lap` (start/end position, total distance, total timer time), timer start
  `event`, the `record`s, timer stop `event`.
* **Sniffing** — `looksLikeFit` checks the header size byte (12 or 14), the
  ASCII `.FIT` signature at bytes 8..11 and a minimum length. It does not
  verify any CRC.

## What it does not cover

* Heart rate, cadence, power, temperature and every other sensor channel —
  `TrackPoint` has nowhere to put them. They are ignored on decode and never
  written.
* Laps beyond a single one, multisport activities, workouts, segments,
  developer fields, and `course_point` turn instructions.
* `accuracyM` from `TrackPoint` — FIT has no per-record horizontal accuracy
  field, so it is dropped on encode.
* Timestamps before the FIT epoch (1989-12-31) cannot be represented and are
  written as "invalid".

## Quantisation

Values go through FIT's scaled integer fields, so a round trip is lossy in a
bounded, testable way:

| value | storage | worst case error |
| --- | --- | --- |
| latitude / longitude | `sint32` semicircles | `0.5 * 180 / 2^31` ≈ 4.2e-8° (< 5 mm) |
| elevation | `uint16`, scale 5, offset 500 | 0.1 m (range −500 … 12606.8 m) |
| speed | `uint16`, scale 1000 | 0.0005 m/s (range 0 … 65.534 m/s) |
| distance | `uint32`, scale 100 | 0.005 m |
| timestamp | `uint32` seconds | exact to the second |

Elevations and speeds outside those ranges are written as "invalid" rather
than wrapping. Longitudes are clamped one semicircle short of `0x7FFFFFFF`,
which is FIT's "no position" sentinel.

## Dependencies

Built on [`fit_sdk`](https://pub.dev/packages/fit_sdk) **0.3.0**, a pure-Dart
MIT port of the Garmin FIT SDK with both `Decode` and `Encode`, including CRC
verification, component expansion and the full v21.188 profile. The package is
used through its generic `Mesg` / `MesgDefinition` API with numeric field
numbers rather than the generated typed message classes, because the generated
classes name their fields in `PascalCase` while the FIT profile uses
`snake_case`, which makes the name-based helpers in `fit_sdk` unreliable
(`Decode`'s internal `getFieldByName('timestamp')` lookup never matches, so
files that use *compressed timestamp headers* decode with wrong times — none
of the files this package writes use them).
