import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../application/cloud_sync_controller.dart';
import '../data/cloudkit_web.dart';
import '../data/google_account.dart';
import '../data/icloud_web_sync.dart';
import '../domain/cloud_sync_status.dart';
import '../domain/sync_service.dart';

/// Settings → Sync with: the services this device offers and off, and a
/// line saying where the sync stands. Shown only where
/// [offeredSyncServicesProvider] has a service. Choosing Google signs in
/// first; while Google is the service, the account and a way to sign out
/// (or in again) are under the line.
///
/// In the web planner both services sign in under the line once chosen,
/// with the provider's own button (Google's, Apple's). A Google token there
/// lasts an hour and no reload, so "Sign in" asks for another in Google's
/// popup.
class CloudSyncSection extends ConsumerStatefulWidget {
  /// Creates the section.
  const CloudSyncSection({super.key});

  @override
  ConsumerState<CloudSyncSection> createState() => _CloudSyncSectionState();
}

class _CloudSyncSectionState extends ConsumerState<CloudSyncSection> {
  /// "2 min ago" moves on while the page is open.
  Timer? _tick;

  /// Whether a Google sign-in is open.
  bool _signingIn = false;

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

  void _choose(SyncService service) {
    if (_signingIn) return;
    if (service == SyncService.google &&
        ref.read(googleSignInServiceProvider) is! ButtonGoogleSignIn &&
        ref.read(googleAccountControllerProvider) == null) {
      unawaited(_signIn(thenSelect: true));
      return;
    }
    unawaited(ref.read(syncServiceChoiceProvider.notifier).select(service));
  }

