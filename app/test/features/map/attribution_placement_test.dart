import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/features/map/presentation/map_attribution.dart';
import 'package:velorki/features/recording/domain/recording_snapshot.dart';

import '../../support/app.dart';
import '../planner/support/pump.dart' show TestMapView;
import '../recording/support/pump.dart';

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
  });
}
