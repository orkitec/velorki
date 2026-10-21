import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import '../../recording/application/recording_controller.dart';

/// How long a calm moment has to last before a store prompt comes up: long
/// enough for a save's snackbar and the screen it leads to to settle.
const Duration calmSettle = Duration(seconds: 2);

/// The clock the store prompts pace themselves by. Overridden in tests.
final storePromptClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// Whether no ride is recording (and so nothing navigates) and no start or
/// finish is in flight, the naming of a finished ride included.
final rideCalmProvider = Provider<bool>(
  (ref) => ref.watch(
    recordingControllerProvider.select((s) => !s.isRecording && !s.busy),
  ),
);

/// Completes once [calm] has said `true` for [calmSettle] in a row.
Future<void> untilCalm(
  ProviderContainer container,
  ProviderListenable<bool> calm,
) async {
  while (true) {
    if (!container.read(calm)) {
      final turned = Completer<void>();
      final subscription = container.listen<bool>(calm, (_, next) {
        if (next && !turned.isCompleted) turned.complete();
      });
      try {
        await turned.future;
      } finally {
        subscription.close();
      }
    }
    await Future<void>.delayed(calmSettle);
    if (container.read(calm)) return;
  }
}
