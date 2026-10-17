import 'dart:typed_data';
import 'dart:ui' as ui;

import 'weather_fetcher.dart' show encodePngRgba;

/// [picture] rasterised at [width] × [height] pixels, as PNG bytes.
///
/// Flutter's renderer in a browser now and then hands back an image of its
/// whole drawing surface, the picture in its top left corner: as a map
/// symbol that was a window-sized image anchored at its middle, so the
/// cycle map's chevrons stood off their line or were not drawn at all. Such
/// an image is cut back to the size asked for.
Future<Uint8List> pictureToPng(
  ui.Picture picture,
  int width,
  int height,
) async {
  final image = await picture.toImage(width, height);
  try {
    if (image.width == width && image.height == height) {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final png = data!.buffer.asUint8List();
      final size = pngSize(png);
      if (size == null || (size.$1 == width && size.$2 == height)) return png;
    }
    final data = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    final rgba = data!.buffer.asUint8List();
    // The rows as the surface has them: as wide as the image says, or as
    // the buffer, for a surface of the picture's height.
    final rows = rgba.length ~/ 4 ~/ image.width == image.height
        ? image.width
        : rgba.length ~/ 4 ~/ height;
    return encodePngRgba(width, height, cropRgba(rgba, rows, width, height));
  } finally {
    image.dispose();
  }
}

/// The width and height a PNG's header gives, or `null` when [png] is not
/// one.
(int, int)? pngSize(Uint8List png) {
  if (png.length < 24 || png[12] != 0x49 || png[13] != 0x48) return null;
  final header = ByteData.sublistView(png, 16, 24);
  return (header.getUint32(0), header.getUint32(4));
}

/// The top left [width] × [height] pixels of [rgba], whose rows are
/// [stride] pixels long.
Uint8List cropRgba(Uint8List rgba, int stride, int width, int height) {
  if (stride == width && rgba.length == width * height * 4) return rgba;
  final out = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    final from = y * stride * 4;
    if (from + width * 4 > rgba.length) break;
    out.setRange(y * width * 4, (y + 1) * width * 4, rgba, from);
  }
  return out;
}
