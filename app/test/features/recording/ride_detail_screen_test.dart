import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/core/db/database.dart' show RouteSource;
import 'package:velorki/core/files/track_exporter.dart';
import 'package:velorki/features/map/domain/map_controller.dart';
import 'package:velorki/features/planner/data/route_repository.dart';
import 'package:velorki/features/planner/domain/route_poi.dart';
import 'package:velorki/features/recording/data/ride_repository.dart';
import 'package:velorki/features/recording/domain/ride_range.dart';
import 'package:velorki/features/recording/domain/ride_upload.dart';
import 'package:velorki/core/geo/power_metrics.dart';
import 'package:velorki/core/geo/ride_analysis.dart';
import 'package:velorki/features/recording/presentation/ride_charts.dart';
import 'package:velorki/features/recording/presentation/ride_climbs.dart';
import 'package:velorki/features/recording/presentation/ride_detail_screen.dart';
import 'package:velorki/features/recording/presentation/recording_format.dart';
import 'package:velorki/features/recording/presentation/ride_heart_rate_zones.dart';
import 'package:velorki/features/recording/presentation/ride_power_zones.dart';
import 'package:velorki/features/recording/presentation/ride_splits.dart';
import 'package:velorki/features/shared/application/active_tab.dart';
import 'package:velorki/features/planner/presentation/surface_stats_bar.dart';
import 'package:velorki/features/shared/presentation/metric_chart.dart';
import 'package:fl_chart/fl_chart.dart' show LineChart;
import 'package:velorki_brouter/velorki_brouter.dart' show SurfaceStats;
import 'package:velorki_geo/velorki_geo.dart';

import '../../support/app.dart';
import '../../support/format.dart';
import 'support/pump.dart';

List<TrackPoint> _track() => <TrackPoint>[
  for (var i = 0; i < 60; i++)
    TrackPoint(
      LatLng(48 + i * 0.0002, 11),
      ele: 500 + (i < 30 ? i * 2.0 : (60 - i) * 2.0),
      time: DateTime.utc(2026, 9, 12, 10, 0, i),
    ),
];

/// Exactly 20 km/h for three kilometres, one fix a second: three whole
/// kilometre splits of three minutes each.
List<TrackPoint> _threeKilometres({
  bool withElevation = true,
  bool withSensors = false,
}) {
  const speedMps = 1000 / 180;
  var position = const LatLng(48, 11);
  return <TrackPoint>[
    for (var i = 0; i <= 540; i++)
      TrackPoint(
        i == 0 ? position : position = destinationPoint(position, 0, speedMps),
        ele: withElevation ? 400 + i * 0.1 : null,
        time: DateTime.utc(2026, 9, 12, 10).add(Duration(seconds: i)),
        heartRateBpm: withSensors ? 120 + i ~/ 20 : null,
        cadenceRpm: withSensors ? 85 : null,
        powerW: withSensors ? 200 : null,
      ),
  ];
}

/// 20 km/h for three kilometres, one fix a second: half a kilometre of flat,
/// two kilometres up a steady 5 %, half a kilometre of flat. One climb of a
/// hundred metres.
List<TrackPoint> _withClimb() {
  const speedMps = 1000 / 180;
  var position = const LatLng(48, 11);
  var height = 400.0;
  return <TrackPoint>[
    for (var i = 0; i <= 540; i++)
      TrackPoint(
        i == 0 ? position : position = destinationPoint(position, 0, speedMps),
        ele: i == 0
            ? height
            : height += i * speedMps > 500 && i * speedMps <= 2500
                  ? speedMps * 0.05
                  : 0,
        time: DateTime.utc(2026, 9, 12, 10).add(Duration(seconds: i)),
      ),
  ];
}

/// Saves a ride of [points] and opens its detail: the content on its own,
/// or with [inShell] the whole app on the ride's card, for what the card
/// around the content does (the chip over the map, the column's route
/// button).
Future<void> _open(
  WidgetTester tester,
  RecordingHarness harness,
  List<TrackPoint> points, {
  List<Override> extraOverrides = const <Override>[],
  Map<String, Object> preferences = const <String, Object>{},
  String? routeId,
  bool inShell = false,
}) async {
  await RideRepository(harness.planner.db.ridesDao).finalizeRide(
    rideId: 'ride-1',
    name: 'Morning loop',
    points: points,
    startedAt: points.first.time!,
    endedAt: points.last.time!,
    routeId: routeId,
  );
  if (inShell) {
    await pumpRecordingApp(
      tester,
      initialLocation: rideDetailLocation('ride-1'),
      harness: harness,
      preferences: preferences,
      extraOverrides: extraOverrides,
    );
  } else {
    await pumpRecordingScreen(
      tester,
      const RideDetailScreen(rideId: 'ride-1'),
      harness: harness,
      extraOverrides: extraOverrides,
      preferences: preferences,
    );
  }
  await tester.pumpAndSettle();
}

/// The three kilometres of [_threeKilometres] saved as the route the ride
/// followed, with a fountain 25 m beside the first kilometre mark and a café
/// 500 m off the second, which the ride never went to.
Future<void> _saveRoute(RecordingHarness harness) async {
  final points = _threeKilometres();
  await RouteRepository(harness.planner.db.routesDao).saveImportedRoute(
    id: 'route-1',
    name: 'Planned loop',
    points: points,
    source: RouteSource.importedGpx,
    pois: <RoutePoi>[
      RoutePoi(
        pos: destinationPoint(points[360].pos, 90, 500),
        name: 'Café',
        kind: PoiKind.food,
      ),
      RoutePoi(
        pos: destinationPoint(points[180].pos, 90, 25),
        name: 'Fountain',
        kind: PoiKind.water,
      ),
    ],
  );
}

