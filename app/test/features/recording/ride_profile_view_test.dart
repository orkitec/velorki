import 'dart:io';
import 'dart:ui' as ui;

import 'package:fl_chart/fl_chart.dart' show LineChart;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/app/theme.dart';
import 'package:velorki/features/planner/domain/elevation_profile.dart';
import 'package:velorki/features/planner/presentation/route_format.dart';
import 'package:velorki/features/settings/data/units.dart';
import 'package:velorki/features/recording/presentation/ride_profile_view.dart';

import '../../support/app.dart';

/// A 12 km route: a climb to a pass at 6 km, a descent, a bump at the end.
List<ElevationSample> _route() => <ElevationSample>[
  for (var m = 0; m <= 12000; m += 250)
    ElevationSample(
      m.toDouble(),
      m <= 6000
          ? 500 + m * 0.06
          : m <= 10000
          ? 860 - (m - 6000) * 0.07
          : 580 + (m - 10000) * 0.02,
    ),
];

void main() {
  Future<void> pump(WidgetTester tester, Widget view) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: testApp(
          theme: buildDarkTheme(),
          home: RepaintBoundary(
            key: const Key('shot'),
            child: SizedBox(height: 420, child: view),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('says what is left', (tester) async {
    await pump(tester, RideProfileView(samples: _route(), alongM: 4000));

    // 8 km to go; the climb left is the 2 km to the pass (120 m) plus the
    // final bump (40 m), said in whatever the test locale counts in.
    final units = ProviderScope.containerOf(
      tester.element(find.byType(RideProfileView)),
    ).read(unitSystemProvider);
    expect(
      find.text(
        l10n.recordingProfileLeft(
          formatDistance(l10n, units, 8000),
          formatHeight(l10n, units, 160),
        ),
      ),
      findsOneWidget,
    );
    expect(find.text(l10n.elevationTitle.toUpperCase()), findsOneWidget);

    // VELORKI_SHOT_DIR=<dir> flutter test ... writes the render there, so the
    // chart can be looked at without a device.
    final dir = Platform.environment['VELORKI_SHOT_DIR'];
    if (dir != null) {
      await tester.pump();
      final boundary = tester.renderObject(
        find.byKey(const Key('shot')),
      ) as RenderRepaintBoundary;
      // Rasterising is real work the fake clock cannot drive.
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$dir/ride-profile.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }
  });

  testWidgets('on a climb it says the grade and what is left to the top, '
      'and when the rider arrives', (tester) async {
    await pump(
      tester,
      RideProfileView(
        samples: _route(),
        alongM: 3000,
        etaAt: DateTime(2026, 9, 20, 14, 32),
      ),
    );

    // 6 % up to the pass at 6 km: 180 m of the 360 m climb still to go.
    final units = ProviderScope.containerOf(
      tester.element(find.byType(RideProfileView)),
    ).read(unitSystemProvider);
    expect(
      find.textContaining(
        l10n.recordingProfileClimb('6', formatHeight(l10n, units, 180)),
      ),
      findsOneWidget,
    );
    expect(find.textContaining(l10n.recordingEta('')), findsOneWidget);
  });

  testWidgets('on the flat and without an average there is no second line', (
    tester,
  ) async {
    await pump(tester, RideProfileView(samples: _route(), alongM: 11000));
    expect(
      find.textContaining(l10n.recordingProfileClimb('', '')),
      findsNothing,
    );
    expect(find.textContaining(l10n.recordingEta('')), findsNothing);
  });

  testWidgets('without a route it says so', (tester) async {
    await pump(
      tester,
      const RideProfileView(samples: <ElevationSample>[], alongM: 0),
    );
    expect(find.text(l10n.recordingProfileNoRoute), findsOneWidget);
  });

  testWidgets('a finger on the profile says where along the route it is, '
      'and a pinch zooms it until "Whole route" shows it all again', (
    tester,
  ) async {
    final cursor = <double?>[];
    await pump(
      tester,
      RideProfileView(samples: _route(), alongM: 4000, onCursor: cursor.add),
    );
    final units = ProviderScope.containerOf(
      tester.element(find.byType(RideProfileView)),
    ).read(unitSystemProvider);
    final rect = tester.getRect(find.byType(LineChart));
    Offset at(double share) =>
        Offset(rect.left + 40 + (rect.width - 40) * share, rect.center.dy);

    await tester.tapAt(at(0.25));
    await tester.pump(const Duration(milliseconds: 400));
    expect(cursor.first, closeTo(3000, 20));
    expect(cursor.last, isNull);

    final a = await tester.createGesture();
    final b = await tester.createGesture();
    await a.down(at(0.5) - const Offset(50, 0));
    await b.down(at(0.5) + const Offset(50, 0));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await a.moveBy(const Offset(-10, 0));
      await b.moveBy(const Offset(10, 0));
      await tester.pump();
    }
    await a.up();
    await b.up();
    await tester.pump(const Duration(milliseconds: 400));
    final whole = units == UnitSystem.metric ? 12.0 : 12000 / 1609.344;
    var data = tester.widget<LineChart>(find.byType(LineChart)).data;
    expect(data.maxX - data.minX, lessThan(whole * 0.6));

    await tester.tap(find.text(l10n.chartResetZoomRoute));
    await tester.pumpAndSettle();
    data = tester.widget<LineChart>(find.byType(LineChart)).data;
    expect(data.maxX - data.minX, closeTo(whole, 1e-6));
  });
}
