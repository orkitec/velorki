import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../application/cloud_sync_controller.dart';
import '../domain/cloud_sync_status.dart';

/// Settings → iCloud: the switch, and a line saying where the sync stands.
/// Shown only where [cloudSyncSupportedProvider] says the device can sync.
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
    final enabled = ref.watch(cloudSyncEnabledProvider);
    final status = ref.watch(cloudSyncControllerProvider);
    final theme = Theme.of(context);
    return SwitchListTile(
      value: enabled,
      title: Text(l10n.cloudSyncTitle),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            cloudSyncStatusLine(
              l10n,
              status,
              enabled: enabled,
              now: DateTime.now(),
            ),
            style: TextStyle(color: theme.colorScheme.onSurface),
          ),
          const SizedBox(height: 4),
          Text(l10n.cloudSyncHint),
        ],
      ),
      onChanged: (value) => unawaited(
        ref.read(cloudSyncEnabledProvider.notifier).set(enabled: value),
      ),
    );
  }
}

/// The status line under the switch.
String cloudSyncStatusLine(
  AppLocalizations l10n,
  CloudSyncStatus status, {
  required bool enabled,
  required DateTime now,
}) {
  if (!enabled) return l10n.cloudSyncOff;
  switch (status.account) {
    case CloudAccount.noAccount:
      return l10n.cloudSyncNoAccount;
    case CloudAccount.restricted:
      return l10n.cloudSyncRestricted;
    case CloudAccount.available:
    case CloudAccount.temporarilyUnavailable:
    case CloudAccount.unknown:
      break;
  }
  if (status.error == CloudSyncError.quotaExceeded) return l10n.cloudSyncQuota;
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
