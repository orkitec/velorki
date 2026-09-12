import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import '../../../app/router.dart';
import '../data/incoming_file_service.dart';
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
      _open(router, candidate);
    },
    fireImmediately: true,
    onError: (error, _) => _log.warning('incoming import failed', error),
  );

  unawaited(container.read(incomingFileServiceProvider).start());
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
