import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../application/cloud_sync_controller.dart';
import '../domain/cloud_sync_status.dart';
import '../domain/sync_service.dart';

/// Settings → Sync with: the services this device offers and off, and a
/// line saying where the sync stands. Shown only where
/// [offeredSyncServicesProvider] has a service.
class CloudSyncSection extends ConsumerStatefulWidget {
  /// Creates the section.
  const CloudSyncSection({super.key});

  @override
  ConsumerState<CloudSyncSection> createState() => _CloudSyncSectionState();
}

class _CloudSyncSectionState extends ConsumerState<CloudSyncSection> {
  /// "2 min ago" moves on while the page is open.
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final offered = ref.watch(offeredSyncServicesProvider);
    final active = ref.watch(activeSyncServiceProvider);
    final status = ref.watch(cloudSyncControllerProvider);
    final theme = Theme.of(context);
    // Off, the hint is the first service's: what switching it on does.
    final hinted = active == SyncService.off
        ? (offered.firstOrNull ?? SyncService.off)
        : active;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.cloudSyncWith, style: theme.textTheme.titleSmall),
          const SizedBox(height: 10),
          SegmentedButton<SyncService>(
            showSelectedIcon: false,
            segments: [
              for (final service in [...offered, SyncService.off])
                ButtonSegment(
                  value: service,
                  label: Text(syncServiceLabel(l10n, service)),
                ),
            ],
            selected: {active},
            onSelectionChanged: (selection) => unawaited(
              ref
                  .read(syncServiceChoiceProvider.notifier)
                  .select(selection.single),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            cloudSyncStatusLine(
              l10n,
              status,
              service: active,
              now: DateTime.now(),
            ),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            hinted == SyncService.google
                ? l10n.cloudSyncGoogleHint
                : l10n.cloudSyncHint,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// The name of [service] on its segment.
String syncServiceLabel(AppLocalizations l10n, SyncService service) =>
    switch (service) {
      SyncService.icloud => l10n.cloudSyncServiceICloud,
      SyncService.google => l10n.cloudSyncServiceGoogle,
      SyncService.off => l10n.cloudSyncServiceOff,
    };

/// The status line under the choice.
String cloudSyncStatusLine(
  AppLocalizations l10n,
  CloudSyncStatus status, {
  required SyncService service,
  required DateTime now,
}) {
  if (service == SyncService.off) return l10n.cloudSyncOff;
  final google = service == SyncService.google;
  switch (status.account) {
    case CloudAccount.noAccount:
      return google ? l10n.cloudSyncGoogleNoAccount : l10n.cloudSyncNoAccount;
    case CloudAccount.restricted:
      return google ? l10n.cloudSyncGoogleNoAccount : l10n.cloudSyncRestricted;
    case CloudAccount.available:
    case CloudAccount.temporarilyUnavailable:
    case CloudAccount.unknown:
      break;
  }
  if (status.error == CloudSyncError.quotaExceeded) {
    return google ? l10n.cloudSyncGoogleQuota : l10n.cloudSyncQuota;
  }
  if (status.syncing) return l10n.cloudSyncSyncing;
  switch (status.error) {
    case CloudSyncError.network:
      return l10n.cloudSyncOffline;
    case CloudSyncError.other:
      return l10n.cloudSyncFailed;
    case CloudSyncError.quotaExceeded:
    case null:
      break;
  }
  final last = status.lastSyncedAt;
  if (last == null) return l10n.cloudSyncWaiting;
  final ago = now.difference(last);
  if (ago.inMinutes < 1) return l10n.cloudSyncJustNow;
  if (ago.inHours < 1) return l10n.cloudSyncMinutesAgo(ago.inMinutes);
  if (ago.inDays < 1) return l10n.cloudSyncHoursAgo(ago.inHours);
  return l10n.cloudSyncOnDate(DateFormat.MMMd(l10n.localeName).format(last));
}
