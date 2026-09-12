import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/map/presentation/map_view.dart';
import '../features/planner/presentation/planner_map_host.dart';
import 'app.dart';
import 'app_config.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  initLogging();

  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        // The real map; every screen reaches it through PlannerMapHost so no
        // screen imports maplibre, and widget tests keep the placeholder.
        mapViewBuilderProvider.overrideWithValue(
          (onReady) => MapView(onControllerReady: onReady),
        ),
      ],
      child: const VelorkiApp(),
    ),
  );
}

void initLogging() {
  Logger.root.level = kReleaseMode ? Level.INFO : Level.ALL;
  Logger.root.onRecord.listen((record) {
    developer.log(
      record.message,
      time: record.time,
      level: record.level.value,
      name: record.loggerName,
      error: record.error,
      stackTrace: record.stackTrace,
    );
  });
}
