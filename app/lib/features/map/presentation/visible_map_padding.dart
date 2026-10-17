import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../app/shell_layout.dart';
import '../../shared/presentation/adaptive_docking_sheet.dart';
import '../../shared/presentation/docking_sheet.dart';
import '../../shared/presentation/wide_panel.dart';
import '../domain/visible_map.dart';
import 'map_controls.dart';

/// The control column's width at [context], glass and its margin included:
/// none in a wide window whose column stands at a side, where the controls
/// stand at the column's edge.
double mapControlsWidth(BuildContext context) =>
    (compactMapControls(context)
        ? compactMapControlButtonSize
        : mapControlButtonSize) +
    6 +
    (wideColumnAtSide(context, ShellLayout.of(context)) ? 0 : 12);

/// What a wide window's column (with the map's controls over it) takes
/// from the window's map, and the window's safe areas elsewhere: the free
/// map is the rest. Read from the window, whatever [context]'s own media.
EdgeInsets wideFreeMap(BuildContext context) {
  final screen = MediaQueryData.fromView(View.of(context));
  return wideMapBeside(context)
      .copyWith(top: screen.viewPadding.top, bottom: screen.viewPadding.bottom);
}

/// The padding a camera move or fit on the tab map at [context] uses so its
/// target lands in the middle of the visible map: below the tab's chrome,
/// which reaches [chromeTop] under the safe area, above the sheet at
/// [sheetExtent] (the resting height when `null`), and left of the column.
///
/// On a phone turned sideways ([layout], the one handed down by default)
/// the side panel takes the sheet's place: the visible map is what the rail,
/// the panel as far as it is open and the row at the top leave. In a wide
/// window it is the free map beside the column ([wideFreeMap]), whatever
/// [chromeTop] and [sheetExtent] say.
EdgeInsets visibleMapPadding(
  BuildContext context, {
  required double chromeTop,
  double? sheetExtent,
  ShellLayout? layout,
}) {
  final shell = layout ?? ShellLayout.of(context);
  if (shell.widePanel) {
    // The large free map beside the column, with a margin: the sheet, the
    // search and the chips are all in the column and take nothing more.
    final free = wideFreeMap(context);
    return EdgeInsets.fromLTRB(
      free.left + 24,
      free.top + 24,
      free.right + 24,
      free.bottom + 24,
    );
  }
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
      // At least the row at the top: the search, the profile menu and the
      // controls, which stand beside the sheet when it is docked.
      chromeTop: math.max(chromeTop, sidewaysTopRowTop + sidewaysTopRowHeight),
      // Nothing but the map's credit along the bottom, which the margin
      // keeps clear of.
      bottomInset: screen.viewPadding.bottom,
      cover: shell.side == RailSide.left
          ? EdgeInsets.only(left: cover)
          : EdgeInsets.only(right: cover),
      safeArea: screen.viewPadding,
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
