/// The cloud a device syncs its library and settings with: Settings →
/// Sync with. One per device.
enum SyncService {
  /// iCloud, through CKSyncEngine (iOS 17 and later).
  icloud,

  /// The hidden app data folder of the rider's Google Drive.
  google,

  /// Nothing leaves the device.
  off;

  /// The service stored as [name], or null.
  static SyncService? fromName(String? name) {
    for (final service in values) {
      if (service.name == name) return service;
    }
    return null;
  }
}
