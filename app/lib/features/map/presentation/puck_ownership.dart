import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../recording/application/recording_controller.dart';

part 'puck_ownership.g.dart';

/// Says whether the screen above the map draws the position puck itself.
///
/// Every map pushes the device's fixes into its own puck, so a map shows the
/// rider without its screen doing anything. A screen that has a better fix —
/// the recorder, which snaps the puck to the route and turns its cone by the
/// compass at a standstill — draws the puck itself, and then the map's own
/// pushes have to stop: two writers with different ideas feed one heading
/// smoother, and the map's plain fix at walking pace hid the cone the
/// compass had just drawn.
class PuckOwnership extends InheritedWidget {
  /// Creates the marker.
  const PuckOwnership({required this.owned, required super.child, super.key});

  /// Whether the screen draws the puck; while true the map leaves it alone.
  final bool owned;

  /// Whether the nearest screen above [context] owns the puck; false without
  /// a marker.
  static bool ownedBy(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PuckOwnership>()?.owned ??
      false;

  @override
  bool updateShouldNotify(PuckOwnership oldWidget) => owned != oldWidget.owned;
}

/// Whether the recorder owns the puck on the map the Plan and Record tabs
/// share: it does for as long as a ride records, whichever of the two tabs
/// is on screen, since the puck it draws is snapped to the route and turned
/// by the compass, and the map's own fix would write over both.
@Riverpod(keepAlive: true)
bool recorderOwnsPuck(Ref ref) =>
    ref.watch(recordingControllerProvider.select((s) => s.isRecording));
