import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/app/shell_layout.dart';
import 'package:velorki/features/map/presentation/map_attribution.dart';
import 'package:velorki/features/recording/domain/recording_snapshot.dart';
import 'package:velorki/features/shared/presentation/docking_sheet.dart';
import 'package:velorki/features/shared/presentation/floating_bar.dart';
import 'package:velorki/features/shared/presentation/gesture_zone_guard.dart';

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
          child: const Center(
            child: GestureZonePassThrough(child: MapAttributionChip()),
          ),
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
          'and opens its notice, with the sheet docked', (tester) async {
        const size = Size(390, 844);
        _shape(tester, size, phone);
        await pumpRecordingApp(
          tester,
          harness: _harness(),
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
        if (phone.zone > 0) {
          expect(
            chip.bottom,
            size.height - 6,
            reason: 'in the band under the bar',
          );
          expect(chip.bottom, greaterThan(size.height - phone.zone));
        } else {
          // The bar reaches down to the edge: the credit goes above it and
          // above the strip of the sheet docked on it.
          final glassTop =
              size.height -
              phone.bottom -
              floatingBarBottomGap -
              floatingBarHeight;
          expect(bar.bottom, size.height - phone.bottom - floatingBarBottomGap);
          expect(chip.bottom, glassTop - sheetHandleDp - 6);
          expect(
            chip.bottom,
            lessThanOrEqualTo(
              tester.getRect(find.byType(DockingSheetShell)).top,
            ),
          );
        }
        await tester.tap(find.byType(MapAttributionChip));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
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
