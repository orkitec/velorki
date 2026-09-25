import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'map_attribution_lift.g.dart';

/// How far, in logical pixels, the tab map's attribution — the licence line
/// and the (i) button — is raised above the band it sits in under the bar.
///
/// The tab bar leaves that band free; a bar a screen lays over the bottom
/// of the map in its place does not, and the attribution is a licence
/// requirement that has to stay in view. The Record screen raises it over
/// its figures bar as its sheet folds into it, a step every frame, and
/// lowers it again when the sheet opens or the tab goes.
@Riverpod(keepAlive: true)
ValueNotifier<double> mapAttributionLift(Ref ref) {
  final lift = ValueNotifier<double>(0);
  ref.onDispose(lift.dispose);
  return lift;
}
