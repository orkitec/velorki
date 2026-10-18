import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/theme.dart';
import 'package:velorki/features/shared/application/glass_blur.dart';
import 'package:velorki/features/shared/presentation/glass_backdrop.dart';

Widget _glass({
  BarStyle style = BarStyle.clear,
  bool enabled = true,
  BorderRadius radius = const BorderRadius.all(Radius.circular(24)),
}) => GlassBackdrop(
  style: style,
  enabled: enabled,
  borderRadius: radius,
  child: const SizedBox(width: 200, height: 60),
);

Widget _at(Widget child, {double left = 40, double top = 100}) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [Positioned(left: left, top: top, child: child)],
      ),
    );

void main() {
  tearDown(() => GlassBackdrop.tracked = false);

  group('the browser blurs the map behind the glass', () {
    test('only with backdrop-filter, no wish for less transparency, and '
        'fast enough', () {
      expect(
        browserBlursGlass(
          backdropFilter: true,
          reducedTransparency: false,
          tooSlow: false,
        ),
        isTrue,
      );
      for (final (filter, reduced, slow) in const [
        (false, false, false),
        (true, true, false),
        (true, false, true),
      ]) {
        expect(
          browserBlursGlass(
            backdropFilter: filter,
            reducedTransparency: reduced,
            tooSlow: slow,
          ),
          isFalse,
          reason: 'filter $filter, reduced $reduced, slow $slow',
        );
      }
    });

    test('too slow is a median of the recent frames under 30 a second, not '
        'a few slow ones, a short sample or a pause', () {
      List<double> frames(int n, double ms) => List<double>.filled(n, ms);
      expect(framesTooSlow(frames(glassFrameWindow, 16.7)), isFalse);
      expect(framesTooSlow(frames(glassFrameWindow, 40)), isTrue);
      // A few long frames among quick ones.
      expect(framesTooSlow([...frames(70, 16.7), ...frames(20, 60)]), isFalse);
      // Too few to tell yet.
      expect(framesTooSlow(frames(20, 50)), isFalse);
      // A tab in the background: one long gap is no frame at all.
      expect(
        framesTooSlow([...frames(glassFrameWindow - 1, 16.7), 5000]),
        isFalse,
      );
      // Only the most recent window counts.
      expect(
        framesTooSlow([...frames(200, 50), ...frames(glassFrameWindow, 16)]),
        isFalse,
      );
    });
  });

  testWidgets('on the phone the glass is the BackdropFilter alone: nothing '
      'reported, nothing changed', (tester) async {
    await tester.pumpWidget(_at(_glass()));
    final filter = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
    expect(filter.enabled, isTrue);
    expect(visibleGlass(), isEmpty);
    // Without blur the filter stays in the tree, switched off.
    await tester.pumpWidget(_at(_glass(style: BarStyle.solid)));
    expect(
      tester.widget<BackdropFilter>(find.byType(BackdropFilter)).enabled,
      isFalse,
    );
    expect(glassBlurSigma(BarStyle.clear), 4);
    expect(glassBlurSigma(BarStyle.subtle), 8);
    expect(glassBlurSigma(BarStyle.transparent), isNull);
  });

  group('in the browser the glass reports itself', () {
    setUp(() => GlassBackdrop.tracked = true);

    testWidgets('where it is in the window, its shape and its blur', (
      tester,
    ) async {
      await tester.pumpWidget(_at(_glass()));
      expect(visibleGlass(), [
        const GlassRect(
          rect: Rect.fromLTWH(40, 100, 200, 60),
          radius: 24,
          sigma: 4,
          opacity: 1,
        ),
      ]);
    });

    testWidgets('a style without blur, or blur switched off, reports none', (
      tester,
    ) async {
      await tester.pumpWidget(_at(_glass(style: BarStyle.transparent)));
      expect(visibleGlass(), isEmpty);
      await tester.pumpWidget(_at(_glass(enabled: false)));
      expect(visibleGlass(), isEmpty);
    });

    testWidgets('cut by its clip, faded with its fade, gone offstage', (
      tester,
    ) async {
      await tester.pumpWidget(
        _at(
          ClipRect(
            child: SizedBox(
              width: 100,
              height: 60,
              child: OverflowBox(
                alignment: Alignment.topLeft,
                maxWidth: 200,
                child: Opacity(opacity: 0.5, child: _glass()),
              ),
            ),
          ),
        ),
      );
      final [glass] = visibleGlass();
      expect(glass.rect, const Rect.fromLTWH(40, 100, 100, 60));
      expect(glass.opacity, 0.5);

      await tester.pumpWidget(_at(Offstage(child: _glass())));
      expect(visibleGlass(), isEmpty);

      await tester.pumpWidget(_at(Opacity(opacity: 0, child: _glass())));
      expect(visibleGlass(), isEmpty);
    });

    testWidgets('a stadium has half its height for corners', (tester) async {
      await tester.pumpWidget(
        _at(
          const GlassBackdrop(
            style: BarStyle.subtle,
            stadium: true,
            child: SizedBox(width: 80, height: 30),
          ),
        ),
      );
      final [glass] = visibleGlass();
      expect(glass.radius, 15);
      expect(glass.sigma, 8);
    });
  });
}
