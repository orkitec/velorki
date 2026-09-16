import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../domain/rd5_format.dart';
import 'brouter_assets.dart';

/// The rd5 format this build of the app can read: the version pair of the
/// `lookups.dat` copied out of the bundle. Tiles newer than this need an app
/// update, and are neither offered for download nor routed on.
///
/// `null` when the file is not there or says nothing, which only happens in
/// tests with an empty profiles directory; nothing is gated then.
final supportedRd5FormatProvider = FutureProvider<Rd5Format?>((ref) async {
  final profiles = await ref.watch(brouterProfilesProvider.future);
  final file = File(p.join(profiles.path, 'lookups.dat'));
  if (!file.existsSync()) return null;
  return Rd5Format.fromLookups(await file.readAsString());
});
