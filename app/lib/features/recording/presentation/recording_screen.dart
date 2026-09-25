import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../../app/router.dart';
import '../../../app/app_config.dart';
import '../../../core/geo/ride_stats.dart';
import '../../../core/permissions/location_permission.dart';
import '../../../app/theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../map/data/compass_heading.dart';
import '../../sensors/application/sensors_seen.dart';
import 'ride_profile_view.dart';
import 'ride_cue_sheet.dart';
import '../../map/data/heading_smoother.dart';
import '../../map/domain/map_controller.dart';
import '../../map/presentation/location_rationale_dialog.dart';
import '../../map/presentation/map_chrome.dart';
import '../../map/presentation/shared_map_host.dart';
import '../../navigation/application/navigation_controller.dart';
import '../../navigation/application/route_cues.dart';
import '../../navigation/application/off_route_thresholds.dart';
import '../../navigation/domain/navigation_progress.dart';
import '../../navigation/presentation/navigation_toggles.dart';
import '../../navigation/presentation/turn_banner.dart';
import '../../navigation/presentation/turn_phrases.dart';
import '../../library/application/library_card.dart';
import '../../planner/application/planner_controller.dart';
import '../../planner/data/route_repository.dart';
import '../../planner/domain/saved_route.dart';
import '../../planner/domain/route_poi.dart';
import '../../planner/presentation/poi_markers.dart';
import '../../planner/presentation/route_format.dart';
import '../../search/data/gazetteer_store.dart';
import '../../sensors/application/ride_health_sync.dart';
import '../../sensors/application/sensor_hub.dart';
import '../../settings/data/units.dart';
import '../../shared/application/active_tab.dart';
import '../../shared/application/nav_bar_docking.dart';
import '../../shared/presentation/docking_sheet.dart';
import '../../shared/presentation/tab_chrome_slide.dart';
import '../../shared/presentation/stat_tile.dart';
import '../../shared/presentation/swipe_pages.dart';
import '../application/recording_controller.dart';
import '../application/ride_finish_request.dart';
import '../data/battery_saver.dart';
import '../data/follow_mode.dart';
import '../data/recording_gateways.dart';
import '../data/recording_recovery.dart';
import '../data/recording_service.dart';
import '../data/recording_settings.dart';
import '../domain/follow_choice.dart';
import '../domain/recording_snapshot.dart';
import '../domain/recording_state.dart';
import '../domain/ride_naming.dart';
import 'follow_route_picker.dart';
import 'recording_format.dart';
import 'save_ride_sheet.dart';

/// Id of the followed route's line on the map.
const String followedRouteLineId = 'follow';

/// Id of the way back onto that route, drawn as a branch beside it.
const String detourRouteLineId = 'detour';

/// Id of the route the ride set out on, drawn faint under a new route that
/// took its place after the rider left it.
const String replacedRouteLineId = 'replaced';

/// Preference key of the one-time battery-optimisation explanation.
const String batteryPromptShownKey = 'recording.batteryPromptShown';

/// The zoom the map follows the rider at; a camera that is already closer
/// keeps its zoom.
const double followZoom = 16;

/// How far the camera may come to rest from the fix we last moved it to
/// before that counts as the rider having panned the map by hand.
///
/// Wide enough that a fix arriving mid-animation, or the small drift of an
/// animated move, is not mistaken for a pan; narrow enough that a deliberate
/// drag always is.
const double handPanMeters = 40;

/// How far north-up may drift from north at a camera idle before that counts
/// as the rider having turned the map by hand.
const double handRotationDegrees = 5;

/// The same, in heading-up, measured against the bearing we last asked for.
///
/// Wider than [handRotationDegrees]: the camera is animating towards a new
/// heading most of the time, so it rarely rests on exactly the one we asked
/// for, and only a deliberate twist opens a gap this large.
const double handRotationFollowDegrees = 20;

/// How long a follow move is given.
///
/// About the gap between two recording fixes, so the camera is still gliding
/// towards this one when the next arrives, instead of jumping and waiting.
const Duration followCameraDuration = Duration(milliseconds: 1000);

/// How far the heading has to have moved before the camera is turned with it.
///
/// A degree or two either way is the GPS breathing, not the rider steering,
/// and a map that answers it is a map that never stands still.
const double cameraBearingDeadbandDegrees = 8;

/// Below this ground speed the map keeps the bearing it has.
const double cameraBearingMinSpeedMps = 1.5;

/// How often a compass heading on its own may redraw the puck.
///
/// Standing still there is no next fix coming to carry a fresh heading to the
/// map, so the compass has to push one itself — five times a second is more
/// than the eye follows and far less than the sensor offers.
const Duration compassPushInterval = Duration(milliseconds: 200);

/// How far the rider's own course may differ from the route's direction
/// before the route stops speaking for them. Riding the route backwards, or
/// turning off it, the course is the truth; a cone glued to the road pointed
/// the wrong way for both.
const double routeBearingAgreementDegrees = 45;

/// How long the record screen waits for a touch before it drops to the glance
/// view, while a battery-saver ride runs.
const Duration glanceAfter = Duration(seconds: 30);

/// The screen brightness a battery-saver ride runs at, while the screen is
/// being held awake. Bright enough to read in daylight, less than half the
/// energy of a display at full tilt.
const double saverBrightness = 0.4;

