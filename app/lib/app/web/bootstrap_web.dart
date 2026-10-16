import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/files/track_exporter.dart';
import '../../core/files/track_exporter_impl.dart';
import '../../features/map/presentation/map_view.dart';
import '../../features/planner/presentation/planner_map_host.dart';
import '../../features/routing_tiles/application/routing_tiles_startup.dart';
import '../../features/subscription/application/subscription_controller.dart';
import '../../features/subscription/data/subscription_service.dart';
import '../app.dart';
import '../app_config.dart';
import '../bootstrap.dart' show initLogging;
import '../licenses.dart';
import 'browser_download.dart';
import 'web_file_store.dart';

/// The browser's start: the planner and the library, without what needs the
/// phone (recording, the watch, sensors, the stores, links from other
/// apps). `main.dart` picks this over `bootstrap.dart` in a web build.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  initLogging();
  registerVelorkiLicenses();

  // The tiles and indexes of an earlier visit, back into the file system
  // the routing engine and the search read, before anything looks.
  await WebFileStore.open();

  final prefs = await SharedPreferences.getInstance();

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      mapViewBuilderProvider.overrideWithValue(
        (onReady) => MapView(onControllerReady: onReady),
      ),
      // The web's share sheet is the download.
      trackExporterProvider.overrideWithValue(
        ShareTrackExporter(shareFiles: downloadFile),
      ),
      // No store sells Plus in a browser yet; the paywall says so.
      subscriptionServiceProvider.overrideWithValue(
        const NoopSubscriptionService(),
      ),
    ],
  );

  startSubscriptions(container);
  prepareOnDeviceRouting(container);

  runApp(
    UncontrolledProviderScope(container: container, child: const VelorkiApp()),
  );
}
