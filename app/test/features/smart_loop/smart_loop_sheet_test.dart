import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/map/domain/map_controller.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/presentation/planner_screen.dart';
import 'package:velorki/features/shared/presentation/stat_tile.dart';
import 'package:velorki/features/smart_loop/application/loop_map_preview.dart';
import 'package:velorki/features/smart_loop/application/smart_loop_controller.dart';
import 'package:velorki/features/smart_loop/domain/loops.dart';
import 'package:velorki/features/smart_loop/presentation/smart_loop_sheet.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../planner/support/fakes.dart';
import '../planner/support/pump.dart';

const LatLng _start = LatLng(48.0, 11.0);

/// The provider container behind the screen under test.
ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(PlannerScreen)));

/// Scopes a finder to the sheet, so the planner's own chips and buttons
/// underneath the modal barrier do not match as well.
Finder _inSheet(Finder finder) =>
    find.descendant(of: find.byType(SmartLoopSheet), matching: finder);

/// The sheet's own scroll view; its form is longer than one screen.
Finder get _sheetList => _inSheet(find.byType(Scrollable)).first;

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 300, scrollable: _sheetList);
  await tester.pumpAndSettle();
}

/// Plots a start point and opens the loop sheet from the planner's bottom bar.
Future<PlannerHarness> _openSheet(
  WidgetTester tester, {
  PlannerHarness? harness,
}) async {
  final h = await pumpScreen(tester, const PlannerScreen(), harness: harness);
  h.map.onTap!(_start);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();

  await tester.tap(find.widgetWithText(LabeledIconButton, 'Loop'));
  await tester.pumpAndSettle();
  return h;
}

