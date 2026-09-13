import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/links/link_opener.dart';
import '../../../core/plus/plus_gate.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../planner/presentation/route_format.dart';
import '../application/subscription_controller.dart';
import '../data/subscription_service.dart';
import '../domain/plus_subscription.dart';
import 'plus_strings.dart';

/// The store's own subscription page for this platform.
///
/// RevenueCat also reports a `managementURL`, which is preferred when it is
/// there; this is the fallback, and the only thing a build without a store
/// key can offer.
String storeSubscriptionsUrl({String? platform}) {
  final os = platform ?? (kIsWeb ? 'web' : Platform.operatingSystem);
  return os == 'ios' || os == 'macos'
      ? appStoreSubscriptionsUrl
      : playSubscriptionsUrl;
}

/// Settings → Subscription: the state of Velorki Plus, with Manage and
/// Restore.
///
/// Cancelling never happens in the app — both stores insist on owning that —
/// so "Manage" opens the store's subscription page. "Restore" is here as well
/// as on the paywall because a rider who reinstalled will look in settings.
class PlusSettingsSection extends ConsumerWidget {
  /// Creates the section.
  const PlusSettingsSection({super.key});

  Future<void> _manage(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final info = ref.read(plusCustomerInfoProvider).value;
    final url = info?.managementUrl ?? storeSubscriptionsUrl();
    final opened = await ref.read(linkOpenerProvider)(Uri.parse(url));
    if (opened) return;
    messenger.showSnackBar(SnackBar(content: Text(l10n.plusManageFailed)));
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final entitled = ref.watch(plusEntitledProvider);
    final info = ref.watch(plusCustomerInfoProvider).value;
    final action = ref.watch(subscriptionControllerProvider);
    final available = ref.watch(subscriptionServiceProvider).isAvailable;

    final theme = Theme.of(context);
    final detail = _detail(l10n, entitled: entitled, info: info);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: Icon(
            entitled
                ? Icons.workspace_premium
                : Icons.workspace_premium_outlined,
            color: entitled ? theme.velorki.success : null,
          ),
          title: Text(l10n.plusTitle),
          subtitle: Row(
            children: [
              Text(
                entitled ? l10n.plusActive : l10n.plusInactive,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: entitled
                      ? theme.velorki.success
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (detail != null)
                Expanded(
                  child: Text(
                    ' · $detail',
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(paywallRoute),
        ),
        if (available)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
            child: Row(
              children: [
                if (entitled)
                  TextButton(
                    onPressed: () => unawaited(_manage(context, ref)),
                    child: Text(l10n.plusManage),
                  ),
                TextButton(
                  onPressed: action == PlusAction.none
                      ? () => unawaited(_restore(context, ref))
                      : null,
                  child: Text(l10n.plusRestore),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// What follows the status word: "Renews on 12 Oct 2026", or `null` when
  /// the subscription is inactive or has no known end.
  String? _detail(
    AppLocalizations l10n, {
    required bool entitled,
    required PlusCustomerInfo? info,
  }) {
    if (!entitled) return null;
    final expires = info?.expiresAt;
    if (expires == null) return null;
    final date = formatDate(l10n, expires);
    return (info?.willRenew ?? false)
        ? l10n.plusRenewsOn(date)
        : l10n.plusEndsOn(date);
  }
}
