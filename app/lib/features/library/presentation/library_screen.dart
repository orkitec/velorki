import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../shared/presentation/placeholder_body.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tabLibrary)),
      body: PlaceholderBody(
        icon: Icons.folder_outlined,
        message: l10n.libraryPlaceholder,
      ),
    );
  }
}
