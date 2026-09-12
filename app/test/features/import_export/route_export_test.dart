import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/core/files/track_exporter.dart';
import 'package:velorki/features/planner/data/route_repository.dart';
import 'package:velorki/features/planner/domain/routing_options.dart';
import 'package:velorki/features/planner/domain/saved_route.dart';
import 'package:velorki/features/planner/domain/waypoint.dart';
import 'package:velorki_geo/velorki_geo.dart';

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

  /// When set, [share] throws it instead of recording.
  Object? failure;

  @override
  Future<void> share({
    required String name,
    required List<TrackPoint> points,
    required TrackKind kind,
    required TrackFormat format,
    DateTime? startTime,
  }) async {
    final error = failure;
    if (error != null) throw error;
    calls.add(_Export(name, kind, format, points.length));
  }
}

Future<SavedRoute> _seed(PlannerHarness h) =>
    RouteRepository(
      h.db.routesDao,
      clock: () => DateTime.utc(2026, 9, 12, 10),
    ).savePlannedRoute(
      name: 'Isar loop',
      route: syntheticRoute(),
      waypoints: const [
        Waypoint(pos: LatLng(48.0, 11.0), kind: WaypointKind.start),
        Waypoint(pos: LatLng(48.04, 11.04), kind: WaypointKind.end),
      ],
      options: const RoutingOptions(),
    );

Future<void> _openExportMenu(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(OutlinedButton, 'Export'));
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
    expect(find.text('GPX route'), findsOneWidget);
    expect(find.text('FIT course'), findsOneWidget);

    await tester.tap(find.text('GPX route'));
    await tester.pumpAndSettle();

    expect(exporter.calls, hasLength(1));
    final call = exporter.calls.single;
    expect(call.name, 'Isar loop');
    expect(call.kind, TrackKind.route);
    expect(call.format, TrackFormat.gpx);
    expect(call.pointCount, saved.geometry.length);
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
    await tester.tap(find.text('FIT course'));
    await tester.pumpAndSettle();

    expect(exporter.calls.single.format, TrackFormat.fit);
    expect(exporter.calls.single.kind, TrackKind.route);
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
    await tester.tap(find.text('GPX route'));
    await tester.pumpAndSettle();

    expect(find.text('The file could not be exported.'), findsOneWidget);
    await unmountApp(tester);
  });
}
