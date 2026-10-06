# Import and export

Everything that turns a GPX or FIT file into a route or a ride, and back.

## Intake

`IncomingFileService` (`data/incoming_file_service.dart`) unifies the three
ways a file can reach the app. It exposes `imports` for decoded files,
`locations` for places (see Places below) and `deepLinks` for other links
(`velorki://oauth/...`, `velorki://share/<id>`), with the providers
`incomingImportsProvider`, `incomingLocationsProvider` and
`incomingDeepLinksProvider`.

| Source | Plugin | Platforms |
|---|---|---|
| share sheet | `receive_sharing_intent` | Android (`ACTION_SEND`), iOS (Share Extension) |
| open-with | `app_links` (`content://`, `file://`) | Android |
| open-with | the `velorki/files` method channel | iOS |

Whatever arrives is read into bytes and **sniffed**, never trusted by MIME type
or file extension: senders send GPX as `application/octet-stream`, name FIT
files `.gpx` and vice versa. `looksLikeGpx` / `looksLikeFit` decide, then
`GpxCodec.decode` / `FitCodec.decodeActivity` produce an `ImportedTrack`, and
`ImportCandidate` carries it to `/import`.

Route or ride is suggested by the presence of timestamps on the points: a
planned route has none, a recording does. The preview screen lets the user
override that with the Route/Ride toggle — which matters for FIT **courses**,
whose records carry a synthetic one-second time base, so they are suggested as
rides even though they are routes. Telling a FIT course from a FIT activity
needs the `file_id` message, which `velorki_fit` does not expose yet.

### Android: reading a `content://` URI

Only the process holding the intent's temporary read grant can open a content
URI, and that is `MainActivity`. `android/app/src/main/kotlin/.../MainActivity.kt`
therefore implements the `velorki/files` method `openInputStream`, which reads
the URI through the `ContentResolver` (32 MB cap) and hands the bytes back to
Dart. Files that arrive through the share sheet need none of this:
`receive_sharing_intent` already copies them to a readable path.

### iOS: the Share Extension

`ios/VelorkiShare` is what **"Share → Velorki"** reaches. Three files — a
`ShareViewController` subclassing `RSIShareViewController` from
`receive_sharing_intent`, an `Info.plist` and an entitlements file — plus the
`VelorkiShare` target in `Runner.xcodeproj`, embedded in Runner by the "Embed
Foundation Extensions" phase, which has to stay ahead of "Thin Binary" exactly
as it does for the live activity.

* Bundle id `com.orkitec.velorki.share`, display name "Velorki", deployment
  target 15.0 — the Runner's. The `.share` suffix is not decoration: the plugin
  works out the host app's bundle id by dropping the last component.
* The activation rule takes files (up to ten), one web URL and text (a place
  shared from a map app or a messenger), not photos, and the extension
  redirects straight into the app rather than showing a compose sheet there
  is nothing to compose in. Text goes over as text, an Apple Maps vCard as its
  text only when no URL came with it (the URL names the same place).
* **App Group `group.com.orkitec.velorki`** — the one the live activity
  already uses. It is in both entitlements files and is the user-defined build
  setting `CUSTOM_GROUP_ID` on both targets, which the `AppGroupId` key in both
  `Info.plist`s reads. The extension copies the shared files into the group
  container and opens `ShareMedia-com.orkitec.velorki:`, which is the second
  `CFBundleURLTypes` entry in the Runner's `Info.plist`.
* `receive_sharing_intent` ships no podspec, so the extension links its
  `receive-sharing-intent` library over Swift Package Manager. The project's
  package reference is the symlink `flutter build` writes,
  `Flutter/ephemeral/Packages/.packages/receive_sharing_intent-1.9.0` — the
  version is part of that name, so bumping the plugin in `pubspec.yaml` means
  editing `relativePath` in `project.pbxproj` to match, or Xcode stops finding
  the package.

`IncomingFileService` listens to `receive_sharing_intent` on both
platforms. `ios/Runner/AppDelegate.swift`
still handles **"Open in Velorki"** from Files, Mail and Safari — it starts
security-scoped access, copies the file into `tmp/incoming/` (the scoped URL is
only readable until `application(_:open:options:)` returns) and invokes
`velorki/files` → `opened` with the copy's path. That is what the
`CFBundleDocumentTypes` and `UTImportedTypeDeclarations` entries in
`Info.plist` register; sharing and opening are separate paths.

**One signed build on a Mac is still owed.** The App Group has to exist in the
developer portal. Automatic signing creates and registers it the first time
Xcode signs Runner and VelorkiShare with the orkitec team; until then a device
or App Store build fails to provision. CI only builds for the simulator, which
does not sign, so a green `integration-ios` run proves the target compiles and
embeds, not that the group is registered.

## Places

Not every share is a file. `IncomingFileService.locations` carries a place
read by `parseLocationLink` (`lib/core/links/location_link.dart`, pure Dart,
offline): a `geo:` intent (Android "Open with", manifest filter on the `geo`
scheme), `velorki://navigate?lat=&lon=[&name=]` or `?q=`, a Google, Apple or
OpenStreetMap link, or shared text with coordinates or an address in it. One
share's text and links are read together, so "Name\n<short link>" is one
place; a link that names no place still goes to `deepLinks`. A text the plugin
reports that is really a file path (Android, `text/*` files) is left to the
file path. The same place twice within three seconds is one place: Android
hands a `geo:` or `velorki://` intent to both plugins.

`listenForIncomingLocations` (`features/planner/application/incoming_place.dart`)
opens the Plan tab and parks the place in `incomingPlaceProvider` until the
planner can take it: coordinates go through `SearchField.select`, the path a
tapped search result takes; an address or a name goes into the field as typed
(`SearchField.searchFor`); a short link (`maps.app.goo.gl`, `osm.org/go`) only
a browser can open gets the message `placeLinkNeedsBrowser`.

## Preview and saving

`ImportPreviewScreen` (route `/import`, candidate in `extra`) shows the map
preview, the detected format, the point count, the statistics and the time
span, and saves through `ImportRepository`:

* **route** → `RouteRepository.saveImportedRoute` with
  `source: importedGpx | importedFit`, waypoints defaulting to the first and
  last point;
* **ride** → a `rides` row with the statistics from
  `lib/core/geo/ride_stats.dart` — the same code the recorder runs live, so an
  imported ride is measured exactly like a recorded one: moving time at a
  1 km/h threshold, ascent and descent with 3 m hysteresis, fixes implying more
  than 30 m/s dropped as GPS jumps, and a gap of more than 30 s treated as a
  break that contributes neither distance nor moving time. A file without
  timestamps has no ride in it, so `computeImportedStats` falls back to
  `computeRouteGeometryStats`: distance and climb from the geometry, every
  duration zero.

## Export

`ShareTrackExporter` (`lib/core/files/track_exporter_impl.dart`) implements the
`TrackExporter` contract: it encodes the track, writes it below
`<temporary>/export/` — clearing what a previous export left — and hands the
file to `share_plus`. A route becomes a GPX `<rte>` or a FIT course; a ride
becomes a GPX `<trk>` with its timestamps or a FIT activity. The share call
itself is injectable so tests exercise the encode-and-write path without a
platform channel.
