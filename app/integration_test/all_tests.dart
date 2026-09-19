// Every integration test in this directory, in one entry point.
//
//   VELORKI_ITEST_COMBINED=1 tool/itest.sh
//
// This exists for the iOS simulator. There the Xcode build and the simulator
// boot dwarf the tests themselves, and `tool/itest.sh` pays both once per
// entry point, so nine files meant nine builds and nine attaches. Importing
// the files here and calling their `main()` inside a group each gives one
// build, one install, one attach and nine groups of tests in one process.
//
// Android keeps running one file per invocation (`tool/itest.sh` without
// VELORKI_ITEST_COMBINED, three shards x three API levels): the emulator
// re-installs cheaply, and a file per process is the stronger isolation — a
// leaked route, a running recording or a wedged map takes only its own file
// down. So every test here has to be good for both: it may not assume a fresh
// process, and it may not assume anything an earlier file left behind either.
// What that means in practice:
//
//   * boot the app through `pumpApp` (a fresh ProviderContainer per test) and
//     take it back off the screen with `unmountApp` at the end;
//   * set up the preferences the test reads rather than trusting the defaults,
//     because the file before it may have changed them and the device keeps
//     them between runs anyway;
//   * name anything written to the database with a timestamp, or record what
//     was there before and look only at what is new;
//   * leave no recording running and no tile download in flight.
//
// plan_route_test.dart is deliberately absent: it needs a BRouter *server*
// (the oracle harness in tools/brouter-oracle), which no CI run has, and
// `tool/itest.sh` skips it for the same reason unless VELORKI_BROUTER_URL
// says where that server is.
//
// The order below is the alphabetical one `tool/itest.sh` walks the directory
// in, so a combined run and a per-file run meet the same tests in the same
// order. The first group downloads the region's tile; the rest find it there.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'appearance_test.dart' as appearance;
import 'close_loop_test.dart' as close_loop;
import 'import_gpx_test.dart' as import_gpx;
import 'live_health_test.dart' as live_health;
import 'live_navigate_test.dart' as live_navigate;
import 'live_recover_test.dart' as live_recover;
import 'live_ride_test.dart' as live_ride;
import 'live_voice_test.dart' as live_voice;
import 'live_watch_test.dart' as live_watch;
import 'navigate_route_test.dart' as navigate_route;
import 'offline_search_test.dart' as offline_search;
import 'on_device_route_test.dart' as on_device_route;
import 'record_ride_test.dart' as record_ride;
import 'save_library_detail_test.dart' as save_library_detail;
import 'search_to_destination_test.dart' as search_to_destination;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('appearance_test.dart', appearance.main);
  group('close_loop_test.dart', close_loop.main);
  group('import_gpx_test.dart', import_gpx.main);
  group('live_health_test.dart', live_health.main);
  group('live_navigate_test.dart', live_navigate.main);
  group('live_recover_test.dart', live_recover.main);
  group('live_ride_test.dart', live_ride.main);
  group('live_voice_test.dart', live_voice.main);
  group('live_watch_test.dart', live_watch.main);
  group('navigate_route_test.dart', navigate_route.main);
  group('offline_search_test.dart', offline_search.main);
  group('on_device_route_test.dart', on_device_route.main);
  group('record_ride_test.dart', record_ride.main);
  group('save_library_detail_test.dart', save_library_detail.main);
  group('search_to_destination_test.dart', search_to_destination.main);
}
