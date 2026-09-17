import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/app/theme.dart';
import 'package:velorki/features/navigation/application/navigation_controller.dart';
import 'package:velorki/features/navigation/domain/navigation_progress.dart';
import 'package:velorki/features/navigation/domain/off_route_guidance.dart';
import 'package:velorki/features/navigation/presentation/turn_banner.dart';
import 'package:velorki/features/shared/presentation/stat_tile.dart';
import 'package:velorki/l10n/generated/app_localizations.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../support/units.dart';

const TurnHint _left = TurnHint(pointIndex: 10, kind: TurnKind.left);

/// A way back onto the route, 120 m off to the left.
const OffRouteGuidance _wayBack = OffRouteGuidance(
  target: LatLng(48, 11),
  distanceM: 120,
  alongM: 400,
  direction: RelativeDirection.left,
);

/// A navigation controller that only remembers what it was asked for, so the
/// banner's buttons can be tapped without a ride behind them.
class _RecordingNav extends NavigationController {
  int rejoins = 0;
  int reroutes = 0;

  @override
  NavigationProgress? build() => null;

  @override
  void requestRejoin() => rejoins++;

  @override
  void requestFullReroute() => reroutes++;
}

const TurnHint _keepRight = TurnHint(pointIndex: 14, kind: TurnKind.keepRight);

