import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/map/data/picture_png.dart';
import 'package:velorki/features/map/data/weather_fetcher.dart'
    show encodePngRgba;

void main() {
  test('a surface-sized image is cut back to its top left corner', () {
    // A 4 × 3 surface whose top left 2 × 2 pixels are the picture.
    final surface = Uint8List(4 * 3 * 4);
    for (final (x, y) in <(int, int)>[(0, 0), (1, 0), (0, 1), (1, 1)]) {
      surface[(y * 4 + x) * 4 + 3] = 255;
    }
    final cut = cropRgba(surface, 4, 2, 2);
    expect(cut.length, 2 * 2 * 4);
    expect(
      [for (var i = 3; i < cut.length; i += 4) cut[i]],
      [255, 255, 255, 255],
    );
    expect(identical(cropRgba(cut, 2, 2, 2), cut), isTrue);
  });

  test('the size comes from the PNG header', () {
    expect(pngSize(encodePngRgba(5, 7, Uint8List(5 * 7 * 4))), (5, 7));
    expect(pngSize(Uint8List(10)), isNull);
  });

  testWidgets('a picture comes out at the size asked for', (tester) async {
    final png = await tester.runAsync(() {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawRect(
        const ui.Rect.fromLTWH(0, 0, 3, 3),
        ui.Paint()..color = const ui.Color(0xff0000ff),
      );
      return pictureToPng(recorder.endRecording(), 6, 4);
    });
    expect(pngSize(png!), (6, 4));
  });
}
