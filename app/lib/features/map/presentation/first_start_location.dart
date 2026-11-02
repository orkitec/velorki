import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/app_config.dart';
import '../../../core/permissions/location_permission.dart';
import '../data/map_preferences.dart';
import 'location_rationale_dialog.dart';

part 'first_start_location.g.dart';

/// Set once the first start has asked for the location, whatever the
/// answer: it is asked that once, and after that by the locate button.
const String firstStartLocationAskedKey = 'onboarding.location_asked';

/// Whether the first start's question for the location is still to come or
/// on screen: what is shown over the app before then waits for it.
@Riverpod(keepAlive: true)
class FirstStartLocationAsk extends _$FirstStartLocationAsk {
  @override
  bool build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return !(prefs.getBool(firstStartLocationAskedKey) ?? false) &&
        !hasStoredMapCamera(prefs);
  }

  /// The question is answered, or not asked after all.
  void done() => state = false;
}

/// On the app's first start, asks for the location the way the locate
/// button does (the explanation, then the system prompt), so the map can go
/// to where the rider is instead of opening over central Europe. Asked only
/// while the permission has never been given or refused for good; a rider
/// who says "Not now" is not asked again here. Completes once answered.
Future<void> askLocationOnFirstStart(
  BuildContext context,
  WidgetRef ref,
) async {
  // Read before the answer is remembered, so it says the question is due.
  final asking = ref.read(firstStartLocationAskProvider.notifier);
  try {
    await _ask(context, ref);
  } finally {
    asking.done();
  }
}

Future<void> _ask(BuildContext context, WidgetRef ref) async {
  final prefs = ref.read(sharedPreferencesProvider);
  // An install with a remembered map view has been used before: an update
  // does not ask.
  if ((prefs.getBool(firstStartLocationAskedKey) ?? false) ||
      hasStoredMapCamera(prefs)) {
    return;
  }
  await prefs.setBool(firstStartLocationAskedKey, true);
  final permissions = ref.read(locationPermissionControllerProvider.notifier);
  final LocationPermissionStatus status;
  try {
    status = await permissions.refresh();
  } on Object {
    return;
  }
  if (status != LocationPermissionStatus.denied || !context.mounted) return;
  if (!await showLocationRationaleDialog(context)) return;
  await permissions.requestWhenInUse();
}
