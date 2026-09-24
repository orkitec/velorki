import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/core/files/track_exporter.dart';
import 'package:velorki/features/planner/data/route_repository.dart';
import 'package:velorki/features/planner/domain/routing_options.dart';
import 'package:velorki/features/planner/domain/saved_route.dart';
import 'package:velorki/features/planner/domain/waypoint.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';
import 'package:velorki/features/planner/domain/route_poi.dart';

import '../../support/app.dart';
import '../planner/support/fakes.dart';
import '../planner/support/pump.dart';

/// One recorded call to [TrackExporter.share].
class _Export {
  const _Export(this.name, this.kind, this.format, this.pointCount);

  final String name;
  final TrackKind kind;
  final TrackFormat format;
  final int pointCount;

  @override
  String toString() => '$name ${kind.name}/${format.name} ($pointCount)';
}

class _RecordingExporter implements TrackExporter {
  final List<_Export> calls = <_Export>[];

  /// The points of interest handed over with each call.
  final List<List<RoutePoi>> exportedPois = <List<RoutePoi>>[];
  final List<List<TurnHint>> exportedTurns = <List<TurnHint>>[];

  /// When set, [share] throws it instead of recording.
  Object? failure;

  @override
  Future<void> share({
    required String name,
    required List<TrackPoint> points,
    required TrackKind kind,
    required TrackFormat format,
    DateTime? startTime,
    List<RoutePoi> pois = const <RoutePoi>[],
    List<TurnHint> turns = const <TurnHint>[],
    List<double?> temperaturesC = const <double?>[],
    List<DateTime> lapEnds = const <DateTime>[],
  }) async {
    exportedTurns.add(turns);
    final error = failure;
    if (error != null) throw error;
    calls.add(_Export(name, kind, format, points.length));
    exportedPois.add(pois);
  }
}

Future<SavedRoute> _seed(PlannerHarness h) =>
    RouteRepository(
      h.db.routesDao,
      clock: () => DateTime.utc(2026, 9, 12, 10),
    ).savePlannedRoute(
      name: 'Isar loop',
      route: syntheticRoute(
        turns: const [
          TurnHint(pointIndex: 2, kind: TurnKind.left),
          TurnHint(pointIndex: 4, kind: TurnKind.end),
        ],
      ),
      waypoints: const [
        Waypoint(pos: LatLng(48.0, 11.0), kind: WaypointKind.start),
        Waypoint(pos: LatLng(48.04, 11.04), kind: WaypointKind.end),
      ],
      options: const RoutingOptions(),
    );

