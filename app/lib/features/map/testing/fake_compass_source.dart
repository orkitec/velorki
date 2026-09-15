import 'dart:async';

import '../data/compass_heading.dart';

/// A [CompassSource] a test drives by hand.
///
/// Ships in `lib/` so widget tests outside `features/map` — the recorder's,
/// mostly — can point the phone wherever the test needs it, with no sensors
/// and no platform channel in sight.
class FakeCompassSource implements CompassSource {
  /// Creates a compass pointing at [initial], or at nothing yet when that is
  /// left out.
  FakeCompassSource({double? initial}) : _last = initial;

  final StreamController<double> _controller =
      StreamController<double>.broadcast();

  double? _last;

  /// The heading the phone points in, if it has been told one.
  double? get heading => _last;

  @override
  Stream<double> get headings async* {
    // A listener that arrives late still learns where the phone points, the
    // way the real compass tells it within a tenth of a second.
    final last = _last;
    if (last != null) yield last;
    yield* _controller.stream;
  }

  /// Points the phone at [degrees].
  void point(double degrees) {
    _last = degrees;
    _controller.add(degrees);
  }

  /// Closes the stream, for a test that wants its listeners gone.
  Future<void> close() => _controller.close();
}
