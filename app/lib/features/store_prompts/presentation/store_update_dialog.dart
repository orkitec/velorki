import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../l10n/generated/app_localizations.dart';

/// Tells the rider the store has a newer version, or with [downloaded]
/// that Google Play has fetched it and a restart installs it. `true` when
/// they chose Update (or Restart), `false` for Later.
///
/// On the root navigator, so it lands in the phone column in a wide window
/// like every other dialog.
Future<bool> showStoreUpdateDialog(
  BuildContext context, {
  bool downloaded = false,
}) async {
  final chosen = await showDialog<bool>(
    context: context,
    useRootNavigator: true,
    builder: (context) => StoreUpdateDialog(downloaded: downloaded),
  );
  return chosen ?? false;
}

/// The dialog [showStoreUpdateDialog] shows.
class StoreUpdateDialog extends StatelessWidget {
  /// Creates the dialog.
  const StoreUpdateDialog({super.key, this.downloaded = false});

  /// Whether the update is already downloaded and waits for a restart.
  final bool downloaded;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(
        downloaded ? l10n.storeUpdateReadyTitle : l10n.storeUpdateTitle,
      ),
      content: Text(
        downloaded ? l10n.storeUpdateReadyBody : l10n.storeUpdateBody,
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.storeUpdateLater),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            downloaded ? l10n.storeUpdateRestart : l10n.storeUpdateAction,
          ),
        ),
      ],
    );
  }
}

/// Puts the update dialog up over whatever the app shows; `true` when the
/// rider chose Update (or Restart).
typedef UpdatePrompt = Future<bool> Function({required bool downloaded});

/// The update dialog, shown from the router's root navigator. Overridden in
/// tests that only check when it comes up.
final updatePromptProvider = Provider<UpdatePrompt>((ref) {
  return ({required bool downloaded}) async {
    final context = ref
        .read(routerProvider)
        .routerDelegate
        .navigatorKey
        .currentContext;
    if (context == null || !context.mounted) return false;
    return showStoreUpdateDialog(context, downloaded: downloaded);
  };
});
