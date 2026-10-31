import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../map/data/offline_regions_repository.dart';
import '../../routing_tiles/application/tile_download_controller.dart';

part 'area_download_activity.g.dart';

/// Whether the download of the area on screen has been started and has not
/// finished: from the tap on the button (or the chip) through the dialog and
/// both downloads. It keeps a second tap from starting a second dialog.
@Riverpod(keepAlive: true)
class AreaDownloadStarting extends _$AreaDownloadStarting {
  @override
  bool build() => false;

  /// Marks the download as started or finished.
  void set(bool value) {
    // The download can outlive the scope it ran in (a test's, a sign-out).
    if (ref.mounted) state = value;
  }
}

/// Whether the rider stopped the running download of the visible area:
/// what is left of it then ends without a word.
@Riverpod(keepAlive: true)
class AreaDownloadCancelled extends _$AreaDownloadCancelled {
  @override
  bool build() => false;

  /// Marks the download as stopped, or a new one as not stopped.
  void set(bool value) {
    if (ref.mounted) state = value;
  }
}

/// A download of the visible area that is under way.
class AreaDownloadActivity {
  /// Creates the activity; [fraction] is `null` when it cannot say.
  const AreaDownloadActivity({this.fraction});

  /// How far the running download is, 0..1; `null` when it cannot say.
  final double? fraction;
}

/// What is being downloaded for the visible area right now, the routing data
/// or the map pack or the dialog before them; `null` when nothing is.
@Riverpod(keepAlive: true)
AreaDownloadActivity? areaDownloadActivity(Ref ref) {
  final starting = ref.watch(areaDownloadStartingProvider);
  final queue = ref.watch(tileDownloadQueueProvider);
  final map = ref.watch(offlineDownloadControllerProvider);
  if (queue.isRunning) {
    return AreaDownloadActivity(fraction: queue.progress?.fraction);
  }
  if (map != null) {
    return AreaDownloadActivity(
      fraction: map.fraction > 0 ? map.fraction : null,
    );
  }
  return starting ? const AreaDownloadActivity() : null;
}
