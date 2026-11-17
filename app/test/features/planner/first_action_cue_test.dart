import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/map/presentation/first_start_location.dart';
import 'package:velorki/features/map/presentation/visible_map_padding.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/presentation/first_action_cue.dart';
import 'package:velorki/features/planner/presentation/planner_screen.dart';
import 'package:velorki/features/planner/presentation/profile_chip_row.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../support/app.dart';
import 'support/fakes.dart';
import 'support/pump.dart';

final Finder _headlinePulse = find.byKey(firstActionCueHeadlinePulseKey);
final Finder _pulse = find.byKey(firstActionCuePulseKey);
final Finder _chipPulse = find.byKey(firstActionCueChipPulseKey);
final Finder _ring = find.byKey(firstActionCueRingKey);

/// Which of the cue's parts are drawn now, in their order.
List<String> _drawn() => [
  if (_headlinePulse.evaluate().isNotEmpty) 'headline',
  if (_pulse.evaluate().isNotEmpty) 'field',
  if (_chipPulse.evaluate().isNotEmpty) 'chip',
  if (_ring.evaluate().isNotEmpty) 'ring',
];

/// Whether the headline is drawn as it is: never faded, never moved.
void _expectHeadlinePlain() {
  for (final type in [Opacity, FadeTransition, Transform]) {
    expect(
      find.descendant(
        of: find.byType(FirstActionCueHeadline),
        matching: find.byType(type),
      ),
      findsNothing,
    );
  }
  expect(find.text(l10n.plannerEmptyState), findsOneWidget);
}

PlannerController _planner(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(PlannerScreen)))
        .read(plannerControllerProvider.notifier);

/// Lets the cue that has just ended by itself wait out its idle time and
/// start again, at the start of its second run.
Future<void> _waitForRepeat(WidgetTester tester) async {
  await tester.pump(
    FirstActionCue.idleAgainAfter - const Duration(milliseconds: 500),
  );
  expect(_drawn(), isEmpty);
  expect(tester.binding.hasScheduledFrame, isFalse);
  await tester.pump(const Duration(milliseconds: 600));
}

/// A harness whose map rests, from the start, over an area that is not
/// downloaded, so the not-downloaded chip is there from the first frames.
PlannerHarness _chipHarness() {
  final harness = PlannerHarness();
  harness.stopsCoverage.covered = (_) => false;
  harness.map
    ..zoom = 13
    ..center = const LatLng(48.05, 11.05)
    ..visibleBounds = const BoundingBox(
      south: 48.0,
      west: 11.0,
      north: 48.1,
      east: 11.1,
    );
  return harness;
}

/// Brings [map] to rest at [zoom] over an area that is not downloaded:
/// the chip shows from zoom 11.
void _showChip(TestMapController map, {double zoom = 13}) {
  map
    ..zoom = zoom
    ..center = const LatLng(48.05, 11.05)
    ..visibleBounds = const BoundingBox(
      south: 48.0,
      west: 11.0,
      north: 48.1,
      east: 11.1,
    );
  for (final listener in [...map.cameraIdleListeners]) {
    listener();
  }
}

