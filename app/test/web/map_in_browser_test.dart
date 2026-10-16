@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/map/data/local_file_url.dart';
import 'package:velorki/features/map/data/position_provider.dart';
import 'package:velorki_io/io.dart';
import 'package:velorki_io/memory_fs.dart';
import 'package:velorki_io/worker.dart';
import 'package:web/web.dart' as web;

/// What the map needs of the browser that the phone does not give it, in a
/// real browser (`flutter test --platform chrome test/web/`).
void main() {
  setUp(MemoryFileSystem.reset);

  Future<Uint8List> fetchBytes(String url) async {
    final response = await web.window.fetch(url.toJS).toDart;
    return (await response.arrayBuffer().toDart).toDart.asUint8List();
  }

  test('a file of the in-memory file system reaches maplibre by a blob: URL, '
      'until it is let go', () async {
    const geojson = '{"type":"FeatureCollection","features":[]}';
    File('/cache/cycle_map/out/m.geojson')
      ..createSync(recursive: true)
      ..writeAsStringSync(geojson);
    final url = localFileUrl('/cache/cycle_map/out/m.geojson');
    expect(url, startsWith('blob:'));
    expect(String.fromCharCodes(await fetchBytes(url)), geojson);
    releaseLocalFileUrl(url);
    await expectLater(fetchBytes(url), throwsA(anything));
  });

  test('a picture does too', () async {
    final png = Uint8List.fromList(<int>[137, 80, 78, 71, 13, 10, 26, 10]);
    final url = pngBytesUrl(png);
    expect(url, startsWith('blob:'));
    expect(await fetchBytes(url), png);
    releaseLocalFileUrl(url);
  });

  test('zlib and the work meant for an isolate run in the browser', () async {
    final data = Uint8List.fromList(List<int>.generate(2000, (i) => i % 13));
    expect(zlib.decode(zlib.encode(data)), data);
    expect(await runIsolated(() => 6 * 7), 42);
  });

  test('the browser keeps no last position: none is asked for, so the '
      'position dot and locate go on to a fresh fix', () async {
    expect(await const GeolocatorPositionSource().lastKnown(), isNull);
  });
}
