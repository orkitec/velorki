import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../shared/presentation/placeholder_body.dart';

class RecordingScreen extends StatelessWidget {
  const RecordingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tabRecord)),
      body: PlaceholderBody(
        icon: Icons.radio_button_checked,
        message: l10n.recordingPlaceholder,
      ),
    );
  }
}
