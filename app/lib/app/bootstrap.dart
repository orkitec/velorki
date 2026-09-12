import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/files/track_exporter.dart';
import '../core/files/track_exporter_impl.dart';
import '../features/import_export/application/incoming_import_listener.dart';
import '../features/map/presentation/map_view.dart';
import '../features/planner/presentation/planner_map_host.dart';
import '../features/recording/data/recording_recovery.dart';
import 'app.dart';
import 'app_config.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  initLogging();

  final prefs = await SharedPreferences.getInstance();

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      // The real map; every screen reaches it through PlannerMapHost so no
      // screen imports maplibre, and widget tests keep the placeholder.
      mapViewBuilderProvider.overrideWithValue(
        (onReady) => MapView(onControllerReady: onReady),
      ),
      // The real share sheet; widget tests keep the throwing default or
      // override it with a recorder.
      trackExporterProvider.overrideWithValue(ShareTrackExporter()),
    ],
  );

  // Looks for a ride that was left unfinished by a crash or a force quit; the
  // record tab awaits the same future and offers Resume or Finish.
  unawaited(RecordingRecovery.checkOnLaunch());

  // Attached before the first frame so a file the app was launched with is
  // not missed.
  listenForIncomingImports(container);

  runApp(
    UncontrolledProviderScope(container: container, child: const VelorkiApp()),
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
