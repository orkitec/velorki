---
title: Search
description: Find places, streets, house numbers and things like drinking water or toilets, on the phone where you have downloaded an area and online everywhere else.
order: 4
---

The search field at the top of the Plan tab finds towns, streets, house numbers and points of interest such as cafés, drinking water and bike shops. Where you have downloaded an area it answers from the phone, instantly and with no signal; everywhere else it asks an online geocoder.

## How to search

1. Open the **Plan** tab and tap the field at the top, hinted **Search for a place**.
2. Type at least three characters. Results appear in a card under the field as you type.
3. Tap a result.

What happens then depends on the plan:

- **Nothing planned yet**: the map moves to the place and drops a pin, and two buttons appear under the bike chips, **From my position** and **Start here**.
- **A route already being planned**: the place is added as the next waypoint straight away.

The **X** in the field clears the text, the pin and those two buttons.

## Offline or online

Velorki decides by the **map centre**, not by your connection. Each downloaded routing tile brings a search index of its area with it, so:

- if the tile under the centre of the map has its index on the phone, the query is answered on the phone;
- if it does not, the query goes online to Photon.

At the bottom of the result card sits exactly one row, and which one it is tells you where the results came from:

| Row | Means | Tapping it |
|---|---|---|
| **Search online for "…"** | you are looking at offline results | runs the same text online |
| **Show offline results** | you are looking at online results | runs the same text on the phone again |
| **Download this area to search offline** | this area has no index on the phone | opens the offline screen for the visible area |

That row stays visible while you scroll the list, and it is shown under an error message too, which is where it matters most.

## What it finds

- **Places**: cities, towns, villages, hamlets, suburbs, neighbourhoods, localities and islands.
- **Streets**, with house numbers.
- **Points of interest**, each with its own icon and label: Cafe, Drinking water, Toilets, Bike repair station, Bike shop, Bike rental, Bike parking, E-bike charging, Shelter, Campsite, Hotel, Hostel, Mountain hut, Supermarket, Bakery, Pharmacy, Picnic site, Station, Ferry terminal, Airport, Viewpoint, Peak, Mountain pass, Park, Beach, Water, Nature reserve, Attraction, Museum, Historic site, Place of worship, Hospital, University, Sports venue, Shopping centre, Tower, Lighthouse, Building.

Offline rows show the kind, the distance, the house number and the town under the name, in that order, as far as each is known: "Drinking water · 350 m", "Street · 400 · Manhattan". A tap, a toilet, a shelter or a bike stand with no name of its own is listed under its kind instead.

## Searching by kind

Type the name of a kind rather than the name of a place. "drinking water", "bakery", "toilets" and the rest all work, in the language the app is running in.

The list then opens with the five nearest of that kind to the map centre, each with its distance, and the ordinary name matches follow underneath. Velorki looks in a box that grows from 5 to 50 km around the map centre until it has enough. This is the quick way to answer "where is the nearest tap" in the middle of a ride.

A search by kind ignores the group switches described below.

## House numbers

Put the number at the start or the end: "Hauptstrasse 12", "400 W 42nd". Velorki takes the number off, matches the street, and answers at the number's own position along it.

Where the index holds that exact number, the position is exact. Where the number falls between two it knows, Velorki interpolates and marks the row **≈ 400** so you can see it is an estimate. A number in the middle of a query is treated as part of the name, and so is an ordinal such as "42nd".

## Typos

If a query matches nothing at all, Velorki takes the words it does not recognise, finds the likeliest words in the index that are one or two letters away, and runs the search again. The card then says **Showing results for "…"** above the list, with what it actually searched for.

## Ordering the groups

Offline results are grouped, and you decide which groups appear and in which order.

1. Open **Settings**.
2. Tap **Search**, subtitled "What offline search shows, and in which order. Drag to change the priority."
3. Drag a row by its handle to move it up or down. Use the switch on the right to turn a group off.

The eight groups, in their default order: **Places**, **Streets and addresses**, **Landmarks**, **Cycling stops**, **Overnight**, **Nature**, **Transport**, **Services**.

There is no save button; changes take effect on your next keystroke. A group that is switched off disappears from name matches, and the order breaks ties between results that match the text equally well.

## When search does not work

- **"Nothing found."** The text matched nothing, offline or online. Try the trailing row to switch source, or fewer words.
- **"Search failed."** with a reason means the online geocoder could not be reached. Offline search keeps working where you have downloaded an area.
- **"No search server configured, set one in Settings → Advanced."** means this build has neither a geocoder address nor any downloaded index. The field is disabled until one exists.

## Related

- [Offline maps and routing](./offline-maps-and-routing)
- [Planning a route](./planning-a-route)
- [Settings and appearance](./settings-and-appearance)
- [Privacy on the phone](./privacy-on-the-phone)
