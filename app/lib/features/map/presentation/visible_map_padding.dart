import 'package:flutter/widgets.dart';

import '../../../app/shell_layout.dart';
import '../../shared/presentation/adaptive_docking_sheet.dart';

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
///
/// On a phone turned sideways ([layout], the one handed down by default)
/// the side panel takes the sheet's place: the visible map is what the rail,
/// the panel as far as it is open and the column beside it leave.
EdgeInsets visibleMapPadding(
  BuildContext context, {
  required double chromeTop,
  double? sheetExtent,
  ShellLayout? layout,
}) {
  final shell = layout ?? ShellLayout.of(context);
  if (shell.sideRail) {
    // The screen's own metrics: [context] may be inside a part laid out
    // beside the rail, with that side's safe area already spent.
    final screen = MediaQueryData.fromView(View.of(context));
    // The sheet comes out from the screen's edge behind the rail, so its
    // extent is what it covers of the width.
    final cover = sheetExtent != null
        ? sheetExtent.clamp(0.0, 1.0) * screen.size.width
        : sidewaysSheetCover(screen, shell, docked: false);
    return sidewaysVisibleMapInsets(
      topInset: screen.viewPadding.top,
      chromeTop: chromeTop,
      // The controls' row along the bottom.
      bottomInset:
          screen.viewPadding.bottom +
          mapControlsRowBottom +
          mapControlButtonSize,
      cover: shell.side == RailSide.left
          ? EdgeInsets.only(left: cover)
          : EdgeInsets.only(right: cover),
      columnWidth: 0,
    );
  }
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
