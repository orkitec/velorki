import 'package:test/test.dart';
import 'package:velorki_geo/velorki_geo.dart';
import 'package:velorki_gpx/velorki_gpx.dart';
import 'package:xml/xml.dart';

const _schemaLocation =
    'http://www.topografix.com/GPX/1/1 '
    'http://www.topografix.com/GPX/1/1/gpx.xsd';

final _points = [
  TrackPoint(
    const LatLng(48.1351, 11.582),
    ele: 519.0,
    time: DateTime.utc(2024, 5, 1, 8),
  ),
  const TrackPoint(LatLng(48.1352, 11.5821)),
];

void expectGpx11Root(String xml, String creator) {
  final root = XmlDocument.parse(xml).rootElement;

  expect(root.name.qualified, 'gpx');
  expect(root.getAttribute('version'), '1.1');
  expect(root.getAttribute('creator'), creator);
  expect(root.getAttribute('xmlns'), 'http://www.topografix.com/GPX/1/1');
  expect(
    root.getAttribute('xmlns:xsi'),
    'http://www.w3.org/2001/XMLSchema-instance',
  );
  expect(root.getAttribute('xsi:schemaLocation'), _schemaLocation);

  // The same attributes, resolved through the namespace rather than by
  // spelling, which is what a schema-aware consumer does.
  expect(
    root.getAttribute(
      'schemaLocation',
      namespaceUri: 'http://www.w3.org/2001/XMLSchema-instance',
    ),
    _schemaLocation,
  );
}

void main() {
  group('encoded XML', () {
    test('a track carries the GPX 1.1 namespace and schema location', () {
      expectGpx11Root(
        GpxCodec.encodeTrack(name: 'Ride', points: _points),
        'Velorki',
      );
    });

    test('a route carries them too, with a custom creator', () {
      expectGpx11Root(
        GpxCodec.encodeRoute(
          name: 'Plan',
          points: _points,
          creator: 'Velorki 0.1.0',
        ),
        'Velorki 0.1.0',
      );
    });

    test('starts with an XML declaration and ends with a newline', () {
      final xml = GpxCodec.encodeTrack(points: _points);
      expect(xml, startsWith('<?xml version="1.0" encoding="UTF-8"?>'));
      expect(xml, endsWith('\n'));
    });

    test('puts the points into trk/trkseg/trkpt with lat and lon', () {
      final xml = GpxCodec.encodeTrack(name: 'Ride', points: _points);
      final root = XmlDocument.parse(xml).rootElement;

      final trkpts = root
          .findElements('trk')
          .single
          .findElements('trkseg')
          .single
          .findElements('trkpt')
          .toList();
      expect(trkpts, hasLength(2));
      expect(trkpts.first.getAttribute('lat'), '48.1351');
      expect(trkpts.first.getAttribute('lon'), '11.582');
      expect(trkpts.first.findElements('ele').single.innerText, '519.0');
      expect(
        trkpts.first.findElements('time').single.innerText,
        '2024-05-01T08:00:00Z',
      );
      expect(trkpts.last.findElements('ele'), isEmpty);
      expect(trkpts.last.findElements('time'), isEmpty);
    });

    test('puts the route points into rte/rtept', () {
      final xml = GpxCodec.encodeRoute(name: 'Plan', points: _points);
      final root = XmlDocument.parse(xml).rootElement;

      expect(root.findElements('trk'), isEmpty);
      final rte = root.findElements('rte').single;
      expect(rte.findElements('name').single.innerText, 'Plan');
      expect(rte.findElements('rtept'), hasLength(2));
    });

    test('writes waypoints as top level wpt elements', () {
      final xml = GpxCodec.encodeTrack(
        points: _points,
        waypoints: const [
          GpxWaypoint(
            LatLng(48.15, 11.6),
            name: 'Brunnen',
            symbol: 'Water Source',
            type: 'water',
          ),
        ],
      );
      final root = XmlDocument.parse(xml).rootElement;

      final wpt = root.findElements('wpt').single;
      expect(wpt.getAttribute('lat'), '48.15');
      expect(wpt.findElements('name').single.innerText, 'Brunnen');
      expect(wpt.findElements('sym').single.innerText, 'Water Source');
      expect(wpt.findElements('type').single.innerText, 'water');
    });

    test('escapes names that contain XML syntax', () {
      final xml = GpxCodec.encodeTrack(name: 'Tour & <ride>', points: _points);
      expect(xml, contains('Tour &amp; &lt;ride>'));
      expect(GpxCodec.decode(xml).name, 'Tour & <ride>');
    });
  });
}
