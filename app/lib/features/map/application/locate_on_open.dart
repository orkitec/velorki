import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/painting.dart' show EdgeInsets;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:velorki_geo/velorki_geo.dart';

import '../../../app/router.dart' show libraryRoute;
import '../../../core/permissions/location_permission.dart';
import '../../planner/application/planner_controller.dart';
import '../../recording/application/recording_controller.dart';
import '../../recording/data/recording_recovery.dart';
import '../../shared/application/active_tab.dart';
import '../data/position_provider.dart';
import '../domain/map_controller.dart';
import '../presentation/shared_map_host.dart';

/// How long the app has to have been away for a return to count as opening
/// it again.
const Duration locateOnOpenAway = Duration(minutes: 30);

/// How long the first fix may take before the move is given up.
const Duration locateOnOpenFixTimeout = Duration(seconds: 10);

/// The zoom the map goes to when it was further out than
/// [locateOnOpenMinZoom].
const double locateOnOpenZoom = 14;

/// A map at this zoom or closer keeps its zoom when it moves to the rider.
const double locateOnOpenMinZoom = 12;

/// How old the phone's last known position may be to be moved to at once.
const Duration locateOnOpenLastKnownAge = Duration(hours: 1);

/// How far the live fix has to be from where the map was centred on the
/// last known position for the map to move again.
const double locateOnOpenCorrectionM = 300;

/// Moves the shared map to the rider when the app is opened.
///
/// The rule: on a cold start, and on a return to the foreground after at
/// least [locateOnOpenAway] in the background, the map first shows the view
/// it was left at, so it is never blank. Then it glides to the rider, into
/// the middle of the part of the map the rider can see, keeping its zoom at
/// [locateOnOpenMinZoom] or closer and going to [locateOnOpenZoom]
/// otherwise: at once to the position the phone already holds, when that is
/// younger than [locateOnOpenLastKnownAge], and then to the first live fix
/// (network accuracy, within [locateOnOpenFixTimeout]) — which, after a
/// move to the held position, only moves the map again when it lies more
/// than [locateOnOpenCorrectionM] from it, so the map does not twitch.
/// Only with the location permission already granted; nothing here ever
/// asks for it. It stays put when the move would get in the way: a plan on
/// the Plan tab, a route or ride card open on the Library tab, a ride being
/// recorded, the rider already in view, or the rider's own hand on the map
/// (a pan, a zoom or a tap) before the move.
class LocateOnOpen {
  /// Creates the controller over [_ref].
  LocateOnOpen(this._ref);

  final Ref _ref;

  /// What covers the map's edges right now, set by the shell; the map's
  /// whole area when unset.
  EdgeInsets Function()? visiblePadding;

  /// Whether the Library tab shows a route or a ride card, set by the
  /// shell.
  bool Function()? cardOpen;

  int _generation = 0;
  bool _touched = false;
  DateTime? _pausedAt;

  /// The rider's hand on the map: whatever move is pending is off.
  void touched() => _touched = true;

  /// The app went to the background at [at].
  void paused(DateTime at) => _pausedAt ??= at;

  /// The app came back at [at]; after long enough away that counts as
  /// opening it. Completes with whether the map moved.
  Future<bool> resumed(DateTime at) {
    final since = _pausedAt;
    _pausedAt = null;
    if (since == null || at.difference(since) < locateOnOpenAway) {
      return Future<bool>.value(false);
    }
    return opened();
  }

