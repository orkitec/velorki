import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/links/link_opener.dart';
import '../../../core/plus/plus_gate.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../application/subscription_controller.dart';
import '../data/subscription_service.dart';
import '../domain/plus_subscription.dart';
import 'plus_strings.dart';

/// The paywall, at `/plus`.
///
/// It has to carry what both stores demand: what the subscription unlocks,
/// the price and the billing period of every option, the free trial when
/// there is one, a restore button that works without any login, links to the
/// terms and the privacy policy, and the auto-renewal wording.
///
/// A build without a RevenueCat key shows the same feature list and says
/// plainly that Plus cannot be bought here — that is the fork case, and it
/// must not look like a broken screen.
class PaywallScreen extends ConsumerStatefulWidget {
  /// Creates the paywall.
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  String? _selected;

  Future<void> _purchase(PlusPackage package) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final info = await ref
          .read(subscriptionControllerProvider.notifier)
          .purchase(package);
      // `null` is the rider closing the store sheet; saying anything about
      // that would be noise.
      if (info == null || !mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.plusPurchaseThanks)));
    } on SubscriptionException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.plusPurchaseFailed(e.message))),
      );
    }
  }

  Future<void> _restore() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final info = await ref
          .read(subscriptionControllerProvider.notifier)
          .restore();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            info.entitled ? l10n.plusRestored : l10n.plusRestoreNothing,
          ),
        ),
      );
    } on SubscriptionException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.plusRestoreFailed(e.message))),
      );
    }
  }

  Future<void> _open(String url) =>
      ref.read(linkOpenerProvider)(Uri.parse(url)).then((_) {});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final available = ref.watch(subscriptionServiceProvider).isAvailable;
    final action = ref.watch(subscriptionControllerProvider);
    final entitled = ref.watch(plusEntitledProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.plusTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(l10n.plusIntro, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 20),
          Text(l10n.plusIncludes, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          // Driven by the one gate list, so moving a feature to the free
          // tier takes it off the paywall in the same edit.
          for (final feature in PlusFeature.values.where(
            gatedFeatures.contains,
          ))
            _FeatureRow(feature: feature),
          const SizedBox(height: 12),
          Text(l10n.plusFreeAnyway, style: theme.textTheme.bodySmall),
          const Divider(height: 32),
          if (entitled)
            const _ActiveBanner()
          else if (!available)
            const _UnavailableCard()
          else
            _Packages(
              selected: _selected,
              busy: action != PlusAction.none,
              onSelected: (id) => setState(() => _selected = id),
              onPurchase: (package) => unawaited(_purchase(package)),
            ),
          if (available) ...[
            const SizedBox(height: 16),
            Center(
              child: TextButton(
                onPressed: action == PlusAction.none
                    ? () => unawaited(_restore())
                    : null,
                child: action == PlusAction.restoring
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.plusRestore),
              ),
            ),
            Center(
              child: Text(
                l10n.plusRestoreHint,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
          const SizedBox(height: 24),
          Text(
            l10n.plusLegal,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: [
              TextButton(
                onPressed: () => unawaited(_open(velorkiTermsUrl)),
                child: Text(l10n.plusTerms),
              ),
              TextButton(
                onPressed: () => unawaited(_open(velorkiPrivacyUrl)),
                child: Text(l10n.plusPrivacy),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.feature});

  final PlusFeature feature;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_outline, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plusFeatureTitle(l10n, feature),
                  style: theme.textTheme.titleSmall,
                ),
                Text(
                  plusFeatureBody(l10n, feature),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveBanner extends StatelessWidget {
  const _ActiveBanner();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.primaryContainer,
      child: ListTile(
        leading: Icon(
          Icons.workspace_premium,
          color: theme.colorScheme.onPrimaryContainer,
        ),
        title: Text(l10n.plusActive),
        subtitle: Text(l10n.plusPurchaseThanks),
      ),
    );
  }
}

class _UnavailableCard extends StatelessWidget {
  const _UnavailableCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.plusUnavailableTitle, style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(l10n.plusUnavailableBody, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _Packages extends ConsumerWidget {
  const _Packages({
    required this.selected,
    required this.busy,
    required this.onSelected,
    required this.onPurchase,
  });

  final String? selected;
  final bool busy;
  final ValueChanged<String> onSelected;
  final ValueChanged<PlusPackage> onPurchase;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final offering = ref.watch(plusOfferingProvider);

    return offering.when(
      loading: () => Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text(l10n.plusLoadingPrices, style: theme.textTheme.bodyMedium),
        ],
      ),
      error: (error, _) => Text(
        l10n.plusPricesFailed(
          error is SubscriptionException ? error.message : error.toString(),
        ),
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.error,
        ),
      ),
      data: (data) {
        final packages = data?.packages ?? const <PlusPackage>[];
        if (packages.isEmpty) {
          return Text(l10n.plusNoPackages, style: theme.textTheme.bodyMedium);
        }
        final chosen = packages.firstWhere(
          (p) => p.id == selected,
          orElse: () => packages.first,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final package in packages)
              _PackageTile(
                package: package,
                selected: package.id == chosen.id,
                onTap: () => onSelected(package.id),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: busy ? null : () => onPurchase(chosen),
              child: busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.plusSubscribe),
            ),
          ],
        );
      },
    );
  }
}

class _PackageTile extends StatelessWidget {
  const _PackageTile({
    required this.package,
    required this.selected,
    required this.onTap,
  });

  final PlusPackage package;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final intro = plusIntroLabel(l10n, package);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: selected ? theme.colorScheme.secondaryContainer : null,
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        ),
        title: Text(
          l10n.plusPricePeriod(
            package.priceString,
            plusPeriodLabel(l10n, package.period),
          ),
        ),
        subtitle: intro == null ? null : Text(intro),
        trailing: package.hasFreeTrial
            ? Icon(Icons.card_giftcard, color: theme.colorScheme.primary)
            : null,
      ),
    );
  }
}
