import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'app_config.freezed.dart';
part 'app_config.g.dart';

/// Build-time configuration, one field per key in `env/example.json`.
///
/// Values come from `--dart-define-from-file=env/<flavor>.json`; every key is
/// optional so a bare `flutter run` still starts a purely local build.
@freezed
abstract class AppConfig with _$AppConfig {
  const factory AppConfig({
    @Default('') String brouterUrl,
    @Default('') String apiUrl,
    @Default('') String segmentsUrl,
    @Default('') String photonUrl,
    @Default('') String mapStyleUrl,
    @Default('') String mapStyleUrlDark,
    @Default('') String cyclosmTileUrl,
    @Default('') String revenueCatKeyAndroid,
    @Default('') String revenueCatKeyIos,
    @Default('') String stravaClientId,
    @Default('') String rwgpsClientId,
    @Default('velorki') String oauthScheme,
  }) = _AppConfig;

  const AppConfig._();

  static const AppConfig fromEnvironment = AppConfig(
    brouterUrl: String.fromEnvironment('VELORKI_BROUTER_URL'),
    apiUrl: String.fromEnvironment('VELORKI_API_URL'),
    segmentsUrl: String.fromEnvironment('VELORKI_SEGMENTS_URL'),
    photonUrl: String.fromEnvironment('VELORKI_PHOTON_URL'),
    mapStyleUrl: String.fromEnvironment('VELORKI_MAP_STYLE_URL'),
    mapStyleUrlDark: String.fromEnvironment('VELORKI_MAP_STYLE_URL_DARK'),
    cyclosmTileUrl: String.fromEnvironment('VELORKI_CYCLOSM_TILE_URL'),
    revenueCatKeyAndroid: String.fromEnvironment(
      'VELORKI_REVENUECAT_KEY_ANDROID',
    ),
    revenueCatKeyIos: String.fromEnvironment('VELORKI_REVENUECAT_KEY_IOS'),
    stravaClientId: String.fromEnvironment('VELORKI_STRAVA_CLIENT_ID'),
    rwgpsClientId: String.fromEnvironment('VELORKI_RWGPS_CLIENT_ID'),
    oauthScheme: String.fromEnvironment(
      'VELORKI_OAUTH_SCHEME',
      defaultValue: 'velorki',
    ),
  );

  /// Empty relay URL hides AI, Strava, RideWithGPS and link sharing entirely.
  bool get hasApi => apiUrl.isNotEmpty;

  bool get hasBrouter => brouterUrl.isNotEmpty;

  bool get hasRevenueCat =>
      revenueCatKeyAndroid.isNotEmpty || revenueCatKeyIos.isNotEmpty;
}

/// The three addresses users may point at their own servers.
@freezed
abstract class ServerOverrideUrls with _$ServerOverrideUrls {
  const factory ServerOverrideUrls({
    @Default('') String brouterUrl,
    @Default('') String photonUrl,
    @Default('') String apiUrl,
  }) = _ServerOverrideUrls;

  const ServerOverrideUrls._();

  bool get isEmpty => brouterUrl.isEmpty && photonUrl.isEmpty && apiUrl.isEmpty;
}

const _prefsBrouterUrl = 'server_override.brouter_url';
const _prefsPhotonUrl = 'server_override.photon_url';
const _prefsApiUrl = 'server_override.api_url';

/// Overridden in `bootstrap()` (and in tests) with a loaded instance.
@Riverpod(keepAlive: true)
SharedPreferences sharedPreferences(Ref ref) =>
    throw UnimplementedError('sharedPreferencesProvider must be overridden');

/// Settings → Advanced → Server URLs, persisted in shared_preferences.
@Riverpod(keepAlive: true)
class ServerOverrides extends _$ServerOverrides {
  @override
  ServerOverrideUrls build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return ServerOverrideUrls(
      brouterUrl: prefs.getString(_prefsBrouterUrl) ?? '',
      photonUrl: prefs.getString(_prefsPhotonUrl) ?? '',
      apiUrl: prefs.getString(_prefsApiUrl) ?? '',
    );
  }

  Future<void> setBrouterUrl(String value) async {
    await _write(_prefsBrouterUrl, value);
    state = state.copyWith(brouterUrl: value.trim());
  }

  Future<void> setPhotonUrl(String value) async {
    await _write(_prefsPhotonUrl, value);
    state = state.copyWith(photonUrl: value.trim());
  }

  Future<void> setApiUrl(String value) async {
    await _write(_prefsApiUrl, value);
    state = state.copyWith(apiUrl: value.trim());
  }

  Future<void> reset() async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.remove(_prefsBrouterUrl);
    await prefs.remove(_prefsPhotonUrl);
    await prefs.remove(_prefsApiUrl);
    state = const ServerOverrideUrls();
  }

  Future<void> _write(String key, String value) async {
    final prefs = ref.read(sharedPreferencesProvider);
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, trimmed);
    }
  }
}

/// [AppConfig] with the user's server overrides applied. Use this everywhere;
/// [appConfigProvider] is only the build-time baseline.
@Riverpod(keepAlive: true)
AppConfig effectiveConfig(Ref ref) {
  final base = ref.watch(appConfigProvider);
  final overrides = ref.watch(serverOverridesProvider);
  if (overrides.isEmpty) return base;
  return base.copyWith(
    brouterUrl: overrides.brouterUrl.isEmpty
        ? base.brouterUrl
        : overrides.brouterUrl,
    photonUrl: overrides.photonUrl.isEmpty
        ? base.photonUrl
        : overrides.photonUrl,
    apiUrl: overrides.apiUrl.isEmpty ? base.apiUrl : overrides.apiUrl,
  );
}

@Riverpod(keepAlive: true)
AppConfig appConfig(Ref ref) => AppConfig.fromEnvironment;
