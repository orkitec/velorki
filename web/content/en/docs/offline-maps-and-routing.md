---
title: Offline maps and routing
description: Download the map you look at and the routing data your routes are computed from, so planning, search and navigation keep working with no signal.
order: 5
---

Two separate downloads make Velorki work without a connection: the **map**, which is what you see, and the **routing data**, which is what routes and offline search are computed from. Download both for the area you ride in before a ride that leaves the signal behind.

## The two kinds

| | Map | Routing data |
|---|---|---|
| Shown as | **Map** | **Routing data** |
| What it is | vector map tiles from OpenFreeMap, drawn from OpenStreetMap | BRouter tiles from the Velorki mirror, built from OpenStreetMap |
| Covers | exactly the rectangle you had on screen | a fixed 5° × 5° square of the world |
| Size | tens of megabytes for a city | often 125 to 250 MB per tile |
| Without it | grey tiles where the map has not been cached | no routing and no offline search in that area |

The routing data also carries the place index, so a downloaded area searches offline too. That is why the routing tiles screen says "A downloaded region also works for place search without a signal."

## Download an area

1. On the **Plan** tab, move the map so the area you want fills the screen. Do not zoom out further than you need: the map download follows exactly what is on screen.
2. Tap the **Offline data** button in the column on the right of the map.
3. Read the two cards, then tap **Download the visible area** at the bottom.
4. The dialog **Download the visible area** lists what you are about to fetch: "Map of the visible area · size known once downloaded" for the map, then one line per routing tile with its size, for example `E5_N45 · 187 MB`, or "Routing data for this area is already on the device".
5. Tap **Download**.

Both downloads run while the app is open. The cards show **Downloading the map…** and **Downloading E5_N45…** with progress bars.

The screen warns you for a reason: "Tiles are large, often 125–250 MB each, and Velorki cannot tell Wi-Fi from mobile data. Start a download when you are on Wi-Fi."

You can also reach this screen from **Settings → Offline data**, but opened that way there is no map behind it, so the download button is disabled and the note says "Open this screen from the map to download the area you are looking at."

## Manage the map areas

**Manage** on the **Map** card opens **Offline maps**, one row per downloaded area:

- The name Velorki gave it, **Map area 1**, **Map area 2** and so on.
- Its size and the date, "12.3 MB · Downloaded 14 Sept 2026".
- **Refresh available** in orange once the area is older than two months, and a **Refresh** button beside it. A refresh is a full re-download.
- A **Delete** button, which asks "Delete offline area?" with "The downloaded tiles are removed from this device."

The card on the offline screen summarises the same thing: "3 areas, 48 MB", and "2 areas are older than two months and can be refreshed".

## Manage the routing tiles

**Manage** on the **Routing data** card opens **Offline routing data**. Each row is one 5° × 5° tile with its name, size and state:

| State | Means |
|---|---|
| **On this device** | ready, routing and offline search work here |
| **Update available** | the mirror has rebuilt this tile; **Update** re-downloads it |
| **Update needs a newer Velorki** | the rebuilt tile is in a data format this app version cannot read |
| **Downloading…** | in progress |
| **Not downloaded** | known to the mirror, not on the phone |

Also on the screen:

- **Needed for this route** appears when you arrived from the planner's missing-tiles banner, with the tiles that route needs already picked out and a button counting them, for example **Download 1 tile (187 MB)**.
- **Download for the visible area** at the bottom, with the total across everything you hold: "3 tiles, 540 MB".
- **Mirror built 1 Sept 2026** under each row, which is the date the mirror last produced that tile.
- A **Delete** button on every row, warning "The tile is removed from this device. Routes in that area then need the routing server again."
- A **Cancel download** button in the progress header while one is running.

Velorki checks weekly whether the mirror has rebuilt anything you hold. When it has, the **Offline data** row in Settings turns orange, shows "2 tiles have updates" and puts a count badge on the chevron.

## The gazetteer, or search index

Every routing tile the mirror publishes has a small search index beside it, and Velorki downloads the two together. Nothing about it is exposed as a separate setting or a separate download.

If the index fails to download, the tile itself is still fine: the area stays routable and its search simply goes online. The same is true of an index in a format this app version does not read; it is skipped, the other areas keep answering offline, and that area searches online.

## Where it all lives, and how to get rid of it

Everything is inside the app's own storage on the phone, not in your documents or your photo library, and nothing is copied to a cloud backup.

To free space:

- delete individual map areas in **Offline maps**,
- delete individual routing tiles in **Offline routing data**,
- or uninstall the app, which removes all of it, along with your routes and rides. Export what you want to keep first, see [import and export](./import-and-export).

## "Update Velorki first"

Routing tiles occasionally change format. When the mirror offers a tile this app version cannot read, Velorki says so instead of downloading rubbish: **Update Velorki first**, "These tiles are in data format 5, and this Velorki reads up to 4. They need a newer Velorki; download them once you have updated to one." Answer **Not now**, or **Open store** to go and update.

Tiles you already have keep working.

## Related

- [Search](./search)
- [Planning a route](./planning-a-route)
- [Turn-by-turn navigation](./navigation)
- [Troubleshooting](./troubleshooting)
