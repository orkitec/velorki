import '../../../l10n/generated/app_localizations.dart';
import '../domain/voice_naming.dart';

/// The translated words every voice name is built from.
///
/// The bundled catalogue is English-only, so nothing it says is ever shown:
/// it only supplies the gender and quality the engine keeps to itself, and
/// the words below do the naming.
VoiceNaming namingFrom(AppLocalizations l10n) => VoiceNaming(
  female: l10n.voiceFemale,
  male: l10n.voiceMale,
  label: l10n.voiceLabel,
  labelGeneric: l10n.voiceLabelGeneric,
  enhanced: l10n.voiceQualityEnhanced,
  premium: l10n.voiceQualityPremium,
  regionName: (tag) => regionNameOf(l10n, tag),
  languageName: (tag) => languageNameOf(l10n, tag),
);

/// What to call the region of [localeTag], e.g. "United States" for
/// `en-US`. A region the translations do not name falls back to the tag
/// itself, which is still better than nothing.
String regionNameOf(AppLocalizations l10n, String localeTag) {
  final parts = localeTag.split(RegExp('[-_]'));
  if (parts.length < 2) return localeTag;
  return switch (parts[1].toUpperCase()) {
    'AR' => l10n.regionAR,
    'AU' => l10n.regionAU,
    'BD' => l10n.regionBD,
    'BE' => l10n.regionBE,
    'BG' => l10n.regionBG,
    'BR' => l10n.regionBR,
    'CA' => l10n.regionCA,
    'CL' => l10n.regionCL,
    'CN' => l10n.regionCN,
    'CO' => l10n.regionCO,
    'CZ' => l10n.regionCZ,
    'DE' => l10n.regionDE,
    'DK' => l10n.regionDK,
    'ES' => l10n.regionES,
    'FI' => l10n.regionFI,
    'FR' => l10n.regionFR,
    'GB' => l10n.regionGB,
    'GR' => l10n.regionGR,
    'HK' => l10n.regionHK,
    'HR' => l10n.regionHR,
    'HU' => l10n.regionHU,
    'ID' => l10n.regionID,
    'IE' => l10n.regionIE,
    'IL' => l10n.regionIL,
    'IN' => l10n.regionIN,
    'IR' => l10n.regionIR,
    'IT' => l10n.regionIT,
    'JP' => l10n.regionJP,
    'KR' => l10n.regionKR,
    'MX' => l10n.regionMX,
    'MY' => l10n.regionMY,
    'NG' => l10n.regionNG,
    'NL' => l10n.regionNL,
    'NO' => l10n.regionNO,
    'PL' => l10n.regionPL,
    'PT' => l10n.regionPT,
    'RO' => l10n.regionRO,
    'RU' => l10n.regionRU,
    'SE' => l10n.regionSE,
    'SI' => l10n.regionSI,
    'SK' => l10n.regionSK,
    'TH' => l10n.regionTH,
    'TR' => l10n.regionTR,
    'TW' => l10n.regionTW,
    'UA' => l10n.regionUA,
    'US' => l10n.regionUS,
    'VN' => l10n.regionVN,
    'ZA' => l10n.regionZA,
    _ => localeTag,
  };
}

/// What to call the language of [localeTag], e.g. "English" for `en-GB`.
/// An unlisted language falls back to the tag itself.
String languageNameOf(AppLocalizations l10n, String localeTag) =>
    switch (localeTag.split(RegExp('[-_]')).first.toLowerCase()) {
      'ar' => l10n.languageAr,
      'bg' => l10n.languageBg,
      'bho' => l10n.languageBho,
      'bn' => l10n.languageBn,
      'ca' => l10n.languageCa,
      'cmn' => l10n.languageCmn,
      'cs' => l10n.languageCs,
      'da' => l10n.languageDa,
      'de' => l10n.languageDe,
      'el' => l10n.languageEl,
      'en' => l10n.languageEn,
      'es' => l10n.languageEs,
      'eu' => l10n.languageEu,
      'fa' => l10n.languageFa,
      'fi' => l10n.languageFi,
      'fr' => l10n.languageFr,
      'gl' => l10n.languageGl,
      'he' => l10n.languageHe,
      'hi' => l10n.languageHi,
      'hr' => l10n.languageHr,
      'hu' => l10n.languageHu,
      'id' => l10n.languageId,
      'it' => l10n.languageIt,
      'ja' => l10n.languageJa,
      'kn' => l10n.languageKn,
      'ko' => l10n.languageKo,
      'mr' => l10n.languageMr,
      'ms' => l10n.languageMs,
      'nb' => l10n.languageNb,
      'nl' => l10n.languageNl,
      'pl' => l10n.languagePl,
      'pt' => l10n.languagePt,
      'ro' => l10n.languageRo,
      'ru' => l10n.languageRu,
      'sk' => l10n.languageSk,
      'sl' => l10n.languageSl,
      'sv' => l10n.languageSv,
      'ta' => l10n.languageTa,
      'te' => l10n.languageTe,
      'th' => l10n.languageTh,
      'tr' => l10n.languageTr,
      'uk' => l10n.languageUk,
      'vi' => l10n.languageVi,
      'wuu' => l10n.languageWuu,
      'yue' => l10n.languageYue,
      'zh' => l10n.languageZh,
      _ => localeTag,
    };
