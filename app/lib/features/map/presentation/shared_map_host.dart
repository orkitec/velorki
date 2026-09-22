import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../planner/presentation/planner_map_host.dart';
import '../data/map_preferences.dart';
import '../domain/map_controller.dart';
import 'map_chrome.dart';
import 'puck_ownership.dart';

part 'shared_map_host.g.dart';

/// The map the Plan and Record tabs share, once it can be driven; `null`
/// before the style has loaded and between a style reload and the next
/// load, when every layer a screen drew is gone.
///
/// The shell paints one map under both tabs, so switching between them
/// neither moves nor flashes it. Each tab draws its own layers on this
/// controller while it is the tab on screen and takes them off when it
/// leaves; the shell's control column drives the camera through it.
@Riverpod(keepAlive: true)
class SharedMapController extends _$SharedMapController {
  @override
  MapController? build() => null;

  /// Records the map, or that there is none right now.
  void set(MapController? controller) {
    if (!ref.mounted || identical(state, controller)) return;
    state = controller;
  }
}

/// The shell's one map under the Plan and Record tabs.
///
/// Built once and kept in place: a map widget that is moved, hidden with
/// `Offstage` or rebuilt makes the platform view start over, and that shows
/// as black frames. What changes around it — which screen owns the puck,
/// where the control column sits — reaches the map through inherited
/// widgets, so the map widget itself is the same element frame after frame.
/// The app-wide overlay setting is applied here, as [PlannerMapHost] does
/// for the other maps.
class SharedMapHost extends ConsumerStatefulWidget {
  /// Creates the host.
  const SharedMapHost({super.key});

  @override
  ConsumerState<SharedMapHost> createState() => _SharedMapHostState();
}

class _SharedMapHostState extends ConsumerState<SharedMapHost> {
  MapController? _map;

  /// The map widget, built once per builder rather than once per build.
  Widget? _view;
  MapViewBuilder? _builder;

  late final SharedMapController _shared;

  @override
  void initState() {
    super.initState();
    _shared = ref.read(sharedMapControllerProvider.notifier);
  }

  /// Takes the map the builder just handed over (a fresh one, or the same
  /// one after a style reload), puts the app-wide overlay on it and
  /// publishes it. After the frame: the builder hands it over from a build,
  /// which may not write a provider.
  void _handleMapReady(MapController controller) {
    _map = controller;
    unawaited(controller.setCyclosmOverlay(ref.read(cyclosmOverlayProvider)));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(_map, controller)) _shared.set(controller);
    });
  }

  @override
  void dispose() {
    // Deferred: the tree is locked while a widget goes.
    final shared = _shared;
    scheduleMicrotask(() => shared.set(null));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(cyclosmOverlayProvider, (_, next) {
      unawaited(_map?.setCyclosmOverlay(next));
    });
    final builder = ref.watch(mapViewBuilderProvider);
    if (!identical(builder, _builder)) {
      _builder = builder;
      _view = builder(_handleMapReady);
    }
    // The shell draws the one control column over this map, so the map
    // draws none of its own.
    return MapChromeInsets(
      hoistedControls: true,
      child: PuckOwnership(
        owned: ref.watch(recorderOwnsPuckProvider),
        child: _view!,
      ),
    );
  }
}
