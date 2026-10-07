import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/core/links/link_opener.dart';
import 'package:velorki/features/search/data/osm_details.dart';
import 'package:velorki/features/search/data/osm_details_cache.dart';
import 'package:velorki/features/search/domain/search_result.dart';
import 'package:velorki/features/search/presentation/place_card.dart';
import 'package:velorki/features/search/presentation/place_details_view.dart';
import 'package:velorki/features/sharing/data/share_service.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../support/app.dart';
import '../../support/units.dart';

/// A cafe whose OpenStreetMap node is known.
const SearchResult _cafe = SearchResult(
  name: 'Café Wolf',
  position: LatLng(47.1405, 9.522),
  city: 'Vaduz',
  source: SearchSource.local,
  kind: SearchKind.poi,
  detail: 'cafe',
  osmType: 'node',
  osmId: 1234,
);

/// The same cafe without its OpenStreetMap identity.
const SearchResult _anonymous = SearchResult(
  name: 'Café Wolf',
  position: LatLng(47.1405, 9.522),
  source: SearchSource.local,
  kind: SearchKind.poi,
  detail: 'cafe',
);

const Map<String, String> _full = {
  'opening_hours': 'Mo-Fr 08:00-18:00; Sa 09:00-12:00',
  'website': 'https://www.cafe-wolf.example/',
  'phone': '+423 232 00 00',
  'cuisine': 'coffee_shop;ice_cream',
  'wheelchair': 'yes',
  'outdoor_seating': 'yes',
  'wikipedia': 'de:Café Wolf',
};

/// Tags answered by the test: [answer], or [error], once [gate] (when set)
/// completes.
class _FakeDetails implements OsmDetailsSource {
  Map<String, String> answer = const <String, String>{};
  Object? error;
  Completer<void>? gate;
  final List<String> asked = <String>[];

  @override
  Future<Map<String, String>> tags(String type, int id) async {
    asked.add('$type/$id');
    await gate?.future;
    final e = error;
    if (e != null) throw e;
    return answer;
  }
}

