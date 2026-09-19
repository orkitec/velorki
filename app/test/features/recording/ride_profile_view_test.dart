import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/app/theme.dart';
import 'package:velorki/features/planner/domain/elevation_profile.dart';
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

  testWidgets('says what is left and gives the map back', (tester) async {
    var shown = 0;
    await pump(
      tester,
      RideProfileView(
        samples: _route(),
        alongM: 4000,
        onShowMap: () => shown++,
      ),
    );

    // 8 km to go; the climb left is the 2 km to the pass (120 m) plus the
    // final bump (40 m). The test locale counts in miles and feet.
    expect(find.text('5.0 mi left, 525 ft to climb'), findsOneWidget);
    expect(find.text('ELEVATION'), findsOneWidget);
    await tester.tap(find.text('Map'));
    expect(shown, 1);

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

  testWidgets('without a route it says so', (tester) async {
    await pump(
      tester,
      RideProfileView(
        samples: const <ElevationSample>[],
        alongM: 0,
        onShowMap: () {},
      ),
    );
    expect(
      find.text('Follow a route to see its elevation profile here.'),
      findsOneWidget,
    );
  });
}
