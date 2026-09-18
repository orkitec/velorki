import 'package:gpx/gpx.dart' as gpxlib;
import 'package:velorki_geo/velorki_geo.dart';
import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

import 'exception.dart';
import 'model.dart';

/// The GPX 1.1 namespace URI.
const String gpx11Namespace = 'http://www.topografix.com/GPX/1/1';

/// The XML Schema instance namespace URI, used for `xsi:schemaLocation`.
const String xmlSchemaInstanceNamespace =
    'http://www.w3.org/2001/XMLSchema-instance';

/// The value written into `xsi:schemaLocation` on the root element.
const String gpx11SchemaLocation = '$gpx11Namespace $gpx11Namespace/gpx.xsd';

/// Namespace URI of Garmin's `TrackPointExtension`, the schema every recorder
/// writes heart rate and cadence into.
const String garminTrackPointExtensionNamespace =
    'http://www.garmin.com/xmlschemas/TrackPointExtension/v1';

/// Reads and writes GPX 1.1 documents.
///
/// The heavy lifting is done by `package:gpx`; this codec adds the parts
/// Velorki needs on top of it:
///
/// * a model built on `velorki_geo`'s [TrackPoint] and [LatLng] instead of
///   `package:gpx`'s own `Wpt`,
/// * Garmin `TrackPointExtension` support that also copes with the `ns3:` and
///   un-prefixed spellings other exporters emit,
/// * a single [GpxFormatException] instead of the assorted errors the
///   underlying parser throws,
/// * output with a stable root element, whole-second timestamps and pretty
///   indentation.
abstract final class GpxCodec {
  /// Parses [xml] into a [GpxDocument].
  ///
  /// Throws a [GpxFormatException] for anything that is not a readable GPX
  /// document: plain text, XML with a different root element, a truncated
  /// file, or a point without `lat`/`lon`. No exception from `package:gpx`,
  /// `package:xml` or `dart:core` escapes.
  ///
  /// Timestamps are returned in UTC. A `<time>` without a zone offset is read
  /// as local time and converted, which is what every other GPX reader does.
  static GpxDocument decode(String xml) {
    if (xml.trim().isEmpty) {
      throw const GpxFormatException('the input is empty');
    }

    // Check well-formedness and the root element ourselves: package:gpx
    // happily scans past a foreign root looking for a <gpx> element anywhere,
    // fails with a TypeError when it finds none, and never notices a file
    // that was cut short.
    final root = _scanDocument(xml);
    if (_localName(root.name).toLowerCase() != 'gpx') {
      throw GpxFormatException('the root element is <${root.name}>, not <gpx>');
    }

    final gpxlib.Gpx parsed;
    try {
      parsed = gpxlib.GpxReader().fromString(xml);
    } on XmlParserException catch (e) {
      throw GpxFormatException('the file is not well-formed XML', e);
    } on StateError catch (e) {
      throw GpxFormatException(
        'a <trkpt>, <rtept> or <wpt> is missing its lat or lon attribute',
        e,
      );
    } on FormatException catch (e) {
      throw GpxFormatException(
        'the file contains a malformed number or timestamp',
        e,
      );
    } catch (e) {
      throw GpxFormatException('the file could not be read as GPX', e);
    }

    return GpxDocument(
      name: _nonEmpty(parsed.metadata?.name),
      description: _nonEmpty(parsed.metadata?.desc),
      creator: _nonEmpty(_attribute(root, 'creator')),
      tracks: [for (final trk in parsed.trks) _toTrack(trk)],
      routes: [for (final rte in parsed.rtes) _toRoute(rte)],
      waypoints: [for (final wpt in parsed.wpts) _toWaypoint(wpt)],
    );
  }

  /// Encodes [points] as a GPX 1.1 file holding a single `<trk>` with one
  /// `<trkseg>`, plus any [waypoints] as top level `<wpt>` elements.
  ///
  /// [name] and [description] are written both to `<metadata>` and to the
  /// track, so that readers which only look at one of the two find them.
  /// Timestamps are written in UTC with whole-second precision; sub-second
  /// parts are dropped, which is the resolution GPX is used at in practice.
  ///
  /// A point that carries sensor values gets an `<extensions>` block: heart
  /// rate and cadence inside Garmin's `TrackPointExtension`, power as a bare
  /// `<power>` beside it.
  static String encodeTrack({
    required List<TrackPoint> points,
    String? name,
    String creator = 'Velorki',
    String? description,
    List<GpxWaypoint> waypoints = const [],
  }) {
    final gpx = gpxlib.Gpx()
      ..version = '1.1'
      ..creator = creator
      ..metadata = _metadata(name, description)
      ..wpts = [for (final w in waypoints) _fromWaypoint(w)]
      ..trks = [
        gpxlib.Trk(
          name: name,
          desc: description,
          trksegs: [
            gpxlib.Trkseg(trkpts: [for (final p in points) _fromPoint(p)]),
          ],
        ),
      ];
    return _render(gpx, garminExtensions: _needsGarminNamespace(points));
  }

