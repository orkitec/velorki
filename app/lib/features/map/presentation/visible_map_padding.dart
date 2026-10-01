import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final open = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(sidePanelFractionProvider).value;
    return sidewaysVisibleMapInsets(
      topInset: screen.viewPadding.top,
      chromeTop: chromeTop,
      bottomInset: screen.viewPadding.bottom,
      cover: sideCover(screen, shell, open),
      columnWidth: mapControlsWidth(context),
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
