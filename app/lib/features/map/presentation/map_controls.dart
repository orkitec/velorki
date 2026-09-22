import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../../app/theme.dart';
import '../../../core/permissions/location_permission.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../offline/presentation/offline_screen.dart';
import '../../shared/presentation/stat_tile.dart';
import '../data/map_preferences.dart';
import '../data/position_provider.dart';
import '../domain/map_controller.dart';
import 'location_rationale_dialog.dart';
import 'map_chrome.dart';

/// The zoom the locate button jumps to when the map is further out.
const double locateZoom = 15;

/// How long the column takes to grow or shrink as a button comes or goes.
const Duration mapControlsResizeDuration = Duration(milliseconds: 200);

/// Floating buttons over the map: locate me, the CyclOSM overlay toggle and
/// zoom in/out.
///
/// The column is inert until [controller] is non-null, which is the case
/// until the map style has finished loading.
class MapControls extends ConsumerWidget {
  const MapControls({required this.controller, super.key});

  final MapController? controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cyclosm = ref.watch(cyclosmOverlayProvider);
    final l10n = AppLocalizations.of(context);
    final chrome = MapChromeInsets.maybeOf(context);
    final enabled = controller != null;
    final headingUp = chrome?.headingUp ?? false;
    final onCompass = chrome?.onCompass;
    // One glass column rather than five floating buttons: less chrome over
    // the map, and the group reads as one control.
    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // A ride that followed a route: the route and its points of
          // interest, on or off. First in the column so a chip over the map
          // is not needed for it.
          if (chrome?.onToggleRoute != null)
            _ControlButton(
              icon: Icons.route,
              tooltip: l10n.rideShowRoute,
              selected: chrome!.routeShown,
              onPressed: enabled ? chrome.onToggleRoute : null,
            ),
          _ControlButton(
            icon: Icons.my_location,
            tooltip: l10n.mapLocateMe,
            // Accent while the screen keeps the camera on the rider, so the
            // button says whether the map is following or has been let go.
            selected: chrome?.following ?? false,
            onPressed: enabled ? () => unawaited(_locate(context, ref)) : null,
          ),
          // Only a screen that has a follow style to switch offers a compass;
          // on every other map the needle would have nothing to say. The
          // column grows and shrinks for it rather than jumping: one column
          // serves the Plan and Record tabs.
          _Resizing(
            child: onCompass == null
                ? const SizedBox.shrink()
                : _CompassButton(
                    headingUp: headingUp,
                    bearingDeg: chrome?.bearingDeg ?? 0,
                    onPressed: enabled ? onCompass : null,
                  ),
          ),
          _ControlButton(
            icon: Icons.directions_bike,
            tooltip: l10n.mapToggleCyclosm,
            selected: cyclosm,
            onPressed: enabled ? () => unawaited(_toggleCyclosm(ref)) : null,
          ),
          // The one place the rider can download the map and the routing
          // tiles for exactly the area they are looking at; the screen needs
          // a live map for that. Embedded maps (record, details) leave it out.
          _Resizing(
            child: (chrome?.showRoutingTiles ?? true)
                ? _ControlButton(
                    icon: Icons.download_for_offline_outlined,
                    tooltip: l10n.offlineEntryTitle,
                    onPressed: enabled ? () => _openOffline(context) : null,
                  )
                : const SizedBox.shrink(),
          ),
          const _ControlDivider(),
          _ControlButton(
            icon: Icons.add,
            tooltip: l10n.mapZoomIn,
            onPressed: enabled ? () => unawaited(_zoomBy(1)) : null,
          ),
          _ControlButton(
            icon: Icons.remove,
            tooltip: l10n.mapZoomOut,
            onPressed: enabled ? () => unawaited(_zoomBy(-1)) : null,
          ),
        ],
      ),
    );
  }

  void _openOffline(BuildContext context) {
    final map = controller;
    if (map == null) return;
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => OfflineScreen(mapController: map),
        ),
      ),
    );
  }

  /// Flips the app-wide overlay setting and nothing else: every map alive
  /// follows that setting through its `PlannerMapHost`, so the map under
  /// these buttons is not a special case.
  Future<void> _toggleCyclosm(WidgetRef ref) =>
      ref.read(cyclosmOverlayProvider.notifier).toggle();

  Future<void> _zoomBy(double delta) async {
    final map = controller;
    final center = map?.center;
    final zoom = map?.zoom;
    if (map == null || center == null || zoom == null) return;
    await map.moveTo(center, zoom: (zoom + delta).clamp(0.0, 22.0));
  }

  Future<void> _locate(BuildContext context, WidgetRef ref) async {
    final map = controller;
    if (map == null) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    // Read before the first await: the context may be gone by the time a
    // permission answer or a fix comes back.
    final l10n = AppLocalizations.of(context);
    final chrome = MapChromeInsets.maybeOf(context);
    final onLocate = chrome?.onLocate;
    // A screen that already keeps the camera on the rider has the position;
    // waiting up to ten seconds for a fresh fix here would only delay the
    // screen's answer to the tap, which it can give straight away.
    if (chrome?.following ?? false) {
      onLocate?.call();
      return;
    }
    final permissions = ref.read(locationPermissionControllerProvider.notifier);

    var status = await permissions.refresh();
    if (status == LocationPermissionStatus.denied) {
      if (!context.mounted) return;
      if (!await showLocationRationaleDialog(context)) return;
      status = await permissions.requestWhenInUse();
    }
    switch (status) {
      case LocationPermissionStatus.granted:
        break;
      case LocationPermissionStatus.denied:
        _show(messenger, l10n.mapLocationDenied);
        return;
      case LocationPermissionStatus.deniedForever:
        _show(
          messenger,
          l10n.mapLocationDeniedForever,
          action: SnackBarAction(
            label: l10n.mapOpenSettings,
            onPressed: () => unawaited(permissions.openAppSettings()),
          ),
        );
        return;
      case LocationPermissionStatus.serviceDisabled:
        _show(
          messenger,
          l10n.mapLocationServiceDisabled,
          action: SnackBarAction(
            label: l10n.mapOpenSettings,
            onPressed: () => unawaited(permissions.openLocationSettings()),
          ),
        );
        return;
    }

    // Asked for directly rather than through devicePositionProvider: that
    // provider is auto-dispose and would be torn down before a first fix
    // arrives when nothing else is listening to it.
    final source = ref.read(positionSourceProvider);
    final fix = await source.current() ?? await source.lastKnown();
    if (fix == null) {
      _show(messenger, l10n.mapLocationUnavailable);
      return;
    }
    await map.moveTo(
      LatLng(fix.latitude, fix.longitude),
      zoom: math.max(map.zoom ?? locateZoom, locateZoom),
    );
    // After the move, not before: the screen's follow mode watches camera
    // idles to spot a hand pan, and this move is ours, not the rider's.
    onLocate?.call();
  }

  static void _show(
    ScaffoldMessengerState? messenger,
    String message, {
    SnackBarAction? action,
  }) {
    messenger?.showSnackBar(SnackBar(content: Text(message), action: action));
  }
}

