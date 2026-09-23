---
title: Library
description: Where your saved routes and recorded rides live, what a route or ride card shows, and how to rename or delete either of them.
order: 8
---

The Library tab holds everything you kept: the routes you planned and the rides you recorded. It is a card over the map, like the Plan and Record tabs: its content scrolls at any height, and the handle at its top moves it. Pull the handle up for more room, pull it all the way down and the card folds into the navigation bar, leaving the map. Go here to open a route again, to read a ride's charts and splits, and to get files in and out.

Everything in the library is on the phone. There is no account and nothing is synchronised anywhere.

## Routes and Rides

A switch under the card's title picks the list: **Routes** or **Rides**. Velorki remembers which you were last looking at.

- A **route** row shows its name and, underneath, the date, the distance and the ascent.
- A **ride** row shows its name and, underneath, the date, the distance and the moving time. Above the list is a count, "12 rides".

Tap a row to open it in the card, with the route or the ride drawn on the map above. The arrow at the top left of the card, or the system back, brings the list back.

Empty lists explain themselves: "No saved routes yet. Plan a route in the Plan tab and save it." and "No rides yet."

## Renaming and deleting

**Routes**: the menu at the right of the row has **Rename** and **Delete**. Swiping a row to the left deletes it too. Either way the message that follows carries an **Undo**.

**Rides**: swipe the row to the left to delete it, again with **Undo**. Renaming and deleting a ride with a confirmation are on the ride's card, under the menu at the right of its header.

Both rename dialogs are the same: one field, **Name**, then **Cancel** or **Save**.

## A route card

Opening a route draws it on the map, fitted to the part of the screen above the card, with its points of interest as small named markers when it was imported with any. The card shows, from the top:

- the date, the bike profile and the ascent,
- the description, if the route has one,
- **Distance**, **Ascent**, **Descent** and **Est. time**,
- the surface breakdown,
- the actions below,
- the elevation profile,
- for a route imported with turns or points of interest, the cue sheet: every turn and point with its distance from the start, a tap on a line panning the map there at your zoom and a tap on a marker scrolling the card to that line.

The actions:

- **Open in planner** loads it into the Plan tab, where you can edit it and save it again.
- **Export** offers **GPX route** and **FIT course**, see [import and export](./import-and-export).
- **Send** offers **Send to Ride with GPS** and **Send to Strava**, see [Strava and Ride with GPS](./strava-and-ridewithgps).
- **Share link** turns it into a link, see [sharing](./sharing).
- **Describe this route** asks the assistant to write a paragraph about it, see [assistant](./assistant).

## A ride card

