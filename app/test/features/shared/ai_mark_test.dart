// The AI's own colours: the same violet-to-magenta whatever accent the rider
// picked, light and dark, readable on every surface the AI's marks sit on.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/theme.dart';
import 'package:velorki/features/shared/presentation/ai_mark.dart';
import 'package:velorki/features/shared/presentation/stat_tile.dart';

import '../../support/app.dart';
import '../../support/contrast.dart';

const Key _boundary = ValueKey<String>('boundary');

/// The colours [tester] painted inside the boundary, as opaque ARGB.
Future<List<Color>> _painted(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_boundary),
  );
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData();
    image.dispose();
    return data!;
  });
  final pixels = bytes!.buffer.asUint8List();
  return <Color>[
    for (var i = 0; i + 3 < pixels.length; i += 4)
      Color.fromARGB(pixels[i + 3], pixels[i], pixels[i + 1], pixels[i + 2]),
  ];
}

/// How far apart two colours are, channel by channel, 0 to 1.
double _distance(Color a, Color b) => [
  (a.r - b.r).abs(),
  (a.g - b.g).abs(),
  (a.b - b.b).abs(),
].reduce((x, y) => x > y ? x : y);

bool _near(Color painted, Color target) =>
    painted.a > 0.98 && _distance(painted, target) < 0.06;

void main() {
  for (final preset in AccentPreset.values) {
    for (final dark in [false, true]) {
      final name = '${dark ? 'dark' : 'light'} ${preset.name}';
      final theme = dark ? buildDarkTheme(preset) : buildLightTheme(preset);
      final colors = theme.velorki;

      test('$name: the AI colours are their own and read on every surface', () {
        expect(colors.ai, dark ? velorkiAiDark : velorkiAiLight);
        expect(colors.aiEnd, dark ? velorkiAiEndDark : velorkiAiEndLight);
        expect(colors.aiGradient.colors, [
          colors.ai,
          colors.aiMid,
          colors.aiEnd,
        ]);
        for (final ai in [colors.ai, colors.aiMid, colors.aiEnd]) {
          expect(_distance(ai, colors.accent), greaterThan(0.2));
          expect(_distance(ai, theme.colorScheme.primary), greaterThan(0.2));
        }
        final scheme = theme.colorScheme;
        for (final surface in [
          scheme.surface,
          scheme.surfaceContainerLowest,
          scheme.surfaceContainerLow,
          scheme.surfaceContainer,
          scheme.surfaceContainerHigh,
          scheme.surfaceContainerHighest,
        ]) {
          for (final ai in [colors.ai, colors.aiMid, colors.aiEnd]) {
            expect(
              contrastRatio(ai, surface),
              greaterThanOrEqualTo(3),
              reason: '$name: $ai on $surface',
            );
          }
        }
        // The flat colour is the one for lines and text.
        expect(
          contrastRatio(colors.ai, scheme.surface),
          greaterThanOrEqualTo(4.5),
        );
      });

      testWidgets('$name: the AI button paints its sparkle in the AI\'s '
          'colours, not the accent; disabled, it fades as any other', (
        tester,
      ) async {
        await tester.pumpWidget(
          testApp(
            theme: theme,
            home: Scaffold(
              body: Center(
                child: RepaintBoundary(
                  key: _boundary,
                  child: LabeledIconButton(
                    icon: Icons.auto_awesome_rounded,
                    label: 'Ask',
                    ai: true,
                    onPressed: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        expect(find.byType(AiSparkle), findsOneWidget);
        final painted = await _painted(tester);
        // The glyph does not fill its box, so neither end of the gradient
        // need be painted exactly; the sparkle must clearly show both halves.
        final opaque = painted.where((c) => c.a > 0.98);
        expect(
          opaque.any(
            (c) => _distance(c, colors.ai) < _distance(c, colors.aiEnd) / 2,
          ),
          isTrue,
        );
        expect(
          opaque.any(
            (c) => _distance(c, colors.aiEnd) < _distance(c, colors.ai) / 2,
          ),
          isTrue,
        );
        expect(painted.any((c) => _near(c, colors.accent)), isFalse);

        await tester.pumpWidget(
          testApp(
            theme: theme,
            home: const Scaffold(
              body: Center(
                child: LabeledIconButton(
                  icon: Icons.auto_awesome_rounded,
                  label: 'Ask',
                  ai: true,
                  onPressed: null,
                ),
              ),
            ),
          ),
        );
        expect(find.byType(AiSparkle), findsNothing);
        expect(
          tester.widget<Icon>(find.byIcon(Icons.auto_awesome_rounded)).color,
          theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
        );
      });

      testWidgets('$name: the AI card\'s edge is drawn in the AI\'s colours', (
        tester,
      ) async {
        await tester.pumpWidget(
          testApp(
            theme: theme,
            home: Scaffold(
              backgroundColor: theme.colorScheme.surface,
              body: Center(
                child: RepaintBoundary(
                  key: _boundary,
                  child: CustomPaint(
                    size: const Size(300, 120),
                    foregroundPainter: AiEdgePainter(
                      gradient: colors.aiGradient,
                      radius: 28,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final painted = await _painted(tester);
        expect(painted.any((c) => _near(c, colors.ai)), isTrue);
        expect(painted.any((c) => _near(c, colors.aiEnd)), isTrue);
        expect(painted.any((c) => _near(c, colors.accent)), isFalse);
      });
    }
  }

  testWidgets('the edge runs up both sides as well as along the top', (
    tester,
  ) async {
    const size = Size(200, 300);
    await tester.pumpWidget(
      Center(
        child: RepaintBoundary(
          key: _boundary,
          child: CustomPaint(
            size: size,
            painter: AiEdgePainter(
              gradient: const LinearGradient(
                colors: <Color>[velorkiAiLight, velorkiAiEndLight],
              ),
              radius: 28,
            ),
          ),
        ),
      ),
    );
    final painted = await _painted(tester);
    Color at(int x, int y) => painted[y * size.width.toInt() + x];

    // Low down on each side, well below the corners, and mid-top.
    expect(at(1, 280).a, greaterThan(0.5));
    expect(at(198, 280).a, greaterThan(0.5));
    expect(at(100, 1).a, greaterThan(0.5));
    // Nothing inside the card.
    expect(at(100, 150).a, 0);
  });
}
