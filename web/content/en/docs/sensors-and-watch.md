---
title: Sensors and your watch
description: Heart rate, cadence and power from a Bluetooth sensor, an Apple Watch or your phone's health app, set up once and kept with every ride.
order: 16
---

Velorki can show your heart rate, your pedalling cadence and your power while you record, and keep all three with the ride afterwards. The readings come from a Bluetooth sensor, from an Apple Watch or from the phone's own health app, and all of it is free and runs on the phone.

Nothing here happens until you switch it on. With every source off, Velorki asks the operating system for nothing and no screen mentions a sensor.

## What you can measure

| Source | What it gives | What it needs |
|---|---|---|
| Bluetooth sensor | heart rate, cadence, wheel speed, power | the sensor, paired once in Velorki |
| Apple Watch | heart rate, and the ride on your wrist | an iPhone with a watch paired to it |
| Apple Health or Health Connect | heart rate that something else wrote to the phone | the phone's health app, and one switch |

When two of them report the same thing at the same time, the watch wins over a Bluetooth sensor, and a Bluetooth sensor wins over the health app. A reading counts as current for ten seconds, and when the source that was winning falls silent the next one takes over by itself, so a strap you left at home is simply not there.

## Turning a source on

Everything is in **Settings → Sensors**, just under **Recording**:

- **Apple Health** on an iPhone, **Health Connect** on Android, with the line "Heart rate from your watch or any app that writes it; rides are saved as workouts". Turning this on is the only thing in Velorki that can raise the health permission prompt. Refuse it and Velorki says "Velorki was not given access to your health data." and leaves the switch off.
- **Save rides to Health** under it, which you can switch off on its own. It does nothing while the switch above it is off.
- **Apple Watch**, with the line "Heart rate from the watch, ride controls on the wrist". The row is there only on an iPhone that has a watch paired to it.
- **Bluetooth sensors**, with the line "Heart-rate straps, speed and cadence sensors, power meters", or "1 sensor paired" once you have one. It opens a screen of its own.

## Bluetooth sensors

### Pairing a sensor

1. Wake the sensor up: put the strap on, or turn the cranks. Most sensors say nothing at all until they are being used.
2. Open **Settings → Sensors → Bluetooth sensors** and tap **Scan**. On an iPhone the screen warns "iOS asks for Bluetooth the first time you scan." before you tap. A scan runs for about fifteen seconds.
3. Under **Found**, tap the sensor you recognise. Each row has its name, small icons for what it measures, and its signal strength in dBm, with the strongest at the top.
4. Velorki connects once to ask the device what it really has, files it under **Paired**, and lets go of it again.

While that screen is open your paired sensors are connected, so each row shows what it is saying right now instead of **Connected**, **Connecting…** or **Not connected**. Leaving the screen disconnects them again unless a ride is recording. **Forget**, in the menu at the right of a paired row, removes a sensor.

### What Velorki pairs with

The three standard cycling profiles, which is what almost everything sold as a bike sensor speaks:

- **heart-rate straps** and armbands,
- **speed and cadence sensors**, on the wheel, on the crank, or one device doing both,
- **power meters**, whose crank counters also give a cadence, so a power meter makes a separate cadence sensor unnecessary.

A device that speaks none of the three is not offered. Velorki pairs with sensors, not with bike computers: a head unit is a different kind of thing and is not connected here.

### Wheel circumference

A speed sensor counts wheel turns, so Velorki has to be told how far one turn is. The **Wheel circumference** field appears at the bottom of the screen as soon as a paired sensor reports speed, with the hint "Millimetres per wheel turn. 2105 is a 700x25c tyre." and **mm** after the number.

While a wheel sensor is reporting, its speed replaces the GPS speed on the Record sheet, which is the point of it: a wheel is right at walking pace, under trees and in a tunnel, where GPS is not. Nothing else in the ride uses it.

### When a sensor is not found

- **"Nothing yet. Wake the sensor up: put the strap on, or turn the cranks."** A strap with no skin contact and a crank standing still are invisible. Move, then scan again.
- **"Switch Bluetooth on to find your sensors."** The phone's radio is off.
- **"Velorki was not allowed to use Bluetooth."** The permission was refused. Grant it for Velorki in the phone's settings and scan again.
- **The sensor is talking to something else.** These sensors serve one device at a time. Close the other app, or switch the head unit off.
- **A paired sensor that says Not connected** is out of range, asleep or flat. Velorki keeps trying while a ride records or that screen is open, waiting a little longer after each attempt.

## Apple Watch

The watch app is a display and a sensor, never a second recorder. The phone records the ride; the watch sends what it measures and what you tap, and draws what the phone reports back.

### Getting the watch app

Velorki's watch app ships inside the iPhone app. It arrives on the watch by itself if your watch installs companion apps automatically; otherwise open the **Watch** app on the iPhone and install Velorki from the list of available apps. Then switch **Apple Watch** on in **Settings → Sensors**; that also asks once to post notifications, for the one described under the buttons. The first time a workout starts on the watch, the watch asks for permission to read your heart rate. That prompt comes from the watch, not from the phone.