  /// Encodes [points] as a GPX 1.1 file holding a single `<rte>`, plus any
  /// [waypoints] as top level `<wpt>` elements.
  ///
  /// Same conventions as [encodeTrack].
  static String encodeRoute({
    required List<TrackPoint> points,
    String? name,
    List<GpxWaypoint> waypoints = const [],
    String creator = 'Velorki',
    String? description,
  }) {
    final gpx = gpxlib.Gpx()
      ..version = '1.1'
      ..creator = creator
      ..metadata = _metadata(name, description)
      ..wpts = [for (final w in waypoints) _fromWaypoint(w)]
      ..rtes = [
        gpxlib.Rte(
          name: name,
          desc: description,
          rtepts: [for (final p in points) _fromPoint(p)],
        ),
      ];
    return _render(gpx, garminExtensions: _needsGarminNamespace(points));
  }

  // --- decoding helpers ----------------------------------------------------

  static GpxTrack _toTrack(gpxlib.Trk trk) {
    final segments = <List<TrackPoint>>[];
    final extensions = <List<GpxExtensions?>>[];
    var anyExtension = false;

    for (final seg in trk.trksegs) {
      segments.add([for (final pt in seg.trkpts) _toTrackPoint(pt)]);
      final segExtensions = <GpxExtensions?>[];
      for (final pt in seg.trkpts) {
        final ext = _toExtensions(pt.extensions);
        anyExtension |= ext != null;
        segExtensions.add(ext);
      }
      extensions.add(segExtensions);
    }

    return GpxTrack(
      name: _nonEmpty(trk.name),
      description: _nonEmpty(trk.desc),
      type: _nonEmpty(trk.type),
      segments: segments,
      // Keep the parallel structure only when it carries something; an
      // all-null shadow of a 20k point track is pure waste.
      segmentExtensions: anyExtension ? extensions : const [],
    );
  }

  static GpxRoute _toRoute(gpxlib.Rte rte) => GpxRoute(
    name: _nonEmpty(rte.name),
    description: _nonEmpty(rte.desc),
    points: [for (final pt in rte.rtepts) _toTrackPoint(pt)],
  );

  static GpxWaypoint _toWaypoint(gpxlib.Wpt wpt) => GpxWaypoint(
    LatLng(wpt.lat ?? 0, wpt.lon ?? 0),
    ele: wpt.ele,
    name: _nonEmpty(wpt.name),
    description: _nonEmpty(wpt.desc),
    symbol: _nonEmpty(wpt.sym),
    type: _nonEmpty(wpt.type),
    time: wpt.time?.toUtc(),
  );

  static TrackPoint _toTrackPoint(gpxlib.Wpt wpt) {
    final sensors = _toExtensions(wpt.extensions);
    return TrackPoint(
      LatLng(wpt.lat ?? 0, wpt.lon ?? 0),
      ele: wpt.ele,
      time: wpt.time?.toUtc(),
      heartRateBpm: sensors?.heartRate,
      cadenceRpm: sensors?.cadence,
      powerW: _powerIn(wpt.extensions),
    );
  }

  /// Power in watts out of an `<extensions>` map.
  ///
  /// There is no agreed element for it: Strava writes a bare `<power>` beside
  /// the `TrackPointExtension`, Garmin a `<gpxpx:PowerInWatts>` inside the
  /// nested `<gpxtpx:Extensions>`, and some tools put either of the two inside
  /// the `TrackPointExtension` itself. All of them are read.
  static int? _powerIn(Map<String, Object> raw) {
    if (raw.isEmpty) return null;
    final direct = _intIn(raw, 'power') ?? _intIn(raw, 'PowerInWatts');
    if (direct != null) return direct;
    final container = _childByLocalName(raw, 'TrackPointExtension');
    if (container == null) return null;
    final inside =
        _intIn(container, 'power') ?? _intIn(container, 'PowerInWatts');
    if (inside != null) return inside;
    final nested = _childByLocalName(container, 'Extensions');
    if (nested == null) return null;
    return _intIn(nested, 'power') ?? _intIn(nested, 'PowerInWatts');
  }

