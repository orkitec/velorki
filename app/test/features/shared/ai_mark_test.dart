// The AI's own colours: the same violet-to-magenta whatever accent the rider
// picked, light and dark, readable on every surface the AI's marks sit on.
import 'dart:io';

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
          colors.aiEnd,
          colors.aiMid,
          colors.ai,
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
          // The light neon pink end is decoration beside the purple, which
          // carries the contrast; it is only held to it on dark surfaces.
          for (final ai in [colors.ai, colors.aiMid, if (dark) colors.aiEnd]) {
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

  test('the AI\'s gradients are drawn two stops at a time', () {
    const a = Color(0xFF000001);
    const b = Color(0xFF000002);
    const c = Color(0xFF000003);
    expect(twoStopRuns(const [a, b, c]), [(a, b), (b, c)]);
    expect(twoStopRuns(const [a, b]), [(a, b)]);
  });

  test('no gradient in the app is built from more than two of the AI\'s '
      'colours at once', () {
    // A gradient of three stops, painted once an integration test had
    // turned the surface into an image for a screenshot, took the CI's x86
    // Android emulator (SwiftShader, Impeller on OpenGLES) down with it. The
    // AI's colours go to a shader through [twoStopRuns] or by their two
    // ends, never as the whole list.
    final wholesale = RegExp(
      r'colors:\s*[\w.]*(gradient|aiGradient)\.colors\b',
    );
    final offenders = [
      for (final file in Directory('lib').listSync(recursive: true))
        if (file is File &&
            file.path.endsWith('.dart') &&
            wholesale.hasMatch(file.readAsStringSync()))
          file.path,
    ];
    expect(offenders, isEmpty);
  });

  for (final dark in [false, true]) {
    testWidgets('${dark ? 'dark' : 'light'}: the edge is one smooth gradient '
        'across the card\'s width, every colour along the top, each side its '
        'end\'s', (tester) async {
      final theme = dark
          ? buildDarkTheme(AccentPreset.values.first)
          : buildLightTheme(AccentPreset.values.first);
      final colors = theme.velorki;
      final [first, middle, last] = colors.aiGradient.colors;
      const size = Size(300, 120);
      await tester.pumpWidget(
        Center(
          child: RepaintBoundary(
            key: _boundary,
            child: CustomPaint(
              size: size,
              painter: AiEdgePainter(gradient: colors.aiGradient, radius: 28),
            ),
          ),
        ),
      );
      final painted = await _painted(tester);
      Color at(int x, int y) => painted[y * size.width.toInt() + x];

      // Along the top: a tenth in, the middle, a tenth from the end.
      final a = at(30, 1);
      final b = at(150, 1);
      final c = at(270, 1);
      expect(_distance(a, first), lessThan(_distance(a, middle)));
      expect(_near(b, middle), isTrue, reason: '$b vs $middle');
      expect(_distance(c, last), lessThan(_distance(c, middle)));
      // No step anywhere along it: one gradient, not segments.
      for (var x = 31; x < 270; x++) {
        expect(
          _distance(at(x, 1), at(x - 1, 1)),
          lessThan(0.03),
          reason: 'at $x',
        );
      }
      // Each side its end's colour.
      expect(_near(at(1, 100), first), isTrue);
      expect(_near(at(298, 100), last), isTrue);
    });
  }
}
