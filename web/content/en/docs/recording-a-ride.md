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
4. While riding the sheet shows a status pill, the elapsed clock, and the figures: **Distance**, **Speed**, **Avg**, then **Ascent**, **Descent**, **Moving**.
5. **Pause** stops the track where you are; **Resume** carries on. The break shows as a gap in the track.
6. **Finish** saves the ride under a default name like **Ride 17 Sept 2026** and opens its page.

If you finish having recorded nothing, Velorki says "Nothing was recorded." and saves no ride.

### Auto-pause

Velorki pauses itself after about ten seconds without movement; the pill then reads **AUTO-PAUSED**. Unlike a manual pause it keeps listening, and the first proper movement resumes it. A manual pause stops listening until you press **Resume**.

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
- [Library](./library)
- [Import and export](./import-and-export)
- [Strava and Ride with GPS](./strava-and-ridewithgps)
- [Settings and appearance](./settings-and-appearance)
