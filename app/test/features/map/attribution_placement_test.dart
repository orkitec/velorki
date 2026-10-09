import 'package:flutter/gestures.dart' show HitTestResult;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/app/shell_layout.dart';
import 'package:velorki/features/map/presentation/map_attribution.dart';
import 'package:velorki/features/recording/domain/recording_snapshot.dart';
import 'package:velorki/features/shared/presentation/docking_sheet.dart';
import 'package:velorki/features/shared/presentation/floating_bar.dart';

import '../../support/app.dart';
import '../planner/support/pump.dart' show TestMapView;
import '../recording/support/pump.dart';

/// A harness whose map places the credit the way the real map view does.
RecordingHarness _harness() {
  final h = RecordingHarness();
  h.planner.mapViewBuilder = (onReady) => Stack(
    fit: StackFit.expand,
    children: [
      TestMapView(controller: h.map, onReady: onReady),
      Builder(
        builder: (context) => Positioned(
          left: 0,
          right: 0,
          bottom: mapAttributionBottom(context),
          child: const Center(child: MapAttributionChip()),
        ),
      ),
    ],
  );
  return h;
}

/// A phone's bottom edge: [bottom] the safe area (the home indicator on
/// iOS, the navigation bar on Android), [gestures] the system's gesture
/// inset there.
typedef _Phone = ({String name, double bottom, double gestures, double zone});

const _phones = <TargetPlatform, List<_Phone>>{
  TargetPlatform.iOS: [
    (name: 'Face ID', bottom: 34, gestures: 0, zone: 34),
    (name: 'home button', bottom: 0, gestures: 0, zone: 0),
  ],
  TargetPlatform.android: [
    (name: 'gesture navigation', bottom: 24, gestures: 32, zone: 32),
    (name: 'three buttons', bottom: 48, gestures: 0, zone: 0),
  ],
};

void _shape(
  WidgetTester tester,
  Size size,
  _Phone phone, {
  bool sideways = false,
}) {
  final ratio = tester.view.devicePixelRatio;
  tester.view.physicalSize = size * ratio;
  final inset = FakeViewPadding(
    top: sideways ? 0 : 47 * ratio,
    left: sideways ? 48 * ratio : 0,
    bottom: phone.bottom * ratio,
  );
  tester.view
    ..viewPadding = inset
    ..padding = inset
    ..systemGestureInsets = FakeViewPadding(bottom: phone.gestures * ratio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetViewPadding);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetSystemGestureInsets);
}

