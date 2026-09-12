import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/links/link_opener.dart';
import '../../../core/links/velorki_urls.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../data/package_info_provider.dart';

/// Settings → About: version, attribution, licences and the legal links.
///
/// The privacy policy has to be reachable from inside the app as well as from
/// the store listing, and an app that bundles OpenStreetMap data, BRouter and
/// a dozen pub packages has to show their licences somewhere. Flutter's own
/// [showLicensePage] does the second job once `registerVelorkiLicenses()` has
/// added the data sources to the registry.
class AboutSection extends ConsumerWidget {
  /// Creates the section.
  const AboutSection({super.key});

  Future<void> _open(BuildContext context, WidgetRef ref, String url) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final opened = await ref.read(linkOpenerProvider)(Uri.parse(url));
    if (opened) return;
    messenger.showSnackBar(SnackBar(content: Text(l10n.settingsOpenFailed)));
  }

  void _showLicenses(BuildContext context, String? version) {
    final l10n = AppLocalizations.of(context);
    showLicensePage(
      context: context,
      applicationName: l10n.appName,
      applicationVersion: version,
      applicationLegalese: l10n.settingsLegalese,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final info = ref.watch(packageInfoProvider);
    final version = info.when<String?>(
      data: (i) => '${i.version}+${i.buildNumber}',
      loading: () => null,
      error: (_, _) => null,
    );
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text(l10n.appName),
          subtitle: Text(
            version == null
                ? l10n.settingsVersionUnknown
                : l10n.settingsVersion(version),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.map_outlined),
          title: Text(l10n.osmAttribution),
        ),
        ListTile(
          leading: const Icon(Icons.article_outlined),
          title: Text(l10n.settingsLicenses),
          subtitle: Text(l10n.settingsLicensesSubtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showLicenses(context, version),
        ),
        ListTile(
          leading: const Icon(Icons.privacy_tip_outlined),
          title: Text(l10n.settingsPrivacyPolicy),
          trailing: const Icon(Icons.open_in_new),
          onTap: () => unawaited(_open(context, ref, velorkiPrivacyUrl)),
        ),
        ListTile(
          leading: const Icon(Icons.gavel_outlined),
          title: Text(l10n.settingsTerms),
          trailing: const Icon(Icons.open_in_new),
          onTap: () => unawaited(_open(context, ref, velorkiTermsUrl)),
        ),
        ListTile(
          leading: const Icon(Icons.bug_report_outlined),
          title: Text(l10n.settingsReportProblem),
          subtitle: Text(l10n.settingsReportProblemSubtitle),
          trailing: const Icon(Icons.open_in_new),
          onTap: () => unawaited(_open(context, ref, velorkiIssuesUrl)),
        ),
      ],
    );
  }
}