/// Opens a ride that followed the route [_saveRoute] stores, on its card in
/// the app: the route button belongs to the card.
Future<void> _openWithRoute(
  WidgetTester tester,
  RecordingHarness harness, {
  Map<String, Object> preferences = const <String, Object>{},
}) async {
  await _saveRoute(harness);
  await _open(
    tester,
    harness,
    _threeKilometres(),
    routeId: 'route-1',
    preferences: preferences,
    inShell: true,
  );
}

/// The marks on the elevation chart, by name.
List<String> _chartMarks(WidgetTester tester) => tester
    .widget<RideElevationChart>(find.byType(RideElevationChart))
    .marks
    .map((m) => m.label)
    .toList();

Future<void> _seed(RecordingHarness harness) =>
    RideRepository(harness.planner.db.ridesDao).finalizeRide(
      rideId: 'ride-1',
      name: 'Morning loop',
      points: _track(),
      startedAt: DateTime.utc(2026, 9, 12, 10),
      endedAt: DateTime.utc(2026, 9, 12, 10, 0, 59),
    );

/// Every power figure on the page, in watts, whatever the locale writes
/// around the number.
List<int> _wattsShown(WidgetTester tester) {
  final pattern = RegExp(
    '^${RegExp.escape(l10n.unitWatts('#')).replaceFirst('#', r'(\d+)')}\$',
  );
  return <int>[
    for (final widget in tester.widgetList<Text>(find.byType(Text)))
      if (widget.data != null)
        if (pattern.firstMatch(widget.data!) case final match?)
          int.parse(match.group(1)!),
  ];
}

/// Scrolls [finder] into view and taps it.
Future<void> _tapRow(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// The range the elevation chart and the speed chart shade, which must be
/// the same one.
RideRange? _chartHighlight(WidgetTester tester) {
  final elevation = tester
      .widget<RideElevationChart>(find.byType(RideElevationChart))
      .highlight;
  final speed = tester
      .widget<RideSpeedChart>(find.byType(RideSpeedChart))
      .highlight;
  expect(speed, elevation, reason: 'one highlight on every chart');
  return elevation;
}

/// The x axis the chart inside [chart] draws.
({double min, double max}) _axisOf(WidgetTester tester, Finder chart) {
  final data = tester
      .widget<LineChart>(
        find.descendant(of: chart, matching: find.byType(LineChart)),
      )
      .data;
  return (min: data.minX, max: data.maxX);
}

/// Whether [axis] runs the whole three kilometres, which the track ends a
/// hair short of.
Matcher _wholeRide() => predicate<({double min, double max})>(
  (axis) => axis.min == 0 && (axis.max - 3).abs() < 1e-6,
  'the whole ride, 0 to 3 km',
);

/// Zooms in on the chart inside [chart] with two fingers moving apart
/// from its middle.
Future<void> _pinchOut(WidgetTester tester, Finder chart) async {
  await tester.ensureVisible(chart);
  await tester.pumpAndSettle();
  final centre = tester
      .getRect(find.descendant(of: chart, matching: find.byType(LineChart)))
      .center;
  final a = await tester.createGesture();
  final b = await tester.createGesture();
  await a.down(centre - const Offset(50, 0));
  await b.down(centre + const Offset(50, 0));
  await tester.pump();
  for (var i = 0; i < 10; i++) {
    await a.moveBy(const Offset(-10, 0));
    await b.moveBy(const Offset(10, 0));
    await tester.pump();
  }
  await a.up();
  await b.up();
  await tester.pumpAndSettle();
}

/// Opens the ride's overflow menu and picks "Continue this ride".
Future<void> _tapContinue(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.more_vert));
  await tester.pumpAndSettle();
  await tester.tap(find.text(l10n.rideContinue).last);
  await tester.pumpAndSettle();
  // Handing the ride back reads the journal off the real file system, which
  // only a real turn of the event loop finishes.
  await settleAsync(tester);
  await tester.pumpAndSettle();
}

/// What the ride's card tells the shell's control column, when it offers
/// the route button.
MapChromeData? _routeButton(WidgetTester tester) {
  final chrome = ProviderScope.containerOf(
    tester.element(find.byType(RideDetailScreen)),
  ).read(activeMapChromeProvider);
  return chrome?.onToggleRoute == null ? null : chrome;
}

