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

/// Asserts that the text at [label] reads against what it is painted on;
/// a translucent fill is blended [over] what shows through it, a map's
/// darkest or lightest, as glass floating over the map is.
void expectReadable(
  WidgetTester tester,
  Finder label, {
  String? reason,
  Color? over,
}) {
  final text = textColorOf(tester, label);
  final painted = fillBehind(tester, label);
  final fill = over == null ? painted : Color.alphaBlend(painted, over);
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

/// What sits behind the glass over the map in a theme of [brightness]: the
/// map of that theme as the glass's blur leaves it, about its average
/// colour. Light maps are mostly the land's cream (#F2EFE9), the dark and
/// night maps a blue-grey (#2B3240).
///
/// Glass contrast is checked over this rather than over a pure black or
/// white: the blur averages the few dp of map behind a label, so a stray
/// black road or white label of the map never sits alone behind it, and the
/// tint is thin (`glassTint`) because the blurred map does part of its job.
/// A light theme sits over a light map and a dark one over a dark map
/// unless the rider picks otherwise.
Color blurredMapBehind(Brightness brightness) => brightness == Brightness.light
    ? const Color(0xFFF2EFE9)
    : const Color(0xFF2B3240);
