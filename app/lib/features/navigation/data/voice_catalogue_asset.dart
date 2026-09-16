import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/voice_catalogue.dart';

/// Where the friendly voice names live. Built by `tool/fetch_voices.py`;
/// see `assets/voices/README.md`.
const String voiceCatalogueAsset = 'assets/voices/catalogue.json';

/// Reads the catalogue out of the app bundle.
///
/// A broken or missing asset is not worth failing the screen over: the list
/// then falls back to numbering the voices, which is still better than the
/// engine's own identifiers.
Future<VoiceCatalogue> loadVoiceCatalogue(AssetBundle bundle) async {
  try {
    final text = await bundle.loadString(voiceCatalogueAsset);
    final json = jsonDecode(text);
    if (json is! Map<String, Object?>) return const VoiceCatalogue.empty();
    return VoiceCatalogue.fromJson(json);
  } catch (error) {
    debugPrint('Voice names are the plain ones: $voiceCatalogueAsset ($error)');
    return const VoiceCatalogue.empty();
  }
}

/// The friendly voice names. Read once and kept: the asset never changes
/// while the app runs.
final voiceCatalogueProvider = FutureProvider<VoiceCatalogue>(
  (ref) => loadVoiceCatalogue(rootBundle),
);