void main() {
  // A phone with a home indicator: the scaffold takes that inset off its body
  // only while the tab bar shows, which a ride on Record hides.
  testWidgets('the map credit sits in one place on Plan and on Record, '
      'before and during a ride', (tester) async {
    final inset = FakeViewPadding(
      top: 47 * tester.view.devicePixelRatio,
      bottom: 34 * tester.view.devicePixelRatio,
    );
    tester.view
      ..viewPadding = inset
      ..padding = inset;
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.view.resetPadding);
    final h = RecordingHarness();
    h.planner.mapViewBuilder = (onReady) => Stack(
      fit: StackFit.expand,
      children: [
        TestMapView(controller: h.map, onReady: onReady),
        // Placed the way the real map view places it.
        Builder(
          builder: (context) => Positioned(
            left: 0,
            right: 0,
            bottom: mapAttributionBottom(context),
            child: const Center(child: MapAttributionChip()),
          ),
        ),
      ],
    );
    await pumpRecordingApp(
      tester,
      harness: h,
      initialLocation: plannerRoute,
      surfaceSize: const Size(390, 844),
    );
    await tester.pumpAndSettle();
    Rect chip() => tester.getRect(find.byType(MapAttributionChip));

    final plan = chip();
    expect(plan.bottom, 844 - 6, reason: 'in the band under the tab bar');

    await tester.tap(find.text(l10n.tabRecord));
    await tester.pumpAndSettle();
    expect(chip(), plan, reason: 'Record, before a ride');

    await emitSnapshot(
      tester,
      h,
      RecordingSnapshot(
        rideId: 'ride-1',
        status: RecordingStatus.active,
        startedAt: DateTime.utc(2026, 9, 12, 10),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(FloatingNavigationBar), findsNothing);
    expect(chip(), plan, reason: 'Record, with the tab bar away for a ride');

    await unmountApp(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  for (final MapEntry(key: platform, value: phones) in _phones.entries) {
    for (final phone in phones) {
      testWidgets('${platform.name}, ${phone.name}: the credit is in view '
          'and takes no touch, with the sheet docked and during a ride', (
        tester,
      ) async {
        const size = Size(390, 844);
        _shape(tester, size, phone);
        final h = _harness();
        await pumpRecordingApp(
          tester,
          harness: h,
          initialLocation: plannerRoute,
          surfaceSize: size,
          expectTextFits: false,
        );
        await tester.pumpAndSettle();
        await tester.dragFrom(
          tester.getCenter(find.byType(SheetHandle)),
          const Offset(0, 900),
        );
        await tester.pumpAndSettle();
        final chip = tester.getRect(find.byType(MapAttributionChip));
        final bar = tester.getRect(
          find
              .descendant(
                of: find.byType(FloatingBarShell),
                matching: find.byType(Container),
              )
              .first,
        );
        // Nothing of the chip takes a touch: a tap on it opens nothing.
        final hit = HitTestResult();
        tester.binding.hitTestInView(hit, chip.center, tester.view.viewId);
        final chipObjects = {
          tester.renderObject(find.byType(MapAttributionChip)),
          for (final e
              in find
                  .descendant(
                    of: find.byType(MapAttributionChip),
                    matching: find.byWidgetPredicate((_) => true),
                  )
                  .evaluate())
            e.renderObject,
        };
        expect(hit.path.where((e) => chipObjects.contains(e.target)), isEmpty);
        if (phone.zone > 0) {
          expect(
            chip.bottom,
            size.height - 6,
            reason: 'in the band under the bar',
          );
          expect(chip.bottom, greaterThan(size.height - phone.zone));
          expect(bar.bottom, size.height - phone.bottom - floatingBarBottomGap);
        } else {
          // No zone: the bar stands a band higher, and the credit sits in
          // that band under it, on the safe area's edge.
          expect(
            bar.bottom,
            size.height -
                phone.bottom -
                floatingBarBottomGap -
                attributionBandHeight,
          );
          expect(chip.bottom, size.height - phone.bottom - 6);
          // Clear of the bar's glass (the test font sets the credit on two
          // lines at this width, so it is not measured against the bar's
          // bottom: on a phone it is one line of about 21 dp).
          expect(chip.bottom, greaterThan(bar.bottom));
          // Under it, the map: a tap there is the map's.
          final map = tester.renderObject(find.byType(TestMapView));
          expect(hit.path.any((e) => identical(e.target, map)), isTrue);
        }
        // The sheet's strip still meets the bar's top edge exactly.
        final strip = find.descendant(
          of: find.byType(DockingSheetShell),
          matching: find.byWidgetPredicate(
            (w) =>
                w is ClipRRect &&
                w.child is BackdropFilter &&
                (w.child! as BackdropFilter).child is DecoratedBox,
          ),
        );
        expect(tester.getRect(strip).bottom, closeTo(bar.top, 0.01));
        await tester.tapAt(chip.center);
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);

        // During a ride the figures bar takes the tab bar's place exactly,
        // and the credit stays where it was.
        await tester.tap(find.text(l10n.tabRecord));
        await tester.pumpAndSettle();
        await emitSnapshot(
          tester,
          h,
          RecordingSnapshot(
            rideId: 'ride-1',
            status: RecordingStatus.active,
            startedAt: DateTime.utc(2026, 9, 12, 10),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(FloatingNavigationBar), findsNothing);
        // Pulled down, the live sheet docks into its figures bar.
        await tester.dragFrom(
          tester.getCenter(find.byType(SheetHandle)),
          const Offset(0, 1500),
        );
        await tester.pumpAndSettle();
        final figures = tester.getRect(
          find
              .descendant(
                of: find.byType(FloatingBarShell),
                matching: find.byType(Container),
              )
              .first,
        );
        expect(figures, bar);
        expect(tester.getRect(find.byType(MapAttributionChip)), chip);
        await unmountApp(tester);
      }, variant: TargetPlatformVariant.only(platform));
    }
  }

  testWidgets('sideways without a zone the credit stays along the bottom', (
    tester,
  ) async {
    debugShellLayoutOverride = null;
    const channel = MethodChannel(ScreenSideChannel.channelName);
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'side' ? RailSide.left.name : null,
    );
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    const size = Size(844, 390);
    _shape(tester, size, (
      name: 'three buttons',
      bottom: 0,
      gestures: 0,
      zone: 0,
    ), sideways: true);
    await pumpRecordingApp(
      tester,
      harness: _harness(),
      initialLocation: plannerRoute,
      surfaceSize: size,
      expectTextFits: false,
    );
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(
      tester.getRect(find.byType(MapAttributionChip)).bottom,
      size.height - 6,
    );
    await unmountApp(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