  /// The app was opened. Completes with whether the map moved.
  Future<bool> opened() async {
    final generation = ++_generation;
    _touched = false;
    bool stale() => generation != _generation || _touched;

    LocationPermissionStatus status;
    try {
      status = await _ref.read(locationPermissionGatewayProvider).check();
    } on Object {
      return false;
    }
    if (status != LocationPermissionStatus.granted || stale()) return false;
    final source = _ref.read(positionSourceProvider);

    // What the phone already knows, from Wi-Fi, cell towers or any app's
    // recent fix: there at once and at no cost, when it is recent.
    LatLng? centred;
    try {
      final held = await source.lastKnown();
      if (held != null &&
          DateTime.now().difference(held.timestamp) <
              locateOnOpenLastKnownAge &&
          !stale()) {
        final at = LatLng(held.latitude, held.longitude);
        if (await _move(at, stale)) centred = at;
      }
    } on Object {
      // No held position is no reason not to wait for a live one.
    }
    if (stale()) return centred != null;

    final LatLng fix;
    try {
      // The source answers `null` once the time limit is up. Network
      // accuracy is what a map at street level needs, and it comes long
      // before a satellite fix.
      final position = await source.current(
        timeLimit: locateOnOpenFixTimeout,
        accuracy: geo.LocationAccuracy.medium,
      );
      if (position == null) return centred != null;
      fix = LatLng(position.latitude, position.longitude);
    } on Object {
      return centred != null;
    }
    if (stale()) return centred != null;
    if (centred == null) return _move(fix, stale);
    // Already on the rider: only a fix well away is worth a second move.
    if (haversineMeters(centred, fix) <= locateOnOpenCorrectionM) return true;
    await _move(fix, stale, evenInView: true);
    return true;
  }

  /// Moves the map to [target] unless the move would get in the way; with
  /// [evenInView], also when [target] is on screen already. Completes with
  /// whether it moved.
  Future<bool> _move(
    LatLng target,
    bool Function() stale, {
    bool evenInView = false,
  }) async {
    final map = await _map();
    if (map == null || stale() || _inTheWay()) return false;
    final padding = visiblePadding?.call() ?? EdgeInsets.zero;
    final zoom = map.zoom;
    if (!evenInView && zoom != null && _inView(map, target, padding, zoom)) {
      return false;
    }
    await map.moveTo(
      target,
      zoom: zoom != null && zoom >= locateOnOpenMinZoom
          ? zoom
          : locateOnOpenZoom,
      padding: padding,
    );
    return true;
  }

  /// Whether something on screen would be disturbed by the move.
  bool _inTheWay() {
    if (_ref.read(plannerControllerProvider).waypoints.isNotEmpty) return true;
    if (_ref.read(recordingControllerProvider).isRecording) return true;
    // A ride found at launch brings Record up, whose camera follows it.
    if (_ref.read(recordingRecoveryProvider).value
        case ReattachRecording() || InterruptedRecording()) {
      return true;
    }
    return _ref.read(activeTabProvider) == libraryRoute &&
        (cardOpen?.call() ?? false);
  }

  /// The shared map, waited for while it is still loading its style; the
  /// wait ends with the next open, which starts one of its own.
  Future<MapController?> _map() async {
    final now = _ref.read(sharedMapControllerProvider);
    if (now != null) return now;
    _waiting?.close();
    final ready = Completer<MapController?>();
    _waiting = _ref.listen<MapController?>(sharedMapControllerProvider, (
      _,
      next,
    ) {
      if (next != null && !ready.isCompleted) ready.complete(next);
    });
    try {
      return await ready.future;
    } finally {
      _waiting?.close();
      _waiting = null;
    }
  }

  ProviderSubscription<MapController?>? _waiting;

  /// Whether [pos] lies in the part of [map] that [padding] leaves visible.
  static bool _inView(
    MapController map,
    LatLng pos,
    EdgeInsets padding,
    double zoom,
  ) {
    final bounds = map.visibleBounds;
    if (bounds == null) return false;
    // Degrees per logical pixel on a map of 512-pixel tiles; near enough
    // over the height of a phone.
    final perPixel = 360 / (512 * math.pow(2, zoom));
    final latPerPixel = perPixel * math.cos(pos.lat * math.pi / 180);
    return pos.lat <= bounds.north - padding.top * latPerPixel &&
        pos.lat >= bounds.south + padding.bottom * latPerPixel &&
        pos.lon >= bounds.west + padding.left * perPixel &&
        pos.lon <= bounds.east - padding.right * perPixel;
  }
}

/// The one [LocateOnOpen] of the app.
final locateOnOpenProvider = Provider<LocateOnOpen>(LocateOnOpen.new);
