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
| share sheet | `receive_sharing_intent` | Android (`ACTION_SEND`) |
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

### iOS: no Share Extension yet

`ios/Runner/AppDelegate.swift` implements
`application(_:open:options:)`: it starts security-scoped access, copies the
file into `tmp/incoming/` (the scoped URL is only readable until the method
returns) and invokes `velorki/files` → `opened` with the copy's path. That
covers **"Open in Velorki"** from Files, Mail and Safari, which is what the
`CFBundleDocumentTypes` and `UTImportedTypeDeclarations` entries in
`Info.plist` register.

**What is missing on iOS is the share sheet.** `receive_sharing_intent` needs a
*Share Extension* target, which cannot be created from this repository: it is a
new Xcode target with its own bundle id, entitlements, an App Group shared with
the main app, and provisioning profiles for both. That is Mac-and-Xcode work
and is deliberately **not part of M2**. Until it is added, "Share → Velorki"
from another iOS app does nothing; "Open in Velorki" works. Adding it later
changes no Dart code — `IncomingFileService` already listens to
`receive_sharing_intent` on both platforms.

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
