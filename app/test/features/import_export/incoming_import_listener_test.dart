import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/features/import_export/application/incoming_import_listener.dart';
import 'package:velorki/features/import_export/data/incoming_file_service.dart';

import '../../support/app.dart';
import '../planner/support/pump.dart';
import 'support/fixtures.dart';

/// Sources that answer from a map and can be pushed to from a test.
class _Sources implements IncomingSources {
  _Sources(this.files);

  final Map<String, Uint8List> files;
  final StreamController<String> opened = StreamController<String>.broadcast();

  @override
  Future<List<SharedMediaFile>> initialSharedMedia() async => const [];

  @override
  Stream<List<SharedMediaFile>> sharedMediaStream() =>
      const Stream<List<SharedMediaFile>>.empty();

  @override
  Future<Uri?> initialLink() async => null;

  @override
  Stream<Uri> linkStream() => const Stream<Uri>.empty();

  @override
  Stream<String> openedFilePaths() => opened.stream;

  @override
  Future<Uint8List?> readFile(String path) async => files[path];

  @override
  Future<Uint8List?> readContentUri(Uri uri) async => null;
}

/// Pumps the app shell with [sources] wired behind the incoming-file service,
/// the way `bootstrap()` does it, and returns the container to listen on.
Future<ProviderContainer> _pumpAppWith(
  WidgetTester tester,
  _Sources sources,
) async {
  final h = PlannerHarness();
  await tester.binding.setSurfaceSize(const Size(1000, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(h.db.close);
  addTearDown(sources.opened.close);

  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final router = createRouter(initialLocation: libraryRoute);
  final container = ProviderContainer(
    overrides: [
      ...h.overrides(prefs),
      routerProvider.overrideWithValue(router),
      incomingFileServiceProvider.overrideWithValue(
        IncomingFileService(sources),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: testRouterApp(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('a file arriving at runtime opens the import preview', (
    tester,
  ) async {
    final sources = _Sources({'/tmp/tour.gpx': fixtureBytes('route.gpx')});
    final container = await _pumpAppWith(tester, sources);
    expect(find.widgetWithText(AppBar, 'Import'), findsNothing);

    listenForIncomingImports(container);
    sources.opened.add('/tmp/tour.gpx');
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Import'), findsOneWidget);
    expect(find.text(l10n.importSummary('GPX', 4)), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('a file that does not decode leaves the app where it was', (
    tester,
  ) async {
    final sources = _Sources({'/tmp/photo.jpg': fixtureBytes('not_gpx.xml')});
    final container = await _pumpAppWith(tester, sources);

    listenForIncomingImports(container);
    sources.opened.add('/tmp/photo.jpg');
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Import'), findsNothing);
    expect(find.widgetWithText(AppBar, l10n.tabLibrary), findsOneWidget);
    await unmountApp(tester);
  });
}