Future<void> _openExportMenu(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(OutlinedButton, l10n.routeDetailExport));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the export menu offers a GPX route and a FIT course', (
    tester,
  ) async {
    final h = PlannerHarness();
    final saved = await _seed(h);
    final exporter = _RecordingExporter();
    await pumpApp(
      tester,
      harness: h,
      initialLocation: routeDetailLocation(saved.id),
      extraOverrides: [trackExporterProvider.overrideWithValue(exporter)],
    );
    await tester.pumpAndSettle();

    await _openExportMenu(tester);
    expect(find.text(l10n.exportGpxRoute), findsOneWidget);
    expect(find.text(l10n.exportFitCourse), findsOneWidget);

    await tester.tap(find.text(l10n.exportGpxRoute));
    await tester.pumpAndSettle();

    expect(exporter.calls, hasLength(1));
    final call = exporter.calls.single;
    expect(call.name, 'Isar loop');
    expect(call.kind, TrackKind.route);
    expect(call.format, TrackFormat.gpx);
    expect(call.pointCount, saved.geometry.length);
    await unmountApp(tester);
  });

  testWidgets('a named waypoint and one with a note go out as points of '
      'interest beside the route\'s own', (tester) async {
    final h = PlannerHarness();
    final saved =
        await RouteRepository(
          h.db.routesDao,
          clock: () => DateTime.utc(2026, 9, 12, 10),
        ).savePlannedRoute(
          name: 'Isar loop',
          route: syntheticRoute(),
          waypoints: const [
            Waypoint(pos: LatLng(48.0, 11.0), kind: WaypointKind.start),
            Waypoint(
              pos: LatLng(48.02, 11.02),
              name: 'Bakery',
              poiKind: PoiKind.food,
              note: 'Croissants',
            ),
            Waypoint(pos: LatLng(48.03, 11.03), note: 'Cobbles'),
            Waypoint(pos: LatLng(48.04, 11.04), kind: WaypointKind.end),
          ],
          options: const RoutingOptions(),
        );
    final exporter = _RecordingExporter();
    await pumpApp(
      tester,
      harness: h,
      initialLocation: routeDetailLocation(saved.id),
      extraOverrides: [trackExporterProvider.overrideWithValue(exporter)],
    );
    await tester.pumpAndSettle();

    await _openExportMenu(tester);
    await tester.tap(find.text(l10n.exportGpxRoute));
    await tester.pumpAndSettle();

    expect(exporter.exportedPois.single, const [
      RoutePoi(
        pos: LatLng(48.02, 11.02),
        name: 'Bakery',
        description: 'Croissants',
        kind: PoiKind.food,
      ),
      RoutePoi(pos: LatLng(48.03, 11.03), name: '', description: 'Cobbles'),
    ]);
    await unmountApp(tester);
  });

  testWidgets('both sets go out: the places beside the route and the points '
      'on it that say something', (tester) async {
    final h = PlannerHarness();
    final saved =
        await RouteRepository(
          h.db.routesDao,
          clock: () => DateTime.utc(2026, 9, 12, 10),
        ).savePlannedRoute(
          name: 'Isar loop',
          route: syntheticRoute(),
          waypoints: const [
            Waypoint(pos: LatLng(48.0, 11.0), kind: WaypointKind.start),
            Waypoint(
              pos: LatLng(48.02, 11.02),
              name: 'Bakery',
              poiKind: PoiKind.food,
            ),
            Waypoint(pos: LatLng(48.04, 11.04), kind: WaypointKind.end),
          ],
          pois: const [
            RoutePoi(
              pos: LatLng(48.5, 11.5),
              name: 'Castle',
              kind: PoiKind.viewpoint,
            ),
          ],
          options: const RoutingOptions(),
        );
    final exporter = _RecordingExporter();
    await pumpApp(
      tester,
      harness: h,
      initialLocation: routeDetailLocation(saved.id),
      extraOverrides: [trackExporterProvider.overrideWithValue(exporter)],
    );
    await tester.pumpAndSettle();

    await _openExportMenu(tester);
    await tester.tap(find.text(l10n.exportGpxRoute));
    await tester.pumpAndSettle();

    expect(exporter.exportedPois.single.map((p) => p.name), [
      'Castle',
      'Bakery',
    ]);
    await unmountApp(tester);
  });

  testWidgets('the FIT entry exports a course', (tester) async {
    final h = PlannerHarness();
    final saved = await _seed(h);
    final exporter = _RecordingExporter();
    await pumpApp(
      tester,
      harness: h,
      initialLocation: routeDetailLocation(saved.id),
      extraOverrides: [trackExporterProvider.overrideWithValue(exporter)],
    );
    await tester.pumpAndSettle();

    await _openExportMenu(tester);
    await tester.tap(find.text(l10n.exportFitCourse));
    await tester.pumpAndSettle();

    expect(exporter.calls.single.format, TrackFormat.fit);
    expect(exporter.calls.single.kind, TrackKind.route);
    // The route's cue sheet goes with it, for the course points.
    expect(exporter.exportedTurns.single.map((t) => t.kind), [
      TurnKind.left,
      TurnKind.end,
    ]);

    // The TCX entry, too.
    await _openExportMenu(tester);
    await tester.tap(find.text(l10n.exportTcxCourse));
    await tester.pumpAndSettle();
    expect(exporter.calls.last.format, TrackFormat.tcx);
    expect(exporter.calls.last.kind, TrackKind.route);
    await unmountApp(tester);
  });

  testWidgets('a failing export says so instead of crashing', (tester) async {
    final h = PlannerHarness();
    final saved = await _seed(h);
    final exporter = _RecordingExporter()..failure = StateError('no sheet');
    await pumpApp(
      tester,
      harness: h,
      initialLocation: routeDetailLocation(saved.id),
      extraOverrides: [trackExporterProvider.overrideWithValue(exporter)],
    );
    await tester.pumpAndSettle();

    await _openExportMenu(tester);
    await tester.tap(find.text(l10n.exportGpxRoute));
    await tester.pumpAndSettle();

    expect(find.text(l10n.exportFailed), findsOneWidget);
    await unmountApp(tester);
  });
}
