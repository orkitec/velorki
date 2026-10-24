import 'google_account.dart';

/// Google's sign-in in a browser, which only a browser has: the phones use
/// `PluginGoogleSignIn`.
ButtonGoogleSignIn createWebGoogleSignIn(String clientId) =>
    throw UnsupportedError('Google Identity Services runs in a browser only');
