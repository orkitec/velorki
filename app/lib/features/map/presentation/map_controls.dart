import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../../app/theme.dart';
import '../../../core/permissions/location_permission.dart';
import '../../routing_tiles/presentation/routing_tiles_screen.dart';
import '../../shared/presentation/stat_tile.dart';
import '../data/map_preferences.dart';
import '../data/position_provider.dart';
import '../domain/map_controller.dart';
import 'location_rationale_dialog.dart';
import 'map_chrome.dart';
import 'map_strings.dart';

/// The zoom the locate button jumps to when the map is further out.
const double locateZoom = 15;

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
    final enabled = controller != null;
    // One glass column rather than five floating buttons: less chrome over
    // the map, and the group reads as one control.
    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _ControlButton(
            icon: Icons.my_location,
            tooltip: MapStrings.locateMe,
            onPressed: enabled ? () => unawaited(_locate(context, ref)) : null,
          ),
          _ControlButton(
            icon: Icons.directions_bike,
            tooltip: MapStrings.toggleCyclosm,
            selected: cyclosm,
            onPressed: enabled ? () => unawaited(_toggleCyclosm(ref)) : null,
          ),
          // The one place the rider can download routing tiles for exactly the
          // area they are looking at; the screen needs a live map for that.
          // Embedded maps (record, details) leave it out.
          if (MapChromeInsets.maybeOf(context)?.showRoutingTiles ?? true)
            _ControlButton(
              icon: Icons.grid_on_outlined,
              tooltip: MapStrings.routingTiles,
              onPressed: enabled ? () => _openRoutingTiles(context) : null,
            ),
          const _ControlDivider(),
          _ControlButton(
            icon: Icons.add,
            tooltip: MapStrings.zoomIn,
            onPressed: enabled ? () => unawaited(_zoomBy(1)) : null,
          ),
          _ControlButton(
            icon: Icons.remove,
            tooltip: MapStrings.zoomOut,
            onPressed: enabled ? () => unawaited(_zoomBy(-1)) : null,
          ),
        ],
      ),
    );
  }

  void _openRoutingTiles(BuildContext context) {
    final map = controller;
    if (map == null) return;
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => RoutingTilesScreen(mapController: map),
        ),
      ),
    );
  }

  Future<void> _toggleCyclosm(WidgetRef ref) async {
    final notifier = ref.read(cyclosmOverlayProvider.notifier);
    await notifier.toggle();
    await controller?.setCyclosmOverlay(ref.read(cyclosmOverlayProvider));
  }

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
        _show(messenger, MapStrings.locationDenied);
        return;
      case LocationPermissionStatus.deniedForever:
        _show(
          messenger,
          MapStrings.locationDeniedForever,
          action: SnackBarAction(
            label: MapStrings.openSettings,
            onPressed: () => unawaited(permissions.openAppSettings()),
          ),
        );
        return;
      case LocationPermissionStatus.serviceDisabled:
        _show(
          messenger,
          MapStrings.locationServiceDisabled,
          action: SnackBarAction(
            label: MapStrings.openSettings,
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
      _show(messenger, MapStrings.locationUnavailable);
      return;
    }
    await map.moveTo(
      LatLng(fix.latitude, fix.longitude),
      zoom: math.max(map.zoom ?? locateZoom, locateZoom),
    );
  }

  static void _show(
    ScaffoldMessengerState? messenger,
    String message, {
    SnackBarAction? action,
  }) {
    messenger?.showSnackBar(SnackBar(content: Text(message), action: action));
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        icon: Icon(icon),
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
