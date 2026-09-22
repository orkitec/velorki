import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/ride_range.dart';

part 'ride_highlight.g.dart';

/// The split or climb the rider picked on the ride card, shaded on its
/// charts, drawn over the track on the shared map and named by a chip over
/// the map; `null` for none.
///
/// A provider rather than the card's own state because the chip sits over
/// the map, outside the sheet the card's content scrolls in: the ride page
/// writes it, the Library card reads it for the chip, and the chip clears it.
@Riverpod(keepAlive: true)
class RideHighlight extends _$RideHighlight {
  @override
  RideRange? build() => null;

  /// Records the pick, or that there is none.
  void set(RideRange? range) {
    if (!ref.mounted || state == range) return;
    state = range;
  }
}
