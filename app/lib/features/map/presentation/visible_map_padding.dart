import 'package:flutter/widgets.dart';

import '../../shared/presentation/docking_sheet.dart';
import '../domain/visible_map.dart';
import 'map_controls.dart';

/// The control column's width at [context], glass and its margin included.
double mapControlsWidth(BuildContext context) =>
    (compactMapControls(context)
        ? compactMapControlButtonSize
        : mapControlButtonSize) +
    6 +
    12;

/// The padding a camera move or fit on the tab map at [context] uses so its
/// target lands in the middle of the visible map: below the tab's chrome,
/// which reaches [chromeTop] under the safe area, above the sheet at
/// [sheetExtent] (the resting height when `null`), and left of the column.
EdgeInsets visibleMapPadding(
  BuildContext context, {
  required double chromeTop,
  double? sheetExtent,
}) {
  final size = MediaQuery.sizeOf(context);
  return visibleMapInsets(
    size: size,
    // The view's own inset, not the padding left at [context]: the shell
    // asks from inside a SafeArea, where the padding is already spent, but
    // the map runs under the status bar all the same.
    topInset: MediaQuery.viewPaddingOf(context).top,
    chromeTop: chromeTop,
    sheetExtent: sheetExtent ?? sheetRestingExtent(size.height),
    columnWidth: mapControlsWidth(context),
  );
}
