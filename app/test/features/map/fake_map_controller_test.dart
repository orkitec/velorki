import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/map/testing/testing.dart';
import 'package:velorki_geo/velorki_geo.dart';

void main() {
  late FakeMapController controller;

  setUp(() => controller = FakeMapController());

  test('implements the MapController contract', () {
    expect(controller, isA<MapController>());
  });

  test('records camera moves and updates centre and zoom', () async {
    await controller.moveTo(const LatLng(47.0, 8.0), zoom: 12);
    await controller.moveTo(const LatLng(48.0, 9.0), animate: false);

    expect(controller.cameraMoves, [
      const RecordedCameraMove(
        center: LatLng(47.0, 8.0),
        zoom: 12,
        animate: true,
      ),
      const RecordedCameraMove(
        center: LatLng(48.0, 9.0),
        zoom: null,
        animate: false,
      ),
    ]);
    expect(controller.center, const LatLng(48.0, 9.0));
    // A move without a zoom leaves the zoom where it was.
    expect(controller.zoom, 12);
  });

  test('records fitBounds and adopts the bounds as visible', () async {
    const bounds = BoundingBox(south: 47, west: 8, north: 48, east: 9);

    await controller.fitBounds(bounds, paddingPx: 24);

    expect(controller.boundsFits, [
      const RecordedFitBounds(bounds: bounds, paddingPx: 24),
    ]);
    expect(controller.visibleBounds, bounds);
    expect(controller.center, bounds.center);
  });

  test('keeps route lines apart by id and records replacements', () async {
    await controller.setRouteLine('main', const [LatLng(0, 0), LatLng(1, 1)]);
    await controller.setRouteLine('alt0', const [
      LatLng(0, 0),
      LatLng(2, 2),
    ], style: RouteLineStyle.alternative);
    await controller.setRouteLine('main', const [LatLng(0, 0), LatLng(3, 3)]);

    expect(controller.routeLines.keys, ['main', 'alt0']);
    expect(controller.routeLines['main']!.points.last, const LatLng(3, 3));
    expect(controller.routeLines['alt0']!.style, RouteLineStyle.alternative);
    expect(controller.routeLineCalls, hasLength(3));
  });

  test('records route line removal and clearing', () async {
    await controller.setRouteLine('a', const [LatLng(0, 0), LatLng(1, 1)]);
    await controller.setRouteLine('b', const [LatLng(0, 0), LatLng(1, 1)]);

    await controller.removeRouteLine('a');
    expect(controller.removedRouteLines, ['a']);
    expect(controller.routeLines.keys, ['b']);

    await controller.clearRouteLines();
    expect(controller.clearRouteLinesCount, 1);
    expect(controller.routeLines, isEmpty);
  });

  test('records waypoints, track and position', () async {
    const waypoints = [
      MapWaypoint(position: LatLng(47, 8), kind: MapWaypointKind.start),
      MapWaypoint(position: LatLng(48, 9), kind: MapWaypointKind.end),
    ];

    await controller.setWaypoints(waypoints);
    await controller.setTrackLine(const [LatLng(47, 8), LatLng(47.5, 8.5)]);
    await controller.setPosition(
      const LatLng(47, 8),
      accuracyM: 7,
      headingDeg: 45,
      speedMps: 4.2,
    );

    expect(controller.waypoints, waypoints);
    expect(controller.waypointCalls, hasLength(1));
    expect(controller.trackLine, hasLength(2));
    expect(
      controller.position,
      const RecordedPosition(
        position: LatLng(47, 8),
        accuracyM: 7,
        headingDeg: 45,
        speedMps: 4.2,
      ),
    );
  });

  test('records a hidden puck and keeps every position call', () async {
    await controller.setPosition(const LatLng(47, 8), accuracyM: 7);
    await controller.setPosition(null);

    expect(controller.positionCalls, hasLength(2));
    expect(controller.position, const RecordedPosition());
  });

  test('records the CyclOSM toggle', () async {
    await controller.setCyclosmOverlay(true);
    await controller.setCyclosmOverlay(false);

    expect(controller.cyclosmOverlayCalls, [true, false]);
    expect(controller.cyclosmOverlay, isFalse);
  });

  test('fires the handlers a screen installed', () {
    LatLng? tapped;
    LatLng? longPressed;
    var idle = 0;
    (int, LatLng)? dragged;

    controller
      ..onTap = ((p) {
        tapped = p;
      })
      ..onLongPress = ((p) {
        longPressed = p;
      })
      ..onCameraIdle = (() {
        idle++;
      })
      ..onWaypointDragged = ((i, p) {
        dragged = (i, p);
      });

    controller
      ..emitTap(const LatLng(1, 2))
      ..emitLongPress(const LatLng(3, 4))
      ..emitWaypointDragged(2, const LatLng(5, 6))
      ..emitCameraIdle();

    expect(tapped, const LatLng(1, 2));
    expect(longPressed, const LatLng(3, 4));
    expect(dragged, (2, const LatLng(5, 6)));
    expect(idle, 1);
  });

  test('reset forgets the recordings but keeps the handlers', () async {
    var taps = 0;
    controller.onTap = (_) {
      taps++;
    };
    await controller.setRouteLine('a', const [LatLng(0, 0), LatLng(1, 1)]);
    await controller.setCyclosmOverlay(true);

    controller.reset();

    expect(controller.routeLines, isEmpty);
    expect(controller.routeLineCalls, isEmpty);
    expect(controller.cyclosmOverlay, isFalse);
    controller.emitTap(const LatLng(0, 0));
    expect(taps, 1);
  });
}
