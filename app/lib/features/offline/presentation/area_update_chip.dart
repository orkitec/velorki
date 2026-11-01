import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../map/application/area_download_hint.dart';
import '../../map/domain/map_controller.dart';
import '../../map/presentation/stops_download_chip.dart';
import '../../routing_tiles/presentation/routing_tiles_screen.dart';
import '../application/area_download_activity.dart';
import '../application/visible_area_status.dart';
import '../application/watch_visible_area_status.dart';
import 'download_visible_area.dart';

/// The chip over the map when everything for the area on screen is on the
/// device but the mirror has changed data for it: "New map data for this
/// area", and a tap asks and updates in place. While the update runs it shows
/// the progress with the button that stops it, and when stopped it comes back.
///
/// Nothing when the area has no update. Closing it hides it for that area
/// until the app restarts ([areaHintDismissalsProvider]). The screens put it
/// where the not-downloaded chips go, and only when none of those applies.
class AreaUpdateChip extends ConsumerStatefulWidget {
  /// Creates the chip over what [controller] shows, with [padding] around it
  /// only while it shows.
  const AreaUpdateChip({
    required this.controller,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  /// `null` while the map is not ready, which shows nothing.
  final MapController? controller;

  /// Space around the chip, kept when there is none.
  final EdgeInsetsGeometry padding;

  @override
  ConsumerState<AreaUpdateChip> createState() => _AreaUpdateChipState();
}

class _AreaUpdateChipState extends ConsumerState<AreaUpdateChip> {
  @override
  void initState() {
    super.initState();
    widget.controller?.addCameraIdleListener(_cameraIdle);
  }

  @override
  void didUpdateWidget(AreaUpdateChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller?.removeCameraIdleListener(_cameraIdle);
    widget.controller?.addCameraIdleListener(_cameraIdle);
  }

  @override
  void dispose() {
    widget.controller?.removeCameraIdleListener(_cameraIdle);
    super.dispose();
  }

  // The bounds are read in build; the camera only says when to read them.
  void _cameraIdle() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // No view of the map, nothing to judge: and nothing of the offline data
    // is read. The camera's rest builds this again.
    if (widget.controller?.visibleBounds == null) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final status = watchVisibleAreaStatus(ref, widget.controller);
    final dismissed = ref.watch(areaHintDismissalsProvider);
    final areaDownload = ref.watch(areaDownloadActivityProvider);
    // The tiles in view with an update, also while it runs; a first download
    // of the area is the other chips' to show.
    final area = status.stale.isEmpty ? null : status.stale.first;
    // An update of the routing data is offered even where the map area
    // itself was never downloaded (tiles fetched for a route).
    final shown = status.state == VisibleAreaState.update || area != null;
    if (!shown || (area != null && dismissed.contains(area))) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: widget.padding,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: StopsDownloadChip(
          message: l10n.mapAreaUpdateAvailable,
          actionLabel: l10n.mapAreaUpdate,
          downloading: areaDownload != null,
          progress: areaDownload?.fraction,
          onDownload: () => unawaited(
            confirmTileDownload(context, ref, status.stale, refreshStale: true),
          ),
          onCancel: () => unawaited(cancelVisibleAreaDownload(context, ref)),
          onClose: area == null
              ? null
              : () =>
                    ref.read(areaHintDismissalsProvider.notifier).dismiss(area),
        ),
      ),
    );
  }
}
