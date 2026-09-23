import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/app/theme.dart';
import 'package:velorki/core/permissions/location_permission.dart';
import 'package:velorki/features/map/data/map_preferences.dart';
import 'package:velorki/features/map/data/position_provider.dart';
import 'package:velorki/features/map/presentation/map_attribution.dart';
import 'package:velorki/features/map/presentation/map_chrome.dart';
import 'package:velorki/features/map/presentation/map_controls.dart';
import 'package:velorki/features/map/presentation/visible_map_padding.dart';
import 'package:velorki/features/shared/presentation/stat_tile.dart';
import 'package:velorki/features/map/testing/testing.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../support/app.dart';

/// The address the OpenStreetMap licence link points at.
const String _osmUrl = 'https://www.openstreetmap.org/copyright';

Future<Widget> _wrap(
  Widget child, {
  bool cyclosm = false,
  List<Override> overrides = const <Override>[],
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'map.cyclosm_overlay': cyclosm,
  });
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      ...overrides,
    ],
    child: testApp(
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

/// A location permission that is simply there.
class _GrantedPermission implements LocationPermissionGateway {
  @override
  Future<LocationPermissionStatus> check() async =>
      LocationPermissionStatus.granted;

  @override
  Future<LocationPermissionStatus> request() async =>
      LocationPermissionStatus.granted;

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;
}

/// A [PositionSource] that always answers with one fix and no stream.
class _OneFixSource implements PositionSource {
  _OneFixSource(this.fix);

  final geo.Position fix;

  @override
  Stream<geo.Position> positions(geo.LocationSettings settings) =>
      const Stream<geo.Position>.empty();

  @override
  Future<geo.Position?> lastKnown() async => fix;

  @override
  Future<geo.Position?> current({
    Duration timeLimit = const Duration(seconds: 10),
  }) async => fix;
}

/// A [PositionSource] whose fix arrives when the test says so.
class _PendingFixSource implements PositionSource {
  final Completer<geo.Position?> fix = Completer<geo.Position?>();

  @override
  Stream<geo.Position> positions(geo.LocationSettings settings) =>
      const Stream<geo.Position>.empty();

  @override
  Future<geo.Position?> lastKnown() async => null;

  @override
  Future<geo.Position?> current({
    Duration timeLimit = const Duration(seconds: 10),
  }) => fix.future;
}

geo.Position _fixAt(double latitude, double longitude) => geo.Position(
  latitude: latitude,
  longitude: longitude,
  timestamp: DateTime.utc(2026, 9, 12, 10),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
  hasAccuracy: true,
);

/// The locate button's foreground colour, which says whether the map follows.
Color? _locateColor(WidgetTester tester) =>
    _buttonColor(tester, Icons.my_location);

/// The compass button's foreground colour, which says which follow style is on.
Color? _compassColor(WidgetTester tester) =>
    _buttonColor(tester, Icons.navigation);

Color? _buttonColor(WidgetTester tester, IconData icon) => tester
    .widget<IconButton>(find.widgetWithIcon(IconButton, icon))
    .style
    ?.foregroundColor
    ?.resolve(const <WidgetState>{});

/// How far the compass needle is turned inside its button, in radians.
double _needleAngle(WidgetTester tester) {
  final transform = tester
      .widget<Transform>(
        find
            .ancestor(
              of: find.byIcon(Icons.navigation),
              matching: find.byType(Transform),
            )
            .first,
      )
      .transform;
  return math.atan2(transform.storage[1], transform.storage[0]);
}

void main() {
  group('MapAttributionChip', () {
    testWidgets('names OpenStreetMap and OpenFreeMap', (tester) async {
      await tester.pumpWidget(await _wrap(const MapAttributionChip()));

      expect(
        find.text('${l10n.osmAttribution} · ${l10n.mapAttributionOpenFreeMap}'),
        findsOneWidget,
      );
    });

    testWidgets('adds CyclOSM while the overlay is on', (tester) async {
      await tester.pumpWidget(
        await _wrap(const MapAttributionChip(), cyclosm: true),
      );

      expect(find.textContaining(l10n.mapAttributionCyclosm), findsOneWidget);
    });

    testWidgets('opens the licence dialog with the source URLs', (
      tester,
    ) async {
      await tester.pumpWidget(await _wrap(const MapAttributionChip()));

      await tester.tap(find.byType(MapAttributionChip));
      await tester.pumpAndSettle();

      expect(find.text(l10n.mapAttributionTitle), findsWidgets);
      expect(find.text(_osmUrl), findsOneWidget);
      expect(find.text('https://openfreemap.org/'), findsOneWidget);
      // Not active, so it is not listed.
      expect(find.text('https://www.cyclosm.org/'), findsNothing);

      await tester.tap(find.text(l10n.mapAttributionClose));
      await tester.pumpAndSettle();
      expect(find.text(_osmUrl), findsNothing);
    });
  });

  group('MapControls', () {
    testWidgets('is inert without a controller', (tester) async {
      await tester.pumpWidget(await _wrap(const MapControls(controller: null)));

      final zoomIn = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.add),
      );
      expect(zoomIn.onPressed, isNull);
    });

    testWidgets('zooms in and out around the current centre', (tester) async {
      final controller = FakeMapController()
        ..center = const LatLng(47.0, 8.0)
        ..zoom = 10;

      await tester.pumpWidget(await _wrap(MapControls(controller: controller)));

      await tester.tap(find.widgetWithIcon(IconButton, Icons.add));
      await tester.pump();
      expect(controller.cameraMoves.last.zoom, 11);
      expect(controller.cameraMoves.last.center, const LatLng(47.0, 8.0));

      await tester.tap(find.widgetWithIcon(IconButton, Icons.remove));
      await tester.pump();
      expect(controller.cameraMoves.last.zoom, 10);
    });

    testWidgets('clamps the zoom to the MapLibre range', (tester) async {
      final controller = FakeMapController()
        ..center = const LatLng(0, 0)
        ..zoom = 22;

      await tester.pumpWidget(await _wrap(MapControls(controller: controller)));

      await tester.tap(find.widgetWithIcon(IconButton, Icons.add));
      await tester.pump();

      expect(controller.cameraMoves.single.zoom, 22);
    });

    testWidgets('toggles the app-wide CyclOSM setting and remembers it', (
      tester,
    ) async {
      final controller = FakeMapController();
      await tester.pumpWidget(await _wrap(MapControls(controller: controller)));
      final element = tester.element(find.byType(MapControls));
      final container = ProviderScope.containerOf(element);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.directions_bike));
      await tester.pumpAndSettle();

      expect(container.read(cyclosmOverlayProvider), isTrue);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.directions_bike));
      await tester.pumpAndSettle();

      expect(container.read(cyclosmOverlayProvider), isFalse);
      // The button drives the setting, not the one map it happens to sit on:
      // every map alive follows the setting through its PlannerMapHost, so a
      // toggle on one tab is not lost on the map of another.
      expect(controller.cyclosmOverlayCalls, isEmpty);
    });

    testWidgets('draws the CyclOSM button in the accent while it is on', (
      tester,
    ) async {
      final controller = FakeMapController();
      await tester.pumpWidget(
        await _wrap(MapControls(controller: controller), cyclosm: true),
      );
      await tester.pump();

      expect(
        _buttonColor(tester, Icons.directions_bike),
        buildLightTheme().velorki.accent,
      );
    });

    testWidgets('draws the locate button in the accent while following', (
      tester,
    ) async {
      final controller = FakeMapController();
      await tester.pumpWidget(
        await _wrap(
          MapChromeInsets(
            following: true,
            child: MapControls(controller: controller),
          ),
        ),
      );
      await tester.pump();

      expect(_locateColor(tester), buildLightTheme().velorki.accent);
    });

    testWidgets('draws it plainly when the map does not follow', (
      tester,
    ) async {
      final controller = FakeMapController();
      await tester.pumpWidget(await _wrap(MapControls(controller: controller)));
      await tester.pump();

      expect(_locateColor(tester), isNot(buildLightTheme().velorki.accent));
    });

    testWidgets('leaves the compass out without a screen behind it', (
      tester,
    ) async {
      final controller = FakeMapController();
      await tester.pumpWidget(await _wrap(MapControls(controller: controller)));
      await tester.pump();

      expect(find.byIcon(Icons.navigation), findsNothing);
    });

    testWidgets('offers the route button only when the screen has one, '
        'first in the column, accent while the route is shown', (tester) async {
      final controller = FakeMapController();
      await tester.pumpWidget(await _wrap(MapControls(controller: controller)));
      await tester.pump();
      expect(find.byIcon(Icons.route), findsNothing);

      var toggled = 0;
      await tester.pumpWidget(
        await _wrap(
          MapChromeInsets(
            routeShown: true,
            onToggleRoute: () => toggled++,
            child: MapControls(controller: controller),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.route), findsOneWidget);
      final route = tester.getTopLeft(find.byIcon(Icons.route));
      final locate = tester.getTopLeft(find.byIcon(Icons.my_location));
      expect(route.dy, lessThan(locate.dy));
      await tester.tap(find.byIcon(Icons.route));
      expect(toggled, 1);
    });

    testWidgets('a compass tap reaches the screen', (tester) async {
      final controller = FakeMapController();
      var compassed = 0;
      await tester.pumpWidget(
        await _wrap(
          MapChromeInsets(
            onCompass: () => compassed++,
            child: MapControls(controller: controller),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.navigation), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.navigation),
            )
            .tooltip,
        l10n.mapFollowNorthUp,
      );

      await tester.tap(find.widgetWithIcon(IconButton, Icons.navigation));
      await tester.pumpAndSettle();

      // The map itself is not touched: the screen owns the follow style.
      expect(controller.cameraMoves, isEmpty);
      expect(compassed, 1);
    });

    testWidgets('a compass tap names the style it switches to, briefly', (
      tester,
    ) async {
      final controller = FakeMapController();
      await tester.pumpWidget(
        await _wrap(
          MapChromeInsets(
            onCompass: () {},
            child: MapControls(controller: controller),
          ),
        ),
      );
      await tester.pump();

      // North-up is on, so the tap switches to heading-up and says so.
      await tester.tap(find.widgetWithIcon(IconButton, Icons.navigation));
      await tester.pump();
      expect(find.text(l10n.mapFollowHeadingUp), findsOneWidget);
      // A label, not a slab: the overlay offers the whole screen and the
      // hint must take only what its text needs.
      final slab = tester.getSize(
        find
            .ancestor(
              of: find.text(l10n.mapFollowHeadingUp),
              matching: find.byType(GlassPanel),
            )
            .first,
      );
      // The test font is a full em per glyph, so the bound is loose.
      expect(slab.width, lessThan(400));
      expect(slab.height, lessThan(48));

      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.text(l10n.mapFollowHeadingUp), findsNothing);
    });

    testWidgets('draws the compass in the accent in heading up', (
      tester,
    ) async {
      final controller = FakeMapController();
      await tester.pumpWidget(
        await _wrap(
          MapChromeInsets(
            following: true,
            headingUp: true,
            onCompass: () {},
            child: MapControls(controller: controller),
          ),
        ),
      );
      await tester.pump();

      expect(_compassColor(tester), buildLightTheme().velorki.accent);
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.navigation),
            )
            .tooltip,
        l10n.mapFollowHeadingUp,
      );
      // The locate button is a plain crosshair either way.
      expect(find.byIcon(Icons.my_location), findsOneWidget);
    });

    testWidgets('turns the needle against the map', (tester) async {
      final controller = FakeMapController();
      await tester.pumpWidget(
        await _wrap(
          MapChromeInsets(
            bearingDeg: 90,
            onCompass: () {},
            child: MapControls(controller: controller),
          ),
        ),
      );
      await tester.pump();

      // The map points east, so the needle turns a quarter turn back to keep
      // pointing at north.
      expect(_needleAngle(tester), closeTo(-math.pi / 2, 0.001));
    });

    testWidgets('tells the screen once it has moved to the fix', (
      tester,
    ) async {
      final controller = FakeMapController()..zoom = 10;
      var located = 0;
      await tester.pumpWidget(
        await _wrap(
          MapChromeInsets(
            onLocate: () => located++,
            child: MapControls(controller: controller),
          ),
          overrides: [
            locationPermissionGatewayProvider.overrideWithValue(
              _GrantedPermission(),
            ),
            positionSourceProvider.overrideWithValue(
              _OneFixSource(_fixAt(47.0, 8.0)),
            ),
          ],
        ),
      );
      await tester.pump();

      await tester.tap(find.widgetWithIcon(IconButton, Icons.my_location));
      await tester.pumpAndSettle();

      // The order matters: the screen's follow mode watches camera idles, so
      // the move has to be on its way before it is told.
      expect(controller.cameraMoves.single.center, const LatLng(47.0, 8.0));
      expect(controller.cameraMoves.single.zoom, locateZoom);
      expect(located, 1);
    });

    testWidgets('moves into the visible middle the shell describes', (
      tester,
    ) async {
      final controller = FakeMapController()..zoom = 10;
      // What the shell would say with the sheet at half the screen.
      const covered = EdgeInsets.fromLTRB(24, 154, 86, 1024);
      await tester.pumpWidget(
        await _wrap(
          MapChromeInsets(
            visiblePadding: () => covered,
            child: MapControls(controller: controller),
          ),
          overrides: [
            locationPermissionGatewayProvider.overrideWithValue(
              _GrantedPermission(),
            ),
            positionSourceProvider.overrideWithValue(
              _OneFixSource(_fixAt(47.0, 8.0)),
            ),
          ],
        ),
      );
      await tester.pump();

      await tester.tap(find.widgetWithIcon(IconButton, Icons.my_location));
      await tester.pumpAndSettle();

      expect(controller.cameraMoves.single.padding, covered);
    });

    testWidgets('without the shell, keeps clear of its own chrome and '
        'column', (tester) async {
      final controller = FakeMapController()..zoom = 10;
      await tester.pumpWidget(
        await _wrap(
          MapChromeInsets(
            controlsTop: 100,
            child: MapControls(controller: controller),
          ),
          overrides: [
            locationPermissionGatewayProvider.overrideWithValue(
              _GrantedPermission(),
            ),
            positionSourceProvider.overrideWithValue(
              _OneFixSource(_fixAt(47.0, 8.0)),
            ),
          ],
        ),
      );
      await tester.pump();

      await tester.tap(find.widgetWithIcon(IconButton, Icons.my_location));
      await tester.pumpAndSettle();

      final padding = controller.cameraMoves.single.padding;
      expect(padding.top, 100 + 24);
      expect(
        padding.right,
        mapControlsWidth(tester.element(find.byType(MapControls))) + 24,
      );
      // No sheet on a map of its own.
      expect(padding.bottom, 24);
    });

    testWidgets('shows a progress ring in the button while the fix is on '
        'its way, and the icon again once the camera moved', (tester) async {
      final controller = FakeMapController()..zoom = 10;
      final source = _PendingFixSource();
      await tester.pumpWidget(
        await _wrap(
          MapControls(controller: controller),
          overrides: [
            locationPermissionGatewayProvider.overrideWithValue(
              _GrantedPermission(),
            ),
            positionSourceProvider.overrideWithValue(source),
          ],
        ),
      );
      await tester.pump();
      final before = tester.getSize(
        find.ancestor(
          of: find.byIcon(Icons.my_location),
          matching: find.byType(IconButton),
        ),
      );

      await tester.tap(find.widgetWithIcon(IconButton, Icons.my_location));
      await tester.pump();
      await tester.pump();

      // The ring stands in for the icon, in a button of the same size.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.my_location), findsNothing);
      expect(
        tester.getSize(
          find.ancestor(
            of: find.byType(CircularProgressIndicator),
            matching: find.byType(IconButton),
          ),
        ),
        before,
      );
      expect(controller.cameraMoves, isEmpty);

      source.fix.complete(_fixAt(47.0, 8.0));
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.my_location), findsOneWidget);
      expect(controller.cameraMoves.single.center, const LatLng(47.0, 8.0));
    });

    testWidgets('the ring goes with the message when no fix comes', (
      tester,
    ) async {
      final controller = FakeMapController()..zoom = 10;
      final source = _PendingFixSource();
      await tester.pumpWidget(
        await _wrap(
          MapControls(controller: controller),
          overrides: [
            locationPermissionGatewayProvider.overrideWithValue(
              _GrantedPermission(),
            ),
            positionSourceProvider.overrideWithValue(source),
          ],
        ),
      );
      await tester.pump();

      await tester.tap(find.widgetWithIcon(IconButton, Icons.my_location));
      await tester.pump();
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      source.fix.complete(null);
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.my_location), findsOneWidget);
      expect(find.text(l10n.mapLocationUnavailable), findsOneWidget);
      expect(controller.cameraMoves, isEmpty);
    });

    testWidgets('while the screen follows, a tap goes straight to it', (
      tester,
    ) async {
      final controller = FakeMapController()..zoom = 10;
      var located = 0;
      await tester.pumpWidget(
        await _wrap(
          MapChromeInsets(
            following: true,
            onLocate: () => located++,
            child: MapControls(controller: controller),
          ),
          overrides: [
            locationPermissionGatewayProvider.overrideWithValue(
              _GrantedPermission(),
            ),
            positionSourceProvider.overrideWithValue(
              _OneFixSource(_fixAt(47.0, 8.0)),
            ),
          ],
        ),
      );
      await tester.pump();

      await tester.tap(find.widgetWithIcon(IconButton, Icons.my_location));
      await tester.pumpAndSettle();

      // No fix fetched, no camera move of its own: the screen owns the
      // camera already and answers the tap itself.
      expect(controller.cameraMoves, isEmpty);
      expect(located, 1);
    });
  });
}