Future<void> _generate(WidgetTester tester) async {
  await tester.tap(_inSheet(find.widgetWithText(FilledButton, 'Generate')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the planner opens the loop sheet with its own defaults', (
    tester,
  ) async {
    await _openSheet(tester);

    expect(find.text('Smart loop'), findsOneWidget);
    // One waypoint is plotted, so the loop starts there.
    expect(
      tester
          .widget<ChoiceChip>(
            _inSheet(find.widgetWithText(ChoiceChip, 'First waypoint')),
          )
          .selected,
      isTrue,
    );
    // The fake map has no centre, so that option is not offered.
    expect(
      _inSheet(find.widgetWithText(ChoiceChip, 'Map centre')),
      findsNothing,
    );
    expect(_inSheet(find.text('40.0 km')), findsOneWidget);
    expect(
      _inSheet(find.widgetWithText(FilledButton, 'Generate')),
      findsOneWidget,
    );
  });

  testWidgets('the slider and the chips shape the request', (tester) async {
    await _openSheet(tester);

    await tester.drag(_inSheet(find.byType(Slider)), const Offset(2000, 0));
    await tester.pumpAndSettle();
    expect(_inSheet(find.text('150.0 km')), findsOneWidget);

    // The profile chips already sit below the fold of a phone-sized sheet.
    await _scrollTo(tester, _inSheet(find.widgetWithText(ChoiceChip, 'MTB')));
    await tester.tap(_inSheet(find.widgetWithText(ChoiceChip, 'MTB')));
    await tester.pumpAndSettle();

    // The rest of the form is below the fold too.
    await _scrollTo(tester, _inSheet(find.text('Seek')));
    await tester.tap(_inSheet(find.text('Seek')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: _inSheet(find.byType(SegmentedButton<Surface>)),
        matching: find.text('Gravel'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(_inSheet(find.byType(Switch)));
    await tester.pumpAndSettle();

    await _generate(tester);

    final request = _container(tester)
        .read(smartLoopControllerProvider)
        .request;
    expect(request, isNotNull);
    expect(request!.targetM, 150000);
    expect(request.profile, 'mtb');
    expect(request.prefs.hills, Hills.seek);
    expect(request.prefs.surface, Surface.gravel);
    expect(request.prefs.avoidTraffic, isFalse);
    expect(request.start, _start);
  });

  testWidgets('generating renders a card per candidate and previews them', (
    tester,
  ) async {
    final h = await _openSheet(tester);

    await _generate(tester);
    await _scrollTo(tester, find.text('Loop 1'));

    expect(find.byType(LoopCandidateCard), findsNWidgets(3));
    expect(find.text('Loop 1'), findsOneWidget);
    expect(find.textContaining('Paved'), findsWidgets);
    expect(find.textContaining('Repeated'), findsWidgets);
    expect(find.textContaining('Score'), findsWidgets);

    // The three loops are on the map, the chosen one as the main line.
    expect(
      h.map.lines.keys,
      containsAll(<String>['loop-0', 'loop-1', 'loop-2']),
    );
    expect(h.map.styles[loopPreviewLineId(0)], RouteLineStyle.main);
    expect(h.map.styles[loopPreviewLineId(1)], RouteLineStyle.alternative);
  });

  testWidgets('tapping a card selects it and redraws the map', (tester) async {
    final h = await _openSheet(tester);
    await _generate(tester);
    await _scrollTo(tester, find.text('Loop 2'));

    await tester.tap(find.text('Loop 2'));
    await tester.pumpAndSettle();

    expect(_container(tester).read(smartLoopControllerProvider).selected, 1);
    expect(h.map.styles[loopPreviewLineId(1)], RouteLineStyle.main);
    expect(h.map.styles[loopPreviewLineId(0)], RouteLineStyle.alternative);
  });

  testWidgets('"Use this loop" hands the route to the planner', (tester) async {
    final h = await _openSheet(tester);
    await _generate(tester);

    final chosen = _container(tester)
        .read(smartLoopControllerProvider)
        .candidates
        .first;

    await tester.tap(
      _inSheet(find.widgetWithText(FilledButton, 'Use this loop')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Smart loop'), findsNothing);
    expect(find.text('Loop opened in the planner'), findsOneWidget);

    final planner = _container(tester).read(plannerControllerProvider);
    expect(planner.result, same(chosen.result));
    expect(planner.waypoints, isNotEmpty);
    expect(planner.isRouting, isFalse);
    // The preview lines are gone; the planner drew the route as its own.
    expect(h.map.lines.keys.where((id) => id.startsWith('loop-')), isEmpty);
    expect(h.map.lines.keys, contains('main'));
  });

  testWidgets('a loop nobody can route says so', (tester) async {
    final backend = FakeRoutingBackend()
      ..error = const RoutingException(
        kind: RoutingErrorKind.noRoute,
        message: 'position not mapped',
      );
    await _openSheet(tester, harness: PlannerHarness(backend: backend));

    await _generate(tester);
    final message = find.text(
      'No loop found, try a shorter distance or another via.',
    );
    await _scrollTo(tester, message);

    expect(message, findsOneWidget);
    expect(find.byType(LoopCandidateCard), findsNothing);
  });

  testWidgets('a broken routing server is reported', (tester) async {
    final backend = FakeRoutingBackend()
      ..error = const RoutingException(
        kind: RoutingErrorKind.network,
        message: 'connection refused',
      );
    await _openSheet(tester, harness: PlannerHarness(backend: backend));

    await _generate(tester);
    final message = find.text('Loop search failed: connection refused');
    await _scrollTo(tester, message);

    expect(message, findsOneWidget);
  });

  testWidgets('regenerating asks the routing server again', (tester) async {
    final h = await _openSheet(tester);
    await _generate(tester);
    final first = h.backend.callCount;

    await tester.tap(_inSheet(find.widgetWithText(TextButton, 'Regenerate')));
    await tester.pumpAndSettle();

    expect(h.backend.callCount, greaterThan(first));
    expect(
      _container(tester).read(smartLoopControllerProvider).candidates,
      hasLength(3),
    );
  });
}
