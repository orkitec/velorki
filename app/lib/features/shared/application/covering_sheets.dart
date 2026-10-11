import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'covering_sheets.g.dart';

/// How many modal sheets are open over a map tab right now.
///
/// While any is, the tab on screen lowers its own sheet out from behind
/// them, and brings it back to where it was once the last one has closed;
/// see `AdaptiveDockingSheet.collapseWhenCovered`. Sheets open through
/// [coverTabSheet], which counts them.
@Riverpod(keepAlive: true)
class CoveringSheets extends _$CoveringSheets {
  @override
  int build() => 0;

  /// A covering sheet opens.
  void opened() {
    if (!ref.mounted) return;
    state = state + 1;
  }

  /// A covering sheet has closed.
  void closed() {
    if (!ref.mounted || state == 0) return;
    state = state - 1;
  }
}

/// Opens a modal sheet over a map tab with [open] (a `showModalBottomSheet`
/// on the root navigator) and counts it in [coveringSheetsProvider] until
/// it has closed, however it closes; answers what [open] answers.
Future<T> coverTabSheet<T>(
  BuildContext context,
  Future<T> Function() open,
) async {
  final sheets = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(coveringSheetsProvider.notifier);
  sheets.opened();
  try {
    return await open();
  } finally {
    sheets.closed();
  }
}
