import 'package:test/test.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

void main() {
  group('parseTags', () {
    test('splits on whitespace then on the first =', () {
      expect(SegmentMessage.parseTags('highway=residential surface=asphalt'), {
        'highway': 'residential',
        'surface': 'asphalt',
      });
    });

    test('keeps = inside a value', () {
      expect(SegmentMessage.parseTags('description=a=b'), {
        'description': 'a=b',
      });
    });

    test('a bare token maps to the empty string', () {
      expect(SegmentMessage.parseTags('oneway highway=track'), {
        'oneway': '',
        'highway': 'track',
      });
    });

    test('an empty value is kept', () {
      expect(SegmentMessage.parseTags('surface='), {'surface': ''});
    });

    test('empty, whitespace-only and null are empty maps', () {
      expect(SegmentMessage.parseTags(''), isEmpty);
      expect(SegmentMessage.parseTags('   '), isEmpty);
      expect(SegmentMessage.parseTags(null), isEmpty);
    });

    test('runs of whitespace do not create empty keys', () {
      expect(SegmentMessage.parseTags('  a=1   b=2  '), {'a': '1', 'b': '2'});
    });
  });

  group('parseTable', () {
    final header = SegmentMessage.headerColumns;

    test('an empty table yields no messages', () {
      expect(SegmentMessage.parseTable(const []), isEmpty);
    });

    test('a header-only table yields no messages', () {
      expect(SegmentMessage.parseTable([header]), isEmpty);
    });

    test('rejects a table that does not start with a header', () {
      expect(
        () => SegmentMessage.parseTable([
          ['1', '2', '3'],
        ]),
        throwsFormatException,
      );
    });

    test('rejects a row that is not a list', () {
      expect(
        () => SegmentMessage.parseTable([header, 'nope']),
        throwsFormatException,
      );
    });

    test('a short row is padded with empty strings', () {
      final m = SegmentMessage.parseTable([
        header,
        ['11500000', '48100000', '520'],
      ]).single;
      expect(m.position.lon, closeTo(11.5, 1e-9));
      expect(m.position.lat, closeTo(48.1, 1e-9));
      expect(m.elevationM, 520);
      expect(m.distanceM, 0);
      expect(m.wayTags, isEmpty);
      expect(m.energyJ, 0);
    });

    test('unparsable numbers fall back to zero', () {
      final m = SegmentMessage.parseTable([
        header,
        [
          '11500000',
          '48100000',
          'n/a',
          '-',
          '',
          '0',
          '0',
          '0',
          '0',
          '',
          '',
          '',
          '',
        ],
      ]).single;
      expect(m.elevationM, 0);
      expect(m.distanceM, 0);
    });

    test('negative microdegrees round trip through the divide', () {
      final m = SegmentMessage.parseTable([
        header,
        [
          '-71058000',
          '42360000',
          '10',
          '100',
          '0',
          '0',
          '0',
          '0',
          '0',
          'highway=cycleway',
          '',
          '30',
          '1000',
        ],
      ]).single;
      expect(m.position.lon, closeTo(-71.058, 1e-9));
      expect(m.position.lat, closeTo(42.36, 1e-9));
      expect(m.highway, 'cycleway');
      expect(m.surface, isNull);
      expect(m.toString(), contains('cycleway'));
    });

    test('columns are looked up by name, not by index', () {
      final swapped = ['Latitude', 'Longitude', ...header.sublist(2)];
      final m = SegmentMessage.parseTable([
        swapped,
        [
          '48100000',
          '11500000',
          '520',
          '100',
          '0',
          '0',
          '0',
          '0',
          '0',
          'highway=path',
          '',
          '20',
          '500',
        ],
      ]).single;
      expect(m.position.lat, closeTo(48.1, 1e-9));
      expect(m.position.lon, closeTo(11.5, 1e-9));
    });
  });
}
