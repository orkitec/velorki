# Battery: where a ride's energy goes and what Velorki does about it

Status: implemented, unmeasured. The work below is in the app; the figures
that would prove it are not, because nobody has run the two rides yet. How to
run them is at the end of this file.

## What costs energy during a recording

Typical Android values for a phone with the screen on, ordered by impact.
These are reported figures, not Velorki measurements.

| Consumer | Typical share | Velorki now |
|---|---|---|
| Screen on, full brightness, light theme | 40–60 % | battery saver: dark theme, black map, 40 % brightness while "keep screen on" is on, and a black glance page after 30 s without a touch |
| GPS at best accuracy, continuous | 15–25 % | one client, not two, while a ride runs; three profiles, `normal` (high, 5 m, 1 s) by default |
| Map rendering | 5–15 % while the screen is on | no camera animation in saver, no accuracy ring, no heading cone, and the map is not painted while the glance page is up |
| Magnetometer + accelerometer for the standstill heading | negligible | 10 Hz, only while the Record tab is on screen (`compassHeadingProvider` is `autoDispose`) |
| CPU: routing, stats, journal writes | small | ascent hysteresis and stats per fix; journal flush every 5 points / 10 s |
| Network | small | tiles as the camera moves; nothing else during a ride |

The order is the point: the screen dwarfs everything else, GPS is second, and
the rest is cosmetic. A saver that dimmed the puck but left the display at
full brightness would be theatre.

## What is implemented

**One GPS client while recording.** `devicePositionProvider` — the stream
every map's puck is drawn from — ends itself while
`recordingControllerProvider` reports a ride
(`app/lib/features/map/data/position_provider.dart`). The recorder already
holds a client, on Android inside the foreground service, and the record
screen draws the puck from its snapshots. The provider is rebuilt, permission
and all, the moment the ride stops, so the planner's puck comes back by
itself.

**A GPS precision setting.** Settings → Recording → GPS precision, three
profiles in `recordingLocationSettings`:

| Profile | Accuracy | Distance filter | Android interval |
|---|---|---|---|
| Battery saver | `high` | 10 m | 2 s |
| Normal (default) | `high` | 5 m | 1 s |
| Precise | `best` | 5 m | 1 s |

Ten metres at 20 km/h is a fix every 1.8 s, so the saver profile loses
nothing on a road; `precise` is for trails, where the stored track is the
point. The choice is read when a ride starts and written into
`recording_state.json`, which is how it reaches the foreground service
isolate — that isolate has no access to the preferences.

**A battery saver switch**, in Settings → Recording and on the record sheet
next to "Keep screen on". While it is on and a ride is running
(`batterySaverActiveProvider`):

- the app runs in the dark theme and the map in the **Black** style, through
  `appearanceOverrideProvider`, which the theme builder and `mapStyleUrlFor`
  consult. Nothing is written to the rider's stored appearance, so their own
  choice is back the second the ride ends or the saver goes off;
- the puck is a bare dot: `setPosition(minimal: true)` drops the accuracy
  ring and the heading cone;
- the camera jumps to each fix (`animate: false`) instead of gliding;
- the display is held at 40 % through the `screen_brightness` plugin, but
  only while "keep screen on" is also on — a screen that switches itself off
  costs nothing already. It is reset when the ride ends, the saver goes off,
  keep-screen-on goes off, or the screen is left;
- after 30 s without a touch the map and the sheet give way to a black page
  with the distance, the speed, the elapsed time and, when a route is being
  navigated, the next turn. No controls at all, so nothing can be stopped by
  accident; a tap anywhere brings the map back for another 30 s. The map
  keeps its state behind the page but Flutter stops painting it — whether
  MapLibre's platform view really stops rendering natively is not known.

**The foreground service** keeps the shape it had: `location` type,
`START_STICKY`, the battery-optimisation exemption asked for once. Ignoring
Doze prevents delayed fixes, which would otherwise cost more in catch-up
bursts.

## What is not implemented

- **Auto-pause does not raise the GPS interval.** A rider standing at a café
  is journalled as paused, but the fixes keep arriving at the ride's profile.
  Dropping to a fix every 10 s while paused and back on the first movement is
  the obvious next saving.
- **Maps on hidden tabs keep rendering.** The shell keeps all four branches
  alive, so the planner's map is still a live platform view while the Record
  tab is on screen. Wrapping it the way the glance page wraps the record map
  is the same trick, one level up.
- **No brightness slider.** 40 % is a constant (`saverBrightness`), not a
  setting.
- **The saver profile is not chosen for the rider.** Switching the saver on
  is a deliberate act; nothing watches the battery level and does it.

## How to measure

Two rides on the same route, one with the saver on and one off, an hour each,
same phone, same brightness setting, same clothes over the handlebars. On the
Pixel:

```bash
# Before each ride — unplug the phone first, this only resets while on battery
adb shell dumpsys batterystats --reset

# Ride for an hour with the app on the Record tab and the screen on.

# After the ride, still unplugged
adb shell dumpsys batterystats --charged com.orkitec.velorki > after.txt
adb shell dumpsys batterystats --charged > after-all.txt
```

What to read in `after.txt`:

- **`Estimated power use (mAh)`** — the `Uid u0a…: <mAh>` line for the app,
  and the `screen:` line in the block above it. The screen figure is the
  system's, not the app's, which is exactly the point being tested.
- **`Screen on:`** near the top of the report: how much of the hour the
  display was actually lit. Two rides are only comparable when these match.
- **`GPS: … realtime`** (or `Sensor 0 (GPS):`) in the app's block: how long
  the location hardware ran for Velorki. The saver profile should not change
  this much — it changes how hard the chip works, not how long — while the
  "one client, not two" fix should have halved the number of requests.
- **`Foreground services:`** — one entry, the recorder, for the whole ride.
  Two would mean something started a second one.

Note the battery percentage at the start and the end of each ride as well;
`dumpsys` is precise about attribution and vague about absolutes, and the two
figures together are what tells the honest story. Write both numbers into
this file when they exist.
