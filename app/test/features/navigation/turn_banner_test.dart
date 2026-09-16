import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/app/theme.dart';
import 'package:velorki/features/navigation/application/navigation_controller.dart';
import 'package:velorki/features/navigation/domain/navigation_progress.dart';
import 'package:velorki/features/navigation/presentation/turn_banner.dart';
import 'package:velorki/features/shared/presentation/stat_tile.dart';
import 'package:velorki/l10n/generated/app_localizations.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

import '../../support/units.dart';

const TurnHint _left = TurnHint(pointIndex: 10, kind: TurnKind.left);
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
}) async {
  SharedPreferences.setMockInitialValues(preferences);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      units ?? metricUnits,
      sharedPreferencesProvider.overrideWithValue(prefs),
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
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: TurnBanner(progress: progress),
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
    expect(panel, lessThanOrEqualTo(banner * 0.8));
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

  testWidgets('the mute button leaves the banner one row and capped', (
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

    final banner = tester.getSize(find.byType(TurnBanner));
    final panel = tester.getSize(find.byType(GlassPanel));
    expect(banner.height, turnBannerHeight);
    expect(panel.height, turnBannerHeight);
    expect(panel.width, lessThanOrEqualTo(banner.width * 0.8));
  });
}