### What the watch shows

- Your **heart rate** in large figures, with the heart beating while the watch measures; two dashes while nothing is measuring, and the last reading dimmed while the ride is paused. The heart and the buttons take the accent colour you chose in the app.
- A line in orange when something is wrong: Health access refused, a workout the watch would not run, or a phone that did not answer.
- While a ride runs, its distance, the elapsed clock and the speed, and **Paused** when it is paused. The phone formats all of them, so they are in your units and your language.
- The next turn with its icon, its name and the distance to it, as the lock screen has it, in orange while you are off route.
- One tap on the wrist when a turn cue is due, and one when you leave the route. A watch that slept through three turns taps once rather than three times.

The watch's own words, which is to say the buttons and the two footnotes, are English whatever language the phone is in. There are no complications yet.

### What the buttons do

| Button | What it does |
|---|---|
| **Start ride** | starts the recording on the phone |
| **Pause**, **Resume** | pause the ride and carry on, as on the phone |
| **Finish** | stops the recording; "Finish opens the save sheet on the phone." |
| **Stop heart rate** | ends the measuring on the watch while the ride goes on |
| **Start heart rate** | starts it again, or starts it for a ride the watch app was opened into late |

When a ride starts on the phone, the watch app opens by itself and starts measuring, so there is nothing to tap on the wrist. The other way round, **Start ride** on the watch starts the recording on the phone and brings the phone to its **Record** tab. A phone in your pocket, with Velorki in the background, gets a notification, "Ride started from your watch", and a tap on it opens the app; that matters because iOS gives an app woken in the background no GPS until it has been opened once, so the track starts then. An app you have swiped away entirely cannot be woken by the watch at all, which is an iOS rule; after a few tries the watch says "The phone did not answer. Open Velorki on the phone and try again." A ride you finish from the wrist is saved like any other: the recording stops, and the save sheet is waiting on the phone next time you look at it.

### Battery on the wrist

Measuring a heart rate for hours is what costs the watch its day. A paused ride, whether you paused it or the phone auto-paused at a standstill, rests the sensor and measures again a few seconds after the ride goes on, so a wait at a light costs nothing and is not part of the ride's heart rate. **Stop heart rate** ends the measuring without touching the ride. The footnote on the screen says the rest, "Low Power Mode in the watch's settings makes a long ride last." Switching **Apple Watch** off in Settings also ends a session that is still running.

## Apple Health and Health Connect

This source is the heart rate your phone already knows about: what an Apple Watch wrote through its own workout, or what another app put into the store. It is the slowest and least live of the three, and a strap or a watch reporting directly takes over from it at once.

### What is read and what is written

- **Read**: heart rate, and nothing else. While a ride records Velorki asks the store for new samples every five seconds, or every thirty seconds with **Battery saver** on.
- **Filled in afterwards**: when the ride is saved, samples from the store fill the points of the track that carry no heart rate, as long as a sample lies within half a minute of the point, and the ride's figures are recomputed. A point that got a reading live from a strap or a watch keeps that one.
- **Written**: one cycling workout per ride, with its start, its end and its distance, and only with **Save rides to Health** on. Each ride is written once. With that switch off, Velorki only reads.

## Where the figures appear

### While you ride

A third row of figures appears on the Record sheet with whatever is being reported: **Heart rate**, **Cadence** and **Power**, each only while a sensor gives it, so a watch alone adds one tile and no sensor adds nothing at all. On an iPhone the pulse joins the figures on the lock screen card and in the Dynamic Island.

### On a saved ride

A ride's page in the [library](./library) grows what that ride actually carries:

- **Avg HR**, **Max HR**, **Avg cadence** and **Avg power** among the figures, each one only if the ride has it,
- a **Heart rate** chart under the speed chart, which you can drag along for a read-out at any distance.

The **Splits** table is unchanged: **Split**, **Moving**, **Avg** and **Ascent**, with no sensor columns. A ride imported from a GPX or FIT file brings its heart rate, cadence and power with it and shows them the same way.

## What is stored, and what leaves the phone

The readings are part of the ride: a heart rate, a cadence and a power value on each point of the track, and the averages and the maximum heart rate among its figures. They live in Velorki's own storage on the phone, with the track.

Nothing is uploaded by itself. A GPX or FIT export carries the values along with the track, so a ride you export or send to Strava or Ride with GPS arrives complete. The exchange with Apple Health or Health Connect happens on the phone. See [privacy on the phone](./privacy-on-the-phone) for the whole picture.

## Related

- [Recording a ride](./recording-a-ride)
- [Library](./library)
- [Settings and appearance](./settings-and-appearance)
- [Privacy on the phone](./privacy-on-the-phone)
- [Troubleshooting](./troubleshooting)
