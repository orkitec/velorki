import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:velorki_gpx/velorki_gpx.dart';

Uint8List ascii(String s) => Uint8List.fromList(utf8.encode(s));

Uint8List withBom(List<int> bom, String s) =>
    Uint8List.fromList([...bom, ...utf8.encode(s)]);

/// Encodes [s] as UTF-16 with the given byte order mark.
Uint8List utf16(String s, {required bool littleEndian}) {
  final bytes = <int>[
    if (littleEndian) ...[0xFF, 0xFE] else ...[0xFE, 0xFF],
  ];
  for (final unit in s.codeUnits) {
    if (littleEndian) {
      bytes.addAll([unit & 0xFF, unit >> 8]);
    } else {
      bytes.addAll([unit >> 8, unit & 0xFF]);
    }
  }
  return Uint8List.fromList(bytes);
}

const _minimalGpx =
    '<gpx version="1.1" creator="x" '
    'xmlns="http://www.topografix.com/GPX/1/1"></gpx>';

void main() {
  group('looksLikeGpx accepts', () {
    test('a plain document', () {
      expect(looksLikeGpx(ascii(_minimalGpx)), isTrue);
    });

    test('an XML declaration in front of it', () {
      expect(
        looksLikeGpx(
          ascii(
            '<?xml version="1.0" encoding="UTF-8"?>\n'
            '$_minimalGpx',
          ),
        ),
        isTrue,
      );
    });

    test('leading whitespace and newlines', () {
      expect(looksLikeGpx(ascii('\n\n   \t$_minimalGpx')), isTrue);
    });

    test('a UTF-8 BOM', () {
      expect(looksLikeGpx(withBom([0xEF, 0xBB, 0xBF], _minimalGpx)), isTrue);
    });

    test('a UTF-16 LE BOM', () {
      expect(looksLikeGpx(utf16(_minimalGpx, littleEndian: true)), isTrue);
    });

    test('a UTF-16 BE BOM', () {
      expect(looksLikeGpx(utf16(_minimalGpx, littleEndian: false)), isTrue);
    });

    test('a self-closing root element', () {
      expect(looksLikeGpx(ascii('<gpx/>')), isTrue);
    });

    test('the real fixtures', () {
      for (final name in ['mixed.gpx', 'komoot.gpx', 'strava.gpx']) {
        expect(
          looksLikeGpx(File('test/fixtures/$name').readAsBytesSync()),
          isTrue,
          reason: name,
        );
      }
    });

    test('a comment in front of the root element', () {
      expect(looksLikeGpx(ascii('<!-- exported -->\n$_minimalGpx')), isTrue);
    });
  });

  group('looksLikeGpx rejects', () {
    test('a FIT file', () {
      // A FIT header: size, protocol, profile, data size, then ".FIT".
      final fit = Uint8List.fromList([
        0x0E, 0x10, 0x62, 0x00, 0x40, 0x1A, 0x00, 0x00,
        0x2E, 0x46, 0x49, 0x54, // ".FIT"
        0x91, 0x33, 0x00, 0x00,
      ]);
      expect(looksLikeGpx(fit), isFalse);
    });

    test('JSON', () {
      expect(
        looksLikeGpx(ascii('{"type":"FeatureCollection","features":[]}')),
        isFalse,
      );
    });

    test('empty input', () {
      expect(looksLikeGpx(Uint8List(0)), isFalse);
    });

    test('input shorter than the tag', () {
      expect(looksLikeGpx(ascii('<gp')), isFalse);
      expect(looksLikeGpx(ascii('<')), isFalse);
    });

    test('arbitrary binary', () {
      final noise = Uint8List.fromList(
        List<int>.generate(256, (i) => (i * 37 + 11) % 256),
      );
      expect(looksLikeGpx(noise), isFalse);
    });

    test('other XML dialects', () {
      expect(
        looksLikeGpx(File('test/fixtures/not_gpx.xml').readAsBytesSync()),
        isFalse,
      );
      expect(looksLikeGpx(ascii('<gpxdata:lap>1</gpxdata:lap>')), isFalse);
    });

    test('a GPX tag that only appears past the sniff window', () {
      final padding = '<!-- ${'.' * 600} -->\n';
      expect(looksLikeGpx(ascii('$padding$_minimalGpx')), isFalse);
    });
  });
}
