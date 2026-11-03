import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/guide.dart';

part 'guide_repository.g.dart';

/// Where `tool/gen.sh` puts the guide: one folder per locale.
const String guideAssetRoot = 'assets/guide';

/// The bundled guide in [languageCode], English for any page that language
/// has not got, in order.
///
/// Throws a [StateError] when no English page is bundled: a build made
/// without `tool/gen.sh`, which should have failed at the asset step.
Future<List<GuidePage>> loadGuide(
  AssetBundle bundle,
  String languageCode,
) async {
  final manifest = await AssetManifest.loadFromAssetBundle(bundle);
  final assets = manifest.listAssets();

  Future<List<GuidePage>> pagesOf(String locale) async {
    final prefix = '$guideAssetRoot/$locale/';
    return [
      for (final key in assets)
        if (key.startsWith(prefix) && key.endsWith('.md'))
          parseGuidePage(
            key.substring(prefix.length, key.length - 3),
            await bundle.loadString(key),
          ),
    ];
  }

  final english = await pagesOf('en');
  if (english.isEmpty) {
    throw StateError('No guide in $guideAssetRoot/en; run tool/gen.sh');
  }
  return mergeGuideLocales(
    english: english,
    locale: languageCode == 'en' ? const [] : await pagesOf(languageCode),
  );
}

/// The guide in [languageCode], read once from the app's bundle.
@Riverpod(keepAlive: true)
Future<List<GuidePage>> guide(Ref ref, String languageCode) =>
    loadGuide(rootBundle, languageCode);
