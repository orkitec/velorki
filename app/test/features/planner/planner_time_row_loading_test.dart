import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/app/shell_layout.dart';
import 'package:velorki/features/map/presentation/weather_time_row.dart';
import 'package:velorki/features/weather/application/free_route_weather.dart';
import 'package:velorki/features/weather/application/route_colouring.dart';
import 'package:velorki/features/weather/application/route_overlay.dart';
import 'package:velorki/features/weather/application/route_weather_controller.dart';
import 'package:velorki/features/weather/domain/route_weather_state.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../recording/support/pump.dart';

void main() {
  setUp(() => debugShellLayoutOverride = null);

  testWidgets('Plan: while the forecast the route is coloured by loads, the '
      'time control\'s spinner turns; gone when it is in', (tester) async {
    const size = Size(402, 874);
    await tester.binding.setSurfaceSize(size);
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = size * 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final forecast = Completer<RouteWeatherState?>();
    await pumpRecordingApp(
      tester,
      initialLocation: plannerRoute,
      surfaceSize: size,
      extraOverrides: [
        weatherRouteGeometryProvider(plannerWeatherRoute)
            .overrideWithValue(<TrackPoint>[
              for (var d = 0.0; d <= 10000; d += 500)
                TrackPoint(destinationPoint(const LatLng(50, 8), 0, d)),
            ]),
        freeRouteWeatherProvider(plannerWeatherRoute)
            .overrideWith((ref) => forecast.future),
      ],
    );
    await tester.pump();
    final spinner = find.byKey(weatherTimeLoadingKey);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(WeatherTimeRow)),
    );
    // Coloured by the gradient: the forecast is not what is waited for.
    await container
        .read(routeOverlayChoiceProvider.notifier)
        .set(RouteOverlay.gradient);
    await tester.pump(weatherLoadingDelay * 2);
    expect(find.byType(WeatherTimeRow), findsOneWidget);
    expect(spinner, findsNothing);
    final row = tester.getRect(find.byType(WeatherTimeRow));
    // By the wind: the spinner while it loads.
    await container
        .read(routeOverlayChoiceProvider.notifier)
        .set(RouteOverlay.wind);
    await tester.pump();
    await tester.pump(weatherLoadingDelay);
    expect(spinner, findsOneWidget);
    expect(tester.getRect(find.byType(WeatherTimeRow)), row);
    forecast.complete(null);
    await tester.pump();
    await tester.pump();
    expect(spinner, findsNothing);
    expect(tester.getRect(find.byType(WeatherTimeRow)), row);
    await tester.pumpAndSettle();
  });
}
