---
title: Recording a ride
description: Start, pause and finish a ride, keep it recording with the screen off, save battery, and get a ride back after the app was killed.
order: 7
---

The Record tab tracks your ride and saves it to the library when you finish. It keeps recording with the screen off and with the app in the background, and it survives the app being closed or killed.

Recording is free and works with no connection at all.

## Start, pause, finish

1. Open the **Record** tab. The sheet says **Ready to ride** and "The track is written to the phone while you ride, even with the screen off."
2. Optionally pick a route under **Follow a route**, which turns on the guidance described in [turn-by-turn navigation](./navigation).
3. Tap **Start ride**.
4. While riding the sheet shows a status pill, the elapsed clock, and the figures: **Distance**, **Speed**, **Avg**, then **Ascent**, **Descent**, **Moving**. While you follow a route a row **Left** and **Arrival** joins them: the distance still to ride and when you will arrive at your average speed so far, two dashes until the ride has an average.
5. **Pause** stops the track where you are; **Resume** carries on. The break shows as a gap in the track. While paused the figures fade and the pill turns to **PAUSED**, so the state is plain at a glance.
6. **Finish** saves the ride under a default name like **Ride 17 Sept 2026** and opens its page.

If you finish having recorded nothing, Velorki says "Nothing was recorded." and saves no ride.

### Auto-pause

Velorki pauses itself after about ten seconds without movement; the pill then reads **AUTO-PAUSED**. Unlike a manual pause it keeps listening, and the first proper movement resumes it. A manual pause stops listening until you press **Resume**.

## Heart rate, cadence and power

Once a sensor is switched on, a third row of figures joins the sheet with what has been reported during this ride: **Heart rate**, **Cadence** and **Power**, so a watch alone adds one tile. The heart-rate tile carries the ride's **Avg HR** underneath. A sensor that falls silent mid-ride, a watch out of range or a strap that slipped, keeps its tile with the last value dimmed and a broken-link mark, so you can see that something stopped reporting; while the ride is paused the sensor rests on purpose and nothing is marked. They can come from a Bluetooth sensor, from an Apple Watch or from the phone's health app, they are written onto the track as you ride, and on an iPhone the pulse shows on the lock screen card as well. While a wheel sensor is reporting, its speed is what **Speed** shows.

Without a sensor none of it appears, and nothing is switched on until you do it in **Settings → Sensors**. See [sensors and your watch](./sensors-and-watch).

## The elevation profile and the cue sheet

The sheet under the map has three pages, a swipe apart, with three dots under the figures saying which is up. A new ride starts on the figures.

**The elevation profile**, one swipe to the left: the followed route as height over distance, the part already ridden filled in the accent colour, the road ahead in grey, a line where you are, and above it what is left, "12.4 km left, 320 m to climb". On a climb of 3 % or more a second line says the grade and what is left to its top, "6 % climb, 120 m to the top", and once the ride has an average speed the same line says when you will arrive, "ETA 14:32". Without a route to follow the page says so: "Follow a route to see its elevation profile here."

**The cue sheet**, one more swipe: **Upcoming turns**, the next eight turns of the route in order with the distance to each, the points of interest on the route between them, and **Arrive** at the end, with "3 more" underneath when more follow. The first line is what the turn banner shows. A route imported with a cue sheet shows the author's own words for each turn, "Turn left onto Main Street", instead of the plain instruction.

## What it asks for the first time

The first ride triggers up to three prompts, described in full in [getting started](./getting-started):

- **Location**, with Velorki's own explanation first.
- **Notifications** on Android, because the recording lives in one. Refuse and Velorki warns "Without the notification permission Android stops the recording when you leave the app."
- **Battery optimisation** on Android, once ever: "Android may stop the recording while the phone sleeps. Letting Velorki ignore battery optimisation keeps the track complete. You are asked only once."

## Screen off, app closed

The track is written to the phone as you ride, flushed every few seconds, so nothing depends on the app staying in the foreground.

- **Android**: the ride runs in a foreground service with an ongoing notification titled **Recording a ride**, whose second line carries your distance and time, and the next turn when you are following a route. Tapping it comes back to the app.
- **iPhone**: the ride keeps running with the screen locked, and a live activity shows the same figures on the lock screen.

**Keep screen on** in the Record sheet stops the display sleeping, which is handy on a handlebar mount and expensive for the battery.

## Battery saver

The screen is what drains a phone on a long ride, so **Battery saver** attacks the screen. Turn it on in the Record sheet or in **Settings → Recording**: "Dark map, no animations, a plain page with the numbers after 30 s; the screen is what drains the battery".

While a ride records with the saver on, Velorki:

- forces the dark theme and a black map,
- draws a bare position dot, with no accuracy ring and no heading cone,
- jumps the camera instead of animating it,
- dims the display to 40 % while **Keep screen on** is holding it awake,
- and after **30 seconds without a touch** replaces everything with a glance page: white on black, the next turn if there is one, then **Distance** as a big figure with **Speed** and **Time** under it.

Touch anywhere to bring the map back; the countdown starts again. Everything reverts when the ride ends or the saver goes off. The saver never changes the theme you chose for the rest of the app.

**GPS precision** in **Settings → Recording** is the other half: **Battery saver**, **Normal** or **Precise**, with the hint "Precise is for trails; Normal is enough for roads".

## If a ride is interrupted

Velorki writes the track to a journal file as it goes, so a crash, a force-quit or a phone that ran out of battery does not lose the ride.

- If the recording service is still alive when you come back, the app quietly reattaches and carries on.
- If it is not, opening the Record tab shows **Unfinished ride**: "A ride from 16 Sept 2026 was never finished. 42.1 km and 2 h 10 min are saved. Continue it or finish it now?" with three answers:
  - **Resume** picks the ride up where it stopped,
  - **Finish** saves what there is and opens the ride page,
  - **Discard** throws it away.

The dialog cannot be dismissed without answering, so a recovered ride is never silently lost.

## Continuing a finished ride

A ride you already finished can be carried on: open it from the library and choose **Continue this ride** from the menu at the top right. "Recording starts again on this ride: its track, distance, time and climb continue where they stopped, and the break until now counts as a pause."

If another ride is recording it is finished and saved first, and if this one was already uploaded to Strava or Ride with GPS you are told that the continued ride will need sending again.

## Recent rides

Under **Recent rides** on the Record tab are your last five, newest first, each with its date, distance and moving time. Swipe a row to the left to delete it, with an **Undo** in the message that follows. The full list is in the [library](./library).

## Related

- [Turn-by-turn navigation](./navigation)
- [Sensors and your watch](./sensors-and-watch)
- [Library](./library)
- [Import and export](./import-and-export)
- [Strava and Ride with GPS](./strava-and-ridewithgps)
- [Settings and appearance](./settings-and-appearance)