void main() {
  late _FakeDetails details;
  late List<Uri> opened;
  late List<String> shared;
  late bool googleMapsInstalled;

  /// Monday 10:00.
  final monday10 = DateTime(2026, 10, 5, 10);

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    details = _FakeDetails();
    opened = <Uri>[];
    shared = <String>[];
    googleMapsInstalled = false;
  });

  /// A screen with a button that opens the card of [place].
  Future<void> pumpCard(
    WidgetTester tester,
    SearchResult place, {
    List<PlaceAction> actions = const <PlaceAction>[],
    Size size = const Size(400, 900),
    DateTime? now,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final clock = now ?? monday10;
    // Read from the device anew, as after a restart.
    SharedPreferences.resetStatic();
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        // A new container each time.
        key: UniqueKey(),
        overrides: [
          metricUnits,
          sharedPreferencesProvider.overrideWithValue(prefs),
          osmDetailsSourceProvider.overrideWithValue(details),
          osmDetailsCacheProvider.overrideWithValue(
            OsmDetailsCache(prefs, now: () => clock),
          ),
          linkOpenerProvider.overrideWithValue((url) async {
            opened.add(url);
            return true;
          }),
          linkProbeProvider.overrideWithValue(
            (url) async => googleMapsInstalled && url.scheme == 'comgooglemaps',
          ),
          textSharerProvider.overrideWithValue((text, {subject}) async {
            shared.add(text);
          }),
          placeDetailsClockProvider.overrideWithValue(() => clock),
        ],
        child: testApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => unawaited(
                    showPlaceCard(
                      context,
                      place: place,
                      actions: actions,
                      riderPosition: const LatLng(47.14, 9.52),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(PlaceCard), findsOneWidget);
  }

  Finder detailsButton() =>
      find.widgetWithText(OutlinedButton, l10n.placeCardDetails);

  bool detailsEnabled(WidgetTester tester) =>
      tester.widget<OutlinedButton>(detailsButton()).onPressed != null;

  /// The labels of the Android sheet's rows, in order.
  List<String> sheetRows(WidgetTester tester) => [
    for (final tile in tester.widgetList<ListTile>(find.byType(ListTile)))
      (tile.title! as Text).data!,
  ];

  /// The labels of the iOS action sheet's actions, cancel last.
  List<String> sheetActions(WidgetTester tester) => [
    for (final action in tester.widgetList<CupertinoActionSheetAction>(
      find.byType(CupertinoActionSheetAction),
    ))
      (action.child as Text).data!,
  ];

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.text(l10n.placeCardOpenIn));
    await tester.pumpAndSettle();
  }

  /// The card's status line: open and closing, or closed and opening, at
  /// [hour]:00 (on [day], when not today).
  String opensOrCloses(
    WidgetTester tester,
    int hour, {
    required bool open,
    String? day,
  }) {
    final card = tester.element(find.byType(PlaceCard));
    final time = MaterialLocalizations.of(card).formatTimeOfDay(
      TimeOfDay(hour: hour, minute: 0),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(card),
    );
    final at = day == null ? time : '$day $time';
    return open
        ? l10n.placeDetailsOpenCloses(at)
        : l10n.placeDetailsClosedOpens(at);
  }

  testWidgets('without an OpenStreetMap id there is no Details button', (
    tester,
  ) async {
    await pumpCard(tester, _anonymous);
    expect(detailsButton(), findsNothing);
    expect(find.text(l10n.placeCardOpenIn), findsOneWidget);
  });

  testWidgets('nothing is fetched until Details is tapped', (tester) async {
    await pumpCard(tester, _cafe);
    expect(details.asked, isEmpty);
    expect(detailsButton(), findsOneWidget);
  });

  testWidgets('Details shows a spinner, then the rows, with links', (
    tester,
  ) async {
    details
      ..answer = _full
      ..gate = Completer<void>();
    await pumpCard(tester, _cafe);

    await tester.tap(detailsButton());
    await tester.pump();
    expect(details.asked, <String>['node/1234']);
    expect(detailsButton(), findsNothing);
    expect(
      find.descendant(
        of: find.byType(PlaceCard),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );

    details.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(PlaceDetailsView), findsOneWidget);
    final card = tester.element(find.byType(PlaceDetailsView));
    final six = MaterialLocalizations.of(card).formatTimeOfDay(
      const TimeOfDay(hour: 18, minute: 0),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(card),
    );
    expect(find.text(l10n.placeDetailsOpenCloses(six)), findsOneWidget);
    expect(find.text('Mo-Fr 08:00-18:00'), findsOneWidget);
    expect(find.text('Sa 09:00-12:00'), findsOneWidget);
    expect(
      find.text(l10n.placeDetailsCuisine('coffee shop, ice cream')),
      findsOneWidget,
    );
    expect(find.text(l10n.placeDetailsWheelchairYes), findsOneWidget);
    expect(find.text(l10n.placeDetailsOutdoorSeating), findsOneWidget);

    await tester.tap(find.text('cafe-wolf.example'));
    await tester.tap(find.text('+423 232 00 00'));
    await tester.tap(find.text(l10n.placeDetailsWikipedia('Café Wolf')));
    expect(opened, <Uri>[
      Uri.parse('https://www.cafe-wolf.example/'),
      Uri.parse('tel:+4232320000'),
      Uri.parse('https://de.wikipedia.org/wiki/Caf%C3%A9_Wolf'),
    ]);

    // Fetched, the rows stay and Details has nothing more to do.
    expect(detailsEnabled(tester), isFalse);
    await tester.tap(detailsButton(), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(PlaceDetailsView), findsOneWidget);
    expect(details.asked, hasLength(1));
  });

  testWidgets('hours it cannot read are shown without a status', (
    tester,
  ) async {
    details.answer = const {'opening_hours': 'Mo-Fr sunrise-sunset'};
    await pumpCard(tester, _cafe);
    await tester.tap(detailsButton());
    await tester.pumpAndSettle();
    expect(find.text('Mo-Fr sunrise-sunset'), findsOneWidget);
    expect(find.textContaining(l10n.placeDetailsOpenNow), findsNothing);
    expect(find.textContaining(l10n.placeDetailsClosed), findsNothing);
  });

  testWidgets('nothing on OpenStreetMap says so, and is not asked again', (
    tester,
  ) async {
    await pumpCard(tester, _cafe);
    await tester.tap(detailsButton());
    await tester.pumpAndSettle();
    expect(find.text(l10n.placeDetailsNone), findsOneWidget);
    expect(detailsEnabled(tester), isFalse);

    await pumpCard(tester, _cafe);
    expect(find.text(l10n.placeDetailsNone), findsOneWidget);
    expect(detailsEnabled(tester), isFalse);
    expect(details.asked, hasLength(1));
  });

  testWidgets('a failed request offers a retry', (tester) async {
    details.error = const OsmDetailsException('offline');
    await pumpCard(tester, _cafe);
    await tester.tap(detailsButton());
    await tester.pumpAndSettle();
    expect(find.text(l10n.placeDetailsFailed), findsOneWidget);
    expect(detailsEnabled(tester), isTrue);

    // Not kept: a card opened again has to fetch.
    await pumpCard(tester, _cafe);
    expect(find.text(l10n.placeDetailsFailed), findsNothing);
    expect(find.byType(PlaceDetailsView), findsNothing);
    await tester.tap(detailsButton());
    await tester.pumpAndSettle();
    expect(find.text(l10n.placeDetailsFailed), findsOneWidget);

    details
      ..error = null
      ..answer = _full;
    await tester.tap(find.text(l10n.commonRetry));
    await tester.pumpAndSettle();
    expect(find.text(l10n.placeDetailsFailed), findsNothing);
    expect(find.byType(PlaceDetailsView), findsOneWidget);
    expect(detailsEnabled(tester), isFalse);
    expect(details.asked, hasLength(3));
  });

  testWidgets('after a failure, Details itself tries again', (tester) async {
    details.error = const OsmDetailsException('offline');
    await pumpCard(tester, _cafe);
    await tester.tap(detailsButton());
    await tester.pumpAndSettle();
    details
      ..error = null
      ..answer = _full;
    await tester.tap(detailsButton());
    await tester.pumpAndSettle();
    expect(find.byType(PlaceDetailsView), findsOneWidget);
    expect(details.asked, hasLength(2));
  });

  testWidgets('details fetched lately show at once on the next card', (
    tester,
  ) async {
    details.answer = _full;
    await pumpCard(tester, _cafe);
    await tester.tap(detailsButton());
    await tester.pumpAndSettle();
    expect(find.text(opensOrCloses(tester, 18, open: true)), findsOneWidget);

    // The same container, the card closed and opened again.
    await tester.tap(find.byTooltip(l10n.placeCardClose));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(PlaceDetailsView), findsOneWidget);
    expect(detailsEnabled(tester), isFalse);

    // After a restart, in the evening: told open or closed anew.
    await pumpCard(tester, _cafe, now: DateTime(2026, 10, 5, 19));
    expect(find.byType(PlaceDetailsView), findsOneWidget);
    expect(detailsEnabled(tester), isFalse);
    expect(find.text(opensOrCloses(tester, 18, open: true)), findsNothing);
    final tuesday = DateFormat.E(l10n.localeName).format(DateTime(2026, 10, 6));
    expect(
      find.text(opensOrCloses(tester, 8, open: false, day: tuesday)),
      findsOneWidget,
    );
    expect(details.asked, hasLength(1));

    // A week and more later they are fetched again, on a tap.
    await pumpCard(tester, _cafe, now: DateTime(2026, 10, 12, 10, 1));
    expect(find.byType(PlaceDetailsView), findsNothing);
    expect(detailsEnabled(tester), isTrue);
    expect(details.asked, hasLength(1));
    await tester.tap(detailsButton());
    await tester.pumpAndSettle();
    expect(find.byType(PlaceDetailsView), findsOneWidget);
    expect(details.asked, hasLength(2));
  });

  testWidgets('Open in on Android: the map apps, OpenStreetMap and sharing', (
    tester,
  ) async {
    await pumpCard(tester, _cafe);
    await openSheet(tester);
    expect(find.byType(CupertinoActionSheet), findsNothing);
    expect(find.text(l10n.placeCardOpenInTitle), findsOneWidget);
    expect(sheetRows(tester), <String>[
      l10n.placeCardOpenInMapApp,
      l10n.serviceOpenStreetMap,
      l10n.placeCardShare,
    ]);
    expect(find.text(l10n.commonCancel), findsOneWidget);

    await tester.tap(find.text(l10n.placeCardOpenInMapApp));
    await tester.pumpAndSettle();
    expect(opened.single.scheme, 'geo');
    expect(opened.single.toString(), contains('(Caf%C3%A9%20Wolf)'));

    await openSheet(tester);
    await tester.tap(find.text(l10n.serviceOpenStreetMap));
    await tester.pumpAndSettle();
    expect(opened.last, Uri.parse('https://www.openstreetmap.org/node/1234'));

    await openSheet(tester);
    await tester.tap(find.text(l10n.placeCardShare));
    await tester.pumpAndSettle();
    expect(shared, <String>[
      'Café Wolf\nhttps://www.openstreetmap.org/node/1234',
    ]);
    // The card stays open.
    expect(find.byType(PlaceCard), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets(
    'Open in on iOS: Apple Maps, and Google Maps only when installed',
    (tester) async {
      await pumpCard(tester, _anonymous);
      await openSheet(tester);
      expect(find.byType(CupertinoActionSheet), findsOneWidget);
      expect(find.text(l10n.placeCardOpenInTitle), findsOneWidget);
      expect(sheetActions(tester), <String>[
        l10n.serviceAppleMaps,
        l10n.serviceOpenStreetMap,
        l10n.placeCardShare,
        l10n.commonCancel,
      ]);

      await tester.tap(find.text(l10n.serviceAppleMaps));
      await tester.pumpAndSettle();
      expect(opened.single.host, 'maps.apple.com');

      // Without an element, OpenStreetMap gets a marker at the place.
      await openSheet(tester);
      await tester.tap(find.text(l10n.serviceOpenStreetMap));
      await tester.pumpAndSettle();
      expect(opened.last.queryParameters['mlat'], '47.140500');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('Open in on iOS with Google Maps installed', (tester) async {
    googleMapsInstalled = true;
    await pumpCard(tester, _cafe);
    await openSheet(tester);
    expect(sheetActions(tester), <String>[
      l10n.serviceAppleMaps,
      l10n.serviceGoogleMaps,
      l10n.serviceOpenStreetMap,
      l10n.placeCardShare,
      l10n.commonCancel,
    ]);
    await tester.tap(find.text(l10n.serviceGoogleMaps));
    await tester.pumpAndSettle();
    expect(opened.single.scheme, 'comgooglemaps');
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('Cancel closes the sheet and opens nothing', (tester) async {
    await pumpCard(tester, _cafe);
    await openSheet(tester);
    await tester.tap(find.text(l10n.commonCancel));
    await tester.pumpAndSettle();
    expect(find.text(l10n.placeCardOpenInTitle), findsNothing);
    expect(find.byType(PlaceCard), findsOneWidget);

    // Nor does a tap beside it.
    await openSheet(tester);
    await tester.tapAt(const Offset(200, 20));
    await tester.pumpAndSettle();
    expect(find.text(l10n.placeCardOpenInTitle), findsNothing);
    expect(find.byType(PlaceCard), findsOneWidget);
    expect(opened, isEmpty);
    expect(shared, isEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('Cancel on Android opens nothing either', (tester) async {
    await pumpCard(tester, _cafe);
    await openSheet(tester);
    await tester.tap(find.text(l10n.commonCancel));
    await tester.pumpAndSettle();
    expect(find.text(l10n.placeCardOpenInTitle), findsNothing);
    expect(find.byType(PlaceCard), findsOneWidget);
    expect(opened, isEmpty);
    expect(shared, isEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('everything fits on a small phone with the details open', (
    tester,
  ) async {
    details.answer = _full;
    await pumpCard(
      tester,
      _cafe,
      actions: const [PlaceAction.addStop, PlaceAction.destination],
      size: const Size(375, 667),
    );
    await tester.tap(detailsButton());
    await tester.pumpAndSettle();
    expect(find.byType(PlaceDetailsView), findsOneWidget);
    expect(tester.takeException(), isNull);
    expectNoClippedText(tester);
  });
}