void main() {
  testWidgets('shows the track, the statistics and the export buttons', (
    tester,
  ) async {
    final harness = RecordingHarness();
    await _seed(harness);
    await pumpRecordingScreen(
      tester,
      const RideDetailScreen(rideId: 'ride-1'),
      harness: harness,
    );
    await tester.pumpAndSettle();

    expect(find.text('Morning loop'), findsOneWidget);
    expect(find.text(l10n.statDistance.toUpperCase()), findsOneWidget);
    // Once in the tiles, once as a column of the splits table; the ascent
    // once more as a column of the climbs table, since the seeded track
    // climbs sixty metres in its first seven hundred.
    expect(find.text(l10n.statMovingTime.toUpperCase()), findsNWidgets(2));
    expect(find.text(l10n.statAscent.toUpperCase()), findsNWidgets(3));
    expect(find.byType(RideClimbsTable), findsOneWidget);
    expect(find.text('00:59'), findsWidgets);
    expect(find.text(l10n.rideDetailExportGpx), findsWidgets);
    expect(find.text(l10n.rideDetailExportFit), findsWidgets);

    // The track went on the map coloured by speed, and the camera was fitted
    // to it.
    final segments = harness.map.trackSegments;
    expect(segments, isNotEmpty);
    expect(
      segments.expand((s) => s.points).length,
      // Every fix is in a segment; the ones where the colour changes are in
      // two, so the line has no holes.
      greaterThanOrEqualTo(60),
    );
    expect(segments.map((s) => s.t), everyElement(inInclusiveRange(0, 1)));
    expect(harness.map.fittedBounds, isNotNull);
    expect(harness.map.fittedBounds!.south, closeTo(48, 1e-9));

    await unmountApp(tester);
  });

  testWidgets('a missing ride says so instead of crashing', (tester) async {
    await pumpRecordingScreen(tester, const RideDetailScreen(rideId: 'gone'));
    await tester.pumpAndSettle();

    expect(find.text(l10n.rideDetailNotFound), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('the GPX button hands the ride to the exporter', (tester) async {
    final harness = RecordingHarness();
    await _seed(harness);
    await pumpRecordingScreen(
      tester,
      const RideDetailScreen(rideId: 'ride-1'),
      harness: harness,
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.widgetWithText(OutlinedButton, l10n.rideDetailExportGpx),
    );
    await tester.pumpAndSettle();

    expect(harness.exporter.exports, hasLength(1));
    final export = harness.exporter.exports.single;
    expect(export.name, 'Morning loop');
    expect(export.kind, TrackKind.ride);
    expect(export.format, TrackFormat.gpx);
    expect(export.points, hasLength(60));
    expect(export.startTime, DateTime.utc(2026, 9, 12, 10));

    await unmountApp(tester);
  });

  testWidgets('the menu exports a FIT activity', (tester) async {
    final harness = RecordingHarness();
    await _seed(harness);
    await pumpRecordingScreen(
      tester,
      const RideDetailScreen(rideId: 'ride-1'),
      harness: harness,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.rideDetailExportFit).last);
    await tester.pumpAndSettle();

    expect(harness.exporter.exports.single.format, TrackFormat.fit);
    await unmountApp(tester);
  });

  testWidgets('a failing export says why', (tester) async {
    final harness = RecordingHarness();
    await _seed(harness);
    harness.exporter.error = const FormatException('no space left');
    await pumpRecordingScreen(
      tester,
      const RideDetailScreen(rideId: 'ride-1'),
      harness: harness,
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.widgetWithText(OutlinedButton, l10n.rideDetailExportGpx),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining(l10n.rideDetailExportFailed('').trim()),
      findsOneWidget,
    );
    await unmountApp(tester);
  });

  testWidgets('continuing hands the ride back to the recorder', (tester) async {
    final harness = RecordingHarness();
    await _seed(harness);
    await pumpRecordingApp(
      tester,
      initialLocation: rideDetailLocation('ride-1'),
      harness: harness,
    );
    await tester.pumpAndSettle();

    await _tapContinue(tester);

    // Nothing else was recording and the ride was never sent anywhere, so
    // there is nothing to confirm.
    expect(harness.service.calls, <String>['continueRide(ride-1)']);
    expect(harness.service.continued.single.name, 'Morning loop');
    expect(find.byType(RideDetailScreen), findsNothing, reason: 'record tab');

    await unmountApp(tester);
  });

  testWidgets('continuing finishes a running recording first, once confirmed', (
    tester,
  ) async {
    final harness = RecordingHarness();
    await _seed(harness);
    harness.service.running = true;
    await pumpRecordingApp(
      tester,
      initialLocation: rideDetailLocation('ride-1'),
      harness: harness,
    );
    await tester.pumpAndSettle();

    await _tapContinue(tester);
    expect(find.text(l10n.rideContinueRunning), findsOneWidget);
    expect(harness.service.calls, isEmpty);

    await tester.tap(find.widgetWithText(FilledButton, l10n.rideContinue));
    await tester.pumpAndSettle();
    await settleAsync(tester);
    await tester.pumpAndSettle();

    expect(harness.service.calls, hasLength(2));
    expect(
      harness.service.calls.first,
      startsWith('stop(${l10n.recordingRideName('')}'.trimRight()),
    );
    expect(harness.service.calls.last, 'continueRide(ride-1)');

    await unmountApp(tester);
  });

  testWidgets('an uploaded ride says it will have to be sent again', (
    tester,
  ) async {
    final harness = RecordingHarness();
    await _seed(harness);
    await RideRepository(harness.planner.db.ridesDao).recordUpload(
      'ride-1',
      serviceId: 'strava',
      upload: RideUpload(
        status: RideUploadStatus.done,
        uploadedAt: DateTime.utc(2026, 9, 12, 11),
        activityId: '99',
      ),
    );
    await pumpRecordingApp(
      tester,
      initialLocation: rideDetailLocation('ride-1'),
      harness: harness,
    );
    await tester.pumpAndSettle();

    await _tapContinue(tester);
    expect(
      find.textContaining(l10n.rideContinueUploaded('Strava')),
      findsOneWidget,
    );

    // Backing out leaves the ride alone.
    await tester.tap(find.widgetWithText(TextButton, l10n.commonCancel));
    await tester.pumpAndSettle();
    expect(harness.service.calls, isEmpty);
    expect(find.byType(RideDetailScreen), findsOneWidget);

    await unmountApp(tester);
  });

  testWidgets('renaming writes the new name', (tester) async {
    final harness = RecordingHarness();
    await _seed(harness);
    await pumpRecordingScreen(
      tester,
      const RideDetailScreen(rideId: 'ride-1'),
      harness: harness,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.commonRename));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Sunday spin');
    await tester.tap(find.widgetWithText(FilledButton, l10n.commonSave));
    await tester.pumpAndSettle();

    expect(find.text('Sunday spin'), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('the analysis draws an elevation chart, a speed chart and '
      'the splits', (tester) async {
    final harness = RecordingHarness();
    await _open(tester, harness, _threeKilometres());

    expect(find.byType(RideElevationChart), findsOneWidget);
    expect(find.byType(RideSpeedChart), findsOneWidget);
    expect(find.byType(RideSplitsTable), findsOneWidget);
    expect(find.text(l10n.elevationTitle.toUpperCase()), findsOneWidget);
    expect(find.text(l10n.statSpeed.toUpperCase()), findsOneWidget);
    expect(
      find.text(l10n.rideSplitsEvery(testSplitLength(1000)).toUpperCase()),
      findsOneWidget,
    );
    // The legend under the map.
    expect(find.byType(RideSpeedLegend), findsOneWidget);
    expect(find.text(l10n.rideSpeedSlow.toUpperCase()), findsOneWidget);
    expect(find.text(l10n.rideSpeedFast.toUpperCase()), findsOneWidget);

    await unmountApp(tester);
  });

  testWidgets('a ride with a sensor shows its figures and its chart', (
    tester,
  ) async {
    final harness = RecordingHarness();
    await _open(tester, harness, _threeKilometres(withSensors: true));

    expect(find.byType(RideHeartRateChart), findsOneWidget);
    expect(find.text(l10n.rideHeartRate.toUpperCase()), findsOneWidget);
    expect(find.text(l10n.statAvgHeartRate.toUpperCase()), findsOneWidget);
    expect(find.text(l10n.statMaxHeartRate.toUpperCase()), findsOneWidget);
    expect(find.text(l10n.statAvgCadence.toUpperCase()), findsOneWidget);
    expect(find.text(l10n.statAvgPower.toUpperCase()), findsOneWidget);
    // Steady 85 rpm and 200 W: the average, the maximum and the normalised
    // power are the same figure, in two tiles and three.
    expect(find.text(l10n.statMaxCadence.toUpperCase()), findsOneWidget);
    expect(find.text(l10n.statMaxPower.toUpperCase()), findsOneWidget);
    expect(find.text(l10n.statNormalizedPower.toUpperCase()), findsOneWidget);
    expect(find.text(l10n.statNormalizedPowerDetail), findsOneWidget);
    expect(find.text(l10n.unitRpm('85')), findsNWidgets(2));
    expect(find.text(l10n.unitWatts('200')), findsNWidgets(3));
    // 120 bpm rising to 147: a mean of 133 and a maximum of 147.
    expect(find.text(l10n.unitBpm('133')), findsOneWidget);
    expect(find.text(l10n.unitBpm('147')), findsOneWidget);
    // None of the switches was on.
    expect(find.text(l10n.statCalories.toUpperCase()), findsNothing);
    expect(find.byType(RideHeartRateZones), findsNothing);
    expect(find.text(l10n.statIntensity.toUpperCase()), findsNothing);
    expect(find.byType(RidePowerZones), findsNothing);

    await unmountApp(tester);
  });

  testWidgets('with the power zones switched on and a threshold set, the ride '
      'shows its intensity and its time in power zones', (tester) async {
    final harness = RecordingHarness();
    await _open(
      tester,
      harness,
      _threeKilometres(withSensors: true),
      preferences: const <String, Object>{
        'rider.powerZones': true,
        'rider.thresholdPowerW': 250,
      },
    );

    // 200 W normalised over a 250 W threshold.
    expect(find.text(l10n.statIntensity.toUpperCase()), findsOneWidget);
    expect(find.text(testIntensity(0.8)), findsOneWidget);
    expect(
      find.text(l10n.statIntensityDetail(l10n.unitWatts('250'))),
      findsOneWidget,
    );
    expect(find.byType(RidePowerZones), findsOneWidget);
    expect(
      find.text(l10n.ridePowerZones(l10n.unitWatts('250')).toUpperCase()),
      findsOneWidget,
    );
    // All seven rows, the top one open-ended.
    for (var zone = 1; zone < 7; zone++) {
      expect(
        find.text(
          l10n.rideHeartRateZoneLabel(
            zone,
            powerZoneBoundsPercent[zone - 1],
            powerZoneBoundsPercent[zone],
          ),
        ),
        findsOneWidget,
      );
    }
    expect(
      find.text(l10n.ridePowerZoneTopLabel(7, powerZoneBoundsPercent[6])),
      findsOneWidget,
    );
    // 200 of 250 is 80 %: the nine minutes are all zone 3, the other six
    // rows read nothing.
    expect(find.text(l10n.rideHeartRateZoneShare(100)), findsOneWidget);
    expect(find.text(l10n.rideHeartRateZoneShare(0)), findsNWidgets(6));
    expect(find.text('00:00'), findsNWidgets(6));

    await unmountApp(tester);
  });

  testWidgets('the switch alone, without a threshold, shows neither', (
    tester,
  ) async {
    final harness = RecordingHarness();
    await _open(
      tester,
      harness,
      _threeKilometres(withSensors: true),
      preferences: const <String, Object>{'rider.powerZones': true},
    );

    expect(find.text(l10n.statNormalizedPower.toUpperCase()), findsOneWidget);
    expect(find.text(l10n.statIntensity.toUpperCase()), findsNothing);
    expect(find.byType(RidePowerZones), findsNothing);

    await unmountApp(tester);
  });

  testWidgets('with the power zones off, a threshold alone shows neither', (
    tester,
  ) async {
    final harness = RecordingHarness();
    await _open(
      tester,
      harness,
      _threeKilometres(withSensors: true),
      preferences: const <String, Object>{'rider.thresholdPowerW': 250},
    );

    expect(find.text(l10n.statIntensity.toUpperCase()), findsNothing);
    expect(find.byType(RidePowerZones), findsNothing);
    expect(
      find.text(l10n.ridePowerZones(l10n.unitWatts('250')).toUpperCase()),
      findsNothing,
    );

    await unmountApp(tester);
  });

  testWidgets('a ride without a meter has no normalised power, switch or not', (
    tester,
  ) async {
    final harness = RecordingHarness();
    await _open(
      tester,
      harness,
      _threeKilometres(),
      preferences: const <String, Object>{
        'rider.powerZones': true,
        'rider.thresholdPowerW': 250,
        'rider.estimatePower': true,
        'rider.weightKg': 75.0,
      },
    );

    expect(find.text(l10n.statEstimatedPower.toUpperCase()), findsOneWidget);
    expect(find.text(l10n.statNormalizedPower.toUpperCase()), findsNothing);
    expect(find.text(l10n.statIntensity.toUpperCase()), findsNothing);
    expect(find.byType(RidePowerZones), findsNothing);

    await unmountApp(tester);
  });

  testWidgets('a ride with a climb lists it under the splits', (tester) async {
    final harness = RecordingHarness();
    final points = _withClimb();
    await _open(tester, harness, points);

    final climb = analyseRide(points).climbs.single;
    expect(find.byType(RideClimbsTable), findsOneWidget);
    expect(find.text(l10n.rideClimbs.toUpperCase()), findsOneWidget);
    expect(
      find.text(l10n.rideClimbAt(testDistance(climb.startM))),
      findsOneWidget,
    );
    expect(find.text(testDistance(climb.lengthM)), findsOneWidget);
    expect(find.text(testGrade(climb.avgGradePercent)), findsOneWidget);
    expect(
      find.textContaining(
        l10n.rideClimbVam(testNumber(climb.vamMPerHour, decimals: 0)),
      ),
      findsOneWidget,
    );
    // The table sits below the splits.
    expect(
      tester.getTopLeft(find.byType(RideClimbsTable)).dy,
      greaterThan(tester.getTopLeft(find.byType(RideSplitsTable)).dy),
    );

    await unmountApp(tester);
  });

  testWidgets('tapping a split shades it on the charts and draws it on the '
      'map; tapping it again clears both', (tester) async {
    final harness = RecordingHarness();
    await _open(tester, harness, _threeKilometres());
    expect(_chartHighlight(tester), isNull);
    expect(harness.map.lines, isNot(contains(rideHighlightLineId)));

    // The second kilometre.
    await _tapRow(tester, find.text(testSplitLength(1000)).at(1));

    final range = _chartHighlight(tester);
    expect(range, isNotNull);
    expect(range!.source, RideRangeSource.split);
    expect(range.index, 1);
    expect(range.startM, closeTo(1000, 1e-6));
    expect(range.endM, closeTo(2000, 1e-6));
    final splits = tester.widget<RideSplitsTable>(find.byType(RideSplitsTable));
    expect(splits.selected, 1);
    // The stretch went on the map as a line of its own, from the first
    // kilometre mark to the second, above the track, which stayed put.
    final line = harness.map.lines[rideHighlightLineId];
    expect(line, isNotNull);
    expect(line!.first.lat, closeTo(48 + 1000 / 111195, 1e-4));
    expect(line.last.lat, closeTo(48 + 2000 / 111195, 1e-4));
    expect(harness.map.trackSegments, isNotEmpty);

    await _tapRow(tester, find.text(testSplitLength(1000)).at(1));

    expect(_chartHighlight(tester), isNull);
    expect(
      tester.widget<RideSplitsTable>(find.byType(RideSplitsTable)).selected,
      isNull,
    );
    expect(harness.map.lines, isNot(contains(rideHighlightLineId)));

    await unmountApp(tester);
  });

  testWidgets('tapping a climb moves the highlight from the split to the '
      'climb', (tester) async {
    final harness = RecordingHarness();
    final points = _withClimb();
    await _open(tester, harness, points);
    final climb = analyseRide(points).climbs.single;

    await _tapRow(tester, find.text(testSplitLength(1000)).first);
    expect(_chartHighlight(tester)?.source, RideRangeSource.split);

    await _tapRow(
      tester,
      find.text(l10n.rideClimbAt(testDistance(climb.startM))),
    );

    final range = _chartHighlight(tester);
    expect(range, isNotNull);
    expect(range!.source, RideRangeSource.climb);
    expect(range.index, 0);
    expect(range.startM, closeTo(climb.startM, 1e-6));
    expect(range.endM, closeTo(climb.startM + climb.lengthM, 1e-6));
    // One highlight: the split let go of its row.
    expect(
      tester.widget<RideSplitsTable>(find.byType(RideSplitsTable)).selected,
      isNull,
    );
    expect(
      tester.widget<RideClimbsTable>(find.byType(RideClimbsTable)).selected,
      0,
    );
    final line = harness.map.lines[rideHighlightLineId];
    expect(line, isNotNull);
    expect(line!.first.lat, closeTo(48 + climb.startM / 111195, 1e-4));

    await unmountApp(tester);
  });

  testWidgets('a tapped split is named in a chip over the map, which clears '
      'it', (tester) async {
    final harness = RecordingHarness();
    await _open(tester, harness, _threeKilometres(), inShell: true);
    expect(find.byType(RideHighlightChip), findsNothing);

    await _tapRow(tester, find.text(testSplitLength(1000)).at(1));

    // The second kilometre: "Split 2 · 1–2 km".
    final label = l10n.rideHighlightChip(
      l10n.rideHighlightSplit(2),
      formatDistanceSpan(l10n, UnitSystem.metric, 1000, 2000),
    );
    expect(find.byType(RideHighlightChip), findsOneWidget);
    expect(find.text(label), findsOneWidget);
    expect(label, contains('1–2'));
    expect(harness.map.lines[rideHighlightLineId], isNotNull);

    await tester.ensureVisible(find.byType(RideHighlightChip));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(RideHighlightChip));
    await tester.pumpAndSettle();

    expect(find.byType(RideHighlightChip), findsNothing);
    expect(_chartHighlight(tester), isNull);
    expect(
      tester.widget<RideSplitsTable>(find.byType(RideSplitsTable)).selected,
      isNull,
    );
    expect(harness.map.lines, isNot(contains(rideHighlightLineId)));

    await unmountApp(tester);
  });

  testWidgets('a tapped climb is named "Climb 1" with its stretch', (
    tester,
  ) async {
    final harness = RecordingHarness();
    final points = _withClimb();
    await _open(tester, harness, points, inShell: true);
    final climb = analyseRide(points).climbs.single;

    await _tapRow(
      tester,
      find.text(l10n.rideClimbAt(testDistance(climb.startM))),
    );

    expect(
      find.text(
        l10n.rideHighlightChip(
          l10n.rideHighlightClimb(1),
          formatDistanceSpan(
            l10n,
            UnitSystem.metric,
            climb.startM,
            climb.startM + climb.lengthM,
          ),
        ),
      ),
      findsOneWidget,
    );

    await unmountApp(tester);
  });

  testWidgets('a pinch on the speed chart zooms the elevation chart to the '
      'same stretch, and one "Whole ride" resets both', (tester) async {
    final harness = RecordingHarness();
    await _open(tester, harness, _threeKilometres());
    final elevation = find.byType(RideElevationChart);
    final speed = find.byType(RideSpeedChart);
    expect(_axisOf(tester, elevation), _wholeRide());
    expect(_axisOf(tester, speed), _wholeRide());

    await _pinchOut(tester, speed);

    // The page holds one window in metres and both charts show it.
    final window = tester.widget<RideSpeedChart>(speed).window;
    expect(window, isNotNull);
    expect(window!.end - window.start, inInclusiveRange(900, 1500));
    expect(tester.widget<RideElevationChart>(elevation).window, window);
    final zoomed = _axisOf(tester, speed);
    expect(zoomed.max - zoomed.min, lessThan(2));
    expect(_axisOf(tester, elevation), zoomed);
    expect(find.text(l10n.chartResetZoom), findsNWidgets(2));

    await tester.tap(find.text(l10n.chartResetZoom).first);
    await tester.pumpAndSettle();

    expect(tester.widget<RideSpeedChart>(speed).window, isNull);
    expect(_axisOf(tester, elevation), _wholeRide());
    expect(_axisOf(tester, speed), _wholeRide());
    expect(find.text(l10n.chartResetZoom), findsNothing);

    await unmountApp(tester);
  });

  testWidgets('a ride up a gentle 1.8 % lists no climbs', (tester) async {
    final harness = RecordingHarness();
    await _open(tester, harness, _threeKilometres());

    expect(find.byType(RideClimbsTable), findsNothing);
    expect(find.text(l10n.rideClimbs.toUpperCase()), findsNothing);

    await unmountApp(tester);
  });

  testWidgets('with the zones switched on and a maximum known, the ride shows '
      'its time in zones', (tester) async {
    final harness = RecordingHarness();
    await _open(
      tester,
      harness,
      _threeKilometres(withSensors: true),
      preferences: const <String, Object>{
        'rider.zones': true,
        'rider.maxHeartRateBpm': 180,
      },
    );

    expect(find.byType(RideHeartRateZones), findsOneWidget);
    expect(
      find.text(l10n.rideHeartRateZones(180).toUpperCase()),
      findsOneWidget,
    );
    // All five rows, whether or not the ride reached the zone.
    for (var zone = 1; zone <= 5; zone++) {
      expect(
        find.text(
          l10n.rideHeartRateZoneLabel(
            zone,
            heartRateZoneBoundsPercent[zone - 1],
            heartRateZoneBoundsPercent[zone],
          ),
        ),
        findsOneWidget,
      );
    }
    // 120–147 of 180 is 67–82 %: zones 2 to 4 hold the nine minutes, the
    // others read nothing.
    expect(find.text(l10n.rideHeartRateZoneShare(0)), findsNWidgets(2));
    expect(find.text('00:00'), findsNWidgets(2));

    await unmountApp(tester);
  });

  testWidgets('the zones are not shown while the switch is off', (
    tester,
  ) async {
    final harness = RecordingHarness();
    await _open(
      tester,
      harness,
      _threeKilometres(withSensors: true),
      preferences: const <String, Object>{'rider.maxHeartRateBpm': 180},
    );

    expect(find.byType(RideHeartRateZones), findsNothing);
    expect(find.text(l10n.rideHeartRateZones(180).toUpperCase()), findsNothing);

    await unmountApp(tester);
  });

  testWidgets('with a weight and the estimate switched on, a ride without '
      'sensors gets calories from its speed', (tester) async {
    final harness = RecordingHarness();
    await _open(
      tester,
      harness,
      _threeKilometres(),
      preferences: const <String, Object>{
        'rider.calories': true,
        'rider.weightKg': 75.0,
      },
    );

    expect(find.text(l10n.statCalories.toUpperCase()), findsOneWidget);
    // Nine minutes at 20 km/h is 8 MET: 8 × 0.15 h × 75 kg = 90 kcal.
    expect(find.text(l10n.unitKcal('90')), findsOneWidget);
    expect(find.text(l10n.calorieSourceSpeed), findsOneWidget);

    await unmountApp(tester);
  });

  testWidgets('a power meter over the whole ride gives the calories from its '
      'work', (tester) async {
    final harness = RecordingHarness();
    await _open(
      tester,
      harness,
      _threeKilometres(withSensors: true),
      preferences: const <String, Object>{
        'rider.calories': true,
        'rider.weightKg': 75.0,
      },
    );

    // 200 W for 540 s is 108 kJ, and a kilojoule of work is a kilocalorie.
    expect(find.text(l10n.unitKcal('108')), findsOneWidget);
    expect(find.text(l10n.calorieSourcePower), findsOneWidget);

    await unmountApp(tester);
  });

  testWidgets('with the power estimate switched on, a ride without a meter '
      'shows an estimated power and its calories rest on it', (tester) async {
    final harness = RecordingHarness();
    await _open(
      tester,
      harness,
      _threeKilometres(),
      preferences: const <String, Object>{
        'rider.estimatePower': true,
        'rider.calories': true,
        'rider.weightKg': 75.0,
      },
    );

    expect(find.text(l10n.statEstimatedPower.toUpperCase()), findsOneWidget);
    expect(find.text(l10n.statEstimatedDetail), findsOneWidget);
    // 20 km/h up a steady 1.8 % on 84 kg: somewhere over a hundred watts,
    // and the only watts on the page.
    final watts = _wattsShown(tester);
    expect(watts, hasLength(1));
    expect(watts.single, inInclusiveRange(100, 200));
    expect(find.text(l10n.calorieSourceEstimatedPower), findsOneWidget);
    expect(find.text(l10n.calorieSourceSpeed), findsNothing);

    await unmountApp(tester);
  });

  testWidgets('with the power estimate off there is no estimated power', (
    tester,
  ) async {
    final harness = RecordingHarness();
    await _open(
      tester,
      harness,
      _threeKilometres(),
      preferences: const <String, Object>{'rider.weightKg': 75.0},
    );

    expect(find.text(l10n.statEstimatedPower.toUpperCase()), findsNothing);
    expect(_wattsShown(tester), isEmpty);

    await unmountApp(tester);
  });

  testWidgets('a ride with a power meter never shows the estimate beside it', (
    tester,
  ) async {
    final harness = RecordingHarness();
    await _open(
      tester,
      harness,
      _threeKilometres(withSensors: true),
      preferences: const <String, Object>{
        'rider.estimatePower': true,
        'rider.weightKg': 75.0,
      },
    );

    expect(find.text(l10n.statAvgPower.toUpperCase()), findsOneWidget);
    expect(find.text(l10n.statEstimatedPower.toUpperCase()), findsNothing);
    expect(find.text(l10n.statEstimatedDetail), findsNothing);

    await unmountApp(tester);
  });

  testWidgets('without a weight the switch alone shows no calories', (
    tester,
  ) async {
    final harness = RecordingHarness();
    await _open(
      tester,
      harness,
      _threeKilometres(),
      preferences: const <String, Object>{'rider.calories': true},
    );

    expect(find.text(l10n.statCalories.toUpperCase()), findsNothing);

    await unmountApp(tester);
  });

  testWidgets('a ride without a sensor shows none of that', (tester) async {
    final harness = RecordingHarness();
    await _open(tester, harness, _threeKilometres());

    expect(find.byType(RideHeartRateChart), findsNothing);
    expect(find.text(l10n.rideHeartRate.toUpperCase()), findsNothing);
    expect(find.text(l10n.statAvgHeartRate.toUpperCase()), findsNothing);
    expect(find.text(l10n.statAvgPower.toUpperCase()), findsNothing);

    await unmountApp(tester);
  });

  testWidgets('a ride without heights shows no elevation chart', (
    tester,
  ) async {
    final harness = RecordingHarness();
    await _open(tester, harness, _threeKilometres(withElevation: false));

    expect(find.byType(RideElevationChart), findsNothing);
    expect(find.text(l10n.elevationTitle.toUpperCase()), findsNothing);
    // The speed chart and the splits are still there.
    expect(find.text(l10n.statSpeed.toUpperCase()), findsOneWidget);
    expect(
      find.text(l10n.rideSplitsEvery(testSplitLength(1000)).toUpperCase()),
      findsOneWidget,
    );

    await unmountApp(tester);
  });

  testWidgets('three kilometres at 20 km/h are three splits of 3:00', (
    tester,
  ) async {
    final harness = RecordingHarness();
    await _open(tester, harness, _threeKilometres());

    expect(find.text(testSplitLength(1000)), findsNWidgets(3));
    expect(find.text('03:00'), findsNWidgets(3));
    expect(find.text(testSpeed(20000 / 3600)), findsWidgets);

    await unmountApp(tester);
  });

  testWidgets('the same ride splits into miles under imperial', (tester) async {
    final harness = RecordingHarness();
    await _open(
      tester,
      harness,
      _threeKilometres(),
      extraOverrides: [imperialUnits],
    );

    // 1.86 miles: one whole mile and the remainder, flagged by its own length.
    expect(
      find.text(testSplitLength(1609.344, system: UnitSystem.imperial)),
      findsOneWidget,
    );
    expect(
      find.text(testSplitLength(3000 - 1609.344, system: UnitSystem.imperial)),
      findsOneWidget,
    );
    expect(find.text('04:50'), findsOneWidget);
    expect(find.text('04:10'), findsOneWidget);

    await unmountApp(tester);
  });

  testWidgets('the ride detail reads in miles, mph and feet under imperial', (
    tester,
  ) async {
    final harness = RecordingHarness();
    await _seed(harness);
    await pumpRecordingScreen(
      tester,
      const RideDetailScreen(rideId: 'ride-1'),
      harness: harness,
      extraOverrides: [imperialUnits],
    );
    await tester.pumpAndSettle();

    // The seeded track runs about 1.3 km up to 558 m and back down.
    expect(find.textContaining(' mi'), findsWidgets);
    expect(find.textContaining(' mph'), findsWidgets);
    expect(find.textContaining(' ft'), findsWidgets);
    expect(find.textContaining(' km'), findsNothing);
    expect(find.textContaining(' km/h'), findsNothing);

    await unmountApp(tester);
  });

  testWidgets('a ride with a matched surface shows the planner bar', (
    tester,
  ) async {
    final harness = RecordingHarness();
    await _seed(harness);
    await RideRepository(harness.planner.db.ridesDao).setSurface(
      'ride-1',
      const SurfaceStats(
        pavedShare: 0.75,
        unpavedShare: 0.25,
        unknownShare: 0,
        cyclewayShare: 0.5,
        busyShare: 0,
        coveredLengthM: 1300,
        totalLengthM: 1300,
      ),
    );
    await pumpRecordingScreen(
      tester,
      const RideDetailScreen(rideId: 'ride-1'),
      harness: harness,
    );
    await tester.pumpAndSettle();

    expect(find.byType(SurfaceStatsBar), findsOneWidget);
    expect(find.text(l10n.surfaceTitle.toUpperCase()), findsOneWidget);
    expect(find.textContaining(l10n.surfacePaved), findsOneWidget);
    expect(find.text(l10n.rideSurfaceUnavailable), findsNothing);
    expect(find.text(l10n.rideSurfaceComputing), findsNothing);
    // The row answered: nothing was routed.
    expect(harness.planner.backend.callCount, 0);

    await unmountApp(tester);
  });

  testWidgets('a ride the map could not follow says so under the caption', (
    tester,
  ) async {
    final harness = RecordingHarness();
    await _seed(harness);
    await RideRepository(harness.planner.db.ridesDao)
        .markSurfaceUnavailable('ride-1');
    await pumpRecordingScreen(
      tester,
      const RideDetailScreen(rideId: 'ride-1'),
      harness: harness,
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.surfaceTitle.toUpperCase()), findsOneWidget);
    expect(find.text(l10n.rideSurfaceUnavailable), findsOneWidget);
    expect(find.byType(SurfaceStatsBar), findsNothing);
    expect(harness.planner.backend.callCount, 0);

    await unmountApp(tester);
  });

  testWidgets('a ride that followed a route shows the route under the '
      'track, its points on the map and the one it passed on the chart', (
    tester,
  ) async {
    final harness = RecordingHarness();
    await _openWithRoute(tester, harness);

    // The route went on in the subdued style, and the track is still there.
    expect(harness.map.lines[rideRouteLineId], hasLength(541));
    expect(harness.map.styles[rideRouteLineId], RouteLineStyle.alternative);
    expect(harness.map.trackSegments, isNotEmpty);
    // Both points are on the map, the café included: the ride skipped it,
    // and the map may as well say so.
    expect(harness.map.pois.map((p) => p.name), <String>['Café', 'Fountain']);
    expect(harness.map.pois.last.kind, MapPoiKind.water);
    // Only the fountain is on the chart, at the kilometre mark.
    expect(_chartMarks(tester), <String>['Fountain']);
    final chart = tester.widget<MetricChart>(
      find.descendant(
        of: find.byType(RideElevationChart),
        matching: find.byType(MetricChart),
      ),
    );
    expect(chart.marks.single.x, closeTo(1, 0.01));
    // The chip is there, and reads as on.
    expect(_routeButton(tester), isNotNull);
    expect(_routeButton(tester)!.routeShown, isTrue);

    await unmountApp(tester);
  });

  testWidgets('a tap on a point pins it with its name and takes the map '
      'there', (tester) async {
    final harness = RecordingHarness();
    await _openWithRoute(tester, harness);

    harness.map.onPoiTapped!(1);
    await tester.pumpAndSettle();

    expect(harness.map.searchPin, harness.map.pois[1].position);
    expect(harness.map.movedTo, harness.map.pois[1].position);

    await unmountApp(tester);
  });

  testWidgets('switching the route off takes it off the map and the chart '
      'and is remembered; on again forgets the choice', (tester) async {
    final harness = RecordingHarness();
    await _openWithRoute(tester, harness);
    final prefs = await SharedPreferences.getInstance();

    _routeButton(tester)!.onToggleRoute!();
    await tester.pumpAndSettle();

    expect(harness.map.lines, isNot(contains(rideRouteLineId)));
    expect(harness.map.pois, isEmpty);
    expect(_chartMarks(tester), isEmpty);
    expect(prefs.getBool('rides.showRoute'), isFalse);
    expect(_routeButton(tester)!.routeShown, isFalse);
    // The track and the highlight line are none of the chip's business.
    expect(harness.map.trackSegments, isNotEmpty);

    _routeButton(tester)!.onToggleRoute!();
    await tester.pumpAndSettle();

    expect(harness.map.lines[rideRouteLineId], isNotNull);
    expect(harness.map.pois, hasLength(2));
    expect(_chartMarks(tester), <String>['Fountain']);
    expect(prefs.containsKey('rides.showRoute'), isFalse);

    await unmountApp(tester);
  });

  testWidgets('a remembered off keeps the route off the map from the start', (
    tester,
  ) async {
    final harness = RecordingHarness();
    await _openWithRoute(
      tester,
      harness,
      preferences: <String, Object>{'rides.showRoute': false},
    );

    expect(_routeButton(tester), isNotNull);
    expect(harness.map.lines, isNot(contains(rideRouteLineId)));
    expect(harness.map.pois, isEmpty);
    expect(_chartMarks(tester), isEmpty);
    expect(harness.map.trackSegments, isNotEmpty);

    await unmountApp(tester);
  });

  testWidgets('a ride without a route has no chip and no route line', (
    tester,
  ) async {
    final harness = RecordingHarness();
    await _open(tester, harness, _threeKilometres(), inShell: true);

    expect(_routeButton(tester), isNull);
    expect(harness.map.lines, isNot(contains(rideRouteLineId)));
    expect(harness.map.pois, isEmpty);
    expect(_chartMarks(tester), isEmpty);

    await unmountApp(tester);
  });

  testWidgets('a ride whose route was deleted shows no chip either', (
    tester,
  ) async {
    final harness = RecordingHarness();
    await _open(
      tester,
      harness,
      _threeKilometres(),
      routeId: 'gone',
      inShell: true,
    );

    expect(_routeButton(tester), isNull);
    expect(harness.map.lines, isNot(contains(rideRouteLineId)));

    await unmountApp(tester);
  });
}
