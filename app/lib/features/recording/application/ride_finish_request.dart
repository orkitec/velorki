import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'ride_finish_request.g.dart';

/// Someone outside the record screen has asked for the ride to be finished.
///
/// Finishing is not something a controller can do on its own: the rider names
/// the ride on a sheet, and the sheet also offers to carry on instead. So a
/// stop that comes from somewhere else — the watch on the rider's wrist — puts
/// the recording down and raises this; the record screen sees it and opens the
/// very sheet its own stop button opens, whenever the phone is next looked at.
///
/// Kept alive, because the screen it is waiting for may not exist yet.
@Riverpod(keepAlive: true)
class RideFinishRequest extends _$RideFinishRequest {
  @override
  bool build() => false;

  /// Asks for the ride to be finished.
  void raise() => state = true;

  /// Taken up, by the screen that is now showing the sheet.
  void clear() => state = false;
}
