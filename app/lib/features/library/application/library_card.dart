import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'library_card.g.dart';

/// The saved route on the Library's card, or `null` while the card shows
/// the list or a ride.
///
/// The card is a location of the Library branch, which only the branch's
/// navigator knows; the Record tab asks here what the rider was looking at
/// when they came over, to propose that route for the next ride.
@Riverpod(keepAlive: true)
class LibraryCard extends _$LibraryCard {
  @override
  String? build() => null;

  /// Records which route the card shows, `null` for none.
  void show(String? routeId) {
    if (!ref.mounted || state == routeId) return;
    state = routeId;
  }
}

/// Where the rider left the Library's list card this session, as a fraction
/// of the screen; `null` until they have dragged it. Once they have, the
/// card comes back to that height rather than to the one it would choose
/// for itself, until the app restarts.
@Riverpod(keepAlive: true)
class LibraryCardExtent extends _$LibraryCardExtent {
  @override
  double? build() => null;

  /// Records the extent the rider dragged the card to.
  void set(double extent) {
    if (!ref.mounted || state == extent) return;
    state = extent;
  }
}