/// The compass: a needle that points north however the map is turned, in
/// the accent while the map turns with the rider.
///
/// Which of the two styles is on is hard to read off a needle alone, so a
/// tap also shows the name of the style just chosen next to the button for
/// a moment. That is the whole explanation the rider gets; nothing else is
/// added to the map.
class _CompassButton extends StatefulWidget {
  const _CompassButton({
    required this.headingUp,
    required this.bearingDeg,
    required this.onPressed,
  });

  final bool headingUp;
  final double bearingDeg;
  final VoidCallback? onPressed;

  @override
  State<_CompassButton> createState() => _CompassButtonState();
}

class _CompassButtonState extends State<_CompassButton> {
  final LayerLink _link = LayerLink();
  final OverlayPortalController _hint = OverlayPortalController();
  Timer? _hide;
  String _hintText = '';

  /// How long the style's name stays next to the button.
  static const Duration hintDuration = Duration(milliseconds: 1800);

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  void _tap() {
    final onPressed = widget.onPressed;
    if (onPressed == null) return;
    final l10n = AppLocalizations.of(context);
    // The name of the style the tap switches to, not the one it leaves.
    _hintText = widget.headingUp
        ? l10n.mapFollowNorthUp
        : l10n.mapFollowHeadingUp;
    onPressed();
    _hide?.cancel();
    setState(() {});
    if (!_hint.isShowing) _hint.show();
    _hide = Timer(hintDuration, () {
      if (mounted && _hint.isShowing) _hint.hide();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _hint,
        // The overlay hands its child the whole screen; the label must
        // take only its own size or it paints a full-screen slab.
        overlayChildBuilder: (context) => Align(
          alignment: Alignment.topLeft,
          child: CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.centerLeft,
            followerAnchor: Alignment.centerRight,
            offset: const Offset(-8, 0),
            child: IgnorePointer(
              // The same glass as the control column it sits next to, so
              // it reads as part of the map chrome rather than a system
              // toast.
              child: GlassPanel(
                radius: 14,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                child: Text(
                  _hintText,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.velorki.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
        child: _ControlButton(
          icon: Icons.navigation,
          // The needle turns with the map, so it points at the real north
          // however the rider has twisted the camera.
          iconTurns: -widget.bearingDeg * math.pi / 180,
          tooltip: widget.headingUp
              ? l10n.mapFollowHeadingUp
              : l10n.mapFollowNorthUp,
          selected: widget.headingUp,
          onPressed: widget.onPressed == null ? null : _tap,
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
    this.iconTurns = 0,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;

  /// How far the icon is turned inside the button, in radians clockwise.
  final double iconTurns;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        icon: Transform.rotate(angle: iconTurns, child: Icon(icon)),
        iconSize: 20,
        tooltip: tooltip,
        style: IconButton.styleFrom(
          shape: const CircleBorder(),
          foregroundColor: selected ? theme.velorki.accent : scheme.onSurface,
          disabledForegroundColor: scheme.onSurfaceVariant.withValues(
            alpha: 0.38,
          ),
        ),
        onPressed: onPressed,
      ),
    );
  }
}

/// A slot in the column whose height animates as its button comes and goes.
class _Resizing extends StatelessWidget {
  const _Resizing({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSize(
    duration: mapControlsResizeDuration,
    curve: Curves.easeOutCubic,
    alignment: Alignment.topCenter,
    child: child,
  );
}

/// The hairline between the map layers and the zoom pair.
class _ControlDivider extends StatelessWidget {
  const _ControlDivider();

  @override
  Widget build(BuildContext context) => Container(
    width: 20,
    height: 1,
    margin: const EdgeInsets.symmetric(vertical: 3),
    color: Theme.of(context).velorki.glassBorder,
  );
}
