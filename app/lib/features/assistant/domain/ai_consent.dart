/// What the rider allowed the assistant to send.
///
/// Stored in `shared_preferences` under [aiConsentPrefsKey] and asked for once,
/// before the first request. Apple's 5.1.2(i) wants explicit consent before
/// personal data reaches a third-party model, and the position is the only
/// personal thing Velorki could send — hence the middle value.
enum AiConsent {
  /// Nothing may be sent. The assistant is switched off.
  denied,

  /// The typed text may be sent, but no position.
  textOnly,

  /// The text and a position rounded to about a kilometre may be sent.
  withLocation;

  /// The stored value, or `null` when it is missing or unknown.
  static AiConsent? fromName(String? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// Whether a request may be sent at all.
  bool get allowsRequests => this != AiConsent.denied;

  /// Whether the rough position may go with it.
  bool get allowsLocation => this == AiConsent.withLocation;
}

/// The `shared_preferences` key the consent is kept under.
const String aiConsentPrefsKey = 'ai.consent';

/// How far the position sent to the model is rounded, in decimal places.
///
/// Two decimals are about 1.1 km at the equator and less towards the poles,
/// which is the "about a kilometre" the consent dialog promises. The relay
/// rounds again; the app rounds first so the precise value never leaves the
/// phone.
const int aiPositionDecimals = 2;

/// Rounds [value] to [aiPositionDecimals] decimal places.
double roundCoordinate(double value) {
  const factor = 100.0; // 10^aiPositionDecimals
  return (value * factor).roundToDouble() / factor;
}