/// Pumps the banner with the navigation settings [preferences] describes.
///
/// Returns the container, so a test can read the ride-only mute the button
/// writes to.
Future<ProviderContainer> _pumpBanner(
  WidgetTester tester,
  NavigationProgress progress, {
  Override? units,
  Map<String, Object> preferences = const <String, Object>{},
  NavigationController? navigation,
  Locale? locale,
  double? width,
}) async {
  SharedPreferences.setMockInitialValues(preferences);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      units ?? metricUnits,
      sharedPreferencesProvider.overrideWithValue(prefs),
      if (navigation != null)
        navigationControllerProvider.overrideWith(() => navigation),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildLightTheme(),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            // A width stands in for the phone the banner really runs on: the
            // test surface is 800 logical pixels wide, where even the longest
            // German instruction would never have to wrap.
            child: SizedBox(
              width: width,
              child: TurnBanner(progress: progress),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('the banner shows the distance and the instruction', (
    tester,
  ) async {
    await _pumpBanner(
      tester,
      const NavigationProgress(next: _left, distanceToNextM: 248),
    );

    expect(find.text('250 m'), findsOneWidget);
    expect(find.text('Turn left'), findsOneWidget);
    expect(find.byIcon(Icons.turn_left), findsOneWidget);
    expect(find.textContaining('then'), findsNothing);
  });

  testWidgets('a turn close behind the next one is a second arrow', (
    tester,
  ) async {
    await _pumpBanner(
      tester,
      const NavigationProgress(
        next: _left,
        distanceToNextM: 120,
        after: _keepRight,
      ),
    );

    expect(find.text('120 m'), findsOneWidget);
    expect(find.text('Turn left'), findsOneWidget);
    // The preview is an arrow on the same row, not a "then ..." line.
    expect(find.byIcon(Icons.fork_right), findsOneWidget);
    expect(find.textContaining('then'), findsNothing);
    expect(tester.getSize(find.byType(GlassPanel)).height, turnBannerHeight);
  });

  testWidgets('kilometres are shown with one decimal', (tester) async {
    await _pumpBanner(
      tester,
      const NavigationProgress(next: _left, distanceToNextM: 1420),
    );

    expect(find.text('1.4 km'), findsOneWidget);
  });

  testWidgets('leaving the route replaces the turn with a warning', (
    tester,
  ) async {
    await _pumpBanner(
      tester,
      const NavigationProgress(
        next: _left,
        distanceToNextM: 300,
        offRoute: true,
      ),
    );

    expect(find.text('Off route'), findsOneWidget);
    expect(find.text('Turn left'), findsNothing);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('a way back being worked out replaces the warning', (
    tester,
  ) async {
    await _pumpBanner(
      tester,
      const NavigationProgress(
        next: _left,
        distanceToNextM: 300,
        offRoute: true,
        rerouting: true,
      ),
    );

    expect(find.text('Recalculating…'), findsOneWidget);
    expect(find.text('Off route'), findsNothing);
    expect(find.byIcon(Icons.autorenew), findsOneWidget);
  });

  testWidgets('the end of the route says so', (tester) async {
    await _pumpBanner(tester, const NavigationProgress(arrived: true));

    expect(find.text('You have arrived'), findsOneWidget);
    expect(find.byIcon(Icons.flag), findsOneWidget);
  });

  testWidgets('the banner stays inside the room the screen reserves', (
    tester,
  ) async {
    await _pumpBanner(
      tester,
      const NavigationProgress(
        next: _left,
        distanceToNextM: 120,
        after: _keepRight,
      ),
    );

    final size = tester.getSize(find.byType(TurnBanner));
    expect(size.height, turnBannerHeight);
    expect(turnBannerHeight, lessThanOrEqualTo(56));
  });

  testWidgets('the banner is only as wide as its content', (tester) async {
    await _pumpBanner(
      tester,
      const NavigationProgress(
        next: _left,
        distanceToNextM: 120,
        after: _keepRight,
      ),
    );

    final banner = tester.getSize(find.byType(TurnBanner)).width;
    final panel = tester.getSize(find.byType(GlassPanel)).width;
    expect(panel, lessThan(banner));
    // Left-aligned: the panel starts where the banner does.
    expect(
      tester.getTopLeft(find.byType(GlassPanel)).dx,
      tester.getTopLeft(find.byType(TurnBanner)).dx,
    );
  });

  testWidgets('imperial shows feet and miles', (tester) async {
    await _pumpBanner(
      tester,
      const NavigationProgress(next: _left, distanceToNextM: 120),
      units: imperialUnits,
    );

    expect(find.text('390 ft'), findsOneWidget);
    expect(find.text('Turn left'), findsOneWidget);

    await _pumpBanner(
      tester,
      const NavigationProgress(next: _left, distanceToNextM: 1400),
      units: imperialUnits,
    );

    expect(find.text('0.9 mi'), findsOneWidget);
  });

  testWidgets('the mute button is there while the voice is on', (tester) async {
    final container = await _pumpBanner(
      tester,
      const NavigationProgress(next: _left, distanceToNextM: 248),
    );

    expect(find.byIcon(Icons.volume_up), findsOneWidget);
    expect(find.byIcon(Icons.volume_off), findsNothing);
    expect(container.read(voiceMutedForRideProvider), isFalse);
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).tooltip,
      'Mute the voice for this ride',
    );
  });

  testWidgets('a silent ride has nothing to mute', (tester) async {
    await _pumpBanner(
      tester,
      const NavigationProgress(next: _left, distanceToNextM: 248),
      preferences: const <String, Object>{'navigation.voice': false},
    );

    expect(find.byIcon(Icons.volume_up), findsNothing);
    expect(find.byIcon(Icons.volume_off), findsNothing);
    expect(find.byType(IconButton), findsNothing);
  });

  testWidgets('the button mutes the ride and gives the voice back', (
    tester,
  ) async {
    final container = await _pumpBanner(
      tester,
      const NavigationProgress(next: _left, distanceToNextM: 248),
    );

    await tester.tap(find.byIcon(Icons.volume_up));
    await tester.pumpAndSettle();

    expect(container.read(voiceMutedForRideProvider), isTrue);
    expect(find.byIcon(Icons.volume_off), findsOneWidget);
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).tooltip,
      'Unmute the voice',
    );

    await tester.tap(find.byIcon(Icons.volume_off));
    await tester.pumpAndSettle();

    expect(container.read(voiceMutedForRideProvider), isFalse);
    expect(find.byIcon(Icons.volume_up), findsOneWidget);
  });

  group('off the route', () {
    testWidgets('the way back replaces the turn, with how far and which way', (
      tester,
    ) async {
      await _pumpBanner(
        tester,
        const NavigationProgress(
          next: _left,
          distanceToNextM: 300,
          offRoute: true,
          offRouteState: OffRouteState.guiding,
          guidance: _wayBack,
        ),
      );

      expect(find.text('120 m'), findsOneWidget);
      expect(find.text('Back to the route, on your left'), findsOneWidget);
      expect(find.text('Turn left'), findsNothing);
      expect(find.text('Off route'), findsNothing);
      expect(find.byIcon(Icons.u_turn_left), findsOneWidget);
    });

    testWidgets('a direction nobody knows is simply left out', (tester) async {
      await _pumpBanner(
        tester,
        const NavigationProgress(
          offRouteState: OffRouteState.guiding,
          offRoute: true,
          guidance: OffRouteGuidance(
            target: LatLng(48, 11),
            distanceM: 120,
            alongM: 400,
          ),
        ),
      );

      expect(find.text('Back to the route'), findsOneWidget);
    });

    testWidgets('imperial reads the way back in feet', (tester) async {
      await _pumpBanner(
        tester,
        const NavigationProgress(
          offRouteState: OffRouteState.guiding,
          offRoute: true,
          guidance: _wayBack,
        ),
        units: imperialUnits,
      );

      expect(find.text('390 ft'), findsOneWidget);
    });

    testWidgets('the banner offers a new route from here', (tester) async {
      final navigation = _RecordingNav();
      await _pumpBanner(
        tester,
        const NavigationProgress(
          offRouteState: OffRouteState.guiding,
          offRoute: true,
          guidance: _wayBack,
        ),
        navigation: navigation,
      );

      expect(find.text('New route from here'), findsOneWidget);

      await tester.tap(find.text('New route from here'));
      await tester.pumpAndSettle();

      expect(navigation.reroutes, 1);
      expect(navigation.rejoins, 0, reason: 'the button is not the banner');
    });

    testWidgets('tapping the banner asks for a way back now', (tester) async {
      final navigation = _RecordingNav();
      await _pumpBanner(
        tester,
        const NavigationProgress(
          offRouteState: OffRouteState.guiding,
          offRoute: true,
          guidance: _wayBack,
        ),
        navigation: navigation,
      );

      await tester.tap(find.text('Back to the route, on your left'));
      await tester.pumpAndSettle();

      expect(navigation.rejoins, 1);
      expect(navigation.reroutes, 0);
    });

    testWidgets('off a way back that is already up is the plain warning', (
      tester,
    ) async {
      await _pumpBanner(
        tester,
        const NavigationProgress(
          offRoute: true,
          offRouteState: OffRouteState.detour,
        ),
      );

      expect(find.text('Off route'), findsOneWidget);
      expect(find.text('New route from here'), findsNothing);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('the way back stays one row high', (tester) async {
      await _pumpBanner(
        tester,
        const NavigationProgress(
          offRouteState: OffRouteState.guiding,
          offRoute: true,
          guidance: _wayBack,
        ),
      );

      expect(tester.getSize(find.byType(TurnBanner)).height, turnBannerHeight);
      expect(tester.getSize(find.byType(GlassPanel)).height, turnBannerHeight);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('the mute button leaves the banner one row', (tester) async {
    await _pumpBanner(
      tester,
      const NavigationProgress(
        next: _left,
        distanceToNextM: 120,
        after: _keepRight,
      ),
    );

    final banner = tester.getSize(find.byType(TurnBanner));
    final panel = tester.getSize(find.byType(GlassPanel));
    expect(banner.height, turnBannerHeight);
    expect(panel.height, turnBannerHeight);
    expect(panel.width, lessThan(banner.width));
  });

  group('a long instruction', () {
    // Narrow enough that a German instruction has to wrap, wide enough that
    // it still can: the test font draws every glyph as a square of the font
    // size, so a word here is about twice as wide as the same word on a
    // phone, and a phone's 369 logical pixels would leave no room at all.
    const double phone = 600;

    /// The paragraph [text] is drawn in, to ask what it did with the room.
    RenderParagraph paragraph(WidgetTester tester, String text) =>
        tester.renderObject<RenderParagraph>(find.text(text));

    testWidgets('a long German turn wraps instead of being cut off', (
      tester,
    ) async {
      await _pumpBanner(
        tester,
        const NavigationProgress(
          next: TurnHint(
            pointIndex: 10,
            kind: TurnKind.roundabout,
            exitNumber: 2,
          ),
          distanceToNextM: 248,
        ),
        locale: const Locale('de'),
        width: phone,
      );

      const String instruction = 'Im Kreisverkehr die 2. Ausfahrt nehmen';
      expect(find.text(instruction), findsOneWidget);
      // Every word of it is on screen: no ellipsis, no clipped last line.
      expect(paragraph(tester, instruction).didExceedMaxLines, isFalse);
      expect(tester.widget<Text>(find.text(instruction)).overflow, isNull);
      // It did not fit on one line, so it took the second one.
      expect(tester.widget<Text>(find.text(instruction)).maxLines, 2);
      expect(paragraph(tester, instruction).size.height, greaterThan(20));
      // And the distance is still the figure it was.
      expect(find.text('250 m'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('250 m')).style?.fontSize,
        buildLightTheme().textTheme.statMedium.fontSize,
      );
      // All of it inside the row the screen reserved.
      expect(tester.getSize(find.byType(TurnBanner)).height, turnBannerHeight);
      expect(tester.getSize(find.byType(GlassPanel)).height, turnBannerHeight);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the German turns that used to be cut off are whole', (
      tester,
    ) async {
      for (final (TurnKind kind, String instruction) in <(TurnKind, String)>[
        (TurnKind.right, 'Rechts abbiegen'),
        (TurnKind.sharpLeft, 'Scharf links abbiegen'),
        (TurnKind.slightRight, 'Leicht rechts abbiegen'),
      ]) {
        await _pumpBanner(
          tester,
          NavigationProgress(
            next: TurnHint(pointIndex: 10, kind: kind),
            distanceToNextM: 248,
            after: _keepRight,
          ),
          locale: const Locale('de'),
          width: phone,
        );

        expect(find.text(instruction), findsOneWidget);
        expect(paragraph(tester, instruction).didExceedMaxLines, isFalse);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('a short English turn keeps the one-line look', (tester) async {
      await _pumpBanner(
        tester,
        const NavigationProgress(
          next: _left,
          distanceToNextM: 248,
          after: _keepRight,
        ),
        width: phone,
      );

      final Text text = tester.widget<Text>(find.text('Turn left'));
      expect(text.maxLines, 1);
      // Full size, not shrunk to make room for a line it does not need.
      expect(
        text.style?.fontSize,
        buildLightTheme().textTheme.titleSmall?.fontSize,
      );
      expect(paragraph(tester, 'Turn left').didExceedMaxLines, isFalse);
    });
  });
}