  /// Pulls heart rate, cadence and temperature out of a raw `<extensions>`
  /// map as `package:gpx` hands it over.
  ///
  /// `package:gpx` does expose a typed `GarminTrackPointExtensionV1`, but it
  /// only recognises the exact keys `gpxtpx:TrackPointExtension` and
  /// `TrackPointExtension`; files written with the `ns3:` prefix (Garmin
  /// Connect, Wahoo) fall through it. So the raw map is walked by local name
  /// instead, which covers every prefix, and the flattened form where the
  /// sensor elements sit directly under `<extensions>`.
  static GpxExtensions? _toExtensions(Map<String, Object> raw) {
    if (raw.isEmpty) {
      return null;
    }
    final container = _childByLocalName(raw, 'TrackPointExtension') ?? raw;
    final result = GpxExtensions(
      heartRate: _intIn(container, 'hr'),
      cadence: _intIn(container, 'cad'),
      temperatureC: _doubleIn(container, 'atemp'),
    );
    return result.isEmpty ? null : result;
  }

  static Map<String, Object>? _childByLocalName(
    Map<String, Object> map,
    String localName,
  ) {
    for (final entry in map.entries) {
      if (_localName(entry.key) == localName &&
          entry.value is Map<String, Object>) {
        return entry.value as Map<String, Object>;
      }
    }
    return null;
  }

  /// The text of the first child of [map] whose local name is [localName].
  ///
  /// Values arrive as a plain string, as a map with a `#text` entry when the
  /// element also had attributes, or as a list when the name repeated.
  static String? _textIn(Map<String, Object> map, String localName) {
    for (final entry in map.entries) {
      if (_localName(entry.key) == localName) {
        return _text(entry.value);
      }
    }
    return null;
  }

  static String? _text(Object? value) {
    if (value is String) {
      return value;
    }
    if (value is Map) {
      final text = value['#text'];
      return text is String ? text : null;
    }
    if (value is List && value.isNotEmpty) {
      return _text(value.first);
    }
    return null;
  }

  static int? _intIn(Map<String, Object> map, String localName) {
    final text = _textIn(map, localName)?.trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    // Some exporters write "132.0" where the schema asks for an integer.
    return int.tryParse(text) ?? double.tryParse(text)?.round();
  }

  static double? _doubleIn(Map<String, Object> map, String localName) {
    final text = _textIn(map, localName)?.trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    return double.tryParse(text);
  }

  /// Checks that [xml] is a well-formed XML document and returns its root
  /// start element.
  ///
  /// This is an event level pass: it builds no tree, but it does tokenise the
  /// whole input a second time next to the pass `package:gpx` makes. That is
  /// the price of a trustworthy error, because `GpxReader` stops at the
  /// closing `</gpx>` and therefore accepts a file that was truncated in the
  /// middle of an element without noticing.
  static XmlStartElementEvent _scanDocument(String xml) {
    XmlStartElementEvent? root;
    try {
      final events = parseEvents(
        xml,
        validateNesting: true,
        validateDocument: true,
      );
      for (final event in events) {
        if (root == null && event is XmlStartElementEvent) {
          root = event;
        }
      }
    } on XmlException catch (e) {
      throw GpxFormatException('the file is not well-formed XML', e);
    } catch (e) {
      throw GpxFormatException('the file could not be read as XML', e);
    }
    if (root == null) {
      throw const GpxFormatException('the input contains no XML element');
    }
    return root;
  }

  static String? _attribute(XmlStartElementEvent root, String name) {
    for (final attribute in root.attributes) {
      if (attribute.name == name) {
        return attribute.value;
      }
    }
    return null;
  }

  // --- encoding helpers ----------------------------------------------------

  static gpxlib.Metadata? _metadata(String? name, String? description) =>
      (name == null && description == null)
      ? null
      : (gpxlib.Metadata()
          ..name = name
          ..desc = description);

