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
