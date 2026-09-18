import 'dart:async';

import 'package:geolocator/geolocator.dart' as geo;

import 'position_provider.dart';

/// One platform position stream shared by everyone who wants fixes.
///
/// geolocator on iOS allows a single position stream: a second `listen` is
/// answered with "already listening" and never delivers a fix. The map's puck
/// and the ride recorder both want fixes, and at the moment a ride starts
/// both are subscribed, so without this the recorder would be the one turned
/// away, silently, and the ride would record nothing.
///
/// Every consumer gets its own stream here; underneath there is at most one
/// subscription to [_inner], configured with the strongest settings any
/// consumer asked for. A background-capable request (the recorder's) wins over
/// the map's, then the finer accuracy, then the smaller distance filter. When
/// the strongest request goes, the platform stream is restarted with what is
/// left; when the last one goes, it is stopped.
class SharedPositionSource implements PositionSource {
  /// Wraps [inner], which talks to the platform.
  SharedPositionSource(PositionSource inner) : _inner = inner;

  final PositionSource _inner;
  final List<_Request> _requests = <_Request>[];
  StreamSubscription<geo.Position>? _subscription;
  geo.LocationSettings? _active;
  Future<void> _reconfiguring = Future<void>.value();

  /// The settings the platform stream currently runs with, or `null` when
  /// nobody is listening. For tests and the odd diagnostic.
  geo.LocationSettings? get activeSettings => _active;

  @override
  Stream<geo.Position> positions(geo.LocationSettings settings) {
    late final _Request request;
    final controller = StreamController<geo.Position>(
      onListen: () {
        _requests.add(request);
        _reconfigure();
      },
      onCancel: () {
        _requests.remove(request);
        _reconfigure();
      },
    );
    request = _Request(settings, controller);
    return controller.stream;
  }

  @override
  Future<geo.Position?> lastKnown() => _inner.lastKnown();

  @override
  Future<geo.Position?> current({
    Duration timeLimit = const Duration(seconds: 10),
  }) => _inner.current(timeLimit: timeLimit);

  /// Restarts the platform stream when the strongest request changed. Serial:
  /// the cancel of the old stream is awaited before the new one is opened,
  /// since the platform only accepts a `listen` once the previous stream has
  /// really gone.
  void _reconfigure() {
    _reconfiguring = _reconfiguring.then((_) async {
      final wanted = _strongest();
      if (wanted == null) {
        await _subscription?.cancel();
        _subscription = null;
        _active = null;
        return;
      }
      final active = _active;
      if (active != null && _sameSettings(active, wanted)) return;
      await _subscription?.cancel();
      _subscription = null;
      _active = wanted;
      _subscription = _inner
          .positions(wanted)
          .listen(
            (position) {
              for (final r in List<_Request>.of(_requests)) {
                r.controller.add(position);
              }
            },
            onError: (Object error, StackTrace stackTrace) {
              for (final r in List<_Request>.of(_requests)) {
                r.controller.addError(error, stackTrace);
              }
            },
          );
    });
  }

  geo.LocationSettings? _strongest() {
    geo.LocationSettings? best;
    for (final r in _requests) {
      if (best == null || _rank(r.settings) > _rank(best)) best = r.settings;
    }
    return best;
  }

  /// Background-capable first, then accuracy, then the smaller distance
  /// filter; the tuple is folded into one comparable number.
  static int _rank(geo.LocationSettings s) {
    final background =
        s is geo.AppleSettings && s.allowBackgroundLocationUpdates ? 1 : 0;
    final filter = (1000 - s.distanceFilter.clamp(0, 1000)).toInt();
    return background * 1000000 + s.accuracy.index * 10000 + filter;
  }

  static bool _sameSettings(geo.LocationSettings a, geo.LocationSettings b) =>
      identical(a, b) ||
      (a.runtimeType == b.runtimeType &&
          a.accuracy == b.accuracy &&
          a.distanceFilter == b.distanceFilter &&
          a.timeLimit == b.timeLimit &&
          (a is! geo.AppleSettings ||
              b is! geo.AppleSettings ||
              (a.allowBackgroundLocationUpdates ==
                      b.allowBackgroundLocationUpdates &&
                  a.pauseLocationUpdatesAutomatically ==
                      b.pauseLocationUpdatesAutomatically &&
                  a.showBackgroundLocationIndicator ==
                      b.showBackgroundLocationIndicator &&
                  a.activityType == b.activityType)));
}

class _Request {
  _Request(this.settings, this.controller);
  final geo.LocationSettings settings;
  final StreamController<geo.Position> controller;
}
