import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/app/shell_layout.dart';
import 'package:velorki/core/permissions/location_permission.dart';
import 'package:velorki/features/map/data/position_provider.dart';
import 'package:velorki/features/map/presentation/layers_sheet.dart';
import 'package:velorki/features/planner/presentation/planner_screen.dart';
import 'package:velorki/features/planner/presentation/waypoint_edit_sheet.dart';
import 'package:velorki/features/recording/domain/recording_snapshot.dart';
import 'package:velorki/features/recording/presentation/live_figures_view.dart';
import 'package:velorki/features/recording/presentation/recording_screen.dart';
import 'package:velorki/features/search/domain/search_result.dart';
import 'package:velorki/features/search/presentation/place_card.dart';
import 'package:velorki/features/shared/application/active_tab.dart';
import 'package:velorki/features/shared/application/covering_sheets.dart';
import 'package:velorki/features/shared/presentation/docking_sheet.dart';
import 'package:velorki/features/shared/presentation/stat_tile.dart';
import 'package:velorki/features/smart_loop/presentation/smart_loop_sheet.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../support/app.dart';
import '../assistant/support/fakes.dart';
import '../planner/support/pump.dart';
import '../recording/support/pump.dart' as rec;

const LatLng _a = LatLng(48.0, 11.0);
const LatLng _b = LatLng(48.2, 11.2);

const SearchResult _place = SearchResult(name: 'Munich', position: _a);

DockingSheetShell _shell(WidgetTester tester) =>
    tester.widget<DockingSheetShell>(find.byType(DockingSheetShell));

double _extent(WidgetTester tester) => _shell(tester).extent;

DraggableScrollableSheet _sheet(WidgetTester tester) => tester
    .widget<DraggableScrollableSheet>(find.byType(DraggableScrollableSheet));

int _covering(WidgetTester tester, Type screen) =>
    ProviderScope.containerOf(tester.element(find.byType(screen)))
        .read(coveringSheetsProvider);

/// Pulls the Plan sheet all the way open: an extent that is not its resting
/// one, which a restore has to come back to.
Future<double> _openFully(WidgetTester tester) async {
  await tester.dragFrom(
    tester.getCenter(find.byType(SheetHandle)),
    const Offset(0, -1500),
  );
  await tester.pumpAndSettle();
  final extent = _extent(tester);
  expect(extent, closeTo(_sheet(tester).maxChildSize, 0.001));
  return extent;
}

/// Closes the modal sheet on top.
Future<void> _closeTop(WidgetTester tester, Finder content) async {
  Navigator.of(tester.element(content)).pop();
  await tester.pumpAndSettle();
}

Future<PlannerHarness> _pumpPlanner(WidgetTester tester) => pumpScreen(
  tester,
  const PlannerScreen(),
  extraOverrides: [
    locationPermissionGatewayProvider.overrideWithValue(
      const GrantedLocationPermission(),
    ),
    positionSourceProvider.overrideWithValue(const FixedPositionSource(_a)),
  ],
);

