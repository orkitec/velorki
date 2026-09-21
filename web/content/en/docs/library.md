---
title: Library
description: Where your saved routes and recorded rides live, what a ride page shows, and how to rename or delete either of them.
order: 8
---

The Library tab holds everything you kept: the routes you planned and the rides you recorded. Go here to open a route again, to read a ride's charts and splits, and to get files in and out.

Everything in the library is on the phone. There is no account and nothing is synchronised anywhere.

## Routes and Rides

A switch under the title picks the list: **Routes** or **Rides**. Velorki remembers which you were last looking at.

- A **route** row shows its name and, underneath, the date, the distance and the ascent.
- A **ride** row shows its name and, underneath, the date, the distance and the moving time. Above the list is a count, "12 rides".

Tap a row to open it.

Empty lists explain themselves: "No saved routes yet. Plan a route in the Plan tab and save it." and "No rides yet."

## Renaming and deleting

**Routes**: the menu at the right of the row has **Rename** and **Delete**. Swiping a row to the left deletes it too. Either way the message that follows carries an **Undo**.

**Rides**: swipe the row to the left to delete it, again with **Undo**. Renaming and deleting a ride with a confirmation are on the ride's own page, under the menu at the top right.

Both rename dialogs are the same: one field, **Name**, then **Cancel** or **Save**.

## A route page

Opening a route shows, from the top:

- a map of the route, with its points of interest as small named markers when it was imported with any,
- the date, the bike profile and the ascent,
- the description, if the route has one,
- **Distance**, **Ascent**, **Descent** and **Est. time**,
- the surface breakdown.

The map stays at the top while the pages under it scroll, with dots under the map saying which page is up. One swipe to the left is the elevation profile. A route imported with turns or points of interest has one more page, the cue sheet: every turn and point with its distance from the start, a tap on a line panning the map there at your zoom and a tap on a marker bringing the sheet up with the line selected, as on the import screen.

Then the actions:

- **Open in planner** loads it into the Plan tab, where you can edit it and save it again.
- **Export** offers **GPX route** and **FIT course**, see [import and export](./import-and-export).
- **Send** offers **Send to Ride with GPS** and **Send to Strava**, see [Strava and Ride with GPS](./strava-and-ridewithgps).
- **Share link** turns it into a link, see [sharing](./sharing).
- **Describe this route** asks the assistant to write a paragraph about it, see [assistant](./assistant).

## A ride page

Opening a ride shows, from the top:

- **the track coloured by speed**, from slow to fast, with a **slow**/**fast** legend under the map. The bands are that ride's own quantiles, so the colours compare the ride with itself rather than with a fixed scale. A ride with no timestamps is drawn as a plain line.
- the date,
- seven figures: **Distance**, **Moving**, **Time**, **Avg**, **Max**, **Ascent**, **Descent**. **Moving** leaves out the time you stood still; **Time** is the whole ride from start to finish.
- the **Elevation** chart, height against distance, drawn only when the track carried heights,
- the **Speed** chart, whose axis always starts at zero,
- the **Heart rate** chart, when the ride carried one; where the reading was lost for a stretch the line breaks, and when less than most of the ride had a reading the caption says how much, "Heart rate · 24 % of the ride", so an average over those minutes is not read as the ride's,
- the **Splits** table.

Touch either chart and drag along it for a read-out of the form `12.3 km · 340 m`.

### Figures from a sensor

A ride recorded with a heart-rate strap, an Apple Watch or a power meter carries more than the seven: **Avg HR**, **Max HR**, **Avg cadence**, **Max cadence**, **Avg power** and **Max power** join the figures, each one only if the ride has it, and the **Heart rate** chart is drawn under the speed chart. A ride recorded without a sensor shows none of it, and a ride imported from a GPX or FIT file shows whatever that file carried. See [sensors and your watch](./sensors-and-watch).

### Calories, heart-rate zones and estimated power

All three are off until you switch them on under Settings → Rider, and all three are computed on the phone from the ride's own points, so older rides get them too.

**Calories** is an estimate, and the small line under the figure says what it rests on. With a power meter over the ride it is the work done, "from power": a kilojoule of pedalling is very nearly a kilocalorie burned. Else, with a heart rate over the ride and your weight, year of birth and sex, it is "from heart rate". Else, with **Estimate power** on, it is "from estimated power", the estimated work in kilojoules again. Else it is "estimated from speed", from your weight and how fast you rode. It needs your weight in every case.

**Est. power** appears only with the switch on and only on rides without a power meter; a ride with a meter shows the meter and nothing else. It is the average of what the Martin power model says you must have put into the pedals to move yourself and your bike at the speed you rode up the slope you rode: from your speed, the grade and the total weight of rider and bike, assuming no wind, no drafting, a rider on the hoods, a fixed rolling resistance per bike type, a 2.5 % drivetrain loss and thinner air with altitude. Heights are smoothed over 20 m because GPS heights jump; coasting and braking count as zero. Expect it to be reasonable on long climbs, where weight dominates; too high in a fast group and wrong in wind, which it cannot see. It is a number to compare your own rides with, not a power meter.

**Heart-rate zones** is a bar under the heart-rate chart, cut into five zones of your maximum heart rate, with a row per zone: its range, the time in it and the share of the ride's heart-rate time. Zone 1 is everything below 60 %, zone 5 everything from 90 %. The caption names the maximum used: the one you entered, or 220 minus your age.

### Splits

One row per split, with four columns: **Split**, **Moving**, **Avg** and **Ascent**. The caption says how long a split is, "Splits, every 5 km". By default the length follows the ride: one kilometre up to 30 km, five up to 150 km, ten beyond, in miles on imperial units, so the table stays short on a long ride; **Split length** under Settings → Recording fixes it at 1, 5 or 10 instead. The last row is the remainder, so it may be shorter than the rest. Behind each row a bar shows that split's average speed against your fastest split, which makes the hard sections obvious at a glance.

### Ride actions

- The cloud button at the top right uploads the ride to a connected service.
- The menu beside it: **Export GPX track**, **Export FIT activity**, **Continue this ride**, **Rename**, **Delete**.
- At the bottom: the same two exports and **Share link**.

## Getting files and routes in

The two buttons at the top right of the Library tab:

- **Import file** opens the phone's file picker for a GPX or FIT file.
- The cloud button offers **Import from Strava** and **Import from Ride with GPS**, when those services are configured.

Both are covered in [import and export](./import-and-export) and [Strava and Ride with GPS](./strava-and-ridewithgps).

## Related

- [Recording a ride](./recording-a-ride)
- [Sensors and your watch](./sensors-and-watch)
- [Import and export](./import-and-export)
- [Sharing](./sharing)
- [Strava and Ride with GPS](./strava-and-ridewithgps)
- [Planning a route](./planning-a-route)
