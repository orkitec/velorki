/// Where the planner is allowed to get its routes from.
///
/// The default, [auto], is the plan's composite rule: on-device whenever every
/// tile a route needs is downloaded, the routing server otherwise. The other
/// two exist for riders who want to be sure — no mobile data, or no 250 MB
/// downloads.
enum RoutingPreference {
  /// On device when the tiles are there, the server otherwise.
  auto,

  /// Never ask the server; routes outside the downloaded tiles fail with
  /// "download N tiles".
  onDeviceOnly,

  /// Always ask the server, even where tiles are downloaded.
  serverOnly;

  /// The value stored under [name], or [auto] for anything unknown.
  static RoutingPreference fromName(String? name) {
    for (final value in RoutingPreference.values) {
      if (value.name == name) return value;
    }
    return RoutingPreference.auto;
  }

  /// Whether the on-device engine may be used.
  bool get allowsLocal => this != RoutingPreference.serverOnly;

  /// Whether the routing server may be used.
  bool get allowsRemote => this != RoutingPreference.onDeviceOnly;
}
