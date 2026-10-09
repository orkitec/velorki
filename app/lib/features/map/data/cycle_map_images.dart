import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

// The chevrons the cycle map draws along its lines, painted as bitmaps the
// style can place: all point along the line, the way a symbol on a line is
// drawn, to the right in the bitmap.

/// A bold chevron pointing along the line, [size] logical pixels square,
/// in [fill] with a rim of [rim], as PNG bytes at [devicePixelRatio]: it
/// reads on a thin line, which a small arrow inside it did not.
Future<Uint8List> buildChevronImage({
  required ui.Color fill,
  required ui.Color rim,
  required double devicePixelRatio,
  double size = 14,
}) => _png(ui.Size(size, size), devicePixelRatio, (canvas) {
  _chevron(canvas, ui.Offset(size / 2, size / 2), size * 0.62, fill, rim);
});

/// A chevron ">" centred on [centre], [extent] wide and high, its stroke
/// drawn twice: the rim, then the fill on it.
void _chevron(
  ui.Canvas canvas,
  ui.Offset centre,
  double extent,
  ui.Color fill,
  ui.Color rim,
) {
  final h = extent / 2;
  final path = ui.Path()
    ..moveTo(centre.dx - h * 0.55, centre.dy - h)
    ..lineTo(centre.dx + h * 0.55, centre.dy)
    ..lineTo(centre.dx - h * 0.55, centre.dy + h);
  ui.Paint stroke(ui.Color color, double width) => ui.Paint()
    ..color = color
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = ui.StrokeCap.round
    ..strokeJoin = ui.StrokeJoin.round;
  canvas
    ..drawPath(path, stroke(rim, extent * 0.42))
    ..drawPath(path, stroke(fill, extent * 0.2));
}

/// The two chevrons of a street one-way for traffic and two-way for bikes,
/// 24 logical pixels square: the traffic's along the line in [traffic]
/// above, the bikes' against it in [bikes] below.
Future<Uint8List> buildContraflowImage({
  required ui.Color traffic,
  required ui.Color bikes,
  required ui.Color rim,
  required double devicePixelRatio,
}) => _png(const ui.Size(24, 24), devicePixelRatio, (canvas) {
  _chevron(canvas, const ui.Offset(12, 7), 10, traffic, rim);
  canvas
    ..save()
    ..translate(24, 24)
    ..rotate(math.pi);
  _chevron(canvas, const ui.Offset(12, 7), 10, bikes, rim);
  canvas.restore();
});

Future<Uint8List> _png(
  ui.Size logical,
  double devicePixelRatio,
  void Function(ui.Canvas canvas) paint,
) async {
  final ratio = devicePixelRatio <= 0 ? 1.0 : devicePixelRatio;
  final width = math.max(1, (logical.width * ratio).round());
  final height = math.max(1, (logical.height * ratio).round());
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)..scale(ratio);
  paint(canvas);
  final image = await recorder.endRecording().toImage(width, height);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}
