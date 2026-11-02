import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'ride_start_request.g.dart';

/// Someone outside the record screen has asked for a ride to start, with the
/// follow choice already set (the Plan tab's Ride button).
///
/// Starting is not something a controller can do on its own: the location
/// explanation, the permissions and the battery prompt are asked by the
/// record screen, and the Start ride button there is the one way through
/// them. So the request is raised and the screen, once it is showing, takes
/// it up and runs that very flow.
///
/// Kept alive, because the screen it is waiting for may not exist yet.
@Riverpod(keepAlive: true)
class RideStartRequest extends _$RideStartRequest {
  @override
  bool build() => false;

  /// Asks for a ride to start.
  void raise() => state = true;

  /// Taken up, by the screen that is now starting the ride.
  void clear() => state = false;
}
