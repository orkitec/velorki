import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// The WCAG 2 contrast ratio between two opaque colours, `1` to `21`.
///
/// Text on a fill needs `4.5` or more to be readable at body sizes; a
/// translucent colour is blended over nothing here, so callers pass the
/// colours as they are painted.
double contrastRatio(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final light = math.max(la, lb);
  final dark = math.min(la, lb);
  return (light + 0.05) / (dark + 0.05);
}

double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

/// The colour the text found by [label] is painted in.
Color textColorOf(WidgetTester tester, Finder label) =>
    tester.renderObject<RenderParagraph>(label).text.style!.color!;

/// The fill the text found by [label] sits on: the nearest ancestor that
/// paints a solid colour, a chip's ink or a tile's material.
Color fillBehind(WidgetTester tester, Finder label) {
  final painted = find.ancestor(
    of: label,
    matching: find.byWidgetPredicate(
      (w) =>
          (w is Ink &&
              w.decoration is ShapeDecoration &&
              (w.decoration! as ShapeDecoration).color != null) ||
          (w is Material && w.color != null && w.color!.a > 0),
    ),
  );
  final widget = tester.widget(painted.first);
  return switch (widget) {
    Ink(:final decoration) => (decoration! as ShapeDecoration).color!,
    Material(:final color) => color!,
    _ => throw StateError('no fill behind $label'),
  };
}

/// Asserts that the text at [label] reads against what it is painted on.
void expectReadable(WidgetTester tester, Finder label, {String? reason}) {
  final text = textColorOf(tester, label);
  final fill = fillBehind(tester, label);
  expect(text.a, 1.0, reason: 'translucent text at $label');
  expect(fill.a, 1.0, reason: 'translucent fill at $label');
  expect(
    contrastRatio(text, fill),
    greaterThanOrEqualTo(4.5),
    reason:
        '${reason ?? label}: $text on $fill is '
        '${contrastRatio(text, fill).toStringAsFixed(2)}:1',
  );
}
