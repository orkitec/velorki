import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart'
    show BuildContext, MaterialScrollBehavior, ScrollableDetails, Widget;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the device the app runs on lets it do, for the screens that offer
/// a feature only where it works.
///
/// The phone and the tablet can do everything. The browser plans, searches,
/// keeps a library and exports, but it does not record a ride (no
/// background location, no foreground service), so it does not navigate
/// either; it has no store to sell Plus through, no Bluetooth sensors or
/// health store, no native offline map packs, no iCloud, the services'
/// OAuth returns to an app link a page cannot receive, and it routes on its
/// own, never on the routing server.
@immutable
class PlatformFeatures {
  /// Creates a feature set; everything is there unless said otherwise.
  const PlatformFeatures({
    this.recording = true,
    this.storePurchases = true,
    this.accountConnections = true,
    this.offlineMapAreas = true,
    this.cloudSync = true,
    this.routingServer = true,
    this.mouseDrags = false,
    this.storeListing = true,
  });

  /// A phone or a tablet.
  static const PlatformFeatures device = PlatformFeatures();

  /// A browser.
  static const PlatformFeatures browser = PlatformFeatures(
    recording: false,
    storePurchases: false,
    accountConnections: false,
    offlineMapAreas: false,
    cloudSync: false,
    routingServer: false,
    mouseDrags: true,
    storeListing: false,
  );

  /// The Record tab, ride recording and turn-by-turn navigation with their
  /// settings, sensors and voice.
  final bool recording;

  /// Buying Velorki Plus through the platform's store.
  final bool storePurchases;

  /// Connecting Strava and Ride with GPS.
  final bool accountConnections;

  /// Downloading map areas for use offline.
  final bool offlineMapAreas;

  /// Syncing the library through iCloud, where the platform has it (iOS).
  final bool cloudSync;

  /// Asking the routing server (`VELORKI_BROUTER_URL`) for a route the
  /// downloaded tiles do not cover. Without it routes are computed on the
  /// device only, and the tiles a route needs are fetched as soon as it
  /// needs them (`MissingTilesBanner`) rather than offered for download.
  final bool routingServer;

  /// A mouse or a trackpad drags sheets and lists as a finger does
  /// ([PointerDragScrollBehavior]): in a browser they are how the page is
  /// used, where Flutter's default lets them only click and wheel.
  final bool mouseDrags;

  /// An app installed from a store listing: the store's rating dialog and
  /// the notice that the store has a newer version.
  final bool storeListing;
}

/// The app's scroll behaviour where [PlatformFeatures.mouseDrags]: a drag
/// with the mouse or on a trackpad moves a sheet by its handle and scrolls
/// a list, as a touch does. The wheel still scrolls as before.
///
/// Scrollbars are the phone's: only those the app draws itself (the
/// sheets' thin bar, the search results'). Material's desktop default puts
/// one on every vertical list, which beside a sheet's own made two.
class PointerDragScrollBehavior extends MaterialScrollBehavior {
  /// Creates the behaviour.
  const PointerDragScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;

  @override
  Set<PointerDeviceKind> get dragDevices => <PointerDeviceKind>{
    ...super.dragDevices,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
  };
}

/// The features of the device the app runs on. The one place that asks
/// whether this is a browser; tests override it to see the browser's app.
final platformFeaturesProvider = Provider<PlatformFeatures>(
  (ref) => kIsWeb ? PlatformFeatures.browser : PlatformFeatures.device,
);