  /// Signs in to Google; the choice stays as it was unless it goes
  /// through.
  Future<void> _signIn({required bool thenSelect}) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _signingIn = true);
    try {
      await ref.read(googleAccountControllerProvider.notifier).signIn();
      if (thenSelect) {
        await ref
            .read(syncServiceChoiceProvider.notifier)
            .select(SyncService.google);
      } else {
        unawaited(ref.read(cloudSyncControllerProvider.notifier).refresh());
      }
    } on GoogleSignInFailure catch (e) {
      _failed(messenger, l10n, e);
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  /// In a browser: asks Google for Drive access again (the token ran out,
  /// or the page was reloaded), then syncs.
  Future<void> _authorize() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _signingIn = true);
    try {
      await ref.read(googleAccountControllerProvider.notifier).authorize();
      _resume();
    } on GoogleSignInFailure catch (e) {
      _failed(messenger, l10n, e);
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  void _failed(
    ScaffoldMessengerState messenger,
    AppLocalizations l10n,
    GoogleSignInFailure failure,
  ) => messenger.showSnackBar(
    SnackBar(
      content: Text(
        failure.canceled
            ? l10n.cloudSyncGoogleSignInCancelled
            : l10n.cloudSyncGoogleSignInFailed,
      ),
    ),
  );

  /// Signs out of Google here and turns sync off; Drive keeps everything.
  Future<void> _signOut() async {
    await ref.read(syncServiceChoiceProvider.notifier).select(SyncService.off);
    await ref.read(googleAccountControllerProvider.notifier).signOut();
  }

  /// Signs out of iCloud in this browser and turns sync off; iCloud keeps
  /// everything.
  Future<void> _signOutOfICloud() async {
    await ref.read(syncServiceChoiceProvider.notifier).select(SyncService.off);
    await ref.read(cloudKitWebProvider)?.signOut();
    await ref.read(iCloudWebStoreProvider)?.signedOut();
  }

  /// Someone signed in, in the browser: the engine fetches and sends now.
  void _resume() =>
      unawaited(ref.read(cloudSyncControllerProvider.notifier).resume());

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final offered = ref.watch(offeredSyncServicesProvider);
    final active = ref.watch(activeSyncServiceProvider);
    final status = ref.watch(cloudSyncControllerProvider);
    final account = active == SyncService.google
        ? ref.watch(googleAccountControllerProvider)
        : null;
    final google = active == SyncService.google
        ? ref.watch(googleSignInServiceProvider)
        : null;
    final buttonGoogle = google is ButtonGoogleSignIn ? google : null;
    final iCloudWeb = active == SyncService.icloud
        ? ref.watch(cloudKitWebProvider)
        : null;
    final iCloudUser = iCloudWeb == null
        ? null
        : ref.watch(iCloudWebUserProvider).value;
    if (buttonGoogle != null) {
      ref.listen(googleAccountControllerProvider, (before, now) {
        if (before == null && now != null) _resume();
      });
    }
    if (iCloudWeb != null) {
      ref.listen(iCloudWebUserProvider, (before, now) {
        if (now.value != null && before?.value != now.value) _resume();
      });
    }
    final theme = Theme.of(context);
    final quiet = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
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
            onSelectionChanged: (selection) => _choose(selection.single),
          ),
          const SizedBox(height: 12),
          Text(
            cloudSyncStatusLine(
              l10n,
              status,
              service: active,
              now: DateTime.now(),
              browser: iCloudWeb != null,
            ),
            style: theme.textTheme.bodyMedium,
          ),
          if (buttonGoogle != null && account == null)
            _ProviderButton(
              key: const Key('cloudSyncGoogleButton'),
              width: 240,
              height: 44,
              child: buttonGoogle.button(
                dark: theme.brightness == Brightness.dark,
              ),
            )
          else if (active == SyncService.google)
            Row(
              children: [
                Expanded(
                  child: Text(
                    account?.email ?? '',
                    style: quiet,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: _signingIn
                      ? null
                      : buttonGoogle != null &&
                            status.error == CloudSyncError.signInNeeded
                      ? () => unawaited(_authorize())
                      : account == null
                      ? () => unawaited(_signIn(thenSelect: false))
                      : () => unawaited(_signOut()),
                  child: Text(
                    account == null ||
                            (buttonGoogle != null &&
                                status.error == CloudSyncError.signInNeeded)
                        ? l10n.cloudSyncGoogleSignIn
                        : l10n.cloudSyncGoogleSignOut,
                  ),
                ),
              ],
            ),
          if (iCloudWeb != null && iCloudUser == null)
            _ProviderButton(
              key: const Key('cloudSyncAppleButton'),
              width: 220,
              height: 42,
              child: appleSignInButton(iCloudWeb),
            )
          else if (iCloudWeb != null)
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.cloudSyncICloudSignedIn,
                    style: quiet,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: () => unawaited(_signOutOfICloud()),
                  child: Text(l10n.cloudSyncGoogleSignOut),
                ),
              ],
            ),
          const SizedBox(height: 4),
          Text(
            hinted == SyncService.google
                ? l10n.cloudSyncGoogleHint
                : ref.watch(cloudKitWebProvider) != null
                ? l10n.cloudSyncICloudWebHint
                : l10n.cloudSyncHint,
            style: quiet,
          ),
        ],
      ),
    );
  }
}

/// A sign-in button the provider draws itself (an element of the page),
/// at the size it draws it, under the status line.
class _ProviderButton extends StatelessWidget {
  const _ProviderButton({
    required this.width,
    required this.height,
    required this.child,
    super.key,
  });

  final double width;
  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: SizedBox(width: width, height: height, child: child),
    ),
  );
}

/// The name of [service] on its segment.
String syncServiceLabel(AppLocalizations l10n, SyncService service) =>
    switch (service) {
      SyncService.icloud => l10n.cloudSyncServiceICloud,
      SyncService.google => l10n.cloudSyncServiceGoogle,
      SyncService.off => l10n.cloudSyncServiceOff,
    };

/// The status line under the choice; [browser] for iCloud in the web
/// planner, which signs in itself where a device has its own account.
String cloudSyncStatusLine(
  AppLocalizations l10n,
  CloudSyncStatus status, {
  required SyncService service,
  required DateTime now,
  bool browser = false,
}) {
  if (service == SyncService.off) return l10n.cloudSyncOff;
  final google = service == SyncService.google;
  if (status.error == CloudSyncError.signInNeeded) {
    return l10n.cloudSyncSignInAgain;
  }
  switch (status.account) {
    case CloudAccount.noAccount:
      return google
          ? l10n.cloudSyncGoogleNoAccount
          : browser
          ? l10n.cloudSyncICloudSignedOut
          : l10n.cloudSyncNoAccount;
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
    case CloudSyncError.signInNeeded:
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
