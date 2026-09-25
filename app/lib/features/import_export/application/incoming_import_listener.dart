import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import '../../../app/router.dart';
import '../../recording/data/recording_recovery.dart';
import '../data/incoming_file_service.dart';
import '../data/track_decoder.dart';
import '../domain/imported_track.dart';

final Logger _log = Logger('IncomingImportListener');

/// Starts the incoming-file service and routes every file it decodes to the
/// import preview.
///
/// Called once from `bootstrap()` with the app's [ProviderContainer]. The
/// listener is attached *before* `start()` drains the launch intent, so a cold
/// start through "open with" is not lost.
///
/// Navigation goes through the router's provider rather than a
/// `BuildContext`, because a file can arrive before the first frame is built.
void listenForIncomingImports(ProviderContainer container) {
  final router = container.read(routerProvider);

  container.listen<AsyncValue<ImportCandidate>>(
    incomingImportsProvider,
    (previous, next) {
      final candidate = next.value;
      if (candidate == null || candidate == previous?.value) return;
      unawaited(_afterRecovery(container, () => _open(router, candidate)));
    },
    fireImmediately: true,
    onError: (error, _) => _log.warning('incoming import failed', error),
  );

  // A file that could not be imported opens the same screen with the reason:
  // "nothing happened" is the one answer a rider must never get.
  container.listen<AsyncValue<ImportException>>(
    incomingImportRejectionsProvider,
    (previous, next) {
      final rejection = next.value;
      if (rejection == null || rejection == previous?.value) return;
      _log.info('refusing ${rejection.fileName}: ${rejection.failure.name}');
      unawaited(
        _afterRecovery(
          container,
          () => WidgetsBinding.instance.addPostFrameCallback((_) {
            router.go(importRoute, extra: rejection);
          }),
        ),
      );
    },
    onError: (error, _) => _log.warning('incoming rejection failed', error),
  );

  unawaited(container.read(incomingFileServiceProvider).start());
}

/// Runs [open] once a ride left unfinished at launch has been answered for:
/// a file that opened the app shows after the question, not over it.
Future<void> _afterRecovery(
  ProviderContainer container,
  void Function() open,
) async {
  try {
    await waitForRecovery(container);
  } on Object catch (error) {
    _log.warning('recovery check failed; opening the file anyway', error);
  }
  open();
}

void _open(GoRouter router, ImportCandidate candidate) {
  _log.info('importing ${candidate.fileName} from ${candidate.sourceHint}');
  // The first frame may not be up yet on a cold start; go_router queues the
  // navigation, but the binding has to have drained its build before the
  // preview's map host can attach.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    router.go(importRoute, extra: candidate);
  });
}