/// The Record tab: start a ride, watch the numbers, finish it.
class RecordingScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const RecordingScreen({super.key});

  @override
  ConsumerState<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends ConsumerState<RecordingScreen> {
  /// The shared map, while it can be driven.
  MapController? _map;

  /// Whether this tab's layers and camera idle handler are on the shared
  /// map right now: while it is the tab on screen and the map is usable.
  bool _drawing = false;

  /// Whether the map still has to be turned back north for a ride that
  /// ended while this tab was away.
  bool _northDue = false;

  bool _keepScreenOn = false;

  /// Whether the map and the sheet have given way to the glance view: the
  /// figures on black, the way a bike computer shows them.
  bool _glance = false;

  /// The countdown to that, restarted by every touch.
  Timer? _glanceTimer;

  /// The sheet's snap points, kept as one instance for as long as the
  /// normal size holds. DraggableScrollableSheet compares the list by
  /// identity and snaps to the nearest point on every rebuild it sees a
  /// new one, which cancels a drag in flight; the screen rebuilds several
  /// times a second while a ride runs.
  List<double> _snapSizes = const [];

  /// Whether a battery-saver ride is running, as the last build saw it.
  bool _saverRide = false;

  /// Whether this is the tab on screen.
  bool _active = false;

  /// The hint under the idle headline, rolled anew whenever the tab comes up.
  int _hintIndex = math.Random().nextInt(idleHintCount);

  /// Where the sheet starts when this screen is built in the middle of a
  /// change to its tab: where the other tab's sheet is, so the two match
  /// from the first frame; `null` once the sheet has taken over.
  double? _arrivingExtent;

  @override
  void initState() {
    super.initState();
    _active = ref.read(activeTabProvider) == recordingRoute;
    _map = ref.read(sharedMapControllerProvider);
    _updateMapUse();
    // Built in the middle of a change to this tab (its first visit, from
    // another tab): the listener in build sees no change, so the sheet is
    // started from here.
    final tabs = ref.read(activeTabProvider.notifier);
    final arriving = _active && tabs.previous != null;
    if (!arriving) return;
    // After the frame: a provider may not be written while this one builds.
    final from = tabs.previous;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _suggestFollow(from);
    });
    _arrivingExtent = ref.read(tabHandoverProvider).sheetExtent;
    // The sheet, once it exists: after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _takeOverSheet();
      setState(() => _arrivingExtent = null);
    });
  }

  /// What the shell's control column was last told about this tab.
  MapChromeData? _chromeData;

  /// Tells the shell's column what this tab wants of it, after the frame.
  void _shareChrome(MapChromeData data) {
    if (data == _chromeData) return;
    _chromeData = data;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _active && _chromeData == data) {
        ref.read(activeMapChromeProvider.notifier).set(data);
      }
    });
  }

  /// Where the map's control column rests under this tab's chrome. The
  /// column itself is one shared, animated value ([mapControlsTopProvider]):
  /// this tab sends it there when it comes on screen and when its chrome
  /// changes while it is.
  double _ownControlsTop = defaultMapControlsTop;

  /// This tab is coming on screen: the column glides from wherever it is
  /// to its place under this tab's chrome.
  void _takeOverControls() =>
      ref.read(mapControlsTopProvider).glide(to: _ownControlsTop);

  /// The idle sheet's controller, for the take-over when the tab comes on
  /// screen. The live sheet is another widget and gets none: a controller
  /// serves one sheet at a time, and the two are swapped in one frame.
  final DraggableScrollableController _idleSheet =
      DraggableScrollableController();

  /// The sheet's extent, while this is the tab on screen, for the tab that
  /// comes next.
  void _onSheetExtent(double extent) {
    if (_active) ref.read(tabHandoverProvider.notifier).setSheetExtent(extent);
  }

  /// The idle sheet's resting size, as computed by the last build.
  double _restingSheetSize = 0.48;

  /// This tab has just come on screen: the idle sheet starts where the last
  /// tab's was and settles where this one's is, so the two tabs read as one
  /// screen re-arranging; and a sheet below its resting height (docked in
  /// the bar, say) rises to it, undocking the bar as it goes. A sheet
  /// already at rest, or pulled higher by the rider, stays; a live sheet is
  /// left alone.
  void _takeOverSheet() {
    if (!_idleSheet.isAttached) return;
    final current = _idleSheet.size;
    final from = ref.read(tabHandoverProvider).sheetExtent ?? current;
    if ((from - current).abs() >= 0.005) _idleSheet.jumpTo(from);
    final target = math.max(current, _restingSheetSize);
    if ((target - from).abs() < 0.005) return;
    unawaited(
      _idleSheet.animateTo(
        target,
        duration: tabSheetSettleDuration,
        curve: tabChromeSlideCurve,
      ),
    );
  }

  /// Whether the sheet was last reported to the bar as docked in it.
  bool _docked = false;
  late final NavBarDocking _docking = ref.read(navBarDockingProvider.notifier);

  void _reportDocked(bool docked) {
    if (docked == _docked) return;
    _docked = docked;
    _docking.setDocked(recordingRoute, docked);
  }

  /// Whether the display is being held at [saverBrightness] by us.
  bool _dimmed = false;

  /// The two screen gateways, kept once read: `ref` is out of bounds in
  /// [dispose], and that is exactly where the display has to be handed back.
  ScreenWake? _wake;
  ScreenDimmer? _dimmer;

  bool _recoveryHandled = false;

  /// Whether a finish asked for from elsewhere — the watch on the rider's
  /// wrist — is already on its way to the save sheet.
  bool _finishRequested = false;

  /// Whether the save sheet is up (or on its way), from any stop.
  bool _stopping = false;

  /// Which page of the live sheet is showing: the figures, or the followed
  /// route's elevation profile. Back to the figures when the ride ends.
  int _sheetPage = 0;

  int _drawnTrackPoints = -1;
  String? _drawnRouteId;
  RouteLineStyle? _drawnRouteStyle;
  String? _drawnBranchId;
  String? _drawnReplacedId;
  String? _drawnPoisId;

  /// Whether the camera stays on the rider. On from the moment a ride starts,
  /// off as soon as the rider drags the map, back on with the locate button.
  bool _following = false;

  /// Whether the camera is moving because *we* moved it. The plugin reports
  /// no gesture source, so the flag plus [_followTarget] is how a hand pan is
  /// told apart from our own follow move: it is set before every move of ours
  /// and cleared by the idle that move ends in.
  bool _autoMoving = false;

  /// The fix the camera was last sent to, the reference a camera idle is
  /// measured against.
  LatLng? _followTarget;

  /// Whether a ride was running on the previous build, so the start of one can
  /// switch following back on.
  bool _wasRecording = false;

  /// Turns the jittery course of each fix into the bearing the map is held
  /// at; the same smoothing the heading cone uses, so cone and map agree.
  final HeadingSmoother _headings = HeadingSmoother();

  /// The bearing heading-up aims for, kept across a stop: a rider waiting at
  /// a red light still faces the way they were going, and the map snapping
  /// back to north there would be worse than a slightly stale heading.
  double? _targetBearing;

  /// The bearing we last asked the camera for.
  ///
  /// The map is only turned when the heading has really moved, so this is
  /// what a move repeats in between, and what a camera idle is measured
  /// against.
  double? _sentBearing;

  /// Where the map currently points, in degrees clockwise from north, so the
  /// compass needle can be drawn turned the same way.
  double _bearing = 0;

  /// Whether [_targetBearing] came from the compass rather than from a course
  /// over ground. A compass bearing means something at a standstill, so the
  /// camera may follow it there; a course may not.
  bool _bearingFromCompass = false;

  /// The snapshot the smoother was last fed, so a rebuild that brings no new
  /// fix does not push the average further along the same course.
  RecordingSnapshot? _fedSnapshot;

  /// The compass heading last drawn, and when, so a standing rider turning
  /// the phone gets a fresh cone without one redraw per sensor sample.
  double? _pushedCompass;
  DateTime? _compassPushedAt;

  @override
  void dispose() {
    if (_keepScreenOn) unawaited(_wake?.disable());
    if (_dimmed) unawaited(_dimmer?.reset());
    _glanceTimer?.cancel();
    if (_drawing) _map?.onCameraIdle = null;
    _idleSheet.dispose();
    if (_docked) {
      // Deferred: the tree is locked while a widget goes, and the shell
      // would rebuild for this.
      final docking = _docking;
      scheduleMicrotask(() => docking.setDocked(recordingRoute, false));
    }
    super.dispose();
  }

  // ------------------------------------------------------- battery saver

  /// Follows the saver in and out of a ride: the glance countdown runs while
  /// one is on and is thrown away with it.
  void _syncSaver(bool saver) {
    if (saver == _saverRide) return;
    _saverRide = saver;
    _glance = false;
    _restartGlanceTimer(saver);
  }

  /// Dims the display for a saver ride, and only while the screen is being
  /// held awake: a screen that switches itself off costs nothing already.
  void _syncBrightness(bool wanted) {
    if (wanted == _dimmed) return;
    _dimmed = wanted;
    final ScreenDimmer dimmer = _dimmer ?? ref.read(screenDimmerProvider);
    _dimmer = dimmer;
    unawaited(wanted ? dimmer.dim(saverBrightness) : dimmer.reset());
  }

  void _restartGlanceTimer(bool saver) {
    _glanceTimer?.cancel();
    _glanceTimer = null;
    if (!saver) return;
    _glanceTimer = Timer(glanceAfter, () {
      if (mounted) setState(() => _glance = true);
    });
  }

  List<double> _snapSizesFor(double initial) {
    if (_snapSizes.length != 1 || _snapSizes.first != initial) {
      _snapSizes = <double>[initial];
    }
    return _snapSizes;
  }

  /// Any touch anywhere brings the map back and buys another 30 seconds.
  void _handlePointerDown() {
    final saver = ref.read(batterySaverActiveProvider);
    if (_glance) setState(() => _glance = false);
    _restartGlanceTimer(saver);
  }

  /// The shared map came, went, or was replaced after a style reload, when
  /// every layer on it is gone. A map that can be drawn on is drawn on by
  /// the next build.
  void _onMapChanged(MapController? map) {
    if (identical(map, _map)) return;
    if (_drawing) {
      _map?.onCameraIdle = null;
      _drawing = false;
    }
    _map = map;
    _updateMapUse();
    if (_drawing && mounted) setState(() {});
  }

  /// Puts this tab's layers and camera idle handler on the shared map while
  /// it is the tab on screen, and takes them off when it is not: the Plan
  /// tab draws its own on the same map, and only one tab's belong there at
  /// a time. The puck is the exception, see [_syncMap].
  void _updateMapUse() {
    final map = _map;
    final wanted = _active && map != null;
    if (wanted == _drawing) return;
    _drawing = wanted;
    if (!wanted) {
      if (map == null) return;
      map.onCameraIdle = null;
      _clearLayers(map);
      return;
    }
    map.onCameraIdle = _handleCameraIdle;
    // Nothing of this tab is on the map yet: the build that follows draws
    // it all, and a ride being followed takes the camera back to the rider
    // once, wherever the other tab left it.
    _drawnTrackPoints = -1;
    _drawnRouteId = null;
    _drawnRouteStyle = null;
    _drawnBranchId = null;
    _drawnReplacedId = null;
    _drawnPoisId = null;
    _autoMoving = false;
    _followTarget = null;
  }

  /// Takes off the map what this tab drew on it, so the other tab finds it
  /// bare.
  void _clearLayers(MapController map) {
    if (_drawnTrackPoints > 0) unawaited(map.setTrackLine(const <LatLng>[]));
    if (_drawnRouteId != null) {
      unawaited(map.removeRouteLine(followedRouteLineId));
    }
    if (_drawnBranchId != null) {
      unawaited(map.removeRouteLine(detourRouteLineId));
    }
    if (_drawnReplacedId != null) {
      unawaited(map.removeRouteLine(replacedRouteLineId));
    }
    if (_drawnPoisId != null) unawaited(map.setPois(const <MapPoi>[]));
    _drawnTrackPoints = -1;
    _drawnRouteId = null;
    _drawnRouteStyle = null;
    _drawnBranchId = null;
    _drawnReplacedId = null;
    _drawnPoisId = null;
  }

  // --------------------------------------------------------- follow mode

  /// Sends the camera to [position] and marks the move as ours.
  void _followTo(
    MapController map,
    LatLng position,
    FollowMode mode, {
    double? speedMps,
    bool fromCompass = false,
    bool saver = false,
  }) {
    _autoMoving = true;
    _followTarget = position;
    // North-up says so on every move; heading-up leaves the map alone until a
    // heading exists, rather than forcing it to north first.
    final double? bearing;
    if (mode == FollowMode.headingUp) {
      bearing = _cameraBearing(
        _targetBearing,
        speedMps,
        fromCompass: fromCompass,
      );
    } else {
      bearing = 0.0;
      _sentBearing = 0;
    }
    unawaited(
      map.moveTo(
        position,
        zoom: math.max(map.zoom ?? followZoom, followZoom),
        bearing: bearing,
        // A saver ride jumps the camera instead of gliding it: an animation
        // is a second of redraws for a move that takes one step anyway.
        animate: !saver,
        duration: saver ? null : followCameraDuration,
      ),
    );
  }

  /// The bearing to hand the camera, which is not always the one we aim for.
  ///
  /// Turning the map costs the rider their bearings, so it is only worth it
  /// when the heading has really moved — and never at a standstill, where the
  /// course is noise and the old bearing is still the right one. A compass
  /// heading is exempt from that last rule: it is at its most useful standing
  /// still, which is the whole point of reading the magnetometer.
  double? _cameraBearing(
    double? wanted,
    double? speedMps, {
    bool fromCompass = false,
  }) {
    final last = _sentBearing;
    if (!fromCompass &&
        last != null &&
        (speedMps ?? 0) < cameraBearingMinSpeedMps) {
      return last;
    }
    if (wanted == null) return last;
    if (last != null &&
        _angleBetween(wanted, last) <= cameraBearingDeadbandDegrees) {
      return last;
    }
    _sentBearing = wanted;
    return wanted;
  }

  /// Whether the map points somewhere else than the heading now says, so a
  /// move is worth making even though the rider has not gone anywhere.
  ///
  /// Mirrors what [_cameraBearing] would decide, so it never asks for a move
  /// that would be handed the bearing the map already has.
  bool _bearingStale(FollowMode mode, double? speedMps) {
    if (mode != FollowMode.headingUp) return false;
    final wanted = _targetBearing;
    if (wanted == null) return false;
    final sent = _sentBearing;
    if (sent == null) return true;
    if (!_bearingFromCompass && (speedMps ?? 0) < cameraBearingMinSpeedMps) {
      return false;
    }
    return _angleBetween(wanted, sent) > cameraBearingDeadbandDegrees;
  }

  /// Whether a compass heading on its own has earned a redraw: a heading we
  /// have not drawn yet, and not within [compassPushInterval] of the last one.
  bool _compassPushDue(double heading) {
    if (heading == _pushedCompass) return false;
    final last = _compassPushedAt;
    if (last != null && DateTime.now().difference(last) < compassPushInterval) {
      return false;
    }
    return true;
  }

  /// Turns the map back to north, for a ride that ended or a rider who left
  /// heading-up: nothing else would ever straighten it again.
  void _resetBearing(MapController map) {
    final center = map.center ?? _followTarget;
    if (center == null) return;
    _headings.reset();
    _targetBearing = null;
    _bearingFromCompass = false;
    _sentBearing = 0;
    _bearing = 0;
    _autoMoving = true;
    _followTarget = center;
    unawaited(map.moveTo(center, bearing: 0));
  }

  /// The map came to rest.
  ///
  /// Our own move ends in exactly one idle, which clears the flag. Any other
  /// idle that leaves the camera far from the fix we aimed at was the rider
  /// dragging the map, and the map is theirs again until they say otherwise.
  void _handleCameraIdle() {
    // Before the early return below: the needle has to follow our own moves
    // as much as the rider's, or heading-up would leave it pointing north.
    final bearing = _map?.bearing;
    if (bearing != null && (bearing - _bearing).abs() > 0.5) {
      if (mounted) setState(() => _bearing = bearing);
    }
    if (_autoMoving) {
      _autoMoving = false;
      return;
    }
    if (!_following) return;
    final map = _map;
    if (map == null) return;
    if (_turnedByHand(map)) {
      if (mounted) setState(() => _following = false);
      return;
    }
    final center = map.center;
    final target = _followTarget;
    if (center == null || target == null) return;
    if (haversineMeters(center, target) <= handPanMeters) return;
    if (mounted) setState(() => _following = false);
  }

  /// Whether the map came to rest turned somewhere we never sent it.
  ///
  /// Rotating the map is as much a way of taking it over as dragging it, so
  /// it ends the following the same way.
  bool _turnedByHand(MapController map) {
    final bearing = map.bearing;
    if (bearing == null) return false;
    final mode = ref.read(followModeProvider);
    final aimedAt = mode == FollowMode.headingUp
        ? _sentBearing ?? _targetBearing ?? 0
        : 0.0;
    final limit = mode == FollowMode.headingUp
        ? handRotationFollowDegrees
        : handRotationDegrees;
    return _angleBetween(bearing, aimedAt) > limit;
  }

  /// The angle between two bearings, 0 to 180 degrees.
  static double _angleBetween(double a, double b) {
    final delta = ((a - b) % 360 + 360) % 360;
    return delta > 180 ? 360 - delta : delta;
  }

  /// The locate button moved the camera to the rider, which is exactly what
  /// following does; so it is following again. That is all it does — the
  /// follow style belongs to the compass next to it.
  void _handleLocate() {
    if (!mounted) return;
    // That move was not ours, but it ends in an idle all the same, and it
    // left the camera on the rider — neither must read as a hand pan.
    _autoMoving = true;
    _followTarget = _map?.center ?? _followTarget;
    if (_following) return;
    setState(() => _following = true);
  }

  /// The compass swaps the follow style, north-up or heading-up, and that
  /// choice is remembered for the next ride.
  ///
  /// A tap while the map has been let go picks the following up again too:
  /// asking for a style only to watch the map stay put would be a riddle.
  void _setSheetPage(int page) {
    if (!mounted || page == _sheetPage) return;
    setState(() => _sheetPage = page);
  }

  void _handleCompass() {
    if (!mounted) return;
    final next = ref.read(followModeProvider) == FollowMode.headingUp
        ? FollowMode.northUp
        : FollowMode.headingUp;
    unawaited(ref.read(followModeProvider.notifier).select(next));
    final map = _map;
    if (next == FollowMode.northUp && map != null) _resetBearing(map);
    // Asked for heading-up standing still, the rider wants to see the map
    // turn now, not once the phone has moved a degree: forget what was last
    // drawn so the next build takes the compass as it stands.
    _pushedCompass = null;
    _compassPushedAt = null;
    setState(() => _following = true);
  }

  /// [navigation] when the rider is close enough to the guided route to be
  /// drawn on it, `null` otherwise.
  ///
  /// Off route, or a long way off the line, the raw fix is the honest answer:
  /// a puck glued to a road the rider has left is worse than a shaky one. The
  /// gap widens with [accuracyM], exactly as the navigator's own back-on-route
  /// gate does, so the puck is not thrown off the line the moment the fix the
  /// navigator still counts as on it gets shaky.
  NavigationProgress? _routeSnap(
    NavigationProgress? navigation,
    double? accuracyM,
  ) {
    if (navigation == null || navigation.offRoute) return null;
    if (navigation.snapped == null) return null;
    if (navigation.distanceFromRouteM > snapThresholdM(accuracyM)) return null;
    return navigation;
  }

  /// Pushes the recording to the map: the track line, the puck, and the route
  /// being followed. Called from build, so it only touches the map when
  /// something actually changed.
  ///
  /// The lines and the camera are this tab's only while it is on screen
  /// ([_drawing]). The puck is the recorder's for as long as a ride records,
  /// whichever tab is on screen: the map's own fix stays off it then, and a
  /// puck that froze while the rider looked at the plan would be a lie.
  /// Proposes what the next ride follows from the tab the rider came from:
  /// the route on the Library's card, or the plan on the Plan tab. The
  /// controller takes it only while no ride runs and the rider has not
  /// picked for themselves.
  void _suggestFollow(String? from) {
    FollowChoice? suggestion;
    if (from == libraryRoute) {
      final routeId = ref.read(libraryCardProvider);
      if (routeId != null) suggestion = FollowSaved(routeId);
    } else if (from == plannerRoute &&
        ref.read(plannerControllerProvider).result != null) {
      suggestion = FollowChoice.plan;
    }
    ref.read(recordingControllerProvider.notifier).suggest(suggestion);
  }

  void _syncMap(
    RecordingUiState state,
    SavedRoute? route,
    List<LatLng> planned,
    GuidedRoute? detour,
    FollowMode mode,
    NavigationProgress? navigation,
    double? compass,
    bool saver,
  ) {
    // A ride that has just started takes the camera with it. Decided before
    // the map is looked at, so a ride that starts while the style is still
    // loading follows once the map arrives.
    var ended = false;
    if (state.isRecording != _wasRecording) {
      ended = _wasRecording;
      _wasRecording = state.isRecording;
      _following = state.isRecording;
      _followTarget = null;
      if (ended) _sheetPage = 0;
    }
    final map = _map;
    if (map == null) return;
    // A finished ride leaves the map wherever the last heading pointed, which
    // is no way to hand it back to the rider. A ride that ended while the
    // tab was away is put right when the tab is back on the map.
    if (ended && !_drawing) _northDue = true;
    if (_drawing && (ended || _northDue)) {
      _northDue = false;
      _resetBearing(map);
    }
    if (_drawing && state.track.length != _drawnTrackPoints) {
      _drawnTrackPoints = state.track.length;
      unawaited(map.setTrackLine(state.track));
    }
    final snapshot = state.snapshot;
    final position = snapshot?.lastPosition;
    if (position != null) {
      // On a route the route is the better answer to both questions. Its
      // matched point does not wander with the fix, and the direction the
      // road runs beats a GNSS course by a wide margin — which is exactly
      // what every other navigation app draws.
      final onRoute = _routeSnap(navigation, snapshot?.accuracyM);
      final course = snapshot?.headingDeg;
      final speed = snapshot?.speedMps;
      final moving = (speed ?? 0) >= headingConeOnSpeedMps;
      // The route only speaks for a rider who is actually going its way. A
      // course that disagrees with it by more than the allowance means the
      // rider is riding it backwards or leaving it, and then the fix and the
      // course are the honest answers, however shaky.
      final roadBearing = onRoute?.routeBearingDeg;
      final againstRoute =
          roadBearing != null &&
          moving &&
          course != null &&
          headingDifference(course, roadBearing) > routeBearingAgreementDegrees;
      final routeBearing = againstRoute ? null : roadBearing;
      final puck = againstRoute ? position : (onRoute?.snapped ?? position);
      // A GNSS course is where the rider has been, so it is worth nothing
      // standing still — and a rider at a red light still faces somewhere.
      // That is what the phone's compass is for, even on the route: the
      // road says which way it runs, not which way the rider is turned.
      final fromCompass = compass != null && !(moving && course != null);
      final heading = fromCompass
          ? compass
          : (moving ? (routeBearing ?? course) : (course ?? routeBearing));

      final freshFix = snapshot != null && !identical(snapshot, _fedSnapshot);
      // A heading the compass turned up between two fixes has to reach the
      // map by itself; at a standstill there is no next fix to carry it.
      final compassPush = fromCompass && !freshFix && _compassPushDue(compass);
      final owner = state.isRecording || _drawing;
      if (owner && (freshFix || !fromCompass || compassPush)) {
        if (fromCompass) _pushedCompass = compass;
        // Only a redraw the compass asked for on its own is worth throttling;
        // the ones a fix brings along are paid for already.
        if (compassPush) _compassPushedAt = DateTime.now();
        unawaited(
          map.setPosition(
            puck,
            accuracyM: snapshot?.accuracyM,
            headingDeg: heading,
            speedMps: speed,
            headingFromCompass: fromCompass,
            // A saver ride draws the bare dot: no ring, no cone.
            minimal: saver,
          ),
        );
      }
      // One heading per fix, not per build: the average would otherwise creep
      // along on rebuilds that brought nothing new. A fresh compass reading
      // counts as news of its own.
      if (snapshot != null && (freshFix || compassPush)) {
        _fedSnapshot = snapshot;
        final smoothed = _headings.update(
          headingDeg: fromCompass ? compass : course,
          speedMps: speed,
          fromCompass: fromCompass,
        );
        if (smoothed != null) {
          _targetBearing = smoothed;
          _bearingFromCompass = fromCompass;
        }
      }
      if (routeBearing != null && !fromCompass) {
        _targetBearing = routeBearing;
        _bearingFromCompass = false;
      }
      // The puck alone is no use to a rider who cannot see it: while a ride
      // runs and nobody has taken the map away from us, the camera goes
      // wherever the fix goes — and, in heading-up, wherever the heading now
      // points, even if the rider has not moved an inch.
      if (_drawing &&
          state.isRecording &&
          _following &&
          (puck != _followTarget || _bearingStale(mode, speed))) {
        _followTo(
          map,
          puck,
          mode,
          speedMps: speed,
          fromCompass: _bearingFromCompass,
          saver: saver,
        );
      }
    }
    if (!_drawing) return;
    // A rejoin is a branch: the plan stays on the map, muted, and the way
    // back onto it is drawn beside it, because a rider has to see both to
    // know what they are being asked to do. A whole new route to the
    // destination has no branch and simply replaces the plan. Failing either,
    // a chosen saved route wins, and failing that the route on the Plan tab
    // is the one the rider is about to ride, saved or not.
    final branch = detour != null && detour.branch.isNotEmpty
        ? detour.branch
        : const <LatLng>[];
    final plan = route != null
        ? route.geometry.map((p) => p.pos).toList(growable: false)
        : planned;
    final planKey = route != null
        ? route.id
        : planned.isEmpty
        ? null
        : 'plan:${planned.length}:${planned.first}:${planned.last}';
    final line = detour != null && branch.isEmpty ? detour.line : plan;
    final key = detour != null && branch.isEmpty ? detour.key : planKey;
    // Muted while a branch runs beside it, so the two never read alike.
    final style = branch.isEmpty
        ? RouteLineStyle.preview
        : RouteLineStyle.alternative;
    if (key != _drawnRouteId || style != _drawnRouteStyle) {
      _drawnRouteId = key;
      _drawnRouteStyle = style;
      if (line.isEmpty) {
        unawaited(map.removeRouteLine(followedRouteLineId));
      } else {
        unawaited(map.setRouteLine(followedRouteLineId, line, style: style));
      }
    }
    // A new route that took the plan's place leaves the plan faint under
    // it, so the rider can see what they left.
    final replaced = detour != null && branch.isEmpty && plan.isNotEmpty;
    final replacedKey = replaced ? '${detour.key}:${planKey ?? ''}' : null;
    if (replacedKey != _drawnReplacedId) {
      _drawnReplacedId = replacedKey;
      if (replacedKey == null) {
        unawaited(map.removeRouteLine(replacedRouteLineId));
      } else {
        unawaited(
          map.setRouteLine(
            replacedRouteLineId,
            plan,
            style: RouteLineStyle.original,
          ),
        );
      }
    }
    // The followed route's points of interest ride along with it: only a
    // saved route has any, a plan never does.
    final poisKey = route?.pois.isEmpty ?? true ? null : route!.id;
    if (poisKey != _drawnPoisId) {
      _drawnPoisId = poisKey;
      unawaited(map.setPois(poiMarkers(route?.pois ?? const <RoutePoi>[])));
    }
    final branchKey = branch.isEmpty ? null : detour!.key;
    if (branchKey != _drawnBranchId) {
      _drawnBranchId = branchKey;
      if (branch.isEmpty) {
        unawaited(map.removeRouteLine(detourRouteLineId));
      } else {
        unawaited(
          map.setRouteLine(
            detourRouteLineId,
            branch,
            style: RouteLineStyle.preview,
          ),
        );
      }
    }
  }

  // ------------------------------------------------------------- recovery

  void _handleRecovery(RecoveryResult result) {
    if (_recoveryHandled || result is NoRecovery) return;
    _recoveryHandled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      switch (result) {
        case ReattachRecording(:final state):
          unawaited(_reattach(state));
        case InterruptedRecording():
          unawaited(_askResumeOrFinish(result));
        case NoRecovery():
          break;
      }
    });
  }

  // --------------------------------------------------- finish from afar

  /// Opens the save sheet for a ride the rider stopped somewhere else.
  ///
  /// The watch cannot finish a ride on its own — it is named on the sheet,
  /// and the sheet also offers to carry on — so it stops the recorder and
  /// asks for this. The rider finds the sheet waiting the next time they look
  /// at the phone.
  void _handleFinishRequest(bool requested) {
    if (!requested) {
      _finishRequested = false;
      return;
    }
    if (_finishRequested) return;
    _finishRequested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(rideFinishRequestProvider.notifier).clear();
      if (!ref.read(recordingControllerProvider).isRecording) return;
      unawaited(_stop());
    });
  }

  Future<void> _reattach(RecordingState state) async {
    final running = await ref
        .read(recordingControllerProvider.notifier)
        .reattach(state);
    if (running || !mounted) return;
    // The service died between the launch check and now; fall back to the
    // interrupted flow so the journal is not orphaned.
    RecordingRecovery.reset();
    ref.invalidate(recordingRecoveryProvider);
    _recoveryHandled = false;
  }

  Future<void> _askResumeOrFinish(InterruptedRecording recovery) async {
    final l10n = AppLocalizations.of(context);
    final decision = await showDialog<_RecoveryDecision>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(l10n.recordingRecoveryTitle),
        content: Text(
          l10n.recordingRecoveryBody(
            formatDate(l10n, recovery.state.startedAt.toLocal()),
            formatDistance(
              l10n,
              ref.read(unitSystemProvider),
              recovery.stats.distanceM,
            ),
            formatDuration(l10n, recovery.stats.movingTime),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_RecoveryDecision.discard),
            child: Text(l10n.recordingRecoveryDiscard),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_RecoveryDecision.finish),
            child: Text(l10n.recordingRecoveryFinish),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(_RecoveryDecision.resume),
            child: Text(l10n.recordingRecoveryResume),
          ),
        ],
      ),
    );
    if (!mounted || decision == null) return;
    final controller = ref.read(recordingControllerProvider.notifier);
    switch (decision) {
      case _RecoveryDecision.resume:
        await controller.resumeInterrupted(
          recovery.state,
          notificationTitle: l10n.recordingNotificationTitle,
        );
      case _RecoveryDecision.finish:
        // The same sheet a ride stopped by hand goes through: an interrupted
        // recording is finished the way every other one is, and "Continue"
        // there means picking the recording up again.
        await _finishRecording(
          rideId: recovery.state.rideId,
          routeId: recovery.state.routeId,
          startedAt: recovery.state.startedAt,
          stats: recovery.stats,
          take: () async => recovery.state,
          onContinue: () => controller.resumeInterrupted(
            recovery.state,
            notificationTitle: l10n.recordingNotificationTitle,
          ),
        );
      case _RecoveryDecision.discard:
        await controller.discardInterrupted(recovery.state);
    }
    RecordingRecovery.reset();
  }

  // -------------------------------------------------------------- actions

  Future<void> _start() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (!await _ensureLocation(l10n, messenger)) return;
    if (!mounted) return;
    await _ensureNotifications(l10n, messenger);
    if (!mounted) return;
    await _maybeAskBatteryOptimization(l10n);
    if (!mounted) return;
    try {
      await ref
          .read(recordingControllerProvider.notifier)
          .start(notificationTitle: l10n.recordingNotificationTitle);
    } on RecordingException catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.recordingFailed(error.message))),
      );
    }
  }

  Future<bool> _ensureLocation(
    AppLocalizations l10n,
    ScaffoldMessengerState messenger,
  ) async {
    final permission = ref.read(locationPermissionControllerProvider.notifier);
    var status = await permission.refresh();
    if (status.canAsk) {
      if (!mounted) return false;
      if (!await showLocationRationaleDialog(context)) return false;
      status = await permission.requestWhenInUse();
    }
    if (status == LocationPermissionStatus.serviceDisabled) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.recordingLocationServiceOff),
          action: SnackBarAction(
            label: l10n.recordingOpenSettings,
            onPressed: () => unawaited(permission.openLocationSettings()),
          ),
        ),
      );
      return false;
    }
    if (!status.isUsable) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.recordingLocationDenied),
          action: SnackBarAction(
            label: l10n.recordingOpenSettings,
            onPressed: () => unawaited(permission.openAppSettings()),
          ),
        ),
      );
      return false;
    }
    return true;
  }

  /// Asks for the notification permission, but does not insist: without it the
  /// foreground service still runs, only its notification stays hidden.
  Future<void> _ensureNotifications(
    AppLocalizations l10n,
    ScaffoldMessengerState messenger,
  ) async {
    final gateway = ref.read(notificationPermissionProvider);
    if (await gateway.isGranted()) return;
    if (await gateway.request()) return;
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.recordingNotificationDenied)),
    );
  }

  Future<void> _maybeAskBatteryOptimization(AppLocalizations l10n) async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (prefs.getBool(batteryPromptShownKey) ?? false) return;
    final gateway = ref.read(batteryOptimizationProvider);
    if (await gateway.isIgnored()) return;
    if (!mounted) return;
    final allow = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.recordingBatteryTitle),
        content: Text(l10n.recordingBatteryBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.recordingBatteryLater),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.recordingBatteryAllow),
          ),
        ],
      ),
    );
    await prefs.setBool(batteryPromptShownKey, true);
    if (allow ?? false) await gateway.request();
  }

  /// Ends the recording and hands it to the save sheet.
  ///
  /// The recorder is *paused*, not stopped: the stop button is easy to hit by
  /// accident and the sheet offers to carry on, which only a recorder that
  /// still has its journal open can do. Saving stops it for good and writes
  /// the row; until then the journal and the state file are all there is,
  /// which is exactly what the launch check knows how to recover.
  Future<void> _stop() async {
    // One sheet at a time: a second Finish from the watch while the first
    // sheet is up would stack another one on top of it.
    if (_stopping) return;
    _stopping = true;
    try {
      await _stopOnce();
    } finally {
      _stopping = false;
    }
  }

  Future<void> _stopOnce() async {
    final controller = ref.read(recordingControllerProvider.notifier);
    final state = ref.read(recordingControllerProvider);
    final snapshot = state.snapshot;
    if (snapshot == null) return;
    // A ride the rider paused themselves must not be resumed by a "Continue"
    // they did not ask for, so only a running recorder is paused here.
    final resumable = !state.isPaused;
    if (resumable) await controller.pause();
    if (!mounted) return;
    await _finishRecording(
      rideId: snapshot.rideId,
      routeId: state.followedRouteId,
      startedAt: snapshot.startedAt,
      stats: _liveStats(snapshot),
      take: controller.halt,
      onContinue: () async {
        if (resumable) await controller.resume();
      },
    );
  }

  /// Names the recording, asks the rider what to do with it, and does it.
  ///
  /// The one path both a ride stopped by hand and one recovered on relaunch
  /// take. [take] hands over the recording to write or throw away — stopping
  /// the recorder for a live ride, the state file itself for a recovered one
  /// — and [onContinue] puts the recorder back to work.
  Future<void> _finishRecording({
    required String rideId,
    required String? routeId,
    required DateTime startedAt,
    required RideStats stats,
    required Future<RecordingState?> Function() take,
    required Future<void> Function() onContinue,
  }) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(recordingControllerProvider.notifier);
    final ends = await controller.trackEnds(rideId);
    if (!mounted) return;
    final name = await _defaultRideName(l10n, routeId, startedAt, ends);
    if (!mounted) return;

    Future<void> nothingRecorded() async {
      final recording = await take();
      if (recording != null) {
        await controller.finishInterrupted(recording, rideName: name);
      }
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.recordingNothingRecorded)),
      );
    }

    // Too little to keep: it is thrown away and said so, rather than the
    // rider being asked to name nothing.
    if (ends == null) return nothingRecorded();

    final outcome = await showSaveRideSheet(
      context,
      defaultName: name,
      stats: stats,
    );
    switch (outcome) {
      case ContinueRide():
        await onContinue();
      case SaveRide(name: final chosen):
        final recording = await take();
        if (recording == null) return nothingRecorded();
        final ride = await controller.finishInterrupted(
          recording,
          rideName: chosen,
        );
        if (ride == null) {
          messenger.showSnackBar(
            SnackBar(content: Text(l10n.recordingNothingRecorded)),
          );
          return;
        }
        // Stamps the heart rate the phone's health store knows about onto the
        // track and saves the ride there as a workout. Not awaited: it does
        // nothing at all unless the rider switched Health on, and the ride
        // page follows its own row, so the numbers appear when they appear.
        unawaited(ref.read(rideHealthSyncProvider).afterRide(ride));
        if (mounted) context.go(rideDetailLocation(ride.id));
      case DiscardRide():
        final recording = await take();
        if (recording != null) await controller.discardInterrupted(recording);
    }
  }

  Future<void> _setKeepScreenOn(bool value) async {
    setState(() => _keepScreenOn = value);
    final ScreenWake wake = _wake ?? ref.read(screenWakeProvider);
    _wake = wake;
    await (value ? wake.enable() : wake.disable());
  }

  /// The name the save sheet starts with: the followed route's name, or the
  /// time of day and the places the ride ran between.
  Future<String> _defaultRideName(
    AppLocalizations l10n,
    String? routeId,
    DateTime startedAt,
    ({LatLng start, LatLng end})? ends,
  ) async {
    final route = routeId == null
        ? null
        : await ref.read(routeRepositoryProvider).routeById(routeId);
    return defaultRideName(
      l10n,
      startedAt: startedAt.toLocal(),
      routeName: route?.name,
      startPlace: await _settlementName(ends?.start),
      endPlace: await _settlementName(ends?.end),
      isLoop: isRideLoop(ends?.start, ends?.end),
    );
  }

  /// What the offline gazetteer calls the settlement at [point], or `null`
  /// when no downloaded tile covers it.
  Future<String?> _settlementName(LatLng? point) async {
    if (point == null) return null;
    try {
      final store = await ref.read(gazetteerStoreProvider.future);
      return (await store.nearestSettlement(point))?.name;
    } on Object catch (e) {
      // A ride always gets a name; the places are the part that may be
      // missing.
      debugPrint('velorki: no place for $point: $e');
      return null;
    }
  }

  /// The live figures as a [RideStats], so the save sheet shows the very
  /// numbers the rider was watching.
  RideStats _liveStats(RecordingSnapshot? snapshot) => snapshot == null
      ? RideStats.empty
      : RideStats(
          distanceM: snapshot.distanceM,
          movingTime: snapshot.moving,
          elapsedTime: snapshot.elapsed,
          ascentM: snapshot.ascentM,
          descentM: snapshot.descentM,
          pointCount: snapshot.pointCount,
        );

  // ----------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    ref.listen(sharedMapControllerProvider, (_, next) => _onMapChanged(next));
    final state = ref.watch(recordingControllerProvider);
    final recovery = ref.watch(recordingRecoveryProvider).value;
    if (recovery != null) _handleRecovery(recovery);
    _handleFinishRequest(ref.watch(rideFinishRequestProvider));

    // What the ride follows, as the rider chose: a saved route, the plan,
    // or nothing at all, which draws no line and guides nowhere.
    final follow = state.follow;
    final route = follow is FollowSaved
        ? ref.watch(savedRouteProvider(follow.id)).value
        : null;
    final planned = follow is FollowPlan
        ? ref.watch(
            plannerControllerProvider.select(
              (p) => p.result?.positions ?? const <LatLng>[],
            ),
          )
        : const <LatLng>[];
    final followMode = ref.watch(followModeProvider);
    // A re-route, while one is being followed, is the line to draw.
    final detour = ref.watch(detourRouteProvider);
    // Turn-by-turn, when there is a route to follow and the rider wants it.
    // Read before the map is synced: it is what puts the puck on the route.
    final navigation = ref.watch(navigationControllerProvider);
    // Where the phone points, for the standstill a GNSS has no heading for.
    // The provider is autoDispose, so the magnetometer runs while this screen
    // does and stops with it; no other map asks for it.
    final compass = ref.watch(compassHeadingProvider).value;
    // Everything the battery saver does hangs off this: the dark theme and the
    // black map (through `appearanceOverrideProvider`), the bare puck, the
    // camera that jumps instead of gliding, the dimmed screen and the glance
    // view. It is false again the moment the ride ends.
    final saver = ref.watch(batterySaverActiveProvider);
    _syncSaver(saver);
    _syncBrightness(saver && _keepScreenOn);
    _syncMap(
      state,
      route,
      planned,
      detour,
      followMode,
      navigation,
      compass,
      saver,
    );

    final guiding = navigation != null && state.isRecording;
    final snapshot = state.snapshot;
    // The glance view needs figures to show; without a snapshot there are
    // none yet and the normal screen stays.
    final glance = saver && _glance && snapshot != null;

    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final screenHeight = MediaQuery.sizeOf(context).height;
    double fraction(double dp) => screenHeight <= 0
        ? 0.3
        : ((bottomInset + dp) / screenHeight).clamp(0.01, 0.9);
    // Collapsed: the handle alone. Before a ride that is above the
    // navigation bar, which the bottom padding covers under `extendBody`,
    // and the sheet docks in the bar; the bar goes while a ride is recorded
    // on this tab, and the handle then rests at the bottom. Live: the status
    // row and the three key figures. Idle: the start button and the chooser.
    final collapsed = fraction(sheetHandleDp);
    // Idle, the sheet rests where the Plan sheet rests, so the tabs agree;
    // the start button and the chooser scroll where they need more.
    // Live: the status row and the two rows of key figures, plus a row per
    // three extra tiles (sensors, what is left of a route), so nothing of
    // the grid is below the fold at rest.
    final extraRows = state.isRecording && snapshot != null
        ? (liveExtraTiles(
                    snapshot: snapshot,
                    remembered: ref.watch(sensorsSeenProvider),
                    remainingM: navigation?.remainingM,
                  ) +
                  2) ~/
              3
        : 0;
    final initial = state.isRecording
        ? fraction(292.0 + 76 * extraRows)
        : sheetRestingExtent(screenHeight);
    _restingSheetSize = sheetRestingExtent(screenHeight);
    final sheetKey = state.isRecording ? 'live' : 'idle';

    // The tab on screen: the banner over the map slides in when it is this
    // one, the ride goes on the map, and the map's control column and the
    // sheet pick up where the last tab left them.
    final active = ref.watch(activeTabProvider) == recordingRoute;
    _active = active;
    ref.listen(activeTabProvider, (previous, next) {
      if (next == recordingRoute && previous != recordingRoute) {
        _active = true;
        _updateMapUse();
        _suggestFollow(previous);
        // A fresh hint each time the tab comes up, never the one just shown.
        _hintIndex = _nextHint(_hintIndex);
        _takeOverControls();
        _takeOverSheet();
      } else if (previous == recordingRoute && next != recordingRoute) {
        _active = false;
        _updateMapUse();
        // The next tab tells the column its own wants; this one tells it
        // again, from scratch, when it comes back.
        _chromeData = null;
        // The bar is square only while a docked strip is on top: the next
        // tab's sheet says so for itself from here on.
        _reportDocked(false);
      }
    });
    if (active) {
      _shareChrome(
        MapChromeData(
          visible: !glance,
          showRoutingTiles: false,
          following: state.isRecording && _following,
          headingUp:
              state.isRecording &&
              _following &&
              followMode == FollowMode.headingUp,
          bearingDeg: _bearing,
          onLocate: _handleLocate,
          onCompass: state.isRecording ? _handleCompass : null,
        ),
      );
    }
    // The turn banner sits over the top of the map, so the control column
    // starts below it while one is showing.
    _ownControlsTop = guiding ? turnBannerHeight + 24 : defaultMapControlsTop;
    final controlsTop = ref.read(mapControlsTopProvider);
    if (active && (controlsTop.target - _ownControlsTop).abs() >= 0.5) {
      // A change of this tab's own chrome, on screen: the column glides,
      // after the frame, since the shell listens to it and may not be told
      // during a build. The first tab of the launch takes its place without
      // a glide.
      final own = _ownControlsTop;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_active) return;
        if (controlsTop.everMoved) {
          controlsTop.glide(to: own);
        } else {
          controlsTop.jump(own);
        }
      });
    }
    final docks = !state.isRecording;
    final dockedRange = screenHeight <= 0
        ? 0.15
        : sheetDockingRangeDp / screenHeight;
    if (!docks && _docked) {
      // The ride started under a docked sheet (from the watch, say): the
      // bar is away now, and it comes back round when the ride ends.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reportDocked(false);
      });
    }

    return Listener(
      // Any touch anywhere postpones the glance view, and a touch on the
      // glance view itself brings the map back. Translucent: a touch that
      // lands on nothing of this screen still counts, and still falls
      // through to the shell's map underneath.
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _handlePointerDown(),
      // Not a Scaffold: a Scaffold's material absorbs every touch, and a
      // tap that lands on nothing of this screen has to fall through to
      // the shell's map. A transparent material is what the buttons need
      // and lets the touch pass; the glance view paints its own black.
      child: Material(
        type: MaterialType.transparency,
        child: SizedBox.expand(
          child: Stack(
            children: [
              if (guiding && !glance)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: TabChromeSlide(
                    active: active,
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: TurnBanner(progress: navigation),
                      ),
                    ),
                  ),
                ),
              if (glance)
                Positioned.fill(
                  child: _GlancePanel(
                    snapshot: snapshot,
                    navigation: guiding ? navigation : null,
                  ),
                )
              else
                DraggableScrollableSheet(
                  // A fresh sheet per state, so the initial size applies again
                  // when a ride starts or ends.
                  key: ValueKey(sheetKey),
                  controller: state.isRecording ? null : _idleSheet,
                  initialChildSize: state.isRecording
                      ? initial
                      : _arrivingExtent ?? initial,
                  minChildSize: collapsed,
                  maxChildSize: 0.85,
                  snap: true,
                  snapSizes: _snapSizesFor(initial),
                  builder: (context, scrollController) => DockingSheet(
                    controller: scrollController,
                    gripDp: sheetGripWithTitleDp,
                    // Where the sheet really starts: for a screen built in
                    // the middle of a change, where the other tab's sheet is.
                    initialExtent: state.isRecording
                        ? initial
                        : _arrivingExtent ?? initial,
                    collapsedExtent: collapsed,
                    dockedRange: dockedRange,
                    docks: docks,
                    dockedBottomInset: bottomInset,
                    onDocked: _reportDocked,
                    onExtent: _onSheetExtent,
                    handle: const SheetHandle(),
                    child: state.isRecording
                        ? _LivePanel(
                            state: state,
                            bottomInset: bottomInset,
                            page: _sheetPage,
                            onPage: _setSheetPage,
                            keepScreenOn: _keepScreenOn,
                            onKeepScreenOn: (v) =>
                                unawaited(_setKeepScreenOn(v)),
                            onPause: () => unawaited(
                              ref
                                  .read(recordingControllerProvider.notifier)
                                  .pause(),
                            ),
                            onResume: () => unawaited(
                              ref
                                  .read(recordingControllerProvider.notifier)
                                  .resume(),
                            ),
                            onStop: () => unawaited(_stop()),
                          )
                        : _IdlePanel(
                            state: state,
                            hintIndex: _hintIndex,
                            bottomInset: bottomInset,
                            keepScreenOn: _keepScreenOn,
                            onKeepScreenOn: (v) =>
                                unawaited(_setKeepScreenOn(v)),
                            onStart: () => unawaited(_start()),
                          ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The glance view: the two or three figures a rider on the move actually
/// reads, white on black, nothing else.
///
/// No controls at all — a screen the rider only glances at is a screen they
/// must not be able to stop the ride on by accident. One tap anywhere brings
/// the map and the sheet back.
class _GlancePanel extends ConsumerWidget {
  const _GlancePanel({required this.snapshot, this.navigation});

  final RecordingSnapshot snapshot;
  final NavigationProgress? navigation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final units = ref.watch(unitSystemProvider);
    // Black is the point on an OLED screen, so the figures are given the
    // colours that read on it whatever theme the app is otherwise in.
    final glanceTheme = theme.copyWith(
      colorScheme: theme.colorScheme.copyWith(
        surface: Colors.black,
        onSurface: Colors.white,
        onSurfaceVariant: Colors.white70,
      ),
    );
    final turn = navigation?.next;
    return ColoredBox(
      color: Colors.black,
      child: Theme(
        data: glanceTheme,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (turn != null) ...[
                  Row(
                    children: [
                      Icon(turnIcon(turn.kind), size: 40, color: Colors.white),
                      const SizedBox(width: 16),
                      Text(
                        distanceLabel(navigation!.distanceToNextM, l10n, units),
                        style: theme.textTheme.statMedium.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          turnLabel(turn, l10n),
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.white70,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                ],
                StatTile(
                  label: l10n.statDistance,
                  value: formatDistance(l10n, units, snapshot.distanceM),
                  size: StatSize.hero,
                ),
                const SizedBox(height: 32),
                StatRow(
                  children: [
                    StatTile(
                      label: l10n.statSpeed,
                      value: formatSpeed(l10n, units, _speedMps(ref, snapshot)),
                    ),
                    StatTile(
                      label: l10n.statElapsed,
                      value: formatClock(snapshot.elapsed),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The drag handle at the top of the sheet.
/// What the speed tile shows: the wheel sensor's speed while one is reporting,
/// and the GPS speed otherwise.
///
/// A wheel sensor measures the road rather than the sky. It is right at
/// walking pace, where a fix is mostly noise and the derived speed wanders,
/// and it goes on reading indoors on a trainer, where there is no sky at all.
/// Only the tile changes: the ride's distance, its average and everything
/// saved with it still come from the fixes.
double _speedMps(WidgetRef ref, RecordingSnapshot snapshot) =>
    ref.watch(sensorHubProvider).readingsAt(DateTime.now()).speedMps ??
    snapshot.speedMps;

enum _RecoveryDecision { resume, finish, discard }

class _IdlePanel extends ConsumerWidget {
  const _IdlePanel({
    required this.state,
    required this.hintIndex,
    required this.bottomInset,
    required this.keepScreenOn,
    required this.onKeepScreenOn,
    required this.onStart,
  });

  final RecordingUiState state;

  /// Which of [idleHints] to show.
  final int hintIndex;
  final double bottomInset;
  final bool keepScreenOn;
  final ValueChanged<bool> onKeepScreenOn;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ListView(
      controller: SheetContentScroll.maybeOf(context),
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottomInset + 24),
      children: [
        Text(l10n.recordingIdleTitle, style: theme.textTheme.headlineMedium),
        const SizedBox(height: 6),
        Text(
          key: recordingIdleHintKey,
          // One of six, a new one each time the tab comes up: something
          // true about the recorder rather than the same sentence every day.
          idleHints(l10n)[hintIndex % idleHints(l10n).length],
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        // The chooser first, the button under it: at the sheet's resting
        // height the button then sits about where the Plan tab's toolbar is.
        const FollowRouteField(),
        const SizedBox(height: 16),
        SizedBox(
          height: primaryButtonHeight,
          child: FilledButton.icon(
            onPressed: state.busy ? null : onStart,
            icon: const Icon(Icons.fiber_manual_record_rounded),
            label: Text(l10n.recordingStart),
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: keepScreenOn,
          onChanged: onKeepScreenOn,
          title: Text(l10n.recordingKeepScreenOn),
        ),
        // The same switch as in Settings → Recording, where the rider needs
        // it: on the screen they start the ride from.
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: ref.watch(recordingSettingsProvider.select((s) => s.saver)),
          onChanged: (value) => unawaited(
            ref.read(recordingSettingsProvider.notifier).setSaver(value),
          ),
          title: Text(l10n.settingsBatterySaver),
        ),
        // The navigation switches, the same rows as Settings > Navigation,
        // below the fold: seen only when the sheet is pulled up, there for a
        // rider who wants the voice off before they set out.
        const NavigationToggles(contentPadding: EdgeInsets.zero),
      ],
    );
  }
}

/// The line under "Ready to ride", for the tests.
const Key recordingIdleHintKey = ValueKey<String>('recording-idle-hint');

/// The one-line hints under the idle headline, all true of the recorder and
/// each short enough for one line on a narrow phone.
List<String> idleHints(AppLocalizations l10n) => <String>[
  l10n.recordingIdleHint,
  l10n.recordingIdleHint2,
  l10n.recordingIdleHint3,
  l10n.recordingIdleHint4,
  l10n.recordingIdleHint5,
  l10n.recordingIdleHint6,
];

/// A random hint index other than [current]; [idleHintCount] of them.
int _nextHint(int current) {
  final next = math.Random().nextInt(idleHintCount - 1);
  return next >= current ? next + 1 : next;
}

/// How many one-line hints [idleHints] has.
const int idleHintCount = 6;

/// When the rider reaches the end at the ride's average speed so far, or
/// `null` without a route ahead or an average worth the name.
DateTime? _eta(double? remainingM, double avgSpeedMps) {
  if (remainingM == null || remainingM <= 0 || avgSpeedMps < 0.5) return null;
  return DateTime.now().add(
    Duration(seconds: (remainingM / avgSpeedMps).round()),
  );
}

/// How many tiles the live grid shows under its two fixed rows: one per
/// sensor that has reported this ride, plus Left and Arrival on a route.
int liveExtraTiles({
  required RecordingSnapshot snapshot,
  required SensorsSeenState remembered,
  required double? remainingM,
}) {
  final seen = remembered.rideId == snapshot.rideId
      ? remembered
      : const SensorsSeenState();
  var count = 0;
  if ((snapshot.heartRateBpm ?? seen.heartRateBpm) != null) count++;
  if ((snapshot.cadenceRpm ?? seen.cadenceRpm) != null) count++;
  if ((snapshot.powerW ?? seen.powerW) != null) count++;
  if (remainingM != null && remainingM > 0) count += 2;
  return count;
}

/// [tiles] in rows of three, the last row padded with empty slots so every
/// column keeps its width.
List<List<Widget>> _rowsOf(List<Widget> tiles) => <List<Widget>>[
  for (var i = 0; i < tiles.length; i += 3)
    <Widget>[
      for (var j = i; j < i + 3; j++)
        j < tiles.length ? tiles[j] : const SizedBox.shrink(),
    ],
];

/// One sensor's tile: the current value, or the last one dimmed and marked
/// with a broken link while the sensor is silent mid-ride. `null` for a sensor
/// that has not reported this ride.
Widget? _sensorTile(
  String label, {
  required int? current,
  required int? last,
  required String Function(int?) format,
  required bool paused,
  String? detail,
}) {
  final value = current ?? last;
  if (value == null) return null;
  final lost = current == null && !paused;
  return StatTile(
    label: label,
    value: format(value),
    size: StatSize.medium,
    icon: lost ? Icons.link_off : null,
    muted: lost,
    detail: detail,
  );
}

class _LivePanel extends ConsumerWidget {
  const _LivePanel({
    required this.state,
    required this.bottomInset,
    required this.page,
    required this.onPage,
    required this.keepScreenOn,
    required this.onKeepScreenOn,
    required this.onPause,
    required this.onResume,
    required this.onStop,
  });

  final RecordingUiState state;
  final double bottomInset;

  /// The page showing: 0 the figures, 1 the elevation profile.
  final int page;
  final ValueChanged<int> onPage;
  final bool keepScreenOn;
  final ValueChanged<bool> onKeepScreenOn;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final units = ref.watch(unitSystemProvider);
    final snapshot = state.snapshot!;
    final seen = ref.watch(sensorsSeenProvider);
    final remembered = seen.rideId == snapshot.rideId
        ? seen
        : const SensorsSeenState();
    final avgHeartRate = snapshot.avgHeartRateBpm;
    // What is left of a followed route and when it ends at today's average:
    // the two figures a rider on a route glances at most, on the page they
    // are already looking at rather than a swipe away.
    final remainingM = ref.watch(navigationControllerProvider)?.remainingM;
    final eta = _eta(remainingM, snapshot.avgSpeedMps);
    final sensorTiles = <Widget>[
      ?_sensorTile(
        l10n.statHeartRate,
        current: snapshot.heartRateBpm,
        last: remembered.heartRateBpm,
        format: (bpm) => formatHeartRate(l10n, bpm),
        paused: state.isPaused,
        detail: avgHeartRate == null
            ? null
            : '${l10n.statAvgHeartRate} ${formatHeartRate(l10n, avgHeartRate)}',
      ),
      ?_sensorTile(
        l10n.statCadence,
        current: snapshot.cadenceRpm,
        last: remembered.cadenceRpm,
        format: (rpm) => formatCadence(l10n, rpm),
        paused: state.isPaused,
      ),
      ?_sensorTile(
        l10n.statPower,
        current: snapshot.powerW,
        last: remembered.powerW,
        format: (watts) => formatPower(l10n, watts),
        paused: state.isPaused,
      ),
    ];
    final extraTiles = <Widget>[
      ...sensorTiles,
      if (remainingM != null && remainingM > 0) ...[
        StatTile(
          label: l10n.statRemaining,
          value: formatDistance(l10n, units, remainingM),
          size: StatSize.medium,
        ),
        StatTile(
          label: l10n.statArrival,
          value: eta == null
              ? '--'
              : MaterialLocalizations.of(context)
                    .formatTimeOfDay(TimeOfDay.fromDateTime(eta)),
          size: StatSize.medium,
        ),
      ],
    ];
    final status = switch (snapshot) {
      RecordingSnapshot(status: RecordingStatus.paused, autoPaused: true) =>
        l10n.recordingStatusAutoPaused,
      RecordingSnapshot(status: RecordingStatus.paused) =>
        l10n.recordingStatusPaused,
      _ => l10n.recordingStatusRecording,
    };
    return ListView(
      controller: SheetContentScroll.maybeOf(context),
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottomInset + 24),
      children: [
        // Everything in view at once: state and elapsed time with the two
        // buttons, then two rows of three figures. Nothing hides below.
        Row(
          children: [
            _StatusPill(label: status, paused: state.isPaused),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                formatClock(snapshot.elapsed),
                style: theme.textTheme.statMedium.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _RoundAction(
              icon: state.isPaused
                  ? Icons.play_arrow_rounded
                  : Icons.pause_rounded,
              tooltip: state.isPaused
                  ? l10n.recordingResume
                  : l10n.recordingPause,
              filled: state.isPaused,
              onPressed: state.busy
                  ? null
                  : state.isPaused
                  ? onResume
                  : onPause,
            ),
            const SizedBox(width: 10),
            _RoundAction(
              icon: Icons.stop_rounded,
              tooltip: l10n.recordingFinish,
              danger: true,
              onPressed: state.busy ? null : onStop,
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Two pages under the header, a swipe apart: the figures, and the
        // followed route as a profile with the rider on it. The dots say
        // which is up. Paused, the figures fade: the pill alone was easy to
        // miss on a sheet that otherwise looks exactly like a running ride.
        SwipePages(
          page: page,
          onPage: onPage,
          children: [
            _PausedFade(
              paused: state.isPaused,
              child: Column(
                children: [
                  StatRow(
                    children: [
                      StatTile(
                        label: l10n.statDistance,
                        value: formatDistance(l10n, units, snapshot.distanceM),
                        emphasize: !state.isPaused,
                      ),
                      StatTile(
                        label: l10n.statSpeed,
                        value: formatSpeed(
                          l10n,
                          units,
                          _speedMps(ref, snapshot),
                        ),
                      ),
                      StatTile(
                        label: l10n.statAvgSpeed,
                        value: formatSpeed(l10n, units, snapshot.avgSpeedMps),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  StatRow(
                    children: [
                      StatTile(
                        label: l10n.statAscent,
                        value: formatHeight(l10n, units, snapshot.ascentM),
                        size: StatSize.medium,
                      ),
                      StatTile(
                        label: l10n.statDescent,
                        value: formatHeight(l10n, units, snapshot.descentM),
                        size: StatSize.medium,
                      ),
                      StatTile(
                        label: l10n.statMovingTime,
                        value: formatClock(snapshot.moving),
                        size: StatSize.medium,
                      ),
                    ],
                  ),
                  // The extra tiles, in rows of three under the fixed two,
                  // filled left to right: first the sensors a sensor has
                  // reported this ride (a rider with a watch and nothing else
                  // gets one tile, not one and two dashes; a sensor that fell
                  // silent keeps its tile, dimmed and marked, with the last
                  // value; paused, nothing is marked), then, on a route, what
                  // is left and when it ends. So a heart rate keeps its tile
                  // when a route is followed, and Left and Arrival take the
                  // free slots beside it or start a row of their own; the
                  // last row is padded to three so the columns line up.
                  for (final row in _rowsOf(extraTiles)) ...[
                    const SizedBox(height: 16),
                    StatRow(children: row),
                  ],
                ],
              ),
            ),
            if (page == 1)
              RideProfileView(
                // Watched only while the page is up: the samples come from
                // the route's geometry, once per route, and a rider who
                // never swipes never pays for them.
                samples: ref.watch(guidedRouteProfileProvider),
                alongM: ref.watch(navigationControllerProvider)?.alongM ?? 0,
                etaAt: _eta(
                  ref.watch(navigationControllerProvider)?.remainingM,
                  snapshot.avgSpeedMps,
                ),
              )
            else
              const SizedBox.shrink(),
            if (page == 2)
              RideCueSheet(
                cues: ref.watch(guidedRouteCuesProvider),
                alongM: ref.watch(navigationControllerProvider)?.alongM ?? 0,
              )
            else
              const SizedBox.shrink(),
          ],
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: keepScreenOn,
          onChanged: onKeepScreenOn,
          title: Text(l10n.recordingKeepScreenOn),
        ),
        // The same switches as on the idle sheet, below the fold: mid-ride is
        // when a rider usually decides they have heard enough of the voice.
        const NavigationToggles(contentPadding: EdgeInsets.zero),
      ],
    );
  }
}

/// A 56dp round button: pause/resume in the accent when it resumes, finish
/// in the error colour.
class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.filled = false,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool filled;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = danger
        ? scheme.errorContainer
        : filled
        ? scheme.primary
        : scheme.surfaceContainerHigh;
    final foreground = danger
        ? scheme.onErrorContainer
        : filled
        ? scheme.onPrimary
        : scheme.onSurface;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: background,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: 56,
            height: 56,
            child: Icon(icon, size: 28, color: foreground),
          ),
        ),
      ),
    );
  }
}

/// Fades the ride's figures while it is paused.
///
/// Animated, so a pause does not snap; short enough that a widget test's
/// `pumpAndSettle` is over before it notices.
class _PausedFade extends StatelessWidget {
  const _PausedFade({required this.paused, required this.child});

  final bool paused;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: paused ? 0.45 : 1,
      duration: const Duration(milliseconds: 250),
      child: child,
    );
  }
}

/// `● RECORDING` with a red dot, or `❙❙ PAUSED` in the tertiary colour.
///
/// Deliberately not animated: a repeating animation never lets a widget test
/// settle, and a steady dot is calmer on the handlebar anyway.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.paused});

  final String label;
  final bool paused;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dotColor = paused ? scheme.onTertiaryContainer : scheme.error;
    final textColor = paused ? scheme.onTertiaryContainer : scheme.onSurface;
    return DecoratedBox(
      decoration: BoxDecoration(
        // Paused stands out in the tertiary colour; recording is the quiet
        // one, because that is the state the sheet is in for hours.
        color: paused ? scheme.tertiaryContainer : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 14, 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (paused)
              Icon(Icons.pause_rounded, size: 14, color: dotColor)
            else
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: dotColor.withValues(alpha: 0.6),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            const SizedBox(width: 8),
            Text(
              label.toUpperCase(),
              style: theme.textTheme.overline.copyWith(color: textColor),
            ),
          ],
        ),
      ),
    );
  }
}
