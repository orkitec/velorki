# velorki_gpx

GPX 1.1 reading and writing for Velorki: decode a file an import gave us into
`velorki_geo` track points, and encode a planned route or a recorded ride back
into a GPX file other apps accept.

Pure Dart, no Flutter dependency, tested on the desktop VM. Built on
`package:gpx` for the parsing and `package:xml` for the finishing touches on
the output.

## Public API

```dart
abstract final class GpxCodec {
  static GpxDocument decode(String xml);                      // throws GpxFormatException

  static String encodeTrack({
    required List<TrackPoint> points,
    String? name,
    String creator = 'Velorki',
    String? description,
    List<GpxWaypoint> waypoints = const [],
  });

  static String encodeRoute({
    required List<TrackPoint> points,
    String? name,
    List<GpxWaypoint> waypoints = const [],
    String creator = 'Velorki',
    String? description,
  });
}

class GpxDocument {
  const GpxDocument({String? name, description, creator,
                     List<GpxTrack> tracks, List<GpxRoute> routes,
                     List<GpxWaypoint> waypoints});
  final String? name, description, creator;     // metadata/name, metadata/desc, @creator
  final List<GpxTrack> tracks;
  final List<GpxRoute> routes;
  final List<GpxWaypoint> waypoints;
  bool get isEmpty;
}

class GpxTrack {
  const GpxTrack({String? name, description, type,
                  List<List<TrackPoint>> segments,
                  List<List<GpxExtensions?>> segmentExtensions});
  final String? name, description, type;        // <type> is Strava's activity id, e.g. "1"
  final List<List<TrackPoint>> segments;
  final List<List<GpxExtensions?>> segmentExtensions;   // parallel to segments
  List<TrackPoint> get points;                  // segments, flattened
  List<GpxExtensions?> get pointExtensions;     // parallel to points
  int get pointCount;
  GpxExtensions? extensionsIn(int segmentIndex, int pointIndex);
  GpxExtensions? extensionsAt(int flatIndex);
}

class GpxRoute {
  const GpxRoute({String? name, description, List<TrackPoint> points});
}

class GpxWaypoint {
  const GpxWaypoint(LatLng pos, {double? ele, String? name, description,
                                 symbol, type, DateTime? time});
  double get lat, lon;
}

class GpxExtensions {                           // Garmin TrackPointExtension
  const GpxExtensions({int? heartRate, cadence, double? temperatureC});
  bool get isEmpty, isNotEmpty;
}

class GpxFormatException implements Exception {
  const GpxFormatException(String message, [Object? cause]);
  final String message;
  final Object? cause;
}

bool looksLikeGpx(Uint8List bytes);             // content sniffer for the import pipeline

const String gpx11Namespace, xmlSchemaInstanceNamespace, gpx11SchemaLocation;
const String packageVersion;
```

## Usage

```dart
import 'dart:convert';
import 'dart:io';

import 'package:velorki_geo/velorki_geo.dart';
import 'package:velorki_gpx/velorki_gpx.dart';

final bytes = File('ride.gpx').readAsBytesSync();
if (!looksLikeGpx(bytes)) return;               // cheap check before parsing

try {
  final doc = GpxCodec.decode(utf8.decode(bytes));
  print('${doc.creator} gave us ${doc.tracks.single.pointCount} points');
  for (var i = 0; i < doc.tracks.single.pointCount; i++) {
    print(doc.tracks.single.extensionsAt(i)?.heartRate);
  }
} on GpxFormatException catch (e) {
  print('not usable: ${e.message}');            // e.cause holds the original error
}

File('plan.gpx').writeAsStringSync(
  GpxCodec.encodeRoute(name: 'Isar loop', points: plannedPoints),
);
```

## Sensor data

GPX has no place for heart rate, cadence or air temperature, so recorders write
them into `<extensions>` using Garmin's `TrackPointExtension`. `TrackPoint`
(from `velorki_geo`) has no field for them either, so they are kept in
`GpxTrack.segmentExtensions`, which mirrors `segments` one to one: entry
`[s][i]` belongs to point `segments[s][i]`, and `null` means that point had
none. Read them through `extensionsAt` / `extensionsIn` rather than indexing.
When a track has no sensor data at all, `segmentExtensions` is left empty
instead of holding an all-`null` shadow of a 20k point track; both helpers
return `null` in that case.

## Dependencies

| package       | version  | used for                                        |
| ------------- | -------- | ----------------------------------------------- |
| `gpx`         | ^2.5.0   | the GPX element model, reader and writer        |
| `xml`         | ^7.0.0   | well-formedness check, root element, `<time>`   |
| `velorki_geo` | path dep | `LatLng`, `TrackPoint`                          |
| `lints`       | ^6.0.0   | dev: `package:lints/recommended.yaml`           |
| `test`        | ^1.25.0  | dev                                             |

## Caveats

* **Time resolution.** GPX is used at whole-second resolution in practice, and
  `package:gpx`'s writer emits `DateTime.toIso8601String()`, which includes
  milliseconds. The encoder rewrites every `<time>` to UTC `...:SSZ`, so
  sub-second parts of a `TrackPoint.time` are dropped. Decoding returns UTC; a
  `<time>` without a zone offset is read as local time and converted, which is
  what other GPX readers do.
* **Numbers round trip exactly, but only because of Dart.** Coordinates and
  elevations are written with `double.toString()`, which emits the shortest
  text that parses back to the same double. Still compare with a tolerance when
  the values came from somewhere else — a file that writes `533.021973` for a
  value that was never exactly that is the normal case.
* **`xsi` attributes.** `package:gpx` 2.5.0 *does* emit the GPX 1.1 namespace
  and `xsi:schemaLocation` when its writer is asked for
  `GpxCompatibilityMode.gpx11` (which is not the default), so nothing has to be
  injected afterwards. The output is still re-parsed with `package:xml` to put
  the root attributes in the conventional `version`, `creator`, namespaces
  order and to fix the timestamps.
* **Extension prefixes.** `package:gpx` exposes a typed
  `GarminTrackPointExtensionV1`, but it only matches the literal keys
  `gpxtpx:TrackPointExtension` and `TrackPointExtension` — files written with
  the `ns3:` prefix (Garmin Connect, Wahoo) fall straight through it. This
  package therefore walks the raw extension map by local name, which also
  catches `gpxx:` and the flattened form where `<hr>` sits directly under
  `<extensions>`.
* **Two parsing passes.** `decode` tokenises the input once itself (to reject
  a foreign root element and a truncated file with a proper error, which
  `GpxReader` does not notice) and then hands it to `package:gpx`. Fine for
  import-sized files; not a streaming parser.
* **What is dropped.** Only what Velorki needs is modelled: links, author,
  copyright, bounds, `<cmt>`, `<number>`, `<src>`, DOP values and non-Garmin
  extensions are ignored on decode and never written. `TrackPoint.speedMps`
  and `accuracyM` stay `null` — GPX 1.1 has no standard element for either.
