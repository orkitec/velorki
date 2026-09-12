// Stub for btools.mapaccess.Rd5DiffTool (BRouter v1.7.10).

import 'dart:io';

import '../util/progress_listener.dart';

/// Calculate, add or merge rd5 delta files
///
/// TODO(track R5): not ported. Upstream is 637 lines of streaming file IO
/// (`diff2files`, `recoverFromDelta`, `addDeltas`, `reEncode`) on top of
/// `MicroCache.calcDelta`/`addDelta`, which the codec module already has. The
/// routing runtime never calls it; only the Android app's `DownloadWorker`
/// uses `recoverFromDelta` to apply `.df5` delta updates, which the plan defers
/// to R5 ("rd5 delta updates deferred"). `Rd5DiffManager` and
/// `Rd5DiffValidator` (server-side batch tools around it, MD5 of whole files)
/// are not ported at all.
class Rd5DiffTool {
  Rd5DiffTool._();

  static void diff2files(File f1, File f2, File outFile) {
    throw UnimplementedError('Rd5DiffTool.diff2files: delta updates are R5');
  }

  static void recoverFromDelta(
    File f1,
    File f2,
    File outFile,
    ProgressListener progress,
  ) {
    throw UnimplementedError(
      'Rd5DiffTool.recoverFromDelta: delta updates are R5',
    );
  }

  static void addDeltas(File f1, File f2, File outFile) {
    throw UnimplementedError('Rd5DiffTool.addDeltas: delta updates are R5');
  }

  static void reEncode(File f1, File outFile) {
    throw UnimplementedError('Rd5DiffTool.reEncode: delta updates are R5');
  }
}