void main() {
  group('the Plan sheet goes down under', () {
    final openers =
        <String, Future<Finder> Function(WidgetTester, PlannerHarness)>{
          'the Layers sheet': (tester, _) async {
            final context = tester.element(find.byType(PlannerScreen));
            unawaited(showLayersSheet(context));
            return find.byType(LayersSheet);
          },
          'a place card': (tester, _) async {
            final context = tester.element(find.byType(PlannerScreen));
            unawaited(showPlaceCard(context, place: _place));
            return find.byType(PlaceCard);
          },
          'a point\'s sheet': (tester, h) async {
            h.map.onWaypointTapped!(0);
            return find.byType(WaypointEditSheet);
          },
          'the loop sheet': (tester, _) async {
            await tester.tap(
              find.widgetWithText(LabeledIconButton, l10n.loopAction),
            );
            return find.byType(SmartLoopSheet);
          },
        };
    for (final MapEntry(key: name, value: open) in openers.entries) {
      testWidgets('$name, and comes back to where it was', (tester) async {
        final h = await _pumpPlanner(tester);
        h.map.onTap!(_a);
        h.map.onTap!(_b);
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        final before = await _openFully(tester);
        final collapsed = _sheet(tester).minChildSize;

        final content = await open(tester, h);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        // On its way down, not there at once.
        expect(_extent(tester), lessThan(before));
        expect(_extent(tester), greaterThan(collapsed + 0.01));
        await tester.pumpAndSettle();
        expect(content, findsOneWidget);
        expect(_extent(tester), closeTo(collapsed, 0.001));
        expect(_covering(tester, PlannerScreen), 1);

        await _closeTop(tester, content);
        expect(content, findsNothing);
        expect(_covering(tester, PlannerScreen), 0);
        expect(_extent(tester), closeTo(before, 0.001));
      });
    }
  });

  testWidgets('a place card with Open in over it keeps the Plan sheet down '
      'until the last one closes', (tester) async {
    await _pumpPlanner(tester);
    final before = await _openFully(tester);
    final collapsed = _sheet(tester).minChildSize;

    unawaited(
      showPlaceCard(tester.element(find.byType(PlannerScreen)), place: _place),
    );
    await tester.pumpAndSettle();
    expect(_extent(tester), closeTo(collapsed, 0.001));

    await tester.tap(find.text(l10n.placeCardOpenIn));
    await tester.pumpAndSettle();
    final openIn = find.text(l10n.placeCardOpenInTitle);
    expect(openIn, findsOneWidget);
    expect(_covering(tester, PlannerScreen), 2);
    expect(_extent(tester), closeTo(collapsed, 0.001));

    await _closeTop(tester, openIn);
    expect(find.byType(PlaceCard), findsOneWidget);
    expect(_covering(tester, PlannerScreen), 1);
    expect(_extent(tester), closeTo(collapsed, 0.001));

    await _closeTop(tester, find.byType(PlaceCard));
    expect(_covering(tester, PlannerScreen), 0);
    expect(_extent(tester), closeTo(before, 0.001));
  });

  testWidgets('a place picked in the search brings the sheet back to where '
      'it was before the search, not to its handle', (tester) async {
    await _pumpPlanner(tester);
    final before = await _openFully(tester);
    final collapsed = _sheet(tester).minChildSize;

    // The field parks the sheet at its handle while it has focus.
    await searchOnlineFor(tester, 'munich');
    expect(_extent(tester), closeTo(collapsed, 0.001));
    await tester.tap(find.text('Bavaria, Germany'));
    await tester.pumpAndSettle();
    expect(find.byType(PlaceCard), findsOneWidget);
    // Held down under the card, the search's own restore notwithstanding.
    expect(_extent(tester), closeTo(collapsed, 0.001));

    await tester.tap(find.byTooltip(l10n.placeCardClose));
    await tester.pumpAndSettle();
    expect(_extent(tester), closeTo(before, 0.001));
  });

  testWidgets('with reduced motion the sheet jumps down and back', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _pumpPlanner(tester);
    final before = await _openFully(tester);
    final collapsed = _sheet(tester).minChildSize;

    unawaited(showLayersSheet(tester.element(find.byType(PlannerScreen))));
    await tester.pump();
    expect(_extent(tester), closeTo(collapsed, 0.001));
    await tester.pumpAndSettle();

    Navigator.of(tester.element(find.byType(LayersSheet))).pop();
    await tester.pump();
    expect(_extent(tester), closeTo(before, 0.001));
    await tester.pumpAndSettle();
    expect(_extent(tester), closeTo(before, 0.001));
  });

  testWidgets('sideways the sheet stays where it is', (tester) async {
    debugShellLayoutOverride = const ShellLayout(sideRail: true);
    await rec.pumpRecordingApp(
      tester,
      initialLocation: plannerRoute,
      surfaceSize: const Size(874, 402),
      expectTextFits: false,
    );
    await tester.pumpAndSettle();
    final before = _extent(tester);

    unawaited(showLayersSheet(tester.element(find.byType(PlannerScreen))));
    await tester.pumpAndSettle();
    expect(find.byType(LayersSheet), findsOneWidget);
    expect(_extent(tester), closeTo(before, 0.001));

    await _closeTop(tester, find.byType(LayersSheet));
    expect(_extent(tester), closeTo(before, 0.001));
    await rec.unmountApp(tester);
  });

  testWidgets('a tab away from the screen leaves its sheet alone', (
    tester,
  ) async {
    await _pumpPlanner(tester);
    final before = await _openFully(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PlannerScreen)),
    );
    container.read(activeTabProvider.notifier).show(recordingRoute);
    await tester.pumpAndSettle();

    container.read(coveringSheetsProvider.notifier).opened();
    await tester.pumpAndSettle();
    expect(_extent(tester), closeTo(before, 0.001));
    container.read(coveringSheetsProvider.notifier).closed();
    await tester.pumpAndSettle();
    expect(_extent(tester), closeTo(before, 0.001));
  });

  testWidgets('during a ride the Record sheet goes down no further than '
      'where it folds into the figures bar', (tester) async {
    final h = await rec.pumpRecordingScreen(tester, const RecordingScreen());
    await tester.pump();
    await rec.emitSnapshot(
      tester,
      h,
      RecordingSnapshot(
        rideId: 'ride-1',
        status: RecordingStatus.active,
        startedAt: DateTime.utc(2026, 9, 12, 10),
        distanceM: 12345,
        elapsed: const Duration(minutes: 42),
        moving: const Duration(minutes: 40),
        speedMps: 6,
        avgSpeedMps: 5,
        ascentM: 210,
        descentM: 190,
        lastPosition: _a,
        accuracyM: 4,
        pointCount: 120,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(l10n.recordingStatusRecording.toUpperCase()),
      findsOneWidget,
    );
    final before = _extent(tester);
    final collapsed = _sheet(tester).minChildSize;
    expect(_shell(tester).docked, 0);

    unawaited(
      showPlaceCard(
        tester.element(find.byType(RecordingScreen)),
        place: _place,
        riderPosition: _a,
      ),
    );
    // Frame by frame: the figures bar never shows, nor does the sheet start
    // to fold into it.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byType(FiguresBar), findsNothing);
      expect(_shell(tester).docked, 0);
    }
    await tester.pumpAndSettle();
    expect(find.byType(PlaceCard), findsOneWidget);
    expect(_extent(tester), lessThan(before - 0.01));
    expect(_extent(tester), greaterThan(collapsed));
    expect(find.byType(FiguresBar), findsNothing);
    expect(_shell(tester).docked, 0);

    await _closeTop(tester, find.byType(PlaceCard));
    expect(_extent(tester), closeTo(before, 0.001));
    expect(find.byType(FiguresBar), findsNothing);
    await rec.unmountApp(tester);
  });
}
