import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../shared/application/active_tab.dart';
import '../data/recording_recovery.dart';

/// Brings the Record tab up at launch when the launch check found a ride:
/// one still running (the rider sees it at once) or one cut off by a crash
/// or a close (the Record screen asks at once whether to resume, finish or
/// discard it).
///
/// The Record screen stays the one that asks; this only makes sure it is
/// built and on screen, whichever tab the app would otherwise open on.
/// Nothing waits for the check: a launch with nothing to recover starts
/// where it always does, without a frame's delay.
///
/// Called once from `bootstrap()` with the app's [ProviderContainer].
void showRecoveryOnLaunch(ProviderContainer container) {
  unawaited(
    container.read(recordingRecoveryProvider.future).then((result) {
      if (result is NoRecovery) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        container.read(activeTabProvider.notifier).show(recordingRoute);
        container.read(routerProvider).go(recordingRoute);
      });
    }, onError: (Object _) {}),
  );
}
