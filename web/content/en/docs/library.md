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

- a map of the route,
- the date, the bike profile and the ascent,
- the description, if the route has one,
- **Distance**, **Ascent**, **Descent** and **Est. time**,
- the elevation profile,
- the surface breakdown.

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
- the **Splits** table.

Touch either chart and drag along it for a read-out of the form `12.3 km · 340 m`.

### Splits

One row per kilometre, or per mile if you are on imperial units, with four columns: **Split**, **Moving**, **Avg** and **Ascent**. The last row is the remainder, so it may be shorter than the rest. Behind each row a bar shows that split's average speed against your fastest split, which makes the hard sections obvious at a glance.

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
- [Import and export](./import-and-export)
- [Sharing](./sharing)
- [Strava and Ride with GPS](./strava-and-ridewithgps)
- [Planning a route](./planning-a-route)