Opening a ride draws **the track coloured by speed** on the map, from slow to fast, fitted above the card, with a **slow**/**fast** legend at the top of the card. The bands are that ride's own quantiles, so the colours compare the ride with itself rather than with a fixed scale. A ride with no timestamps is drawn as a plain line. The card shows, from the top:

- the date,
- seven figures: **Distance**, **Moving**, **Time**, **Avg**, **Max**, **Ascent**, **Descent**. **Moving** leaves out the time you stood still; **Time** is the whole ride from start to finish.
- the **Elevation** chart, height against distance, drawn only when the track carried heights,
- the **Speed** chart, whose axis always starts at zero,
- the **Heart rate** chart, when the ride carried one; where the reading was lost for a stretch the line breaks, and when less than most of the ride had a reading the caption says how much, "Heart rate · 24 % of the ride", so an average over those minutes is not read as the ride's,
- the **Splits** table.

Touch a chart and drag along it for a read-out of the form `12.3 km · 340 m`. Pinch a chart to zoom in on a stretch, drag to pan while zoomed, and double-tap it or tap **Whole ride** to see the whole ride again; the three charts zoom together.

### Route and points of interest

A ride that followed a route shows that route under the track, in the quieter colour of a planner alternative, and the route's points of interest as markers on the map and as marks on the **Elevation** chart at the point where you passed them — only for points the ride came within 60 m of. A tap on a marker pins it with its name; the read-out names a mark the finger rests on. The route button at the top of the map's control column hides all of it, and the choice is remembered.

### Figures from a sensor

A ride recorded with a heart-rate strap, an Apple Watch or a power meter carries more than the seven: **Avg HR**, **Max HR**, **Avg cadence**, **Max cadence**, **Avg power**, **Max power** and **Norm. power** join the figures, each one only if the ride has it, and the **Heart rate** chart is drawn under the speed chart. **Norm. power** is the meter's readings weighted the way the legs feel them: the power on a one second grid, its 30 s rolling mean, each mean raised to the fourth power, those averaged and the fourth root taken. A steady ride comes out at its average; a ride of surges and rests comes out higher. It needs at least half a minute of readings in one piece, and a gap of more than five seconds in the meter starts a new piece. With **Power zones** on and a threshold set, **Intensity** stands beside it: normalised power divided by your threshold power, so 0.80 is a ride at four fifths of what you can hold for an hour. A ride recorded without a sensor shows none of it, and a ride imported from a GPX or FIT file shows whatever that file carried. See [sensors and your watch](./sensors-and-watch).

### Calories, heart-rate zones, power zones and estimated power

All four are off until you switch them on under Settings → Rider, and all four are computed on the phone from the ride's own points, so older rides get them too.

**Calories** is an estimate, and the small line under the figure says what it rests on. With a power meter over the ride it is the work done, "from power": a kilojoule of pedalling is very nearly a kilocalorie burned. Else, with a heart rate over the ride and your weight, year of birth and sex, it is "from heart rate". Else, with **Estimate power** on, it is "from est. power", the estimated work in kilojoules again. Else it is "from speed", from your weight and how fast you rode. It needs your weight in every case.

**Est. power** appears only with the switch on and only on rides without a power meter; a ride with a meter shows the meter and nothing else. It is the average of what the Martin power model says you must have put into the pedals to move yourself and your bike at the speed you rode up the slope you rode: from your speed, the grade and the total weight of rider and bike, assuming no wind, no drafting, a rider on the hoods, a fixed rolling resistance per bike type, a 2.5 % drivetrain loss and thinner air with altitude. Heights are smoothed over 50 m because GPS heights jump, and the work is summed over half a minute at a time before anything below zero is dropped, so a height that wobbles up and down costs nothing; coasting and braking count as zero, and speeding up is priced from speeds averaged over ten seconds, which in town is most of the work. Expect it to be reasonable on long climbs, where weight dominates; too high in a fast group and wrong in wind, which it cannot see. It is a number to compare your own rides with, not a power meter.

**Heart-rate zones** is a bar under the heart-rate chart, cut into five zones of your maximum heart rate, with a row per zone: its range, the time in it and the share of the ride's heart-rate time. Zone 1 is everything below 60 %, zone 5 everything from 90 %. The caption names the maximum used: the one you entered, or 220 minus your age.

**Power zones** is the same bar for rides with a power meter, cut into seven zones of your threshold power: below 55 %, 55–75, 75–90, 90–105, 105–120, 120–150 and from 150 %. Each second of the ride goes to the zone of the meter's reading at that moment; time stood still counts nowhere. The caption names the threshold, "Power zones · threshold 250 W". It needs the switch and your threshold power under Settings → Rider, and it puts the **Intensity** figure among the tiles.

### Splits

One row per split, with four columns: **Split**, **Moving**, **Avg** and **Ascent**. The caption says how long a split is, "Splits, every 5 km". By default the length follows the ride: one kilometre up to 30 km, five up to 150 km, ten beyond, in miles on imperial units, so the table stays short on a long ride; **Split length** under Settings → Recording fixes it at 1, 5 or 10 instead. The last row is the remainder, so it may be shorter than the rest. Behind each row a bar shows that split's average speed against your fastest split, which makes the hard sections obvious at a glance. Tap a row to see that split shaded on the charts and drawn over the track on the map, where a chip names it, "Split 3 · 2–3 km"; tap the row again or the chip to clear it.

### Climbs

Under the splits, on a ride that had any, a **Climbs** table: one row per climb with **Start** (where along the ride it began, "at 12.3 km"), **Length**, **Ascent** and **Grade**, and a quieter line under it with the moving time, the VAM and, when the ride carried them, the average heart rate and power over the climb. VAM is metres of height gained per hour of moving time, the customary measure of how fast a climb was ridden: 1,000 m/h is a hundred metres every six minutes. Behind each row a bar shows that climb's ascent against the biggest one. Tap a row to see that climb shaded on the charts and drawn over the track on the map, where a chip names it, "Climb 1 · 0.5–2.5 km"; tap the row again or the chip to clear it. One stretch is highlighted at a time, whether it is a split or a climb.

A climb is found the way the record sheet's profile finds the one you are on: it starts where the next 100 m of road rise by at least 3 %, and it ends at its high point once the road has dropped 10 m below it, so a dip in a long climb does not cut it in two. Rises shorter than 300 m, gaining less than 20 m or averaging under 3 % from foot to top are not listed. Heights are smoothed over 50 m first, as for the power estimate, and pauses count towards neither the time nor the height.

### Surface

Under the climbs, a **Surface** bar like the one on a route card: how much of the ride was paved, unpaved or unknown, with the cycleway and busy-road shares beside it. The ride was never planned, so the app finds out afterwards: it lays the recorded track over the offline routing tiles on the phone and reads the surface off the roads it lands on. No track leaves the phone for this. It needs the routing region for the area to be downloaded; until it is, the section says so. A track the map cannot follow, through a park, over a ferry or along a cut through, shows "The track could not be matched to the map" instead, and the result, either way, is kept with the ride, so it is worked out once. A new routing tile gives an unmatched ride another go.

### Ride actions

- The cloud button at the right of the card's header uploads the ride to a connected service.
- The menu beside it: **Export GPX track**, **Export FIT activity**, **Continue this ride**, **Rename**, **Delete**.
- At the bottom: the same two exports and **Share link**.

## Getting files and routes in

The two buttons at the right of the card's header:

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