  /// A `<trkpt>` or `<rtept>`, with the sensor values in `<extensions>` when
  /// the point carries any.
  ///
  /// Heart rate and cadence go into Garmin's `TrackPointExtension`, which is
  /// what every reader understands. Power has no place in that schema, so it
  /// is written as a bare `<power>` element beside it — the spelling Strava
  /// writes and reads.
  static gpxlib.Wpt _fromPoint(TrackPoint point) {
    final wpt = gpxlib.Wpt(
      lat: point.lat,
      lon: point.lon,
      ele: point.ele,
      time: point.time,
    );
    if (point.heartRateBpm != null || point.cadenceRpm != null) {
      wpt.typedExtensions = gpxlib.WptTypedExtensions(
        garmin: gpxlib.GarminWptExtensions(
          trackPointV1: gpxlib.GarminTrackPointExtensionV1(
            heartRate: point.heartRateBpm,
            cadence: point.cadenceRpm,
          ),
        ),
      );
    }
    if (point.powerW case final int watts) {
      wpt.extensions['power'] = '$watts';
    }
    return wpt;
  }

  /// Whether any of [points] needs the `gpxtpx` namespace on the root.
  static bool _needsGarminNamespace(Iterable<TrackPoint> points) =>
      points.any((p) => p.heartRateBpm != null || p.cadenceRpm != null);

  static gpxlib.Wpt _fromWaypoint(GpxWaypoint waypoint) => gpxlib.Wpt(
    lat: waypoint.lat,
    lon: waypoint.lon,
    ele: waypoint.ele,
    time: waypoint.time,
    name: waypoint.name,
    desc: waypoint.description,
    sym: waypoint.symbol,
    type: waypoint.type,
  );

  /// Serialises [gpx] and cleans up what `package:gpx`'s writer leaves behind.
  ///
  /// `GpxWriter` in 2.5.0 does emit the GPX 1.1 namespace and the
  /// `xsi:schemaLocation` when asked for [gpxlib.GpxCompatibilityMode.gpx11],
  /// so no attribute has to be injected. The document is still re-parsed with
  /// `package:xml` to put the root attributes in the conventional order
  /// (`version`, `creator`, then the namespaces) and to cut the milliseconds
  /// off every `<time>`, which the writer emits because it calls
  /// `DateTime.toIso8601String()`.
  ///
  /// [garminExtensions] adds the `gpxtpx` namespace, which the writer uses as
  /// a prefix but never declares. It is only added when a point actually
  /// carries a heart rate or a cadence, so an ordinary track keeps the root
  /// element it has always had.
  static String _render(gpxlib.Gpx gpx, {bool garminExtensions = false}) {
    final document = XmlDocument.parse(
      gpxlib.GpxWriter().asString(
        gpx,
        compatibility: gpxlib.GpxCompatibilityMode.gpx11,
      ),
    );
    final root = document.rootElement;

    final attributes = {
      for (final attribute in root.attributes)
        attribute.name.qualified: attribute.value,
    };
    root.attributes
      ..clear()
      ..addAll([
        XmlAttribute(XmlName.parts('version'), attributes['version'] ?? '1.1'),
        XmlAttribute(
          XmlName.parts('creator'),
          attributes['creator'] ?? 'Velorki',
        ),
        XmlAttribute(const XmlName.namespace(), gpx11Namespace),
        XmlAttribute(
          const XmlName.namespace(name: 'xsi'),
          xmlSchemaInstanceNamespace,
        ),
        XmlAttribute(
          XmlName.parts('schemaLocation', prefix: 'xsi'),
          gpx11SchemaLocation,
        ),
        if (garminExtensions)
          XmlAttribute(
            const XmlName.namespace(name: 'gpxtpx'),
            garminTrackPointExtensionNamespace,
          ),
      ]);

    for (final element in root.findAllElements('time')) {
      final seconds = _isoSeconds(element.innerText);
      if (seconds != null) {
        element.innerText = seconds;
      }
    }

    return '${document.toXmlString(pretty: true, indent: '  ')}\n';
  }

  /// Reformats an ISO-8601 timestamp to UTC whole seconds, or `null` if it
  /// cannot be parsed.
  static String? _isoSeconds(String value) {
    final parsed = DateTime.tryParse(value.trim());
    if (parsed == null) {
      return null;
    }
    final utc = parsed.toUtc();
    String pad(int v, [int width = 2]) => v.toString().padLeft(width, '0');
    return '${pad(utc.year, 4)}-${pad(utc.month)}-${pad(utc.day)}'
        'T${pad(utc.hour)}:${pad(utc.minute)}:${pad(utc.second)}Z';
  }

  // --- shared helpers ------------------------------------------------------

  static String _localName(String qualifiedName) {
    final colon = qualifiedName.indexOf(':');
    return colon == -1 ? qualifiedName : qualifiedName.substring(colon + 1);
  }

  static String? _nonEmpty(String? value) {
    if (value == null) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
