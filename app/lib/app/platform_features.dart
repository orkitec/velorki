import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the device the app runs on lets it do, for the screens that offer
/// a feature only where it works.
///
/// The phone and the tablet can do everything. The browser plans, searches,
/// keeps a library and exports, but it does not record a ride (no
/// background location, no foreground service), so it does not navigate
/// either; it has no store to sell Plus through, no Bluetooth sensors or
/// health store, no native offline map packs, and the services' OAuth
/// returns to an app link a page cannot receive.
@immutable
class PlatformFeatures {
  /// Creates a feature set; everything is there unless said otherwise.
  const PlatformFeatures({
    this.recording = true,
    this.storePurchases = true,
    this.accountConnections = true,
    this.offlineMapAreas = true,
  });

  /// A phone or a tablet.
  static const PlatformFeatures device = PlatformFeatures();

  /// A browser.
  static const PlatformFeatures browser = PlatformFeatures(
    recording: false,
    storePurchases: false,
    accountConnections: false,
    offlineMapAreas: false,
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
}

/// The features of the device the app runs on. The one place that asks
/// whether this is a browser; tests override it to see the browser's app.
final platformFeaturesProvider = Provider<PlatformFeatures>(
  (ref) => kIsWeb ? PlatformFeatures.browser : PlatformFeatures.device,
);
