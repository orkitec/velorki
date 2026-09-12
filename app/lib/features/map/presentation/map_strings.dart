/// User facing English strings for the map feature.
///
/// They live here rather than in `lib/l10n/app_en.arb` only until the ARB file
/// is free to edit; every constant below is meant to move over unchanged.
abstract final class MapStrings {
  // Attribution.
  static const String attributionOsm = '© OpenStreetMap contributors';
  static const String attributionOpenFreeMap = 'OpenFreeMap';
  static const String attributionCyclosm = 'CyclOSM';
  static const String attributionTitle = 'Map data and tiles';
  static const String attributionOsmUrl =
      'https://www.openstreetmap.org/copyright';
  static const String attributionOpenFreeMapUrl = 'https://openfreemap.org/';
  static const String attributionCyclosmUrl = 'https://www.cyclosm.org/';
  static const String attributionBody =
      'Map data from OpenStreetMap, available under the Open Database '
      'Licence. Vector tiles by OpenFreeMap; the optional cycling overlay is '
      'rendered by CyclOSM on OpenStreetMap Foundation tile servers.';
  static const String close = 'Close';

  // Controls.
  static const String locateMe = 'Show my position';
  static const String toggleCyclosm = 'Cycling map overlay';
  static const String routingTiles = 'Offline routing data';
  static const String zoomIn = 'Zoom in';
  static const String zoomOut = 'Zoom out';

  // Location permission.
  static const String locationRationaleTitle = 'Show your position?';
  static const String locationRationaleBody =
      'Velorki uses your location to centre the map on you and to record '
      'rides. The position stays on this device; it is never uploaded.';
  static const String locationRationaleAllow = 'Continue';
  static const String locationRationaleDeny = 'Not now';
  static const String locationDenied =
      'Location permission is needed to show your position.';
  static const String locationDeniedForever =
      'Location permission is turned off for Velorki. Enable it in the system '
      'settings.';
  static const String locationServiceDisabled =
      'Location services are switched off on this device.';
  static const String openSettings = 'Settings';
  static const String locationUnavailable = 'No position fix yet.';

  // Offline regions.
  static const String offlineRegionsTitle = 'Offline maps';
  static const String offlineRegionsSubtitle =
      'Download map areas for rides without a signal';
  static const String offlineRegionsEmpty =
      'No offline areas yet. Open the planner, move the map to the area you '
      'want and download it from here.';
  static const String downloadVisibleArea = 'Download visible area';
  static const String downloadNeedsMap =
      'Open this screen from the map to download the area you are looking at.';
  static const String downloadBlockedByCyclosm =
      'Offline download is not available while the CyclOSM overlay is on: the '
      'OpenStreetMap Foundation tile policy forbids bulk downloading those '
      'tiles. Turn the overlay off and download the vector base map instead.';
  static const String downloading = 'Downloading…';
  static const String deleteRegion = 'Delete';
  static const String deleteRegionTitle = 'Delete offline area?';
  static const String deleteRegionBody =
      'The downloaded tiles are removed from this device.';
  static const String cancel = 'Cancel';
  static const String downloadFailed = 'Download failed.';
  static const String regionNameDefault = 'Map area';

  /// "12.3 MB", or "—" while the size is still unknown.
  static String formatBytes(int bytes) {
    if (bytes <= 0) return '—';
    const units = <String>['B', 'kB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final digits = value >= 100 || unit == 0 ? 0 : 1;
    return '${value.toStringAsFixed(digits)} ${units[unit]}';
  }
}
