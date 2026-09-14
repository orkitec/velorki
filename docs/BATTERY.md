# Battery: where a ride's energy goes and what Velorki can do about it

Status: plan. Nothing below is implemented.

## What costs energy during a recording

Measured and reported figures for a phone with the screen on, ordered by
impact. The numbers are typical Android values, not Velorki measurements;
the first task of the work below is to measure them on the Pixel 3 XL with
`adb shell dumpsys batterystats` before and after a one-hour ride.

| Consumer | Typical share | Velorki today |
|---|---|---|
| Screen on, full brightness, light theme | 40–60 % | "Keep screen on" holds a wake lock at whatever brightness the phone has; the light theme paints mostly white; the map redraws on every fix |
| GPS at best accuracy, continuous | 15–25 % | the recorder uses `LocationAccuracy.best`, `distanceFilter: 5 m`, `intervalDuration: 1 s`; the map's own stream runs alongside it at `high` / 5 m |
| Map rendering | 5–15 % while the screen is on | Vector map, animated camera moves on every fix while following, heading cone image, three route layers; keeps rendering under the sheet |
| CPU: routing, stats, journal writes | small | Ascent hysteresis and stats per fix; journal flush every 5 points / 10 s |
| Network | small | Tiles for the map as the camera moves; nothing else during a ride |

Two things stand out. The screen is the dominant cost and Velorki does
nothing to reduce it. And GPS is sampled twice: once by the recorder in the
foreground service and once by the map view's `devicePosition` provider, which
is alive whenever a map is on screen.

## The plan

### 1. Stop sampling GPS twice (implement first, no UI)

While a recording runs, the map must take its position from the recorder's
snapshots (it already receives them through `setPosition`) and the
`devicePosition` stream must pause. One provider watching
`recordingControllerProvider.isRecording` and returning an empty stream is
enough. Expected saving: the whole second GPS client.

### 2. Coarser GPS while riding (setting, default on)

Cycling does not need a fix every 5 m at best accuracy. A `LocationSettings`
of `LocationAccuracy.high`, `distanceFilter: 10 m` and, on Android,
`intervalDuration: 2 s` with `AndroidSettings.forceLocationManager: false`
halves the GPS duty cycle with no visible effect on a 20 km/h track (10 m at
20 km/h is one fix every 1.8 s). Auto-pause raises the interval to 10 s when
the rider is stopped and drops it back on the first movement. Expose it as
Settings → Recording → "GPS precision: Battery saver / Normal / Precise"
(precise = today's values, for mountain-bike trails).

### 3. Screen: dim, dark, and off by default

- "Keep screen on" stays a choice, off by default. When it is on, offer a
  slider "Brightness while riding" (default 40 %) applied through the
  `screen_brightness` plugin only while the recording runs and restored on
  finish. That alone is the biggest saving on an OLED phone.
- Battery saver mode switches the app to the dark theme and the **Black**
  map look for the duration of the ride (OLED pixels that are off cost
  nothing) and hides the heading cone and the accuracy ring.
- After 30 s without touch the record sheet collapses to the two figures the
  rider glances at (distance, speed) in a large font on a black background,
  the map hidden, the way bike computers do it; any touch brings the map
  back. The camera does not move while the map is hidden, so the map does
  not render either.

### 4. Map rendering while recording

- Camera follows the rider with `moveCamera` (no animation) when battery
  saver is on; animated moves at most every 3 s otherwise.
- The map view is not rendered at all while the screen is off or another
  tab is shown (`IndexedStack` keeps the platform view alive; wrap the map
  in a `Visibility(maintainState: true, visible: tabIsRecord)` so MapLibre
  stops drawing).
- Route casing and alternative layers stay; they are cheap.

### 5. Android battery optimisation

Already asked for once (`Keep recording in the background`). Keep it: a
foreground service with the `location` type and `START_STICKY` is the
correct shape; ignoring optimisation prevents Doze from delaying fixes,
which would otherwise cost more later in catch-up bursts.

### 6. One switch for riders: "Battery saver" on the record sheet

A toggle in the record sheet's lower half and in Settings → Recording:

- on: GPS "Battery saver" profile, dark theme + Black map for the ride,
  brightness 40 % while keep-screen-on is on, no cone, no accuracy ring,
  sheet auto-collapses to the big figures, no camera animation;
- off: today's behaviour with the GPS "Normal" profile.

The mode is remembered per user; the theme and map look return to the
rider's own choice when the ride ends.

## Order of work and how to measure

1. Measure a baseline: one hour of recording on the Pixel 3 XL, screen on
   at the phone's own brightness, `dumpsys batterystats --reset` before and
   `dumpsys batterystats` after; note the percentage drop and the GPS time.
2. Implement 1 and 2 (no UI beyond the GPS precision setting), measure again.
3. Implement 3 and 6, measure again. Expect the screen work to matter most.
4. Implement 4 last; it is the most invasive change to the map view.

Each step lands only with a before/after figure from the same route, so the
saving is a number and not a feeling.
