import 'package:flutter/widgets.dart';

import 'cloudkit_web.dart';

/// [CloudKitWeb] over CloudKit JS, which only a browser has: the phones
/// sync with iCloud through CKSyncEngine instead.
CloudKitWeb createCloudKitWeb({
  required String apiToken,
  required String environment,
}) => throw UnsupportedError('CloudKit JS runs in a browser only');

/// Apple's sign-in button, which only a browser draws.
Widget appleSignInButton(CloudKitWeb api) => const SizedBox.shrink();
