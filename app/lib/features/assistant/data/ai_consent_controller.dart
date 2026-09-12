import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/app_config.dart';
import '../domain/ai_consent.dart';

part 'ai_consent_controller.g.dart';

/// The rider's AI consent, or `null` while they have not been asked.
///
/// `null` and [AiConsent.denied] are deliberately different: the first opens
/// the consent dialog, the second means the rider said no and is not asked
/// again until they change it in Settings.
@Riverpod(keepAlive: true)
class AiConsentController extends _$AiConsentController {
  @override
  AiConsent? build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return AiConsent.fromName(prefs.getString(aiConsentPrefsKey));
  }

  /// Records [consent] and remembers it for the next launch.
  Future<void> set(AiConsent consent) async {
    await ref
        .read(sharedPreferencesProvider)
        .setString(aiConsentPrefsKey, consent.name);
    state = consent;
  }

  /// Forgets the answer, so the dialog appears again.
  Future<void> reset() async {
    await ref.read(sharedPreferencesProvider).remove(aiConsentPrefsKey);
    state = null;
  }
}
