import 'dart:io';

import 'package:test/test.dart';
import 'package:velorki_gpx/velorki_gpx.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

Matcher throwsGpxFormat([String? messagePart]) => throwsA(
  isA<GpxFormatException>().having(
    (e) => e.message,
    'message',
    messagePart == null ? isNotEmpty : contains(messagePart),
  ),
);

void main() {
  group('GpxCodec.decode rejects', () {
    test('input that is not XML at all', () {
      expect(() => GpxCodec.decode(fixture('not_xml.txt')), throwsGpxFormat());
    });

    test('well-formed XML whose root is not <gpx>', () {
      expect(
        () => GpxCodec.decode(fixture('not_gpx.xml')),
        throwsGpxFormat('root element'),
      );
    });

    test('a truncated file', () {
      expect(
        () => GpxCodec.decode(fixture('truncated.gpx')),
        throwsGpxFormat('well-formed'),
      );
    });

    test('an empty string', () {
      expect(() => GpxCodec.decode(''), throwsGpxFormat('empty'));
      expect(() => GpxCodec.decode('   \n '), throwsGpxFormat('empty'));
    });

    test('a <trkpt> without lat/lon', () {
      const xml =
          '<gpx version="1.1" creator="x"><trk><trkseg>'
          '<trkpt><ele>2</ele></trkpt></trkseg></trk></gpx>';
      expect(() => GpxCodec.decode(xml), throwsGpxFormat('lat'));
    });

    test('a <trkpt> with an unparsable lat', () {
      const xml =
          '<gpx version="1.1" creator="x"><trk><trkseg>'
          '<trkpt lat="north" lon="11.5"/></trkseg></trk></gpx>';
      expect(() => GpxCodec.decode(xml), throwsGpxFormat());
    });

    test('a <gpx> element nested in a foreign root', () {
      const xml = '<archive><gpx version="1.1" creator="x"></gpx></archive>';
      expect(() => GpxCodec.decode(xml), throwsGpxFormat('root element'));
    });
  });

  group('GpxFormatException', () {
    test('keeps the underlying error as cause', () {
      try {
        GpxCodec.decode(fixture('truncated.gpx'));
        fail('expected a GpxFormatException');
      } on GpxFormatException catch (e) {
        expect(e.cause, isNotNull);
        expect(e.toString(), contains('GpxFormatException'));
        expect(e.toString(), contains('caused by'));
      }
    });

    test('reads well without a cause', () {
      const e = GpxFormatException('boom');
      expect(e.cause, isNull);
      expect(e.toString(), 'GpxFormatException: boom');
    });
  });
}
