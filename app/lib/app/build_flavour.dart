/// Whether this build carries Google's own libraries.
///
/// `true` everywhere but the F-Droid flavour, which `main_fdroid.dart` builds
/// without `purchases_flutter`, `google_sign_in`, `in_app_update`,
/// `in_app_review`, `watch_connectivity` and `live_activities` — and on a
/// phone that has no Google Play Services either. What the flavour leaves out
/// of the interface it leaves out by the providers it does *not* override; the
/// one thing a provider cannot say is which location client geolocator should
/// ask for, and that is what this flag is for.
///
/// Set once by the entry point, before the first frame, and never again.
/// `docs/FDROID.md` is the whole picture.
bool googleServicesAvailable = true;
