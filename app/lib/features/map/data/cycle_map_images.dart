import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// The arrows the cycle map draws along its lines, painted as bitmaps the
/// style can place: all point along the line, the way a symbol on a line
/// is drawn, to the right in the bitmap.

/// An arrow of [fill] with a rim of [rim], [width] × [height] logical
/// pixels, as PNG bytes at [devicePixelRatio].
Future<Uint8List> buildArrowImage({
  required ui.Color fill,
  required ui.Color rim,
  required double devicePixelRatio,
  double width = 18,
  double height = 8,
}) => _png(ui.Size(width + 2, height + 2), devicePixelRatio, (canvas) {
  final path = _arrow(1, 1, width, height);
  canvas
    ..drawPath(
      path,
      ui.Paint()
        ..color = rim
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = ui.StrokeJoin.round,
    )
    ..drawPath(path, ui.Paint()..color = fill);
});

/// The two arrows of a street one-way for traffic and two-way for bikes:
/// the traffic's along the line in [traffic], over the bikes' against it in
/// [bikes].
Future<Uint8List> buildContraflowImage({
  required ui.Color traffic,
  required ui.Color bikes,
  required ui.Color rim,
  required double devicePixelRatio,
}) => _png(const ui.Size(22, 18), devicePixelRatio, (canvas) {
  final rimPaint = ui.Paint()
    ..color = rim
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..strokeJoin = ui.StrokeJoin.round;
  final ahead = _arrow(1, 1, 20, 7);
  canvas
    ..drawPath(ahead, rimPaint)
    ..drawPath(ahead, ui.Paint()..color = traffic);
  // The bikes' arrow, turned round below it.
  canvas
    ..save()
    ..translate(22, 18)
    ..rotate(math.pi);
  final against = _arrow(1, 1, 20, 7);
  canvas
    ..drawPath(against, rimPaint)
    ..drawPath(against, ui.Paint()..color = bikes)
    ..restore();
});

/// An arrow pointing right in the box at [x], [y] of [w] × [h]: a shaft of
/// a third of the height and a head of half the width.
ui.Path _arrow(double x, double y, double w, double h) {
  final mid = y + h / 2;
  final shaft = h / 3;
  final headStart = x + w * 0.55;
  return ui.Path()
    ..moveTo(x, mid - shaft / 2)
    ..lineTo(headStart, mid - shaft / 2)
    ..lineTo(headStart, y)
    ..lineTo(x + w, mid)
    ..lineTo(headStart, y + h)
    ..lineTo(headStart, mid + shaft / 2)
    ..lineTo(x, mid + shaft / 2)
    ..close();
}

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
