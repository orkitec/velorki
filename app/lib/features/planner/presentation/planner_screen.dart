import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../shared/presentation/placeholder_body.dart';

class PlannerScreen extends StatelessWidget {
  const PlannerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tabPlan)),
      body: PlaceholderBody(
        icon: Icons.route_outlined,
        message: l10n.plannerPlaceholder,
      ),
    );
  }
}
