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
import '../features/integrations/common/data/external_route_cache.dart';
import '../features/integrations/common/data/oauth_flow.dart';
import '../features/map/presentation/map_view.dart';
import '../features/planner/presentation/planner_map_host.dart';
import '../features/recording/data/recording_recovery.dart';
import '../features/routing_tiles/application/routing_tiles_startup.dart';
import '../features/sharing/application/share_link_listener.dart';
import '../features/subscription/application/subscription_controller.dart';
import 'app.dart';
import 'app_config.dart';
import 'licenses.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  initLogging();

  // Map data, tiles, routing and search are not pub packages, so their
  // licences have to be added to the ones Flutter collects by itself.
  registerVelorkiLicenses();

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

  // Strava's API terms allow its data to be cached for seven days. Enforcing
  // that at launch means the rule holds even for an app that is never opened
  // on the Strava screen again.
  unawaited(container.read(externalRouteListCacheProvider).purgeExpired());

  // Subscribes the OAuth flows to the deep-link stream before anything can
  // arrive: on Android the app can be resumed by the callback intent itself.
  container.read(oauthDeepLinksProvider);

  // Configures RevenueCat and keeps the Plus entitlement in step with it;
  // nothing waits for the store, the gated screens simply react when the
  // answer arrives.
  startSubscriptions(container);

  // Copies the bundled BRouter profiles out of the app package and reconciles
  // the downloaded rd5 tiles with what is on disk, so the planner can route on
  // the device as soon as both are done.
  prepareOnDeviceRouting(container);

  // Attached before the first frame so a file the app was launched with is
  // not missed.
  listenForIncomingImports(container);

  // The other half of the deep-link stream: velorki://share/<id> fetches the
  // shared GPX and sends it into the same import preview.
  listenForShareLinks(container);

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