void main() {
  testWidgets('the headline is simply there; after a moment its outline '
      'pulses, then the field\'s, then a ring spreads, once', (tester) async {
    await pumpScreen(tester, const PlannerScreen());
    var elapsed = 100;
    await tester.pump(const Duration(milliseconds: 100));
    _expectHeadlinePlain();
    expect(_drawn(), isEmpty);

    // Times since the cue started, each a little inside its window.
    Future<void> at(int ms) async {
      await tester.pump(Duration(milliseconds: ms - elapsed));
      elapsed = ms;
    }

    await at(450);
    expect(_drawn(), isEmpty);
    // 0.6–1.5 s: the headline's outline, the headline as it was.
    await at(700);
    expect(_drawn(), ['headline']);
    _expectHeadlinePlain();
    await at(1400);
    expect(_drawn(), ['headline']);
    // 1.5–1.7 s: a breath.
    await at(1600);
    expect(_drawn(), isEmpty);
    // 1.7–2.6 s: the field's.
    await at(1800);
    expect(_drawn(), ['field']);
    await at(2500);
    expect(_drawn(), ['field']);
    await at(2700);
    expect(_drawn(), isEmpty);
    // 2.8–3.9 s: no chip, so the ring comes next.
    await at(2900);
    expect(_drawn(), ['ring']);
    await at(3800);
    expect(_drawn(), ['ring']);
    await at(4000);
    expect(_drawn(), isEmpty);

    // Finite: it settles, and does not come back before the idle wait.
    await tester.pumpAndSettle();
    expect(_drawn(), isEmpty);
    await tester.pump(const Duration(seconds: 5));
    expect(_drawn(), isEmpty);
    expect(find.text(l10n.plannerEmptyState), findsOneWidget);
  });

  testWidgets('with the not-downloaded chip shown as it starts, the chip\'s '
      'outline pulses between the field\'s and the ring', (tester) async {
    // An app start over an area that is not downloaded: the chip is over
    // the map as the cue starts.
    final harness = PlannerHarness();
    harness.stopsCoverage.covered = (_) => false;
    harness.map
      ..zoom = 13
      ..center = const LatLng(48.05, 11.05)
      ..visibleBounds = const BoundingBox(
        south: 48.0,
        west: 11.0,
        north: 48.1,
        east: 11.1,
      );
    final h = await pumpScreen(
      tester,
      const PlannerScreen(),
      harness: harness,
      surfaceSize: const Size(360, 780),
    );
    for (final listener in [...h.map.cameraIdleListeners]) {
      listener();
    }
    await tester.pump();
    expect(find.text(l10n.searchAreaNotDownloaded), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 500));
    expect(_drawn(), isEmpty);
    await tester.pump(const Duration(milliseconds: 500));
    expect(_drawn(), ['headline']);
    await tester.pump(const Duration(milliseconds: 1000));
    expect(_drawn(), ['field']);
    // 2.8–3.7 s: the chip's.
    await tester.pump(const Duration(milliseconds: 1000));
    expect(_drawn(), ['chip']);
    expect(
      find.descendant(
        of: find.byType(FirstActionCueChipPulse),
        matching: find.text(l10n.searchAreaNotDownloaded),
      ),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(_drawn(), ['chip']);
    // 3.7–3.9 s: a breath; then 3.9–5.0 s the ring.
    await tester.pump(const Duration(milliseconds: 200));
    expect(_drawn(), isEmpty);
    await tester.pump(const Duration(milliseconds: 200));
    expect(_drawn(), ['ring']);
    await tester.pump(const Duration(milliseconds: 900));
    expect(_drawn(), ['ring']);
    await tester.pump(const Duration(milliseconds: 200));
    expect(_drawn(), isEmpty);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('on a normal start with the chip over the map from the first '
      'frames, the run has the chip\'s step', (tester) async {
    final harness = _chipHarness();
    final h = await pumpScreen(
      tester,
      const PlannerScreen(),
      harness: harness,
      surfaceSize: const Size(360, 780),
    );
    expect(h.map, same(harness.map));
    await tester.pump();
    expect(find.text(l10n.searchAreaNotDownloaded), findsOneWidget);

    // pumpScreen has pumped one frame; times from there.
    await tester.pump(const Duration(milliseconds: 900));
    expect(_drawn(), ['headline']);
    await tester.pump(const Duration(milliseconds: 1000));
    expect(_drawn(), ['field']);
    await tester.pump(const Duration(milliseconds: 1000));
    expect(_drawn(), ['chip']);
    // Painted, and nothing around the chip cuts it off.
    expect(_chipPulse, paints..rrect());
    // A clip around it (the screen's own) leaves room for the outline.
    final outline = tester.getRect(_chipPulse).inflate(12);
    final clips = find.ancestor(
      of: _chipPulse,
      matching: find.byWidgetPredicate(
        (w) => w is ClipRect || w is ClipRRect || w is ClipPath,
      ),
    );
    for (final element in clips.evaluate()) {
      final clip = tester.getRect(find.byElementPredicate((e) => e == element));
      expect(clip.intersect(outline), outline);
    }
    await tester.pump(const Duration(milliseconds: 1100));
    expect(_drawn(), ['ring']);
    await tester.pumpAndSettle();
    expect(_drawn(), isEmpty);
  });

  testWidgets('a chip that comes before its step in the run is taken into '
      'it, the ring after it', (tester) async {
    final harness = PlannerHarness();
    harness.stopsCoverage.covered = (_) => false;
    final h = await pumpScreen(
      tester,
      const PlannerScreen(),
      harness: harness,
      surfaceSize: const Size(360, 780),
    );
    await tester.pump(const Duration(milliseconds: 1000));
    expect(_drawn(), ['headline']);
    _showChip(h.map);
    // The frame that shows the chip, and the cue's next.
    await tester.pump();
    await tester.pump();
    expect(_drawn(), ['headline']);
    await tester.pump(const Duration(milliseconds: 1000));
    expect(_drawn(), ['field']);
    // 2.8–3.7 s the chip's, 3.9–5.0 s the ring.
    await tester.pump(const Duration(milliseconds: 1000));
    expect(_drawn(), ['chip']);
    await tester.pump(const Duration(milliseconds: 1000));
    expect(_drawn(), ['ring']);
    await tester.pump(const Duration(milliseconds: 800));
    expect(_drawn(), ['ring']);
    await tester.pump(const Duration(milliseconds: 400));
    expect(_drawn(), isEmpty);
    // No pulse of its own after.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 300));
      expect(_drawn(), isEmpty);
    }
    await tester.pumpAndSettle();
  });

  testWidgets('a chip that comes after the cue started gets a pulse of its '
      'own once the run is over, and the ring is not played again', (
    tester,
  ) async {
    final harness = PlannerHarness();
    harness.stopsCoverage.covered = (_) => false;
    final h = await pumpScreen(
      tester,
      const PlannerScreen(),
      harness: harness,
      surfaceSize: const Size(360, 780),
    );
    await tester.pump(const Duration(milliseconds: 3000));
    expect(_drawn(), ['ring']);
    _showChip(h.map);
    await tester.pump();
    expect(find.text(l10n.searchAreaNotDownloaded), findsOneWidget);

    // The run goes on as it was: the ring to 3.9 s.
    await tester.pump(const Duration(milliseconds: 700));
    expect(_drawn(), ['ring']);
    // At 3.9 s the run ends; the chip's own pulse, 0.9 s, then nothing.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_drawn(), ['chip']);
    expect(_chipPulse, paints..rrect());
    await tester.pump(const Duration(milliseconds: 700));
    expect(_drawn(), ['chip']);
    await tester.pump(const Duration(milliseconds: 300));
    expect(_drawn(), isEmpty);
    await tester.pump(const Duration(seconds: 10));
    expect(_drawn(), isEmpty);
    await tester.pumpAndSettle();
    expect(_drawn(), isEmpty);
  });

  testWidgets('a chip that comes while the cue waits to play again pulses at '
      'once, and the run again comes the idle wait after that', (tester) async {
    final harness = PlannerHarness();
    harness.stopsCoverage.covered = (_) => false;
    final h = await pumpScreen(
      tester,
      const PlannerScreen(),
      harness: harness,
      surfaceSize: const Size(360, 780),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    _showChip(h.map);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(_drawn(), ['chip']);
    await tester.pump(const Duration(milliseconds: 900));
    expect(_drawn(), isEmpty);

    // 15 s from the pulse's end, not from the run's, which have passed.
    await tester.pump(const Duration(seconds: 12));
    expect(_drawn(), isEmpty);
    await tester.pump(const Duration(milliseconds: 2500));
    expect(_drawn(), isEmpty);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 1000));
    expect(_drawn(), ['headline']);
    await tester.pump(const Duration(milliseconds: 1000));
    expect(_drawn(), ['field']);
    await tester.pump(const Duration(milliseconds: 1000));
    expect(_drawn(), ['chip']);
    await tester.pump(const Duration(milliseconds: 1200));
    expect(_drawn(), ['ring']);
    await tester.pumpAndSettle();
    expect(_drawn(), isEmpty);
  });

  testWidgets('a chip that comes after a touch gets no pulse', (tester) async {
    final harness = PlannerHarness();
    harness.stopsCoverage.covered = (_) => false;
    final h = await pumpScreen(
      tester,
      const PlannerScreen(),
      harness: harness,
      surfaceSize: const Size(360, 780),
    );
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.tapAt(const Offset(180, 300));
    await tester.pump();
    _showChip(h.map);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 300));
      expect(_drawn(), isEmpty);
    }
    expect(find.text(l10n.searchAreaNotDownloaded), findsOneWidget);
  });

  testWidgets('a chip that goes and comes again gets one pulse of its own '
      'per empty state', (tester) async {
    final harness = PlannerHarness();
    harness.stopsCoverage.covered = (_) => false;
    final h = await pumpScreen(
      tester,
      const PlannerScreen(),
      harness: harness,
      surfaceSize: const Size(360, 780),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    _showChip(h.map);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(_drawn(), ['chip']);
    await tester.pump(const Duration(seconds: 1));
    expect(_drawn(), isEmpty);

    // Gone with a zoom out, back with a zoom in, while the cue waits.
    _showChip(h.map, zoom: 8);
    await tester.pump();
    expect(find.text(l10n.searchAreaNotDownloaded), findsNothing);
    _showChip(h.map);
    await tester.pump();
    expect(find.text(l10n.searchAreaNotDownloaded), findsOneWidget);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 300));
      expect(_drawn(), isEmpty);
    }
    await tester.pump(const Duration(seconds: 20));
    await tester.pumpAndSettle();
  });

  testWidgets('with animations off a late chip gets no pulse either', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final harness = PlannerHarness();
    harness.stopsCoverage.covered = (_) => false;
    final h = await pumpScreen(
      tester,
      const PlannerScreen(),
      harness: harness,
      surfaceSize: const Size(360, 780),
    );
    await tester.pump(const Duration(milliseconds: 1000));
    _showChip(h.map);
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 300));
      expect(_drawn(), isEmpty);
    }
  });

  testWidgets('left alone after it has played, it plays once more, and only '
      'once', (tester) async {
    await pumpScreen(tester, const PlannerScreen());
    await tester.pumpAndSettle();
    expect(_drawn(), isEmpty);

    await _waitForRepeat(tester);
    await tester.pump(const Duration(milliseconds: 1000));
    expect(_drawn(), ['headline']);
    await tester.pump(const Duration(milliseconds: 1000));
    expect(_drawn(), ['field']);
    await tester.pump(const Duration(milliseconds: 1000));
    expect(_drawn(), ['ring']);
    await tester.pumpAndSettle();
    expect(_drawn(), isEmpty);

    // Its second end asks for no third run.
    await tester.pump(const Duration(seconds: 20));
    expect(_drawn(), isEmpty);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a touch while it waits to play again calls it off', (
    tester,
  ) async {
    await pumpScreen(tester, const PlannerScreen());
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));

    await tester.tapAt(const Offset(400, 600));
    await tester.pump();
    await tester.pump(const Duration(seconds: 20));
    expect(_drawn(), isEmpty);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('stopped by a touch, it does not play again', (tester) async {
    await pumpScreen(tester, const PlannerScreen());
    await tester.pump(const Duration(milliseconds: 2000));
    expect(_drawn(), ['field']);

    await tester.tapAt(const Offset(400, 600));
    await tester.pump();
    expect(_drawn(), isEmpty);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 20));
    expect(_drawn(), isEmpty);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a point on the plan while it waits calls it off', (
    tester,
  ) async {
    await pumpScreen(tester, const PlannerScreen());
    await tester.pumpAndSettle();
    _planner(tester).addWaypoint(const LatLng(48.1, 11.5));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 20));
    expect(_drawn(), isEmpty);
  });

  testWidgets('a touch on the map ends it at once', (tester) async {
    await pumpScreen(tester, const PlannerScreen());
    await tester.pump(const Duration(milliseconds: 3300));
    expect(_ring, findsOneWidget);

    await tester.tapAt(const Offset(400, 600));
    await tester.pump();
    expect(_drawn(), isEmpty);
    _expectHeadlinePlain();
  });

  testWidgets('a tap on the search field ends it', (tester) async {
    await pumpScreen(tester, const PlannerScreen());
    await tester.pump(const Duration(milliseconds: 1000));
    expect(_drawn(), ['headline']);

    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    expect(_drawn(), isEmpty);
    await tester.pumpAndSettle();
  });

  testWidgets('it does not come back when the plan is empty again', (
    tester,
  ) async {
    await pumpScreen(tester, const PlannerScreen());
    await tester.pumpAndSettle();

    _planner(tester).addWaypoint(const LatLng(48.1, 11.5));
    await tester.pumpAndSettle();
    expect(find.text(l10n.plannerEmptyState), findsNothing);

    // Cleared: the empty state is back, quiet, however long it is left.
    _planner(tester).clear();
    await tester.pump();
    expect(find.text(l10n.plannerEmptyState), findsOneWidget);
    for (var i = 0; i < 30; i++) {
      expect(_drawn(), isEmpty);
      await tester.pump(const Duration(seconds: 1));
    }

    // Undone back to empty: the same.
    _planner(tester).addWaypoint(const LatLng(48.1, 11.5));
    await tester.pumpAndSettle();
    _planner(tester).undo();
    await tester.pump();
    expect(find.text(l10n.plannerEmptyState), findsOneWidget);
    for (var i = 0; i < 30; i++) {
      expect(_drawn(), isEmpty);
      await tester.pump(const Duration(seconds: 1));
    }
  });

  testWidgets('with animations off the text is simply there', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpScreen(tester, const PlannerScreen());
    for (var i = 0; i < 20; i++) {
      _expectHeadlinePlain();
      expect(_drawn(), isEmpty);
      await tester.pump(const Duration(milliseconds: 300));
    }
    // Nor again once it would have played.
    await tester.pump(const Duration(seconds: 20));
    expect(_drawn(), isEmpty);
  });

  testWidgets('switched off, nothing moves', (tester) async {
    await pumpScreen(
      tester,
      const PlannerScreen(),
      extraOverrides: [firstActionCueEnabledProvider.overrideWithValue(false)],
    );
    for (var i = 0; i < 20; i++) {
      _expectHeadlinePlain();
      expect(_drawn(), isEmpty);
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tester.pump(const Duration(seconds: 20));
    expect(_drawn(), isEmpty);
  });

  testWidgets('the ring spreads from the middle of the map left visible', (
    tester,
  ) async {
    // The window as large as the screen the harness lays out in, as on a
    // phone, where the two are one.
    tester.view
      ..physicalSize = const Size(1000, 2000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpScreen(tester, const PlannerScreen());
    await tester.pump(const Duration(milliseconds: 3300));
    final painter =
        tester.widget<CustomPaint>(_ring).painter! as FirstActionCueRingPainter;
    final element = tester.element(find.byType(PlannerScreen));
    final width = tester.getSize(find.byType(PlannerScreen)).width;
    // Beside the control column at the right.
    expect(
      painter.centre.dx,
      closeTo((width - mapControlsWidth(element)) / 2, 0.5),
    );
    // Between the chrome and the resting sheet, halfway.
    final chromeBottom = tester.getBottomLeft(find.byType(ProfileChipRow)).dy;
    final sheetTop = tester.getTopLeft(find.byType(DraggableScrollableSheet));
    final sheet = tester.widget<DraggableScrollableSheet>(
      find.byType(DraggableScrollableSheet),
    );
    final height = tester.getSize(find.byType(PlannerScreen)).height;
    final top = sheetTop.dy + (1 - sheet.initialChildSize) * height;
    expect(painter.centre.dy, greaterThan(chromeBottom + 24));
    expect(painter.centre.dy, lessThan(top - 24));
    expect(painter.centre.dy, closeTo((chromeBottom + top) / 2, 10));
    await tester.pumpAndSettle();
  });

  testWidgets('after the first start\'s location question it runs once the '
      'dialog has gone, not skipped for it', (tester) async {
    await pumpScreen(
      tester,
      const PlannerScreen(),
      harness: PlannerHarness(locationQuestionDue: true),
    );
    final context = tester.element(find.byType(PlannerScreen));
    final asking = ProviderScope.containerOf(context)
        .read(firstStartLocationAskProvider.notifier);
    // The question's dialog, answered: it starts to close as the answer
    // comes, the way askLocationOnFirstStart ends.
    final navigator = Navigator.of(context, rootNavigator: true);
    final closed = showDialog<void>(
      context: context,
      builder: (_) => const AlertDialog(content: Text('?')),
    );
    await tester.pumpAndSettle();
    expect(_ring, findsNothing);
    navigator.pop();
    asking.done();
    await closed;
    // The wait for the dialog, then the cue up to its ring.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 3300));
    expect(_ring, findsOneWidget);
    await tester.pumpAndSettle();
  });
}
