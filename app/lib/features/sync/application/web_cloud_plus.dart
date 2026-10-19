import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:velorki_api/velorki_api.dart';

import '../../subscription/application/web_plus.dart';
import '../data/icloud_web_sync.dart';
import '../domain/sync_service.dart';
import 'cloud_sync_controller.dart';

part 'web_cloud_plus.g.dart';

final Logger _log = Logger('velorki.sync.plus');

/// Trades the web planner's cloud sign-in for Plus bought in the apps
/// ([WebPlus]): iCloud's session whenever someone is signed in (a session
/// kept from an earlier visit too), Google's token each time the rider
/// grants one ([trade], from Settings). The rotated CloudKit token the
/// relay hands back replaces the session's. No Plus to be had is no error:
/// the browser simply has none.
class WebCloudPlus {
  /// Creates the link.
  WebCloudPlus(this._ref);

  final Ref _ref;

  /// Asks the relay for Plus with [service]'s [token].
  Future<void> trade(PlusWebService service, String token) async {
    try {
      final plus = await _ref
          .read(webPlusProvider.notifier)
          .signIn(service, token);
      final rotated = plus.ckWebAuthToken;
      if (service == PlusWebService.icloud && rotated != null) {
        _ref.read(cloudKitWebProvider)?.sessionToken = rotated;
      }
    } on Object catch (e) {
      _log.info('no Plus through ${service.json}: $e');
    }
  }

  Future<void> _tradeICloud() async {
    final token = _ref.read(cloudKitWebProvider)?.sessionToken;
    if (token != null) await trade(PlusWebService.icloud, token);
  }
}

/// [WebCloudPlus] for the service the browser syncs with; listened to from
/// the browser's start (`bootstrap_web.dart`).
@Riverpod(keepAlive: true)
WebCloudPlus webCloudPlus(Ref ref) {
  final plus = WebCloudPlus(ref);
  if (!kIsWeb) return plus;
  final service = ref.watch(activeSyncServiceProvider);
  if (service == SyncService.icloud) {
    ref.listen(iCloudWebUserProvider, (previous, next) {
      final user = next.value;
      if (user == null) {
        if (previous?.value != null) {
          ref.read(webPlusProvider.notifier).forget();
        }
      } else if (user != previous?.value) {
        unawaited(plus._tradeICloud());
      }
    }, fireImmediately: true);
  } else if (service == SyncService.off) {
    // No cloud, no Plus from one.
    Future.microtask(() => ref.read(webPlusProvider.notifier).forget());
  }
  return plus;
}
