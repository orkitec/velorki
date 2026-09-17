# Import and export

Everything that turns a GPX or FIT file into a route or a ride, and back.

## Intake

`IncomingFileService` (`data/incoming_file_service.dart`) unifies the three
ways a file can reach the app. It exposes two streams — `imports` for decoded
files and `deepLinks` for links that are not files (`velorki://oauth/...`,
`velorki://s/<id>`; those belong to later milestones) — and the providers
`incomingImportsProvider` and `incomingDeepLinksProvider`.

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
* The activation rule takes files (up to ten) and one web URL and nothing else.
  Offering Velorki in the share sheet for a photo or a paragraph of text would
  be a lie, and the extension redirects straight into the app rather than
  showing a compose sheet there is nothing to compose in.
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

No Dart code changes: `IncomingFileService` already listens to
`receive_sharing_intent` on both platforms. `ios/Runner/AppDelegate.swift`
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
