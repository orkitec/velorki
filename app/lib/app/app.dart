import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/recording/data/battery_saver.dart';
import '../features/settings/data/appearance_controller.dart';
import '../l10n/generated/app_localizations.dart';
import 'router.dart';
import 'theme.dart';

class VelorkiApp extends ConsumerWidget {
  const VelorkiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appearanceSettingProvider);
    // A battery-saver ride runs the app dark whatever the rider picked; the
    // choice itself is untouched and comes back when the ride ends.
    final override = ref.watch(appearanceOverrideProvider);
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appName,
      theme: buildLightTheme(appearance.accent),
      darkTheme: buildDarkTheme(appearance.accent),
      themeMode: override?.mode ?? appearance.mode,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
