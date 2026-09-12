import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/app_config.dart';

/// The shared_preferences key the app user id is kept under.
const String appUserIdPrefsKey = 'plus.app_user_id';

/// The prefix that marks an id the app made up rather than one RevenueCat
/// handed out.
const String anonymousAppUserIdPrefix = 'anon-';

/// A fresh anonymous app user id, `anon-<uuid v4>`.
String generateAnonymousAppUserId({Uuid uuid = const Uuid()}) =>
    '$anonymousAppUserIdPrefix${uuid.v4()}';

/// Whether [id] was made up by the app rather than issued by RevenueCat.
bool isAnonymousAppUserId(String id) => id.startsWith(anonymousAppUserIdPrefix);

/// The identity the relay authenticates every request against.
///
/// The relay checks the RevenueCat entitlement of whatever comes in as
/// `Authorization: Bearer <app_user_id>`, which doubles as the authentication
/// of the OAuth endpoints. Until the subscription feature lands in M6 there is
/// no RevenueCat SDK to ask, so the app generates one stable anonymous id and
/// keeps it in `shared_preferences` for the life of the installation.
///
/// Stability matters more than secrecy here: when RevenueCat is wired up in
/// M6 its anonymous id takes this one's place, and a purchase made under the
/// old id is restored through the store, not through this string.
final appUserIdProvider = Provider<String>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final existing = prefs.getString(appUserIdPrefsKey);
  if (existing != null && existing.isNotEmpty) return existing;
  final created = generateAnonymousAppUserId();
  // Writing is asynchronous but the value is returned now; a crash before the
  // write lands simply means a new id next launch, which costs nothing while
  // the id is anonymous.
  unawaited(prefs.setString(appUserIdPrefsKey, created));
  return created;
});
