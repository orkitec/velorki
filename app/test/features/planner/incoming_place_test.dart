import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/features/import_export/data/incoming_file_service.dart';
import 'package:velorki/features/map/application/locate_on_open.dart';
import 'package:velorki/features/planner/application/incoming_place.dart';
import 'package:velorki/features/recording/data/recording_recovery.dart';
import 'package:velorki/features/search/presentation/place_card.dart';
import 'package:velorki/features/shared/application/active_tab.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../support/app.dart';
import 'support/pump.dart';

/// Sources a test pushes links and shares into.
class _Sources implements IncomingSources {
  _Sources({this.launchLink});

  final Uri? launchLink;
  final StreamController<Uri> links = StreamController<Uri>.broadcast();
  final StreamController<List<SharedMediaFile>> media =
      StreamController<List<SharedMediaFile>>.broadcast();

  @override
  Future<List<SharedMediaFile>> initialSharedMedia() async => const [];

  @override
  Stream<List<SharedMediaFile>> sharedMediaStream() => media.stream;

  @override
  Future<Uri?> initialLink() async => launchLink;

  @override
  Stream<Uri> linkStream() => links.stream;

  @override
  Stream<String> openedFilePaths() => const Stream<String>.empty();

  @override
  Future<Uint8List?> readFile(String path) async => null;

  @override
  Future<Uint8List?> readContentUri(Uri uri) async => null;
}

/// The app shell on the Library tab, with the incoming places listened to
/// the way `bootstrap()` does it.
Future<PlannerHarness> _pumpApp(WidgetTester tester, _Sources sources) async {
  final h = PlannerHarness();
  await tester.binding.setSurfaceSize(const Size(1000, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(h.db.close);
  addTearDown(sources.links.close);
  addTearDown(sources.media.close);

  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final router = createRouter(initialLocation: libraryRoute);
  final container = ProviderContainer(
    overrides: [
      ...h.overrides(prefs),
      routerProvider.overrideWithValue(router),
      recordingRecoveryProvider.overrideWith((ref) async => const NoRecovery()),
      incomingFileServiceProvider.overrideWithValue(
        IncomingFileService(sources),
      ),
    ],
  );
  addTearDown(container.dispose);

  // As in bootstrap(): listening before the launch link is drained.
  listenForIncomingLocations(container);
  unawaited(container.read(incomingFileServiceProvider).start());

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: testRouterApp(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return h;
}

String _activeTab(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(Scaffold).first))
        .read(activeTabProvider);

void main() {
  testWidgets('the same place shared twice opens twice', (tester) async {
    final sources = _Sources();
    final h = await _pumpApp(tester, sources);
    const link = 'velorki://navigate?lat=48.1374&lon=11.5755&name=Marienplatz';

    sources.links.add(Uri.parse(link));
    await tester.pumpAndSettle();
    expect(h.map.searchPin, const LatLng(48.1374, 11.5755));
    expect(find.byType(PlaceCard), findsOneWidget);

    // The rider closes the card, then shares the very same place again
    // (later than the three seconds the double-delivery guard spans).
    await tester.tap(find.byTooltip(l10n.placeCardClose));
    await tester.pumpAndSettle();
    expect(h.map.searchPin, isNull);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 3100)),
    );
    sources.links.add(Uri.parse(link));
    await tester.pumpAndSettle();
    expect(
      h.map.searchPin,
      const LatLng(48.1374, 11.5755),
      reason: 'the second share is not swallowed as a repeat',
    );
  });

  testWidgets('a place with coordinates opens like a tapped search result', (
    tester,
  ) async {
    final sources = _Sources();
    final h = await _pumpApp(tester, sources);
    expect(_activeTab(tester), libraryRoute);

    sources.links.add(
      Uri.parse('velorki://navigate?lat=48.1374&lon=11.5755&name=Marienplatz'),
    );
    await tester.pumpAndSettle();

    expect(_activeTab(tester), plannerRoute);
    expect(h.map.movedTo, const LatLng(48.1374, 11.5755));
    expect(h.map.searchPin, const LatLng(48.1374, 11.5755));
    // The place's card, with what an empty plan can do with it.
    expect(find.byType(PlaceCard), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(PlaceCard),
        matching: find.text('Marienplatz'),
      ),
      findsOneWidget,
    );
    expect(find.text(l10n.placeCardRouteHere), findsOneWidget);
    expect(find.text(l10n.plannerSetAsStart), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Marienplatz'), findsOneWidget);

    await tester.tap(find.text(l10n.plannerSetAsStart));
    await tester.pumpAndSettle();
    expect(h.map.waypoints.single.position, const LatLng(48.1374, 11.5755));
    expect(h.map.waypoints.single.label, 'Marienplatz');
    await unmountApp(tester);
  });

  testWidgets('a place the app was launched with is shown', (tester) async {
    final sources = _Sources(launchLink: Uri.parse('geo:48.1374,11.5755'));
    final h = await _pumpApp(tester, sources);

    expect(_activeTab(tester), plannerRoute);
    expect(h.map.searchPin, const LatLng(48.1374, 11.5755));
    expect(find.text(l10n.placeCardRouteHere), findsOneWidget);
    // The move to the rider that a cold start begins is called off: its fix
    // would otherwise take the map back from the place.
    final locate = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold).first),
    ).read(locateOnOpenProvider) as StayPutOnOpen;
    expect(locate.touches, 1);
    // Without a name, the coordinates stand in for one.
    expect(
      find.widgetWithText(TextField, '48.13740, 11.57550'),
      findsOneWidget,
    );
    await unmountApp(tester);
  });

  testWidgets('an address goes into the search field as typed', (tester) async {
    final sources = _Sources();
    final h = await _pumpApp(tester, sources);

    sources.links.add(Uri.parse('velorki://navigate?q=munich'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(_activeTab(tester), plannerRoute);
    expect(find.widgetWithText(TextField, 'munich'), findsOneWidget);
    expect(h.map.searchPin, isNull);
    // The search ran and offers what it found, as if the rider had typed it.
    await tester.tap(find.text('Bavaria, Germany'));
    await tester.pumpAndSettle();
    expect(h.map.searchPin, const LatLng(48.1374, 11.5755));
    await unmountApp(tester);
  });

  testWidgets('shared text with an address searches for it', (tester) async {
    final sources = _Sources();
    await _pumpApp(tester, sources);

    sources.media.add([
      SharedMediaFile(path: 'munich', type: SharedMediaType.text),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'munich'), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('a short link says it has to be opened in a browser', (
    tester,
  ) async {
    final sources = _Sources();
    final h = await _pumpApp(tester, sources);

    sources.media.add([
      SharedMediaFile(
        path: 'https://maps.app.goo.gl/AbCdEf',
        type: SharedMediaType.url,
      ),
    ]);
    await tester.pumpAndSettle();

    expect(_activeTab(tester), plannerRoute);
    expect(find.text(l10n.placeLinkNeedsBrowser), findsOneWidget);
    expect(h.map.searchPin, isNull);
    await tester.pumpAndSettle(const Duration(seconds: 5));
    await unmountApp(tester);
  });
}
